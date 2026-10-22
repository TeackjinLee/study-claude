class_name PoliceDispatcher
extends Node2D
## 경찰 전체: 순찰차 유지, 범죄 목격, 별 단계별 추격차 배치, 하차 도보 추격, 체포, ★3 도로 봉쇄,
## ★4 특공대·다리 검문소, ★5 경찰 헬기(탐조등·기관총), ★6 군 트럭·군인.
##
## 경찰차 한 대는 셋 중 하나다:
##   순찰 — TrafficAI로 일반 차처럼 달린다 (★0). 범죄를 보면 신고한다.
##   추격 — PursuitAI가 주인공을 쫓는다. 가까이서 멈추면 경찰이 내려 뛰어간다(그동안 차는 빈 차).
##   봉쇄 — ★3에서 도로를 가로질러 세워 둔 빈 차.
## 주인공이 경찰차를 빼앗거나 경찰차에 불이 붙으면 그 차는 경찰 것이 아니다(cars에서 빠진다).
## ★2부터 도보 경찰은 주인공을 쫓으며 총을 쏜다 (차는 느리거나 멈췄을 때만).

signal busted(fine: int)
signal crime_witnessed(crime: WantedSystem.Crime, raised: bool)

const POLICE_TYPE: VehicleType = preload("res://data/vehicles/police_patrol.tres")
const OFFICER_TYPE: NpcType = preload("res://data/npc/police.tres")
const SWAT_TYPE: VehicleType = preload("res://data/vehicles/sp_swat.tres")
const SWAT_NPC: NpcType = preload("res://data/npc/swat.tres")
const ARMY_TYPE: VehicleType = preload("res://data/vehicles/sp_army.tres")
const SOLDIER_NPC: NpcType = preload("res://data/npc/soldier.tres")
const HELI_NPC: NpcType = preload("res://data/npc/police_heli.tres")
const PARAMEDIC_NPC: NpcType = preload("res://data/npc/paramedic.tres")   ## 기절시키면 바로 ★4
const ARMY_HELI_TYPE: VehicleType = preload("res://data/vehicles/army_heli.tres")   ## ★6: 헬기 한 대는 군 기동헬기
const SPG_TYPE: VehicleType = preload("res://data/vehicles/army_spg.tres")           ## ★6: 자주포 (포탑을 돌려 곡사포를 쏜다)
const JEEP_TYPE: VehicleType = preload("res://data/vehicles/army_jeep.tres")         ## ★6: 소형 전술차량 (군인 둘)
const TANK_CANNON: WeaponType = preload("res://data/weapons/tank_cannon.tres")
const SEED := 112
const PATROL_COUNT := 3
const PURSUERS: Array[int] = [0, 1, 3, 4, 5, 5, 6]   ## 별마다 추격차 수 (★4부터 그중 SWAT_VANS대가 특공대, ★6은 ARMY_TRUCKS대가 군 트럭)
const CREW: Array[int] = [0, 1, 2, 2, 2, 2, 2]       ## 별마다 경찰차에서 내리는 경찰 수
const HELIS: Array[int] = [0, 0, 0, 0, 0, 1, 2]      ## 별마다 경찰 헬기 수
const ARMY_LEVEL := 6
const ARMY_TRUCKS := 2
const ARMY_CREW := 4
const ARMY_SPGS := 1
const ARMY_JEEPS := 1
const JEEP_CREW := 2
const SPG_RELOAD := 3.0          ## 자주포 AI는 포 연사 간격의 이 배마다 쏜다 (주인공 손보다 느리게)
const SPG_SPREAD := 90.0         ## 자주포 AI 포탄이 주인공에게서 빗나가는 거리 (최대 px)
const SPG_AIMED := 0.08          ## 포탑이 이만큼(rad) 안으로 돌아와야 쏜다
const CHECKPOINT_LEVEL := 4                    ## 이 별부터 다리 끝에 검문소가 선다 (docs/01 §4)
const CHECKPOINT_RANGE := [700.0, 4000.0]      ## 주인공에게서 이 거리 사이의 다리 끝에만 세운다
const CHECKPOINT_ONTO := 150.0                 ## 다리 위로 이만큼 들어가서 세운다
const HELI_SPAWN := 1800.0
const SWAT_LEVEL := 4                          ## 이 별부터 특공대 차량이 온다
const SWAT_VANS := 2
const SWAT_CREW := 4                           ## 특공대 차량에서 내리는 대원 수 (4인 1조)
const SIGHT := 650.0                           ## 경찰 눈에 띄는 거리
const SPAWN_MIN := 1000.0                      ## 새 경찰차는 주인공에게서 이만큼 떨어진 도로에 나타난다
const SPAWN_MAX := 1700.0
const OFFSCREEN := 950.0                       ## 카메라에서 이보다 멀면 화면 밖으로 본다
const UPKEEP_INTERVAL := 1.0
const CONVERT_RANGE := 2600.0                  ## 이 안의 순찰차가 먼저 추격에 나선다
const SEARCH_REACH := 150.0
const DEPLOY_RANGE := 200.0                    ## 도보 주인공이 이 안에 보이면 차를 세우고 내린다
const CAR_DEPLOY_RANGE := 170.0
const CAR_BUST_SPEED := 40.0                   ## 주인공 차가 이보다 느리면 문을 열고 끌어낸다
const DOOR_REACH := 26.0
const BEAT_RANGE := 18.0                       ## 도보 경찰이 이만큼 붙으면 곤봉으로 때린다
const BEAT_WINDUP := 0.3                       ## 손이 닿고 첫 매까지
const BEAT_INTERVAL := 0.8                     ## 경찰 한 명이 다시 휘두르기까지
const BEAT_DAMAGE := 13.0
const BEAT_STUN := 0.4                         ## 맞으면 이만큼 못 움직인다 (그사이 경찰이 따라붙는다)
const BUST_HEALTH := 35.0                      ## 맞아서 체력이 이 아래가 되면 쓰러져 체포된다 (매로는 죽지 않는다)
const BUST_FALL_TIME := 1.2                    ## 쓰러지고 체포 화면까지
const CAR_ARREST_TIME := 0.8                   ## 차 문을 열고 끌어내리는 데 걸리는 시간 (끌려 나오면 도보처럼 맞는다)
const CAR_PULL_STUN := 0.7                     ## 차에서 끌려 나와 이만큼 못 움직인다
const CAR_STOP_BEFORE_DEPLOY := 1.0            ## 주인공 차가 이만큼 서 있어야 경찰이 내린다
const FOOT_GIVE_UP := 650.0                    ## 도보 경찰이 이보다 멀어지면 차로 돌아간다
const CAR_ESCAPE_SPEED := 150.0                ## 주인공이 이보다 빨리 차로 달아나면 경찰은 차로 돌아간다
const FINE_PER_STAR := 50000
const RAM_SPEED := 120.0
const RAM_TARGET_SPEED := 150.0                ## ★2부터 이보다 빨리 달아나는 차는 들이받는다
const RAM_COOLDOWN := 2.0
const STUCK_LIMIT := 4                         ## 이만큼 갇혔던 추격차는 화면 밖에서 치운다
const ROADBLOCK_INTERVAL := 12.0
const ROADBLOCK_LIFETIME := 45.0
const ROADBLOCK_MIN_AHEAD := 1100.0
const ROADBLOCK_PAST_BOX := 380.0              ## 교차로 상자에서 이만큼 지난 구간 가운데쯤 — 보고 나서 앞 교차로에서 꺾을 여유
const MAX_ROADBLOCKS := 2
const SHOOT_LEVEL := 2                         ## 이 별부터 도보 경찰이 발포한다
const SHOOT_RANGE := 340.0
const SHOOT_DELAY := [1.0, 1.6]                ## 발포 간격 = 무기 연사 간격 × 이 범위의 무작위 배율
const GUNFIRE_COOLDOWN := 2.0                  ## 총소리·경찰차 공격은 이 간격으로 한 번만 범죄로 센다

var wanted := WantedSystem.new()
var director: Director
var combat: Combat                             ## 없으면 경찰이 총을 쏘지 않는다 (M3 테스트)
var traffic: TrafficSystem
var pedestrians: PedestrianManager
var vehicles: Array[Vehicle] = []              ## 도시의 모든 차 (main과 공유)
var patrol_count := PATROL_COUNT

var cars: Array[Vehicle] = []
var crews := {}                                ## 경찰차 → 내려서 뛰는 경찰 Array
var officers: Array[PoliceOfficer] = []
var roadblocks: Array[Dictionary] = []         ## {cars, officers, age, checkpoint}
var helis: Array[PoliceHeli] = []
var seen := false
var roadblocks_placed := 0
var last_known := Vector2.ZERO
var rng := RandomNumberGenerator.new()
var shoot_rng := RandomNumberGenerator.new()   ## 발포 간격 전용 — 총을 쏴도 추격·봉쇄 결정(rng)이 바뀌지 않게

var _search := {}                              ## 추격차 → 수색 중 목표 지점
var _player_car: Vehicle = null
var _upkeep_timer := 0.0
var _roadblock_timer := ROADBLOCK_INTERVAL * 0.5
var _arrest := 0.0
var _player_stopped := 0.0
var _ram_cooldown := 0.0
var _gunfire_cooldown := 0.0
var _attack_cooldown := 0.0
var _bust_pending := false
var _bust_token := 0                           ## reset()마다 바뀐다 — 쓰러진 뒤 체포 신호가 재시작 뒤에 늦게 오지 않게


func _ready() -> void:
	rng.seed = SEED
	shoot_rng.seed = SEED + 1
	wanted.level_changed.connect(_on_level_changed)
	director.control_changed.connect(_on_control_changed)
	director.vehicle_stolen.connect(_on_vehicle_stolen)
	pedestrians.person_hurt.connect(_on_person_hurt)
	if combat:
		combat.gunfire.connect(_on_gunfire)
		combat.vehicle_attacked.connect(_on_vehicle_attacked)
	for i in patrol_count:
		var car := traffic.spawn_random(POLICE_TYPE, true)
		if car:
			_register(car)


func _physics_process(delta: float) -> void:
	if _bust_pending:
		return
	var ppos := _player_pos()
	seen = sees(ppos)
	if seen:
		last_known = ppos
	wanted.update(delta, seen)
	_ram_cooldown -= delta
	_gunfire_cooldown -= delta
	_attack_cooldown -= delta
	var pcar := director.current_vehicle
	_player_stopped = _player_stopped + delta if pcar and pcar.speed() < CAR_BUST_SPEED else 0.0
	_upkeep_timer -= delta
	if _upkeep_timer <= 0.0:
		_upkeep_timer = UPKEEP_INTERVAL
		_upkeep()
	_drive_cars()
	_update_officers()
	_update_roadblocks(delta)
	_update_helis()
	_spg_fire()
	_check_arrest(delta)


func _player_pos() -> Vector2:
	return director.controlled_target().global_position


func pursuer_count() -> int:
	var n := 0
	for car in cars:
		if car.pursuit:
			n += 1
	return n


func swat_count() -> int:
	return _count_type(SWAT_TYPE)


func army_count() -> int:
	return _count_type(ARMY_TYPE)


func _count_type(t: VehicleType) -> int:
	var n := 0
	for car in cars:
		if car.stats == t:
			n += 1
	return n


func owns(v: Vehicle) -> bool:
	return cars.has(v)


# ── 시야 · 범죄 ───────────────────────────────────────────

## 경찰(운전 중인 경찰차나 도보 경찰) 누군가의 눈에 pos가 보이는지. 헬기 탐조등 안이면 보인다
func sees(pos: Vector2) -> bool:
	for h in helis:
		if h.lit(pos):
			return true
	var space := get_world_2d().direct_space_state
	for car in cars:
		if car.has_driver and _can_see(space, car.global_position, pos):
			return true
	for o in officers:
		if o.state != Pedestrian.State.KNOCKED and not o.is_dead() and _can_see(space, o.global_position, pos):
			return true
	return false


func _can_see(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> bool:
	if from.distance_to(to) > SIGHT:
		return false
	return space.intersect_ray(PhysicsRayQueryParameters2D.create(from, to, Layers.WORLD)).is_empty()


func _crime(crime: WantedSystem.Crime, witnessed: bool) -> void:
	if not witnessed or _bust_pending:
		return
	last_known = _player_pos()
	var raised := wanted.report(crime)
	crime_witnessed.emit(crime, raised)


func _on_vehicle_stolen(_v: Vehicle, driver: Pedestrian) -> void:
	if _v.stats.silent:
		return   # 자전거는 빼앗아도 아무도 신고하지 않는다
	if driver != null:
		_crime(WantedSystem.Crime.CAR_THEFT, sees(driver.global_position))


## 주인공이 사람을 다치게 했다 (차·총·주먹·폭발). 경찰관은 본인이 목격자다.
## 구급대원을 기절시키면 목격과 상관없이 바로 ★4다 (무전이 끊긴 구급대를 본부가 안다).
func _on_person_hurt(p: Pedestrian, by_player: bool, killed: bool) -> void:
	if not by_player:
		return
	if p is StreetCriminal and p.offender():
		return   # 거리 이벤트의 도둑·강도를 막았다 — 범죄가 아니다 (StreetEvents가 보상한다)
	if p is PoliceOfficer:
		var kill := WantedSystem.Crime.KILL_OFFICER
		if p.npc == SWAT_NPC:
			kill = WantedSystem.Crime.KILL_SWAT
		elif p.npc == SOLDIER_NPC:
			kill = WantedSystem.Crime.KILL_SOLDIER
		_crime(kill if killed else WantedSystem.Crime.HIT_OFFICER, true)
	elif killed and p.npc == PARAMEDIC_NPC:
		_crime(WantedSystem.Crime.KO_PARAMEDIC, true)
	else:
		_crime(WantedSystem.Crime.KILL_PEDESTRIAN if killed else WantedSystem.Crime.HIT_PEDESTRIAN, sees(p.global_position))


func _on_gunfire(pos: Vector2, by_player: bool) -> void:
	if by_player and _gunfire_cooldown <= 0.0 and sees(pos):
		_gunfire_cooldown = GUNFIRE_COOLDOWN
		_crime(WantedSystem.Crime.GUNFIRE, true)


func _on_vehicle_attacked(v: Vehicle, by_player: bool) -> void:
	if by_player and cars.has(v) and _attack_cooldown <= 0.0:
		_attack_cooldown = GUNFIRE_COOLDOWN
		_crime(WantedSystem.Crime.ATTACK_POLICE_CAR, v.has_driver or sees(v.global_position))


## 주인공 차와 경찰차가 부딪혔다. 주인공 쪽이 더 세게 들이받았으면 범죄.
## (Vehicle.bumped는 충격량을 나누기 전에 나온다 — 부딪히기 직전 속도로 판단한다)
func _on_contact(a: Vehicle, b: Vehicle) -> void:
	var pv := director.current_vehicle
	if pv == null or _ram_cooldown > 0.0:
		return
	var pc: Vehicle = b if a == pv else (a if b == pv else null)
	if pc == null or not cars.has(pc):
		return
	var to_police := (pc.global_position - pv.global_position).normalized()
	var mine := pv.motor.velocity.dot(to_police)
	var theirs := pc.motor.velocity.dot(-to_police)
	if mine > RAM_SPEED and mine > theirs:
		_ram_cooldown = RAM_COOLDOWN
		_crime(WantedSystem.Crime.RAM_POLICE, pc.has_driver or sees(pc.global_position))


## 조종 대상이 바뀌었다. 경찰차에 탔으면 그 차는 이제 주인공 것 — 경찰차 탈취.
func _on_control_changed(target: Node2D) -> void:
	if _player_car and _player_car.bumped.is_connected(_on_player_bumped):
		_player_car.bumped.disconnect(_on_player_bumped)
	_player_car = target as Vehicle
	if _player_car == null:
		return
	_player_car.bumped.connect(_on_player_bumped)
	if not cars.has(_player_car):
		return
	var car := _player_car
	cars.erase(car)
	_search.erase(car)
	car.pursuit = null
	car.siren = false
	for o: PoliceOfficer in crews.get(car, []):
		o.car = null
	crews.erase(car)
	for rb in roadblocks:
		rb.cars.erase(car)
	_crime(WantedSystem.Crime.STEAL_POLICE_CAR, sees(car.global_position))


func _on_player_bumped(other: Vehicle, _strength: float) -> void:
	_on_contact(director.current_vehicle, other)


## 운전 중인 경찰차를 빼앗기면 운전한 경찰이 내려서 쫓아온다 (Director가 부른다)
func eject_crew(v: Vehicle, pos: Vector2) -> void:
	var o := _spawn_officer(pos, v, PoliceOfficer.Duty.CHASE, _crew_npc(v))
	crews[v] = crews.get(v, []) + [o]


func _crew_npc(car: Vehicle) -> NpcType:
	if car.stats == SWAT_TYPE:
		return SWAT_NPC
	if car.stats in [ARMY_TYPE, SPG_TYPE, JEEP_TYPE]:
		return SOLDIER_NPC
	return OFFICER_TYPE


## 불붙은 경찰차 등: 경찰 것에서 뺀다 (차는 그대로 남는다. 탔던 경찰은 Combat이 미리 내린다)
func abandon(car: Vehicle) -> void:
	if not cars.has(car):
		return
	cars.erase(car)
	_search.erase(car)
	car.pursuit = null
	car.siren = false
	for o: PoliceOfficer in crews.get(car, []):
		o.car = null
	crews.erase(car)
	for rb in roadblocks:
		rb.cars.erase(car)
	traffic.remove_ai(car)


## 체포·사망 연출 동안 경찰을 멈춘다 (reset()으로 풀린다)
func freeze() -> void:
	_bust_pending = true


# ── 경찰차 관리 ───────────────────────────────────────────

func _register(car: Vehicle) -> void:
	cars.append(car)
	car.bumped.connect(func(other: Vehicle, _s): _on_contact(car, other))


func _upkeep() -> void:
	var level := wanted.level
	var ppos := _player_pos()
	if pursuer_count() < PURSUERS[level]:
		var car: Vehicle = null
		if level >= ARMY_LEVEL and army_count() < ARMY_TRUCKS:
			car = _spawn_far(ppos, ARMY_TYPE)
		elif level >= ARMY_LEVEL and _count_type(SPG_TYPE) < ARMY_SPGS and not Vehicle.exists(vehicles, SPG_TYPE):
			car = _spawn_far(ppos, SPG_TYPE)
		elif level >= ARMY_LEVEL and _count_type(JEEP_TYPE) < ARMY_JEEPS:
			car = _spawn_far(ppos, JEEP_TYPE)
		elif level >= SWAT_LEVEL and swat_count() < SWAT_VANS:
			car = _spawn_far(ppos, SWAT_TYPE)
		else:
			car = _nearest_patrol(ppos)
			if car == null:
				car = _spawn_far(ppos)
		if car:
			_start_pursuit(car)
	var patrols: Array[Vehicle] = []
	for car in cars:
		if car.ai:
			patrols.append(car)
	if level == 0 and patrols.size() < patrol_count:
		var car := traffic.spawn_random(POLICE_TYPE, true)
		if car:
			_register(car)
	elif level == 0 and patrols.size() > patrol_count:
		for car in patrols:
			if _offscreen(car.global_position):
				_despawn(car)
				break
	# 도시가 넓다: 멀리 가 버린 순찰차는 치우고 주인공 둘레에 새로 세운다
	for car in patrols:
		if car.global_position.distance_to(ppos) > TrafficSystem.DESPAWN_RADIUS and _offscreen(car.global_position):
			_despawn(car)
			break
	# 벽에 자꾸 걸리는 추격차는 화면 밖에서 치운다 (다음 정비 때 새 차가 온다)
	for car in cars:
		if car.pursuit and car.has_driver and car.pursuit.stuck_count >= STUCK_LIMIT and _offscreen(car.global_position):
			_despawn(car)
			break


func _nearest_patrol(pos: Vector2) -> Vehicle:
	var best: Vehicle = null
	var best_d := CONVERT_RANGE
	for car in cars:
		if car.ai and car.global_position.distance_to(pos) < best_d:
			best_d = car.global_position.distance_to(pos)
			best = car
	return best


## 주인공에게서 SPAWN_MIN~MAX 떨어진 화면 밖 도로에 새 경찰차를 세운다
func _spawn_far(near: Vector2, type: VehicleType = POLICE_TYPE) -> Vehicle:
	var pieces := traffic.nearby_segments(SPAWN_MIN - City.BLOCK, SPAWN_MAX + City.BLOCK, near)
	if pieces.is_empty():
		return null
	for attempt in 40:
		var piece: LanePiece = pieces[rng.randi() % pieces.size()]
		var s := rng.randf_range(60.0, piece.length - 120.0)
		var pos := piece.point_at(s)
		var d := pos.distance_to(near)
		if d < SPAWN_MIN or d > SPAWN_MAX or not _offscreen(pos) or not traffic.is_clear(pos):
			continue
		var car := traffic.spawn_at(type, piece, s)
		_register(car)
		return car
	return null


func _start_pursuit(car: Vehicle) -> void:
	traffic.remove_ai(car)
	car.pursuit = PursuitAI.new(car, vehicles)
	car.siren = true


## 수배가 풀렸다: 사이렌을 끄고 일반 순찰로 돌아간다
func _stand_down(car: Vehicle) -> void:
	car.pursuit = null
	car.siren = false
	_search.erase(car)
	if car.ai == null:
		traffic.adopt(car)


func _despawn(car: Vehicle) -> void:
	cars.erase(car)
	_search.erase(car)
	for o: PoliceOfficer in crews.get(car, []):
		o.car = null
		o.duty = PoliceOfficer.Duty.LEAVE
	crews.erase(car)
	traffic.remove_ai(car)
	vehicles.erase(car)
	car.queue_free()


func _drive_cars() -> void:
	var target := director.controlled_target()
	var on_foot := director.current_vehicle == null
	for car in cars:
		var p := car.pursuit
		if p == null or not car.has_driver:
			continue
		if seen:
			p.target = target.global_position
			p.target_velocity = target.call("follow_velocity")
			p.target_level = target.get("level")
			_search.erase(car)
		else:
			# 마지막으로 본 곳에 가 보고, 거기도 없으면 근처 교차로를 돌며 찾는다
			var goal: Vector2 = _search.get(car, last_known)
			if car.global_position.distance_to(goal) < SEARCH_REACH:
				var cell := RoadNav.road_ends(last_known)[rng.randi() % 2]
				var d := rng.randi() % 4
				goal = LaneGraph.center(cell + LaneGraph.STEPS[d] if LaneGraph.connected(cell, d) else cell)
			_search[car] = goal
			p.target = goal
			p.target_velocity = Vector2.ZERO
			p.target_level = -1
		p.target_vehicle = director.current_vehicle
		# 달아나는 차만 들이받는다. 멈춘 차를 들이받으면 계속 밀고 가서 세우지 못한다.
		p.ram = wanted.level >= 2 and not on_foot and seen and director.current_vehicle.speed() > RAM_TARGET_SPEED
		p.stop_at_target = on_foot and seen
		if not seen or not p.direct or car.speed() > 40.0:
			continue
		var d := car.global_position.distance_to(target.global_position)
		if on_foot and d < DEPLOY_RANGE:
			_deploy(car)
		elif not on_foot and _player_stopped > CAR_STOP_BEFORE_DEPLOY and d < CAR_DEPLOY_RANGE:
			_deploy(car)


## 차를 세우고 경찰이 내린다 (차는 빈 차가 된다)
func _deploy(car: Vehicle) -> void:
	if car.stats == SPG_TYPE:
		return   # 자주포 승무원은 내리지 않고 포를 쏜다 (_spg_fire)
	car.has_driver = false
	var crew: Array = crews.get(car, [])
	var squad := car.stats == SWAT_TYPE or car.stats == ARMY_TYPE
	var npc := _crew_npc(car)
	var count: int = (SWAT_CREW if car.stats == SWAT_TYPE else ARMY_CREW) if squad else CREW[maxi(wanted.level, 1)]
	if car.stats == JEEP_TYPE:
		count = JEEP_CREW
	for i in count:
		var door := car.door_position(i == 1)
		if squad:   # 넷이 앞뒤 양쪽 문으로
			door = car.door_position(i % 2 == 1) + car.motor.forward() * (14.0 if i < 2 else -14.0)
		crew.append(_spawn_officer(door, car, PoliceOfficer.Duty.CHASE, npc))
	crews[car] = crew


# ── 도보 경찰 ─────────────────────────────────────────────

func _spawn_officer(pos: Vector2, car: Vehicle, duty: PoliceOfficer.Duty, npc: NpcType = OFFICER_TYPE) -> PoliceOfficer:
	var o := PoliceOfficer.new()
	o.setup(npc, rng, City.sidewalk_loop(City.nearest_block(pos)), 0, 0.0, 1)
	o.position = pos
	o.car = car
	o.duty = duty
	o.goal = pos
	if car:
		o.level = car.level   # 고가 위 경찰차에서 내리면 고가 위에 선다
	pedestrians.add(o)
	officers.append(o)
	return o


## 쓰러져 죽은 경찰: 명단에서만 뺀다 (시신은 PedestrianManager가 치운다).
## 타고 온 차의 경찰이 모두 죽었으면 그 차는 버려진 빈 차가 된다.
func _drop_officer(o: PoliceOfficer) -> void:
	officers.erase(o)
	var car := o.car
	if car and crews.has(car):
		crews[car].erase(o)
		if crews[car].is_empty() and not car.has_driver:
			abandon(car)


func _remove_officer(o: PoliceOfficer) -> void:
	officers.erase(o)
	if o.car and crews.has(o.car):
		crews[o.car].erase(o)
	pedestrians.remove(o)


func _update_officers() -> void:
	var ppos := _player_pos()
	var pcar := director.current_vehicle
	var level := wanted.level
	for o: PoliceOfficer in officers.duplicate():
		if o.is_dead():
			_drop_officer(o)
			continue
		var pos := o.global_position
		o.goal_level = -1
		match o.duty:
			PoliceOfficer.Duty.CHASE:
				o.goal = _nearest_door(pcar, pos) if pcar else ppos
				o.goal_level = pcar.level if pcar else director.player.level
				# 달아나는 차(CAR_ESCAPE_SPEED 이상)는 도보로 맞히기 어렵다 — 멈추거나 느린 차, 도보 주인공만 쏜다
				if level >= SHOOT_LEVEL and (pcar == null or pcar.speed() < CAR_ESCAPE_SPEED):
					_shoot(o, pcar.global_position if pcar else ppos, pcar != null and pcar.airborne())
				var escaping := pcar != null and pcar.speed() > CAR_ESCAPE_SPEED and pos.distance_to(ppos) > 220.0
				if level == 0 or escaping or pos.distance_to(ppos) > FOOT_GIVE_UP:
					_recall(o)
			PoliceOfficer.Duty.GUARD:
				o.goal = pos
				if level > 0 and pos.distance_to(ppos) < 260.0 and (pcar == null or pcar.speed() < CAR_BUST_SPEED):
					o.duty = PoliceOfficer.Duty.CHASE
			PoliceOfficer.Duty.RETURN:
				if o.car and not cars.has(o.car):
					o.car = null
				if o.car == null and o.post == Vector2.ZERO:
					o.duty = PoliceOfficer.Duty.LEAVE
					continue
				o.goal = o.car.door_position(false) if o.car else o.post
				if level > 0 and seen and pos.distance_to(ppos) < 200.0 and (pcar == null or pcar.speed() < CAR_BUST_SPEED):
					o.duty = PoliceOfficer.Duty.CHASE
				elif o.arrived():
					if o.car:
						_board(o)
					else:
						o.duty = PoliceOfficer.Duty.GUARD
			PoliceOfficer.Duty.LEAVE:
				o.goal = pos + (pos - ppos).normalized() * 100.0
				if _offscreen(pos):
					_remove_officer(o)


## 보이는 곳에 있으면 주인공(차에 탔으면 그 차)을 쏜다. 하늘(떠 있는 헬기)은 건물 너머로도 보인다
func _shoot(o: PoliceOfficer, target: Vector2, in_air := false) -> void:
	var weapon := o.npc.weapon
	if combat == null or weapon == null or o.reload > 0.0 or o.state != Pedestrian.State.WALK:
		return
	var pos := o.global_position
	if pos.distance_to(target) > SHOOT_RANGE or not (in_air or _can_see(get_world_2d().direct_space_state, pos, target)):
		return
	o.reload = weapon.fire_interval * shoot_rng.randf_range(SHOOT_DELAY[0], SHOOT_DELAY[1])
	var dir := (target - pos).normalized()
	o.facing = Vector2.UP.angle_to(dir)
	var exclude: Array[RID] = [o.get_rid()]
	combat.fire(pos + dir * 10.0, dir, weapon, false, exclude, 0.0, o.level)


func _nearest_door(v: Vehicle, from: Vector2) -> Vector2:
	var a := v.door_position(false)
	var b := v.door_position(true)
	return a if from.distance_to(a) <= from.distance_to(b) else b


func _recall(o: PoliceOfficer) -> void:
	if o.car and not cars.has(o.car):
		o.car = null
	o.duty = PoliceOfficer.Duty.RETURN if o.car or o.post != Vector2.ZERO else PoliceOfficer.Duty.LEAVE


## 경찰이 차로 돌아와 탔다. 모두 타면 차가 다시 움직인다.
func _board(o: PoliceOfficer) -> void:
	var car := o.car
	_remove_officer(o)
	if crews.has(car) and not crews[car].is_empty():
		return
	crews.erase(car)
	car.has_driver = true
	if wanted.level == 0:
		_stand_down(car)


func _check_arrest(delta: float) -> void:
	if wanted.level == 0:
		_arrest = 0.0
		return
	var pcar := director.current_vehicle
	if pcar and pcar.airborne():
		_arrest = maxf(_arrest - delta, 0.0)   # 떠 있는 헬기에는 손이 안 닿는다
		return
	if pcar:
		# 차: 선 차 문에 경찰 손이 닿아 있으면 끌어내린다 — 그다음은 도보처럼 맞는다
		var at_door := false
		for o in officers:
			if _can_grab(o) and pcar.speed() < CAR_BUST_SPEED \
					and o.global_position.distance_to(_nearest_door(pcar, o.global_position)) < DOOR_REACH \
					and CityMap.meet(o.global_position, o.level, pcar.global_position, pcar.level):
				at_door = true
		_arrest = _arrest + delta if at_door else maxf(_arrest - delta, 0.0)
		if _arrest >= CAR_ARREST_TIME:
			_arrest = 0.0
			director.exit_vehicle()
			director.player.stun(CAR_PULL_STUN)
		return
	_arrest = 0.0
	# 도보: 붙은 경찰마다 BEAT_INTERVAL마다 곤봉을 휘두른다. 체력이 BUST_HEALTH 아래가 되면 쓰러져 체포
	var player := director.player
	for o in officers:
		if not _can_grab(o) or o.global_position.distance_to(player.global_position) >= BEAT_RANGE \
				or not CityMap.meet(o.global_position, o.level, player.global_position, player.level):
			o.beat_wait = maxf(o.beat_wait - delta, BEAT_WINDUP)   # 떨어졌다 다시 붙어도 매가 빨라지지 않게
			continue
		o.beat_wait -= delta
		if o.beat_wait > 0.0:
			continue
		o.beat_wait = BEAT_INTERVAL
		o.swing(player.global_position)
		player.beaten(BEAT_DAMAGE, player.global_position - o.global_position, BEAT_STUN)
		if player.health <= BUST_HEALTH:
			_knock_down_and_bust()
			return


func _can_grab(o: PoliceOfficer) -> bool:
	return o.duty == PoliceOfficer.Duty.CHASE and o.state != Pedestrian.State.KNOCKED and not o.is_dead()


## 맞아 쓰러진 주인공: 넘어지는 그림을 보여 준 뒤 체포 (그동안 경찰은 멈춘다)
func _knock_down_and_bust() -> void:
	_bust_pending = true
	var fine := FINE_PER_STAR * wanted.level
	var token := _bust_token
	director.player.knock_down()
	await get_tree().create_timer(BUST_FALL_TIME, true, true).timeout
	if token == _bust_token and _bust_pending:
		busted.emit(fine)


## 체포 후 재시작: 경찰을 모두 물리고 별을 지운다 (순찰차는 정비 때 다시 생긴다)
func reset() -> void:
	for o in officers.duplicate():
		_remove_officer(o)
	for car in cars.duplicate():
		_despawn(car)
	crews.clear()
	for rb in roadblocks:
		if is_instance_valid(rb.get("visual")):
			rb.visual.queue_free()
	roadblocks.clear()
	for h in helis:
		h.queue_free()
	helis.clear()
	_search.clear()
	wanted.clear()
	_arrest = 0.0
	_bust_pending = false
	_bust_token += 1


func _on_level_changed(level: int, _previous: int) -> void:
	if level != 0:
		return
	for car in cars:
		if car.pursuit and car.has_driver:
			_stand_down(car)


# ── ★3 도로 봉쇄 ──────────────────────────────────────────

func _update_roadblocks(delta: float) -> void:
	for rb in roadblocks.duplicate():
		rb.age += delta
		rb.cars = rb.cars.filter(is_instance_valid)    # 부서져 치워진 봉쇄 차 (Combat._cleanup_wrecks)·쓰러져 치워진 경찰
		rb.officers = rb.officers.filter(is_instance_valid)
		if rb.checkpoint and wanted.level >= CHECKPOINT_LEVEL:
			continue
		if not rb.checkpoint and wanted.level >= 3 and rb.age < ROADBLOCK_LIFETIME:
			continue
		var in_view := false
		for car: Vehicle in rb.cars:
			in_view = in_view or not _offscreen(car.global_position)
		if in_view:
			continue
		for car: Vehicle in rb.cars:
			if cars.has(car):
				_despawn(car)
		for o: PoliceOfficer in rb.officers:
			if officers.has(o) and o.duty == PoliceOfficer.Duty.GUARD:
				_remove_officer(o)
		if is_instance_valid(rb.get("visual")):
			rb.visual.queue_free()
		roadblocks.erase(rb)
	if wanted.level >= CHECKPOINT_LEVEL:
		_place_checkpoints()
	var pcar := director.current_vehicle
	var normal := roadblocks.filter(func(rb: Dictionary): return not rb.checkpoint).size()
	if wanted.level < 3 or pcar == null or pcar.airborne() or normal >= MAX_ROADBLOCKS:
		return
	_roadblock_timer -= delta
	if _roadblock_timer > 0.0:
		return
	_roadblock_timer = 2.0   # 못 세웠으면 곧 다시 본다
	if pcar.speed() > 150.0 and place_roadblock(pcar.global_position, pcar.motor.velocity):
		_roadblock_timer = ROADBLOCK_INTERVAL


## 주인공이 달려가는 방향, 앞쪽 교차로를 지난 구간 가운데에 경찰차 두 대를 가로로 세운다. 한쪽에 좁은 틈이 있다.
## 화면 밖에 세우고, 보인 뒤에도 앞 교차로에서 꺾거나 틈을 노릴 거리가 남게 한다.
func place_roadblock(from: Vector2, velocity: Vector2) -> bool:
	var axis := Vector2i(signi(roundi(velocity.x)), 0) if absf(velocity.x) > absf(velocity.y) \
		else Vector2i(0, signi(roundi(velocity.y)))
	var d := LaneGraph.dir_index(axis)
	var dir := LaneGraph.DIRS[d]
	var cell := RoadNav.cell_at(from)
	if cell == RoadNav.INVALID:
		for e in RoadNav.road_ends(from):
			if (LaneGraph.center(e) - from).dot(dir) > 0.0:
				cell = e
	if cell == RoadNav.INVALID:
		return false
	var spot := LaneGraph.center(cell) + dir * (LaneGraph.HALF + ROADBLOCK_PAST_BOX)
	while spot.distance_to(from) < ROADBLOCK_MIN_AHEAD or not _offscreen(spot):
		if not LaneGraph.connected(cell, d):
			return false
		cell += LaneGraph.STEPS[d]
		spot = LaneGraph.center(cell) + dir * (LaneGraph.HALF + ROADBLOCK_PAST_BOX)
	if not LaneGraph.connected(cell, d):
		return false
	return _build_roadblock(spot, dir, false)


## spot에 경찰차 두 대를 dir에 가로로 세운다. 한쪽에 좁은 틈이 있다
func _build_roadblock(spot: Vector2, dir: Vector2, checkpoint: bool) -> bool:
	var across := LaneGraph.right_of(dir)
	var gap_side := 1.0 if rng.randf() < 0.5 else -1.0
	var length := POLICE_TYPE.size.y
	# 틈은 한쪽 가장자리에 차 두 대 폭(56px)쯤 — 맞춰 들어가야 빠져나간다
	var offsets := [-gap_side * (LaneGraph.HALF - 18.0 - length * 0.5), -gap_side * (LaneGraph.HALF - 20.0 - length * 1.5)]
	for off: float in offsets:
		if not traffic.is_clear(spot + across * off, 70.0):
			return false
	var rb := {"cars": [], "officers": [], "age": 0.0, "checkpoint": checkpoint, "spot": spot}
	for off: float in offsets:
		var car := Vehicle.new()
		car.stats = POLICE_TYPE
		add_child(car)
		car.place(spot + across * off, Vector2.UP.angle_to(across))
		car.siren = true
		vehicles.append(car)
		_register(car)
		rb.cars.append(car)
	var guard := _spawn_officer(spot + dir * 50.0, null, PoliceOfficer.Duty.GUARD)
	guard.post = guard.global_position
	rb.officers.append(guard)
	if checkpoint:
		var visual := CheckpointVisual.new()
		visual.spot=spot
		visual.across=across
		visual.dir=dir
		add_child(visual)
		rb["visual"]=visual
	roadblocks.append(rb)
	roadblocks_placed += 1
	return true


## ★4부터: 주인공 근처 다리 끝마다 검문소 (다리 위로 조금 들어간 곳, 화면 밖)
func _place_checkpoints() -> void:
	var ppos := _player_pos()
	for end: Array in bridge_ends():
		var c: Vector2i = end[0]
		var d: int = end[1]
		var dir := LaneGraph.DIRS[d]
		var spot := LaneGraph.center(c) + dir * (LaneGraph.HALF + CHECKPOINT_ONTO)
		var dist := spot.distance_to(ppos)
		if dist < CHECKPOINT_RANGE[0] or dist > CHECKPOINT_RANGE[1] or not _offscreen(spot) or not LaneGraph.connected(c, d):
			continue
		var taken := false
		for rb in roadblocks:
			taken = taken or (rb.checkpoint and (rb.spot as Vector2).distance_to(spot) < 10.0)
		if not taken:
			_build_roadblock(spot, dir, true)


## 다리 끝 [땅 교차로, 다리 쪽 방향] 목록
static func bridge_ends() -> Array:
	var ends := []
	for k in CityMap.BRIDGES:
		for j in range(CityMap.MIN.y, CityMap.MAX.y + 2):
			var c := Vector2i(k, j)
			var land := false
			for b in CityMap.node_blocks(c):
				land = land or CityMap.is_land(b)
			if not land:
				continue
			for d in [0, 2]:
				if CityMap.is_bridge(c, d):
					ends.append([c, d])
	return ends


# ── ★5 경찰 헬기 · ★6 군 기동헬기 ────────────────────────

func _update_helis() -> void:
	var level := wanted.level
	var ppos := _player_pos()
	var want: int = HELIS[level]
	var flying := helis.filter(func(h: PoliceHeli): return not h.leaving and not h.down).size()
	if flying < want:
		var h := PoliceHeli.new()
		h.gunner = HELI_NPC
		# ★6(군 투입)이면 한 대는 군 기동헬기 — 체력이 더 높고 경광등이 없다
		if level >= ARMY_LEVEL and not helis.any(func(x: PoliceHeli): return x.stats == ARMY_HELI_TYPE and not x.leaving and not x.down):
			h.stats = ARMY_HELI_TYPE
			h.beacons = false
		h.position = ppos + Vector2.RIGHT.rotated(rng.randf() * TAU) * HELI_SPAWN
		add_child(h)
		h.shot_down.connect(_on_heli_down.bind(h))
		helis.append(h)
	elif flying > want:
		for h in helis:
			if not h.leaving and not h.down:
				h.leaving = true
				break
	for h: PoliceHeli in helis.duplicate():
		if h.crashed():
			helis.erase(h)
			if combat:
				combat.explode(h.global_position, true, null, 1.4)
			h.queue_free()
			continue
		if h.leaving and h.global_position.distance_to(ppos) > HELI_SPAWN + 400.0:
			helis.erase(h)
			h.queue_free()
			continue
		h.target = ppos if seen else last_known
		var w := h.gunner.weapon
		if combat and w and level >= 5 and h.reload <= 0.0 and h.lit(ppos) \
				and h.global_position.distance_to(ppos) < PoliceHeli.SHOOT_RANGE:
			h.reload = w.fire_interval * shoot_rng.randf_range(SHOOT_DELAY[0], SHOOT_DELAY[1])
			combat.fire_from_air(h.global_position, ppos, w)


## ★6 자주포: 주인공이 보이고 사거리 안이면 포탑을 돌려 겨누고, 다 돌았으면 주인공 둘레로 포탄을 떨어뜨린다
func _spg_fire() -> void:
	if combat == null or not seen:
		return
	var ppos := _player_pos()
	for car in cars:
		if car.stats != SPG_TYPE or not car.has_driver or car.wrecked or car.controlled:
			continue
		var rel := ppos - car.global_position
		var d := rel.length()
		if d < SPG_TYPE.cannon_min or d > SPG_TYPE.cannon_max:
			continue
		var want := car.motor.forward().angle_to(rel)
		car.turret_goal = car.turret + angle_difference(car.turret, want)
		car.aim_range = d
		if car.gun_reload > 0.0 or absf(angle_difference(car.turret, want)) > SPG_AIMED:
			continue
		car.gun_reload = TANK_CANNON.fire_interval * SPG_RELOAD * shoot_rng.randf_range(SHOOT_DELAY[0], SHOOT_DELAY[1])
		var miss := Vector2.RIGHT.rotated(shoot_rng.randf() * TAU) * shoot_rng.randf_range(0.0, SPG_SPREAD)
		combat.fire_shell(car.muzzle(), ppos + miss, TANK_CANNON, false, car)
		car.recoil = 1.0


func _on_heli_down(by_player: bool, _h: PoliceHeli) -> void:
	if by_player:
		_crime(WantedSystem.Crime.DOWN_HELI, true)


func _offscreen(pos: Vector2) -> bool:
	var camera := ChaseCamera.current_cam()
	return camera == null or pos.distance_to(camera.global_position) > OFFSCREEN
