class_name Vehicle
extends CharacterBody2D
## 차 한 대. 물리 계산은 VehicleMotor가 하고, 이 노드는 입력·충돌·그리기만 맡는다.

signal impacted(strength: float)
signal bumped(other: Vehicle, strength: float)
signal caught_fire                           ## 체력이 0이 됐다 — burning초 뒤 터진다
signal exploded(by_player: bool)
signal landing_blocked                       ## 헬기가 내려앉으려는데 밑이 막혀 있다 (건물·차·강물)
signal dug(at: Vector2)                      ## 굴삭기 버킷이 땅을 찍었다 (Combat이 차 집기·내려놓기·피해를 맡는다)

const RESTITUTION := 0.35
const COLLISION_FRICTION := 0.8
const SKID_LATERAL_SPEED := 140.0
const PARKED_DRAG := 500.0   ## 아무도 조종하지 않는 차가 서는 감속 px/s²
const SMOLDER_TIME := 25.0   ## 잔해에서 연기·불씨가 이만큼 난다
const WRECK_FLAME_TIME := 7.0 ## 잔해 위 남은 불꽃이 이만큼 타다 꺼진다
const ROT_STEP := 0.03        ## 이만큼(약 1.7도) 돌아야 모형을 다시 그린다
const REDRAW_RANGE := 2400.0 ## 카메라에서 이보다 먼 차는 다시 그리지 않는다 (가장 멀리 줌아웃해도 화면 밖)
const AIRBORNE_HEIGHT := 4.0  ## 헬기가 이보다 높이 떠 있으면 아무것과도 부딪히지 않는다
const LIFTOFF := 0.35         ## 헬기는 날 높이의 이만큼 오르기 전에는 움직이지 않는다 (시동·이륙)
const LAND_SPEED := 70.0      ## 내려앉는 동안 이보다 빨리 못 간다 (보행자를 치는 속도보다 느리게)
const ELEV_MIN := 0.06         ## 포신을 가장 낮게 든 각 (rad, 가까이 쏠 때)
const ELEV_MAX := 0.78         ## 가장 높이 든 각 (최대 사거리)
const ELEV_RATE := 0.6         ## 포신이 오르내리는 빠르기 (rad/s)
const MUZZLE_REACH := 0.72     ## 포구가 차 가운데에서 차 길이의 이만큼 앞 (포신이 차체 밖으로 나온다)
const ARM_RATE := 2.4          ## 굴삭기 붐·암이 겨눈 자세를 따라가는 빠르기 (rad/s)
const BLADE_UP := 0.32         ## 불도저 블레이드를 든 각 (rad)
const BLADE_RATE := 0.8        ## 블레이드가 오르내리는 빠르기 (rad/s)
const DROP_GRAVITY := 900.0    ## 굴삭기가 놓은 차가 떨어지는 가속 (화면 px/s²)
const DROP_DAMAGE := 0.12      ## 떨어진 차가 받는 피해: 떨어진 속도(px/s) × 이 값
const CLIMB_RATE := 28.0       ## 깔고 넘는 차에 올라타는 빠르기 (화면 px/s)
const CLIMB_PITCH := 0.16      ## 올라타고 내려올 때 들고 숙이는 각 (rad)
const ROTOR_ABOVE := 7.0       ## 주 회전날개가 동체 높이(VehicleType.height)보다 이만큼 위에 돈다 (VehicleModel의 헬기 모형들)
const BANK_PIVOT := 12.0      ## 헬기가 기울·숙일 때 도는 축 높이 (동체 가운데)
const BANK_RATE := 1.6        ## 기울기가 목표를 따라가는 속도 (rad/s)
const PITCH_RATE := 0.9       ## 숙이기가 목표를 따라가는 속도 (rad/s)
const MAP_MARGIN := 40.0      ## 헬기는 지도 가장자리에서 이만큼 안쪽까지만 난다

@export var stats: VehicleType
var control := PlayerControl.new()   ## 운전자의 입력 출처 (탑승 시 Director가 연결)
var controlled := false       ## 플레이어가 운전 중 (Director가 정한다)
var has_driver := false       ## NPC 운전자가 타고 있음 — 탈취하면 끌려 나와 도망친다
var ai: TrafficAI = null      ## 도로를 달리는 NPC 차의 운전자 (주차된 차는 null)
var pursuit: PursuitAI = null ## 추격 중인 경찰차의 운전자
var rotor_off := false         ## 날개를 세웠다 (병원 옥상에 서 있는 구급헬기 — PoliceHeli.parked)
var siren := false            ## 경광등 (경찰차)
var motor: VehicleMotor
var health := 0.0             ## 0이 되면 불이 붙는다 (최대 stats.durability)
var burning := -1.0           ## 불붙은 뒤 터지기까지 남은 시간. 음수면 불이 안 붙었다
var wrecked := false          ## 터져서 잔해만 남았다 — 탈 수도 움직일 수도 없다
var on_fire := false          ## 체력이 FIRE_HEALTH 아래라 불이 났다 — 체력이 타들어가 0이 되면 burning (아직 탈 수 있다)
## 찌그러진 곳: [차 기준 위치 Vector2(차 가장자리), 안쪽 방향 Vector2, 깊이 px]. 그림만 바뀌고 충돌 모양은 그대로다
var dents: Array = []
var wreck_age := 0.0          ## 터진 뒤 지난 시간 — 잔해의 남은 불·연기가 이만큼 사그라든다
var _dent_rev := 0            ## 찌그러짐이 바뀔 때마다 늘린다 (다시 그리기 판단)
var hit_by_player := false    ## 마지막 피해를 주인공이 줬다 (폭발 피해를 누구 탓으로 할지)
var paint := Color.WHITE      ## 차체 색 (카센터에서 다시 칠할 수 있다)
var beam := true              ## 2.5D에서 바닥에 전조등 빛을 그린다 (차량 도감에선 끈다)
var ground := 0.0             ## 2.5D 땅 높이 (다리 위·경사로). 그림만 올리고 물리는 평면 그대로다
## 헬기가 떠 있는 높이 (2.5D 화면 px). 그림에만 쓴다 — AIRBORNE_HEIGHT보다 높으면 충돌체를 끈다
var altitude := 0.0
var bank := 0.0               ## 옆으로 기운 각 (rad, +면 오른쪽이 내려간다). 그림에만 쓴다
var sound: HeliSound         ## 헬기 소리 (나는 차종만)
var pitch := 0.0              ## 앞으로 숙인 각 (rad, +면 코가 내려간다). 그림에만 쓴다
var _last_fwd := 0.0          ## 지난 틱 전진 속도 (가속도 → 숙이기)
var landing := false          ## 주인공이 내리려고 헬기를 내려앉히는 중 (Director가 정한다)
var touched_down := false     ## 내리려고 내려앉았다 — Director가 주인공을 내리고 끈다
var _ghost := false           ## 막힌 곳(건물 위)으로 떨어진 헬기 — 충돌체를 끈 채로 둔다
## 포탑 (자주포·전술차량 기관총, VehicleType.turret_rate > 0)
var turret := 0.0             ## 포탑 각 (rad, 차 앞 기준 — 무기는 forward().rotated(turret)로 나간다)
var turret_goal := 0.0        ## 겨눈 각 — 포탑이 turret_rate로 따라 돈다
var aim_range := 0.0          ## 포가 겨눈 거리 (px, cannon_min~cannon_max). 0이면 아직 안 정했다 (가운데)
var elevation := 0.0          ## 포신을 든 각 (rad) — 멀리 쏠수록 높이 든다 (그림만)
var recoil := 0.0             ## 쏜 뒤 포신 밀림 (1 → 0, 그림만)
var gun_reload := 0.0         ## 다음 발까지 남은 시간
## 무한궤도: 깔고 넘는 차 높이만큼 올라탄다 (그림만, Combat._crush가 climb_goal을 정한다)
var climb := 0.0
var climb_goal := 0.0
var crushed := 0.0            ## 무한궤도에 깔려 납작해진 정도 (0~1, 그림만)
var over_z := 0               ## 깔고 있는 차보다 위에 그린다 (Combat._crush가 정한다, 0이면 평소대로)
## 중장비 (굴삭기 팔 VehicleType.arm_reach, 불도저 VehicleType.blade)
var joints := Vector3.ZERO    ## 관절 각: 굴삭기 붐·암·버킷, 불도저는 x = 블레이드 든 각 (그림 — VehicleModel 관절 부품)
var dig := -1.0               ## 퍼 올리는 중이면 지난 시간 (0 → ExcavatorArm.DIG_TIME), 아니면 −1
var carried: Vehicle = null   ## 굴삭기가 버킷으로 들고 있는 차
var carried_by: Vehicle = null ## 이 차를 들고 있는 굴삭기
var blade_up := false         ## 불도저 블레이드를 들었다 (내리면 앞의 차·사람을 밀어붙인다)
var _fall_v := -1.0           ## 굴삭기가 내려놓은 차가 떨어지는 속도 (음수면 떨어지는 중이 아니다)
var _blocked_told := false
## 차 category → 체력 배율 (부업 보너스: 택시·버스·오토바이 +50%). main이 정한다
static var durability_bonus := {}

var throttle_input := 0.0
var steer_input := 0.0
var handbrake_input := false

var _shape: CollisionShape2D
var level := 0                ## 고가차도 층 (0 땅 · 1 고가 위, CityMap.level_zone) — 충돌 비트를 Layers.at으로 옮긴다
var _col_base := Vector2i(Layers.VEHICLES, Layers.WORLD | Layers.VEHICLES)   ## 땅 기준 충돌 (층, 마스크)
var _drawn_look: Array = []   ## 마지막으로 그린 모습 (같으면 다시 그리지 않는다)
var _fx: Node2D               ## 불·연기를 그리는 위층 — 매 프레임 다시 그려도 차 모형은 다시 그리지 않는다
var _fx_shown := false        ## 위층에 지금 무언가 그려져 있다


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	z_as_relative = false
	z_index = 1
	_track_level()
	_set_collision(Layers.VEHICLES, Layers.WORLD | Layers.VEHICLES)
	_shape = CollisionShape2D.new()
	add_child(_shape)
	_fx = Node2D.new()
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	apply_stats(stats)


## 차종 교체. 위치·방향은 유지하고 속도는 0으로 만든다.
func apply_stats(new_stats: VehicleType) -> void:
	stats = new_stats
	var heading := motor.heading if motor else rotation
	motor = VehicleMotor.new(stats)
	motor.heading = heading
	health = max_health()
	on_fire = false
	dents = []
	paint = stats.body_color
	var rect := RectangleShape2D.new()
	rect.size = stats.size
	_shape.shape = rect
	# 무한궤도는 차에 막히지 않는다 — 깔고 넘는다 (Combat._crush). 다른 차는 여전히 무한궤도에 부딪힌다.
	# 값이 바뀔 때만 넣는다 — 같은 값이라도 다시 넣으면 물리 서버가 몸체를 다시 등록해 충돌 순서가 바뀐다 (추격 결과가 나비효과로 바뀐다)
	if stats.arm_reach.y > 0.0:   # 굴삭기 팔은 접은 자세로 시작한다
		var fold := ExcavatorArm.solve(stats.arm_reach.x, ExcavatorArm.CARRY_Z + 8.0)
		joints = Vector3(fold.x, fold.y, ExcavatorArm.bucket_angle(0.0, false))
	_set_collision(_col_base.x, Layers.WORLD if stats.crusher else Layers.WORLD | Layers.VEHICLES)
	if stats.flies and sound == null:
		sound = HeliSound.new()
		add_child(sound)
	queue_redraw()


func place(pos: Vector2, heading: float) -> void:
	global_position = pos
	motor.heading = heading
	motor.velocity = Vector2.ZERO
	motor.steer = 0.0
	rotation = heading
	_track_level()


func _physics_process(delta: float) -> void:
	_track_level()
	if _carried_step(delta):
		return
	if burning >= 0.0:
		burning -= delta
		if burning <= 0.0:
			_explode()
	if on_fire and not wrecked:
		if health > max_health() * DamageModel.FIRE_HEALTH:
			on_fire = false   # 카센터에서 고쳤다
		elif burning < 0.0:
			take_damage(max_health() * DamageModel.FIRE_HEALTH / DamageModel.FIRE_TIME * delta, hit_by_player)
	if not dents.is_empty() and health >= max_health():
		dents.clear()         # 카센터에서 고쳤다
		_dent_rev += 1
	if wrecked:
		wreck_age += delta
		throttle_input = 0.0
		steer_input = 0.0
		handbrake_input = false
	elif controlled:
		var command := control.read()
		throttle_input = command.throttle
		steer_input = command.steer
		handbrake_input = command.handbrake
	elif pursuit and has_driver:
		pursuit.drive(delta)
	elif ai and has_driver:
		ai.drive(delta)
	else:
		throttle_input = 0.0
		steer_input = 0.0
		handbrake_input = false
	if stats.flies:
		_fly(delta)
	motor.step(throttle_input, steer_input, handbrake_input, delta)
	if stats.flies:
		_tilt(delta)
	if stats.turret_rate > 0.0:
		_aim(delta)
	if stats.crusher:
		_ride(delta)
	if stats.arm_reach.y > 0.0:
		_operate(delta)
	if stats.blade:
		joints.x = move_toward(joints.x, BLADE_UP if blade_up else 0.0, BLADE_RATE * delta)
	if wrecked or (not controlled and not (has_driver and (ai or pursuit))):
		motor.velocity = motor.velocity.move_toward(Vector2.ZERO, PARKED_DRAG * delta)
	if landing:
		motor.velocity = motor.velocity.move_toward(motor.velocity.limit_length(LAND_SPEED), stats.brake_force * delta)
	rotation = motor.heading
	_move(delta)
	if airborne():
		_keep_on_map()
	# 2.5D: 깊이(월드 x+y)로 그리는 순서를 정한다. 떠 있는 헬기는 건물 위에 그린다
	if IsoView.enabled:
		z_index = IsoView.Z_AIR if airborne() else maxi(IsoView.z_at(global_position, level), over_z)
	else:
		z_index = 20 if airborne() else 1
	ground = IsoView.ground(global_position, level) + climb


## 다시 그릴지는 화면 프레임마다 한 번 정한다 (물리 틱마다 정하면 느려질수록 한 프레임에 여러 번 그려 더 느려진다).
## 화면 밖(카메라에서 먼) 차는 다시 그리지 않는다 — 다가오면 그때 그린다.
## 가까워도 모습이 그대로면(곧게 달리거나 서 있으면) 다시 그리지 않는다 — 노드가 움직이면 그림도 따라간다
func _process(_delta: float) -> void:
	var cam := ChaseCamera.current_cam()
	if cam == null or global_position.distance_squared_to(cam.global_position) < REDRAW_RANGE * REDRAW_RANGE:
		var look := _look()
		if look != _drawn_look or _animated():
			_drawn_look = look
			queue_redraw()
		var fx := _fx_active()
		if fx or _fx_shown:
			_fx_shown = fx
			_fx.queue_redraw()


## 그림을 바꾸는 상태: 방향·탑승·브레이크·후진·잔해·도색·경적·화면 방식·경광등 깜빡임·불에 그을린 정도
func _look() -> Array:
	# 방향은 ROT_STEP마다만 다시 그린다 — 그 사이엔 그린 모형을 노드 회전이 그대로 돌린다 (높이 방향이 1도 남짓 어긋날 뿐)
	return [snappedf(rotation, ROT_STEP), occupied(), is_braking(), motor.forward_speed() < -5.0, wrecked, paint,
		ai != null and ai.honking, IsoView.enabled, snappedf(ground, 0.5), _dent_rev,
		siren and _siren_phase(), snappedf(fire_level(), 0.1), snappedf(altitude, 0.5), snappedf(bank, 0.02), snappedf(pitch, 0.02),
		snappedf(turret, ROT_STEP), snappedf(elevation, 0.03), snappedf(recoil, 0.1), snappedf(crushed, 0.1),
		snappedf(joints.x, 0.02), snappedf(joints.y, 0.02), snappedf(joints.z, 0.04)]


## 매 프레임 다시 그리는 모형 (위에서 보기의 레미콘 드럼). 불·연기는 위층(_fx)이 따로 그린다
func _animated() -> bool:
	return not IsoView.enabled and stats.category == &"mixer"


## 위층에 그릴 것이 있다 (불·연기·잔해 불씨, 도는 헬기 날개)
func _fx_active() -> bool:
	return _damage_fx() or _rotor_spinning()


## 불·연기·잔해 불씨
func _damage_fx() -> bool:
	if burning >= 0.0 or on_fire or health < max_health() * 0.35:
		return not wrecked or wreck_age < SMOLDER_TIME
	return wrecked and wreck_age < SMOLDER_TIME


func _draw_fx() -> void:
	if _rotor_spinning():
		_draw_rotor()
	if _damage_fx():
		_draw_damage(stats.size.x, stats.size.y)


# ── 포탑 · 무한궤도 ───────────────────────────────────────

## 포탑이 겨눈 각을 따라 돌고, 포신은 겨눈 거리만큼 든다 (가까우면 낮게, 최대 사거리면 45°)
func _aim(delta: float) -> void:
	turret = rotate_toward(turret, turret_goal, stats.turret_rate * delta)
	recoil = move_toward(recoil, 0.0, delta * 2.2)
	gun_reload = maxf(gun_reload - delta, 0.0)
	if stats.cannon_max > 0.0:
		var k := clampf((range_now() - stats.cannon_min) / maxf(stats.cannon_max - stats.cannon_min, 1.0), 0.0, 1.0)
		elevation = move_toward(elevation, lerpf(ELEV_MIN, ELEV_MAX, k), ELEV_RATE * delta)


## 도시에 한 대만 있는 차종(VehicleType.unique)이 이미 멀쩡히 있는가 (부서진 잔해는 세지 않는다)
static func exists(list: Array[Vehicle], t: VehicleType) -> bool:
	return t.unique and list.any(func(v: Vehicle): return is_instance_valid(v) and v.stats == t and not v.wrecked)


## 포가 지금 겨눈 거리 (안 정했으면 사거리 가운데)
func range_now() -> float:
	if aim_range <= 0.0:
		return (stats.cannon_min + stats.cannon_max) * 0.5
	return clampf(aim_range, stats.cannon_min, stats.cannon_max)


## 포탑 무기가 나가는 방향 (월드)
func gun_dir() -> Vector2:
	return motor.forward().rotated(turret)


## 포탄이 떨어질 곳 (포탑 방향 · 겨눈 거리)
func gun_target() -> Vector2:
	return global_position + gun_dir() * range_now()


## 포구 (포신 끝, 월드 평면)
func muzzle() -> Vector2:
	return global_position + motor.forward().rotated(turret) * stats.size.y * MUZZLE_REACH


## 깔고 넘는 차에 올라타고 내려온다. 올라탈 때는 코를 들고 내려올 때는 숙인다 (그림만)
func _ride(delta: float) -> void:
	var before := climb
	climb = move_toward(climb, climb_goal, CLIMB_RATE * delta)
	var going := signf(motor.forward_speed()) if absf(motor.forward_speed()) > 3.0 else 0.0
	pitch = move_toward(pitch, -clampf((climb - before) / delta / CLIMB_RATE, -1.0, 1.0) * going * CLIMB_PITCH, delta * 1.2)


# ── 중장비 ────────────────────────────────────────────────

## 굴삭기: 팔 끝(버킷)을 겨눈 거리에 두고, 퍼 올리는 중이면 내려찍었다가 들어 올린다. 내려찍는 순간 dug를 낸다.
## 들고 있는 차는 버킷을 따라간다. 아무도 안 몰면 팔을 접는다
func _operate(delta: float) -> void:
	var reach := arm_reach_now()
	var digging := dig >= 0.0
	var t := dig / ExcavatorArm.DIG_TIME if digging else 0.0
	var z := ExcavatorArm.dig_height(t) if digging else ExcavatorArm.CARRY_Z + (0.0 if controlled or carried else 8.0)
	var goal := ExcavatorArm.solve(reach, z)
	var rate := ARM_RATE * (4.0 if digging else 1.0)
	joints.x = move_toward(joints.x, goal.x, rate * delta)
	joints.y = move_toward(joints.y, goal.y, rate * delta)
	joints.z = move_toward(joints.z, ExcavatorArm.bucket_angle(t, digging) if not carried else -1.9, rate * delta)
	if digging:
		var before := dig
		dig += delta
		if before < ExcavatorArm.DIG_TIME * 0.5 and dig >= ExcavatorArm.DIG_TIME * 0.5:
			dug.emit(bucket_ground())
		if dig >= ExcavatorArm.DIG_TIME:
			dig = -1.0
	if carried:
		if not is_instance_valid(carried) or wrecked:
			release()
			return
		var tip := ExcavatorArm.tip(Vector2(joints.x, joints.y))
		carried.global_position = global_position + gun_dir() * tip.x
		carried.altitude = maxf(tip.y - carried.stats.height * 0.6, 0.5)
		carried.rotation = rotation + turret + PI * 0.5   # 버킷에 가로로 걸린다
		carried.motor.heading = carried.rotation
		carried.motor.velocity = Vector2.ZERO


## 굴삭기 팔이 겨눈 거리 (arm_reach 안으로 당긴다. 안 정했으면 가장 가까이)
func arm_reach_now() -> float:
	if aim_range <= 0.0:
		return stats.arm_reach.x
	return clampf(aim_range, stats.arm_reach.x, stats.arm_reach.y)


## 버킷이 내려찍는 땅 (상부 방향 · 팔 거리)
func bucket_ground() -> Vector2:
	return global_position + gun_dir() * arm_reach_now()


## 한 번 퍼 올린다 (퍼 올리는 중이면 false)
func start_dig() -> bool:
	if dig >= 0.0 or wrecked:
		return false
	dig = 0.0
	return true


## 들고 있는 차를 놓는다 — 그 자리에서 떨어진다 (Vehicle._carried_step)
func release() -> void:
	if carried and is_instance_valid(carried):
		carried.carried_by = null
		carried._fall_v = 0.0
	carried = null


## 굴삭기가 집었다: 충돌을 끄고 버킷을 따라간다 (탄 사람은 Combat이 미리 내린다)
func pick_up_by(excavator: Vehicle) -> void:
	carried_by = excavator
	excavator.carried = self
	_set_collision(0, 0)


## 들려 있거나 떨어지는 중이면 그것만 하고 true (보통 물리는 건너뛴다). 땅에 닿으면 떨어진 속도만큼 다치고 충돌을 되살린다
func _carried_step(delta: float) -> bool:
	if carried_by:
		if not is_instance_valid(carried_by):
			carried_by = null
		else:
			z_index = IsoView.Z_AIR if IsoView.enabled else 20
			return true
	if stats.flies or altitude <= 0.0 or _fall_v < 0.0:
		return false
	_fall_v += DROP_GRAVITY * delta
	altitude -= _fall_v * delta
	if altitude > 0.0:
		return true
	altitude = 0.0
	take_damage(_fall_v * DROP_DAMAGE, hit_by_player)
	dent_at(global_position + Vector2(0, stats.size.y * 0.5).rotated(rotation), _fall_v * DROP_DAMAGE)
	impacted.emit(_fall_v)
	_fall_v = -1.0
	_set_collision(Layers.VEHICLES, Layers.WORLD if stats.crusher else Layers.WORLD | Layers.VEHICLES)
	return false


## 충돌 층·마스크(땅 기준)를 정한다. 고가 위면 Layers.at으로 옮겨 넣는다.
## 값이 바뀔 때만 넣는다 (같은 값을 다시 넣으면 물리 서버가 몸체를 다시 등록해 충돌 순서가 바뀐다)
func _set_collision(layer: int, mask: int) -> void:
	_col_base = Vector2i(layer, mask)
	var l := Layers.at(layer, level)
	var m := Layers.at(mask, level)
	if collision_layer != l:
		collision_layer = l
	if collision_mask != m:
		collision_mask = m


## 자리가 정하는 고가 층으로 바꾼다 (넘는 교차로 상자 안이면 그대로)
func _track_level() -> void:
	var z := CityMap.level_zone(global_position)
	if z >= 0 and z != level:
		level = z
		_set_collision(_col_base.x, _col_base.y)


## 층이 달라 닿지 않는 자리에 있는가 (고가 위와 밑). 떠 있는 헬기도 닿지 않는다
func apart(pos: Vector2, other_level: int) -> bool:
	return airborne() or not CityMap.meet(global_position, level, pos, other_level)


# ── 헬기 ──────────────────────────────────────────────────

## 떠 있다 — 건물·차·사람과 부딪히지 않고, 교통·보행자도 피하지 않는다
func airborne() -> bool:
	return altitude > AIRBORNE_HEIGHT


## 시동이 걸려 날개가 돈다 (조종 중이거나 아직 떠 있다)
func _rotor_spinning() -> bool:
	return stats.flies and not wrecked and not rotor_off and (controlled or altitude > 0.0)


## 조종하면 날 높이까지 오르고, 내려앉는 중(landing)이거나 아무도 안 타면 내려온다.
## 땅에 닿기 직전 밑이 막혀 있으면 조종 중인 헬기는 그 높이에서 기다리고(옮기면 내려앉는다),
## 버려진 헬기는 떨어져 부서진다. 이륙 높이(LIFTOFF)에 닿기 전에는 움직이지 않는다
func _fly(delta: float) -> void:
	var goal := stats.fly_height if controlled and not landing and not wrecked else 0.0
	var next := move_toward(altitude, goal, stats.climb_rate * delta)
	if altitude > AIRBORNE_HEIGHT and next <= AIRBORNE_HEIGHT and not can_land_here():
		if controlled:
			next = AIRBORNE_HEIGHT + 0.5
			if not _blocked_told:
				_blocked_told = true
				landing_blocked.emit()
		elif not wrecked:
			_ghost = true
			take_damage(max_health(), hit_by_player, DamageModel.CHAIN_FUSE_MIN)
	elif next > AIRBORNE_HEIGHT + 1.0 or next <= 0.0:
		_blocked_told = false
	altitude = next
	if landing and altitude <= 0.0:
		landing = false
		touched_down = true
	var flying := airborne() or _ghost
	_set_collision(0 if flying else Layers.VEHICLES, 0 if flying else Layers.WORLD | Layers.VEHICLES)
	if altitude < stats.fly_height * LIFTOFF and not landing:
		throttle_input = 0.0
		steer_input = 0.0
		handbrake_input = false


## 땅에서 쏜 총알 피해 배율: 높이 뜰수록 약하다 (날 높이에서 stats.ground_fire_damage)
func ground_fire_factor() -> float:
	return lerpf(1.0, stats.ground_fire_damage, clampf(altitude / stats.fly_height, 0.0, 1.0))


## 빠르게 돌수록 도는 쪽으로 기울고(조향 × 속도), 속도를 올리는 동안 앞으로 숙인다(가속도 — 최고 속도에 닿으면 펴지고,
## 브레이크·감속이면 코를 든다). 땅에서는 수평
func _tilt(delta: float) -> void:
	var fwd := motor.forward_speed()
	var accel := (fwd - _last_fwd) / delta
	_last_fwd = fwd
	var bank_goal := 0.0
	var pitch_goal := 0.0
	if airborne() and not wrecked:
		bank_goal = motor.steer * clampf(motor.velocity.length() / stats.max_speed, 0.0, 1.0) * stats.bank_angle
		pitch_goal = clampf(accel / stats.acceleration, -1.0, 1.0) * stats.pitch_angle
	bank = move_toward(bank, bank_goal, BANK_RATE * delta)
	pitch = move_toward(pitch, pitch_goal, PITCH_RATE * delta)


## 헬기가 지금 자리에 내려앉을 수 있는가: 지도 안, 열린 땅(강물·잠긴 구역 블록이 아님), 건물·차와 겹치지 않음
func can_land_here() -> bool:
	var pos := global_position
	if not CityMap.world_rect().grow(-MAP_MARGIN).has_point(pos):
		return false
	var b := CityMap.block_at(pos)
	if City.block_rect(b.x, b.y).has_point(pos) and not CityMap.is_open_block(b):
		return false
	if CityMap.overpass_at(pos) >= 0:
		return false   # 고가차도 위·밑 (날개가 상판에 걸린다)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _shape.shape
	query.transform = global_transform
	query.collision_mask = Layers.at(Layers.WORLD | Layers.VEHICLES, level)
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


## 떠 있는 헬기는 담에 막히지 않으니 지도 밖으로 못 나가게 붙잡는다
func _keep_on_map() -> void:
	var r := CityMap.world_rect().grow(-MAP_MARGIN)
	var pos := global_position.clamp(r.position, r.end)
	if pos.x != global_position.x:
		motor.velocity.x = 0.0
	if pos.y != global_position.y:
		motor.velocity.y = 0.0
	global_position = pos


## 도는 주 회전날개: 흐린 원판과 날개 두 장 (모형의 멈춘 날개 위에 겹친다)
func _draw_rotor() -> void:
	draw_rotor(_fx, self)


## 주 회전날개 높이 (화면 px)
static func rotor_z(t: VehicleType) -> float:
	return t.height + ROTOR_ABOVE


## 도는 주 회전날개를 target(car 방향으로 돈 좌표계)에 그린다 — 경찰 헬기처럼 차 노드가 아닌 것도 쓴다
static func draw_rotor(target: CanvasItem, car: Vehicle) -> void:
	var c := Vector2(0, 0.5)
	var reach := car.stats.size.y * 0.6
	# 기울거나 숙이면 날개 원판도 모형과 같이 축(BANK_PIVOT)을 중심으로 돈다
	var up := IsoView.lift_local(1.0, car.rotation) if IsoView.enabled else Vector2.ZERO
	var center := VehicleModel.tilt(Vector3(0, 0, rotor_z(car.stats) + 0.6), BANK_PIVOT, car.bank, car.pitch)
	var ex := VehicleModel.tilt(Vector3(1, 0, 0), 0.0, car.bank, car.pitch)
	var ey := VehicleModel.tilt(Vector3(0, 1, 0), 0.0, car.bank, car.pitch)
	target.draw_set_transform_matrix(Transform2D(Vector2(ex.x, ex.y) + up * ex.z, Vector2(ey.x, ey.y) + up * ey.z,
		Vector2(center.x, center.y) + up * (center.z + car.ground + car.altitude)))
	FireFx.circle(target, c, reach, Color(0.85, 0.88, 0.92, 0.1))
	var a := Time.get_ticks_msec() / 1000.0 * 24.0
	for k in 2:
		var d := Vector2.from_angle(a + k * PI * 0.5) * reach
		target.draw_line(c - d, c + d, Color(0.08, 0.08, 0.1, 0.5), 2.4)
	target.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _move(delta: float) -> void:
	var motion := motor.velocity * delta
	for i in 2:
		var col := move_and_collide(motion)
		if col == null:
			return
		var n := col.get_normal()
		var other := col.get_collider() as Vehicle
		if other:
			_bump(other, n, col.get_position())
		else:
			var vn := motor.velocity.dot(n)
			if vn < 0.0:
				motor.velocity -= n * vn * (1.0 + RESTITUTION)
				motor.velocity *= COLLISION_FRICTION
				impacted.emit(-vn)
				var damage := DamageModel.crash_damage(-vn)
				dent_at(col.get_position(), damage)
				take_damage(damage, controlled)
		motion = col.get_remainder().slide(n)


## 차끼리 부딪히면 질량비로 양쪽에 충격량을 나눈다. 무거운 차가 덜 밀린다.
## bumped는 충격량을 나누기 전에 낸다 — 받는 쪽이 부딪히기 직전 속도로 누가 들이받았는지 판단한다.
func _bump(other: Vehicle, n: Vector2, at: Vector2) -> void:
	var vn := (motor.velocity - other.motor.velocity).dot(n)
	if vn >= 0.0:
		return
	bumped.emit(other, -vn)
	var j := -(1.0 + RESTITUTION) * vn / (1.0 / stats.mass + 1.0 / other.stats.mass)
	motor.velocity += n * j / stats.mass
	other.motor.velocity -= n * j / other.stats.mass
	impacted.emit(-vn)
	other.impacted.emit(-vn)
	# 같은 무게 차끼리 정면으로 부딪히면 벽에 절반 속도로 박은 것과 같다 — 가벼운 쪽이 더 다친다
	var by_player := controlled or other.controlled
	var total := stats.mass + other.stats.mass
	var mine := DamageModel.crash_damage(-vn * other.stats.mass / total)
	var theirs := DamageModel.crash_damage(-vn * stats.mass / total)
	dent_at(at, mine)
	other.dent_at(at, theirs)
	take_damage(mine, by_player)
	other.take_damage(theirs, by_player)


## 부딪힌 곳을 찌그러뜨린다 (그림만). at은 월드 접촉점, damage는 이번 충돌 피해.
## 접촉점을 차 가장자리로 옮기고, 가까운 곳에 이미 찌그러진 데가 있으면 그곳이 더 들어간다
func dent_at(at: Vector2, damage: float) -> void:
	if damage <= 0.0 or wrecked or stats.category in [&"bike", &"bicycle"]:
		return
	var half := stats.size * 0.5
	var p := to_local(at).clamp(-half, half)
	var k := Vector2(p.x / half.x, p.y / half.y)
	if absf(k.x) > absf(k.y):
		p.x = signf(k.x) * half.x
	else:
		p.y = signf(k.y) * half.y
	k = Vector2(p.x / half.x, p.y / half.y)
	# 모서리 가까이면 두 면 사이로 비스듬히 들어간다
	var inward := -Vector2(signf(k.x) * pow(absf(k.x), 4.0), signf(k.y) * pow(absf(k.y), 4.0)).normalized()
	var depth := damage * DamageModel.DENT_PER_DAMAGE
	_dent_rev += 1
	for d: Array in dents:
		if (d[0] as Vector2).distance_to(p) < DamageModel.DENT_RADIUS:
			d[2] = minf(d[2] + depth, DamageModel.DENT_MAX)
			return
	dents.append([p, inward, minf(depth, DamageModel.DENT_MAX)])
	if dents.size() > DamageModel.MAX_DENTS:
		dents.sort_custom(func(a: Array, b: Array) -> bool: return a[2] > b[2])
		dents.pop_back()


## 피해를 입는다. 체력이 0이 되면 불이 붙고 fuse초 뒤 터진다 (이미 불타면 더 빨리 터질 뿐).
func take_damage(amount: float, by_player: bool, fuse := DamageModel.BURN_TIME) -> void:
	if wrecked or amount <= 0.0:
		return
	hit_by_player = by_player
	health = maxf(health - amount, 0.0)
	if health > 0.0:
		if health <= max_health() * DamageModel.FIRE_HEALTH:
			on_fire = true
		return
	if burning < 0.0:
		burning = fuse
		caught_fire.emit()
	else:
		burning = minf(burning, fuse)


func _explode() -> void:
	burning = -1.0
	on_fire = false
	wrecked = true
	has_driver = false
	siren = false
	queue_redraw()
	exploded.emit(hit_by_player)


func occupied() -> bool:
	return not wrecked and (controlled or has_driver)


## 최대 체력 (부업 보너스 포함)
func max_health() -> float:
	return stats.durability * durability_bonus.get(stats.category, 1.0)


## 사람이 탈 수 있는 차인지 (불타거나 터진 차는 안 된다)
func usable() -> bool:
	return not wrecked and burning < 0.0 and stats.enterable


## 운전석(왼쪽) 또는 조수석 문 바깥 지점
func door_position(passenger: bool) -> Vector2:
	var side := 1.0 if passenger else -1.0
	return to_global(Vector2(side * (stats.size.x * 0.5 + 12.0), -stats.size.y * 0.08))


func follow_velocity() -> Vector2:
	return motor.velocity


func zoom_ratio() -> float:
	var k := clampf(speed() / stats.max_speed, 0.0, 1.0)
	if stats.flies:
		k = maxf(k, 0.45 * clampf(altitude / stats.fly_height, 0.0, 1.0))   # 높이 뜨면 조금 멀리 본다
	return k


func speed() -> float:
	return motor.velocity.length()


func is_braking() -> bool:
	return throttle_input < 0.0 and motor.forward_speed() > 10.0


func is_skidding() -> bool:
	if stats.flies:
		return false   # 바퀴가 없다
	return absf(motor.lateral_speed()) > SKID_LATERAL_SPEED \
		or (handbrake_input and speed() > 80.0) \
		or (is_braking() and motor.forward_speed() > stats.max_speed * 0.6)


func rear_wheel_positions() -> Array[Vector2]:
	var x := stats.size.x * 0.36
	var y := stats.size.y * 0.32
	return [to_global(Vector2(-x, y)), to_global(Vector2(x, y))]


func _draw() -> void:
	var w := stats.size.x
	var h := stats.size.y
	var top := -h * 0.5
	var left := -w * 0.5
	if IsoView.enabled:
		_draw_iso(w, h)
		return
	if wrecked:
		_draw_wreck(w, h)
		return

	# 헤드라이트 빛 (밤 분위기) — 사람이 타 있을 때만 켠다 (헬기는 없다)
	if occupied() and not stats.flies:
		draw_colored_polygon(PackedVector2Array([
			Vector2(left + 4, top), Vector2(-w * 1.6, top - h * 1.6),
			Vector2(w * 1.6, top - h * 1.6), Vector2(-left - 4, top)]),
			Color(1.0, 0.95, 0.7, 0.07))
	# 그림자 (떠 있는 헬기는 높을수록 멀리 떨어진다)
	draw_rect(Rect2(Vector2(left + 3, top + 4) + Vector2(1, 1).rotated(-rotation) * altitude * 0.3, Vector2(w, h)), Color(0, 0, 0, 0.35))
	if stats.category == &"bike":
		_draw_bike(w, h)
		return
	if stats.category == &"bicycle":
		_draw_bicycle(w, h)
		return
	# 바퀴
	for r in _wheels(w, h):
		draw_rect(r, Color(0.08, 0.08, 0.09))
	_draw_body(w, h)


func _wheels(w: float, h: float) -> Array[Rect2]:
	var wheel := Vector2(6, 12)
	var out: Array[Rect2] = []
	for sx in [-1.0, 1.0]:
		for wy in [-h * 0.5 + h * 0.12, -h * 0.5 + h * 0.70]:
			out.append(Rect2(Vector2(sx * (w * 0.5 + 1) - wheel.x * 0.5, wy), wheel))
	return out


## 위에서 본 차체 (2.5D에서는 지붕 높이로 올려 같은 그림을 쓴다)
func _draw_body(w: float, h: float) -> void:
	var top := -h * 0.5
	var left := -w * 0.5
	var body := Rect2(left, top, w, h)
	var glass := Color(0.12, 0.17, 0.26)
	if stats.category == &"bus":
		draw_rect(body, paint)
		draw_rect(Rect2(left + 3, top + 4, w - 6, h * 0.06), glass)
		var roof := Rect2(left + 4, top + h * 0.12, w - 8, h * 0.84)
		draw_rect(roof, stats.roof_color)
		for i in 3:
			draw_rect(Rect2(left + 8, roof.position.y + 10 + i * h * 0.27, w - 16, h * 0.12), stats.roof_color.darkened(0.15))
		draw_rect(Rect2(left + 1, top + h * 0.15, 3, h * 0.8), glass)
		draw_rect(Rect2(-left - 4, top + h * 0.15, 3, h * 0.8), glass)
	elif stats.category in TRUCKS:
		# 앞쪽은 캡, 나머지는 차종마다 다른 짐칸
		var cab_h := minf(h * 0.32, 26.0) if stats.category != &"truck" else h * 0.32
		draw_rect(Rect2(left, top, w, cab_h), paint)
		draw_rect(Rect2(left + 3, top + cab_h * 0.22, w - 6, cab_h * 0.28), glass)
		draw_rect(Rect2(left + 3, top + cab_h * 0.55, w - 6, cab_h * 0.38), stats.roof_color if stats.category == &"truck" else paint.darkened(0.15))
		var bed := Rect2(left, top + cab_h + 2, w, h - cab_h - 2)
		_draw_truck_bed(bed, w)
	elif stats.category == &"camper":
		# 캠핑카: 큰 상자형 차체, 지붕 창과 차양
		draw_rect(body, paint)
		draw_rect(Rect2(left + 3, top + h * 0.06, w - 6, h * 0.1), glass)
		var roof := Rect2(left + 3, top + h * 0.2, w - 6, h * 0.76)
		draw_rect(roof, paint.lightened(0.05))
		draw_rect(Rect2(left, top + h * 0.45, w, h * 0.07), stats.roof_color)
		draw_rect(Rect2(left + 8, top + h * 0.6, w - 16, h * 0.14), glass.lightened(0.2))
		draw_rect(Rect2(-left - 2, top + h * 0.3, 4, h * 0.5), Color(0.9, 0.5, 0.2))
	elif stats.category == &"ambulance" or stats.category == &"swat":
		# 승합형: 짧은 보닛, 긴 상자 지붕
		draw_rect(body, paint)
		draw_rect(Rect2(left + 3, top + h * 0.1, w - 6, h * 0.12), glass)
		var roof := Rect2(left + 3, top + h * 0.25, w - 6, h * 0.71)
		draw_rect(roof, paint.lightened(0.06))
		if stats.category == &"ambulance":
			draw_rect(Rect2(left, top + h * 0.5, w, h * 0.08), stats.roof_color)
			var c := roof.get_center()
			draw_rect(Rect2(c - Vector2(3, 9), Vector2(6, 18)), Color(0.9, 0.12, 0.15))
			draw_rect(Rect2(c - Vector2(9, 3), Vector2(18, 6)), Color(0.9, 0.12, 0.15))
		else:
			for i in 4:
				draw_line(Vector2(left + 6, roof.position.y + 8 + i * roof.size.y / 4.0),
					Vector2(-left - 6, roof.position.y + 8 + i * roof.size.y / 4.0), paint.darkened(0.3), 2.0)
			draw_rect(Rect2(left + 1, top + h * 0.3, 3, h * 0.6), Color(0.85, 0.85, 0.9, 0.7))
			draw_rect(Rect2(-left - 4, top + h * 0.3, 3, h * 0.6), Color(0.85, 0.85, 0.9, 0.7))
		_draw_lightbar(w, top + h * 0.26)
	else:
		draw_rect(body, paint)
		if stats.category == &"police":
			# 옆구리 파란 띠 + 노란 줄 (가상의 경찰차 도색)
			draw_rect(Rect2(left, top + h * 0.40, w, h * 0.22), stats.roof_color)
			draw_rect(Rect2(left, top + h * 0.62, w, h * 0.04), Color(0.95, 0.8, 0.15))
		draw_rect(Rect2(left + 4, top + h * 0.22, w - 8, h * 0.15), glass)
		draw_rect(Rect2(left + 4, top + h * 0.37, w - 8, h * 0.30), stats.roof_color)
		draw_rect(Rect2(left + 4, top + h * 0.67, w - 8, h * 0.10), glass)
		if stats.category == &"police":
			_draw_lightbar(w, top + h * 0.44)
		elif stats.category == &"suv":
			# 지붕 짐받이
			for x in [left + 7, -left - 7]:
				draw_line(Vector2(x, top + h * 0.38), Vector2(x, top + h * 0.66), paint.darkened(0.5), 2.0)
		elif stats.category == &"taxi":
			var lamp := Rect2(-7, top + h * 0.47, 14, 7)
			draw_rect(lamp, Color(1.0, 0.92, 0.4))
			draw_rect(lamp, Color(0.3, 0.2, 0.05), false, 1.0)
		elif stats.category == &"sport":
			# 보닛부터 트렁크까지 두 줄 스트라이프
			for x in [-4.0, 2.0]:
				draw_rect(Rect2(x, top + 2, 2, h * 0.2), Color(1, 1, 1, 0.8))
				draw_rect(Rect2(x, top + h * 0.78, 2, h * 0.2), Color(1, 1, 1, 0.8))
	draw_rect(body, paint.darkened(0.45), false, 2.0)
	if occupied() and stats.category != &"bus":
		draw_circle(Vector2(-w * 0.18, top + h * 0.33), 4.5, Color(0.06, 0.05, 0.05))

	# 전조등 · 후미등
	var head := Color(1.0, 0.95, 0.65)
	draw_rect(Rect2(left + 2, top + 1, 6, 3), head)
	draw_rect(Rect2(-left - 8, top + 1, 6, 3), head)
	var tail := Color(1.0, 0.15, 0.2) if is_braking() else Color(0.6, 0.05, 0.08)
	if motor.forward_speed() < -5.0:
		tail = Color(0.95, 0.95, 0.95)
	draw_rect(Rect2(left + 2, -top - 4, 6, 3), tail)
	draw_rect(Rect2(-left - 8, -top - 4, 6, 3), tail)
	if siren:
		# 경광등 불빛이 바닥에 번진다
		var red := _siren_phase()
		draw_circle(Vector2(0, top + h * 0.47), w * 1.3, Color(1.0, 0.1, 0.15, 0.10) if red else Color(0.15, 0.35, 1.0, 0.12))
	if ai and ai.honking and not IsoView.enabled:
		draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
		draw_string(ThemeDB.fallback_font, Vector2(-20, -h * 0.5 - 10), "빵!",
			HORIZONTAL_ALIGNMENT_CENTER, 40, 16, Color(1.0, 0.9, 0.3))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ── 2.5D ──────────────────────────────────────────────────
## 바닥에 그림자·전조등 빛, 그 위에 차종별 입체 모형(VehicleModel, docs/12의 참고 그림을 보고 만든 것).

func _draw_iso(w: float, h: float) -> void:
	var top := -h * 0.5
	var left := -w * 0.5
	var two_wheel := stats.category in [&"bike", &"bicycle"]
	# 떠 있는 헬기: 그림자는 땅에, 모형은 떠 있는 높이에 그린다 (높을수록 그림자가 옅다)
	if altitude > 0.5:
		draw_set_transform(IsoView.lift_local(ground, rotation), 0.0, Vector2.ONE)
		var fade := 1.0 - 0.6 * clampf(altitude / stats.fly_height, 0.0, 1.0)
		FireFx.circle(self, Vector2(0, 0.5), stats.size.y * 0.6, Color(0, 0, 0, 0.22 * fade))
		draw_rect(Rect2(left - 2, top - 2, w + 4, h + 4), Color(0, 0, 0, 0.35 * fade))
	# 다리 위면 그 높이에서부터 그린다 (전조등 빛·그림자·모형 모두)
	_lift(0.0)
	if beam and occupied() and not wrecked and not two_wheel and not stats.flies:
		draw_colored_polygon(PackedVector2Array([
			Vector2(left + 4, top), Vector2(-w * 1.6, top - h * 1.6),
			Vector2(w * 1.6, top - h * 1.6), Vector2(-left - 4, top)]),
			Color(1.0, 0.95, 0.7, 0.07))
	if altitude <= 0.5:
		draw_rect(Rect2(left - 2, top - 2, w + 4, h + 4), Color(0, 0, 0, 0.35))
	# 차종별 입체 모형 (VehicleModel). 터진 차는 같은 모형을 그을려 그린다
	VehicleModel.draw(self, self)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if ai and ai.honking:
		draw_set_transform_matrix(_screen_local(stats.height + 14.0))
		draw_string(ThemeDB.fallback_font, Vector2(-20, 0), "빵!", HORIZONTAL_ALIGNMENT_CENTER, 40, 16, Color(1.0, 0.9, 0.3))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 노드가 회전해 있으므로, 높이 오프셋도 노드 좌표로 돌려 둔다
func _lift(height: float) -> void:
	draw_set_transform(IsoView.lift_local(height + ground + altitude, rotation), 0.0, Vector2.ONE)


## 화면 기준 좌표계 (회전한 노드 안에서): 차 위 글자를 세워 쓴다
func _screen_local(height: float) -> Transform2D:
	return Transform2D(-rotation, Vector2.ZERO) * IsoView.screen_frame(Vector2.ZERO, height + ground + altitude)


const TRUCKS := [&"truck", &"tanker", &"garbage", &"mixer", &"fire", &"tow", &"bigtruck", &"army"]


## 트럭 짐칸: 화물칸·탱크·청소 상자·믹서 드럼·소방 사다리·견인 크레인·컨테이너
func _draw_truck_bed(bed: Rect2, w: float) -> void:
	var left := bed.position.x
	match stats.category:
		&"tanker":
			draw_rect(bed.grow(-1), stats.body_color)
			draw_rect(Rect2(left + 3, bed.position.y + 3, w - 6, bed.size.y - 6), stats.body_color.darkened(0.08))
			draw_rect(Rect2(left, bed.get_center().y - 6, w, 12), stats.roof_color)
			draw_string(ThemeDB.fallback_font, Vector2(left, bed.get_center().y + 4), "SR", HORIZONTAL_ALIGNMENT_CENTER, w, 10, Color.WHITE)
			for k in 3:
				draw_circle(Vector2(0, bed.position.y + 10 + k * bed.size.y * 0.33), 3.0, Color(0.4, 0.4, 0.42))
		&"garbage":
			draw_rect(bed, paint)
			draw_rect(Rect2(left + 3, bed.position.y + 3, w - 6, bed.size.y * 0.7), paint.lightened(0.1))
			draw_rect(Rect2(left, bed.end.y - bed.size.y * 0.22, w, bed.size.y * 0.22), Color(0.3, 0.3, 0.32))
			draw_line(Vector2(left + 2, bed.get_center().y), Vector2(-left - 2, bed.get_center().y), paint.darkened(0.3), 2.0)
		&"mixer":
			draw_rect(bed, Color(0.4, 0.4, 0.42))
			var drum := Rect2(left + 3, bed.position.y + 4, w - 6, bed.size.y - 10)
			draw_rect(drum, stats.roof_color)
			var t := Time.get_ticks_msec() / 400.0
			for k in 5:
				var y := drum.position.y + fposmod(k * drum.size.y / 5.0 + t * 6.0, drum.size.y)
				draw_line(Vector2(drum.position.x, y), Vector2(drum.end.x, y - 6), stats.roof_color.darkened(0.3), 3.0)
		&"fire":
			draw_rect(bed, paint)
			draw_rect(Rect2(left + 6, bed.position.y + 4, w - 12, bed.size.y - 8), Color(0.75, 0.75, 0.78))
			var y := bed.position.y + 8
			while y < bed.end.y - 6:
				draw_line(Vector2(left + 8, y), Vector2(-left - 8, y), Color(0.5, 0.5, 0.52), 2.0)
				y += 7
			draw_circle(Vector2(0, bed.position.y + 6), 5.0, Color(0.85, 0.85, 0.2))
			_draw_lightbar(w, bed.position.y - 6)
		&"tow":
			draw_rect(bed, Color(0.3, 0.3, 0.32))
			draw_line(Vector2(0, bed.position.y + 4), Vector2(0, bed.end.y + 6), stats.body_color, 5.0)
			draw_line(Vector2(-6, bed.end.y + 2), Vector2(6, bed.end.y + 2), Color(0.15, 0.15, 0.16), 3.0)
			draw_rect(Rect2(-w * 0.5 + 4, bed.position.y - 4, w - 8, 4), Color(1.0, 0.6, 0.1))
		&"army":
			# 국방색 천막 짐칸과 늑골
			draw_rect(bed, stats.roof_color)
			for k in range(1, 6):
				var y := bed.position.y + bed.size.y * k / 6.0
				draw_line(Vector2(left + 2, y), Vector2(-left - 2, y), stats.roof_color.darkened(0.3), 2.0)
			draw_rect(bed, stats.body_color.darkened(0.4), false, 2.0)
			draw_string(ThemeDB.fallback_font, Vector2(left, bed.get_center().y + 5), "★", HORIZONTAL_ALIGNMENT_CENTER, w, 14, Color(0.95, 0.9, 0.6, 0.8))
		&"bigtruck":
			draw_rect(bed, stats.roof_color)
			for k in range(1, 8):
				var x := left + w * k / 8.0
				draw_line(Vector2(x, bed.position.y + 2), Vector2(x, bed.end.y - 2), stats.roof_color.darkened(0.25), 2.0)
			draw_rect(bed, stats.roof_color.darkened(0.45), false, 2.0)
		_:
			draw_rect(bed, Color(0.42, 0.44, 0.48))
			for i in range(1, 5):
				var y := bed.position.y + bed.size.y * i / 5.0
				draw_line(Vector2(left + 2, y), Vector2(-left - 2, y), Color(0.32, 0.33, 0.37), 2.0)
			draw_rect(bed, Color(0.25, 0.26, 0.29), false, 2.0)


## 자전거: 가는 몸체와 두 바퀴, 탄 사람
func _draw_bicycle(w: float, h: float) -> void:
	var top := -h * 0.5
	draw_rect(Rect2(-1.5, top, 3, 8), Color(0.08, 0.08, 0.09))
	draw_rect(Rect2(-1.5, -top - 8, 3, 8), Color(0.08, 0.08, 0.09))
	draw_line(Vector2(0, top + 6), Vector2(0, -top - 6), paint, 3.0)
	draw_line(Vector2(-w * 0.6, top + 7), Vector2(w * 0.6, top + 7), Color(0.2, 0.2, 0.22), 2.0)
	if occupied():
		draw_circle(Vector2(0, top + h * 0.45), 4.5, Color(0.3, 0.6, 0.9))
		draw_circle(Vector2(0, top + h * 0.4), 2.5, Color(0.08, 0.07, 0.07))


## 오토바이: 앞뒤 바퀴, 몸통, 배달 상자, 탄 사람(헬멧)
func _draw_bike(w: float, h: float) -> void:
	var top := -h * 0.5
	if occupied():
		draw_colored_polygon(PackedVector2Array([Vector2(-3, top), Vector2(-w * 2.5, top - h * 1.4),
			Vector2(w * 2.5, top - h * 1.4), Vector2(3, top)]), Color(1.0, 0.95, 0.7, 0.07))
	draw_rect(Rect2(-w * 0.5 + 2, top + 3, w, h), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(-2.5, top, 5, 9), Color(0.08, 0.08, 0.09))
	draw_rect(Rect2(-2.5, -top - 9, 5, 9), Color(0.08, 0.08, 0.09))
	draw_rect(Rect2(-w * 0.32, top + 6, w * 0.64, h - 14), paint)
	draw_line(Vector2(-w * 0.75, top + 8), Vector2(w * 0.75, top + 8), Color(0.2, 0.2, 0.22), 2.0)
	draw_rect(Rect2(-w * 0.55, top + h * 0.62, w * 1.1, h * 0.34), stats.roof_color)
	draw_rect(Rect2(-w * 0.55, top + h * 0.62, w * 1.1, h * 0.34), Color(0.3, 0.3, 0.32), false, 1.0)
	if occupied():
		draw_circle(Vector2(0, top + h * 0.42), 5.0, Color(0.95, 0.95, 0.95))
		draw_circle(Vector2(0, top + h * 0.38), 2.5, Color(0.1, 0.1, 0.12))
	draw_rect(Rect2(-2, top, 4, 2), Color(1.0, 0.95, 0.65))
	draw_rect(Rect2(-2, -top - 2, 4, 2), Color(1.0, 0.15, 0.2) if is_braking() else Color(0.6, 0.05, 0.08))


## 빨강·파랑 교차 0.25초 (docs/06)
func _siren_phase() -> bool:
	return (Time.get_ticks_msec() / 250) % 2 == 0


## 지붕 경광등: 왼쪽 빨강 · 오른쪽 파랑. 사이렌이 켜지면 번갈아 깜빡인다.
func _draw_lightbar(w: float, y: float) -> void:
	var half := w * 0.5 - 5.0
	var red_on := siren and _siren_phase()
	var blue_on := siren and not _siren_phase()
	draw_rect(Rect2(-half, y, half, 5), Color(1.0, 0.15, 0.2) if red_on else Color(0.45, 0.08, 0.1))
	draw_rect(Rect2(0, y, half, 5), Color(0.25, 0.5, 1.0) if blue_on else Color(0.08, 0.12, 0.4))


## 터진 잔해: 시커멓게 그을린 차체와 빈 창틀, 남은 불씨
func _draw_wreck(w: float, h: float) -> void:
	var body := Rect2(-w * 0.5, -h * 0.5, w, h)
	draw_rect(Rect2(body.position + Vector2(3, 4), body.size), Color(0, 0, 0, 0.35))
	draw_rect(body, Color(0.11, 0.1, 0.1))
	draw_rect(body.grow(-4), Color(0.2, 0.17, 0.15), false, 2.0)
	draw_rect(Rect2(-w * 0.5 + 4, -h * 0.28, w - 8, h * 0.5), Color(0.05, 0.05, 0.05))


## 화재 단계 (참고 그림 5단계): 많이 부서지면 회색 연기 → 불나면(체력 20% 아래) 보닛에서 작은 불과 검은 연기,
## 체력이 타들어갈수록 불이 차 뒤로 번지고 커진다 → 체력 0(burning)이면 차 전체가 타오른다 → 터진 잔해는 불씨·연기가 사그라든다.
## 불빛은 바닥에, 불꽃·연기·불씨는 화면 기준으로 세워 그린다 (FireFx)
func _draw_damage(w: float, h: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var seed := float(get_instance_id() % 97)
	var level := fire_level()
	var z := stats.height if IsoView.enabled else 0.0
	var sc := clampf(w / 26.0, 0.7, 1.6)
	var hood := Vector2(0, -h * 0.3)
	if wrecked:
		_draw_smolder(w, h, t, seed, z, sc)
		return
	if level <= 0.0:
		if health < max_health() * 0.35:
			# 부서진 차: 보닛에서 회색 연기 (체력이 낮을수록 짙다)
			var dark := 1.0 - health / (max_health() * 0.35)
			_fx.draw_set_transform_matrix(_fx_frame())
			FireFx.smoke(_fx, _fx_pt(hood, z * 0.8), t, 0.55 * sc, 0.2 + 0.5 * dark, 0.5 + 0.4 * dark, seed, 4)
			_fx.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var blaze := level > 1.0
	var k := minf(level, 1.0)
	# 바닥 불빛
	_fx.draw_set_transform(IsoView.lift_local(ground, rotation), 0.0, Vector2.ONE)
	FireFx.glow(_fx, hood.lerp(Vector2.ZERO, k), w * (2.2 if blaze else 1.0 + 1.0 * k), 1.6 if blaze else 0.7 + 0.7 * k, t, seed)
	_fx.draw_set_transform_matrix(_fx_frame())
	# 연기는 불꽃 뒤에서 솟는다
	var top := _fx_pt(hood.lerp(Vector2.ZERO, k * 0.5), z) + Vector2(0, -8.0 * sc)
	FireFx.smoke(_fx, top, t, (1.5 if blaze else 0.75 + 0.5 * k) * sc, 1.0, 1.0, seed, 6 if blaze else 5)
	if blaze:
		FireFx.smoke(_fx, _fx_pt(Vector2(0, h * 0.2), z) + Vector2(0, -10.0 * sc), t + 0.4, 1.1 * sc, 0.9, 0.8, seed + 3.0, 4)
	# 불꽃: 보닛부터 뒤로 번진다 (화면 위쪽 — 먼 것부터 그린다)
	var spots: Array = []
	var n := FIRE_SPOTS.size() if blaze else 1 + int(k * 3.99)
	for i in n:
		var s: Vector3 = FIRE_SPOTS[i]
		var size: float
		if blaze:
			size = (17.0 + (6.0 if i % 3 == 0 else 0.0)) * sc
		else:
			size = (6.0 + 12.0 * k) * sc * (1.0 - 0.12 * i)
		spots.append([_fx_pt(Vector2(s.x * w, s.y * h), s.z * z), size, i])
	spots.sort_custom(func(a: Array, b: Array): return a[0].y < b[0].y)
	for sp: Array in spots:
		FireFx.flame(_fx, sp[0], sp[1], t, seed + sp[2] * 1.7)
	if blaze or k > 0.35:
		FireFx.embers(_fx, top + Vector2(0, 2.0 * sc), t, 10 if blaze else 4, w * (0.6 if blaze else 0.3), 50.0 * sc, seed)
	_fx.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 불이 번지는 자리: (로컬 x 비율, 로컬 y 비율, 차 높이 비율). 앞(보닛)부터 뒤로
const FIRE_SPOTS := [Vector3(0.0, -0.3, 0.75), Vector3(-0.22, -0.16, 0.85), Vector3(0.22, -0.08, 0.92),
	Vector3(0.0, 0.04, 1.0), Vector3(-0.2, 0.18, 0.95), Vector3(0.2, 0.26, 0.85), Vector3(0.0, 0.36, 0.75)]


## 0: 불 없음, 0~1: 불난 차(체력 20% 아래)가 타들어간 정도, 2: 체력 0 — 차 전체가 타오른다
func fire_level() -> float:
	if wrecked:
		return 0.0
	if burning >= 0.0:
		return 2.0
	if on_fire:
		return clampf(1.0 - health / (max_health() * DamageModel.FIRE_HEALTH), 0.05, 1.0)
	return 0.0


## 터진 잔해: 처음 몇 초는 작은 불꽃이 남고, 차체 곳곳의 불씨가 깜박이며 가는 연기가 사그라든다
func _draw_smolder(w: float, h: float, t: float, seed: float, z: float, sc: float) -> void:
	if wreck_age >= SMOLDER_TIME:
		return
	var fade := 1.0 - wreck_age / SMOLDER_TIME
	var flames := clampf(1.0 - wreck_age / WRECK_FLAME_TIME, 0.0, 1.0)
	_fx.draw_set_transform(IsoView.lift_local(ground, rotation), 0.0, Vector2.ONE)
	if flames > 0.0:
		FireFx.glow(_fx, Vector2.ZERO, w * 1.6, flames, t, seed)
	_fx.draw_set_transform_matrix(_fx_frame())
	FireFx.smoke(_fx, _fx_pt(Vector2.ZERO, z), t, (0.6 + 0.6 * flames) * sc, 0.7, 0.35 + 0.5 * fade, seed, 4)
	# 차체에 남은 불씨 (주황 점이 숨 쉬듯 밝아졌다 어두워진다)
	for i in FIRE_SPOTS.size():
		var s: Vector3 = FIRE_SPOTS[i]
		var p := _fx_pt(Vector2(s.x * w * 1.3, s.y * h * 1.1), s.z * z * 0.9)
		var pulse := 0.5 + 0.5 * sin(t * (2.0 + i * 0.4) + i * 1.9)
		_fx.draw_rect(Rect2(p - Vector2(1.5, 1.0), Vector2(3.0, 2.0)), Color(FireFx.MID.lerp(FireFx.OUTER, pulse), (0.5 + 0.5 * pulse) * fade))
	if flames > 0.0:
		for i in 3:
			var s: Vector3 = FIRE_SPOTS[i * 3]
			FireFx.flame(_fx, _fx_pt(Vector2(s.x * w, s.y * h), s.z * z), 11.0 * sc * flames, t, seed + i * 2.1)
		FireFx.embers(_fx, _fx_pt(Vector2.ZERO, z), t, 5, w * 0.4, 36.0 * sc, seed, flames)
	_fx.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 불꽃·연기를 세워 그리는 화면 기준 좌표계 (차 가운데 바닥이 원점, y가 화면 위로 음수)
func _fx_frame() -> Transform2D:
	return _screen_local(0.0) if IsoView.enabled else Transform2D(-rotation, Vector2.ZERO)


## 차 위 한 점(로컬 l, 높이 z)이 _fx_frame() 안에서 놓이는 자리
func _fx_pt(l: Vector2, z: float) -> Vector2:
	if IsoView.enabled:
		return IsoView.BASIS.basis_xform(l.rotated(rotation)) + Vector2(0, -z)
	return l.rotated(rotation)
