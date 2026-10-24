class_name PlayerWeapons
extends Node
## 주인공의 무기 입력: 쏘기(Z·J·마우스 왼쪽), 무기 바꾸기(Q·E).
## 도보는 바라보는 쪽으로 쏘되 앞쪽 부채꼴 안의 표적을 자동으로 겨눈다.
## 차 안에서는 드라이브바이 — 진행 방향 좌우 중 표적이 있는 쪽으로, 없으면 번갈아 쏜다.
## 마우스를 쓰면(움직이거나 누르면) 커서 쪽으로 정확히 쏜다 — 부채꼴 자동 조준 없이, 커서가 사람 그림
## 위에 있을 때만 그 사람을 겨눈다. 드라이브바이는 커서가 있는 옆으로, 옆 방향에서 DRIVE_BY_SPREAD 안으로.
## 쏘기 키(Z·J)·패드로 쏘면 다시 예전 방식이다.
## 차량 기관총은 차 안에서만 앞으로 쏜다. 소방차를 몰면 쏘기 버튼은 늘 물대포(앞으로).
## 떠 있는 헬기에서는 헬기 몸에서 땅으로 내려쏜다(`Combat.fire_down`) — 마우스면 커서가 있는 땅(사람 그림 위면 그 사람)으로
## 사방 어디로나, 키보드면 앞쪽 부채꼴 안의 표적을 겨눈다. 사거리 밖 커서는 사거리까지 당긴다. 던지는 무기·화염·주먹은 못 쓴다.
## 포탑 달린 차(자주포·전술차량)를 몰면 포탑은 Q·E로만 돌린다(마우스는 포탑을 돌리지 않는다), 쏘기 버튼은 포탑 무기다.
## 자주포는 곡사포 — 포탑 방향으로 커서까지 거리(사거리 안으로 당긴다)에 포탄이 떨어지고, 포신은 그 거리만큼 든다. 키보드만 쓰면 마지막 거리 그대로.
## 굴삭기는 상부가 커서 쪽으로 돌고 팔이 커서까지 뻗는다 — 쏘기 버튼은 퍼 올리기(찍은 곳의 차를 집고, 들고 있으면 놓는다).
## 불도저는 쏘기 버튼이 블레이드 올리기·내리기다.
## 표적 고르기(도보): 사람을 오른쪽 클릭하면 고르고(빈 땅을 오른쪽 클릭하면 푼다), Tab·패드 RB는 가까운 사람부터 차례로 고른다.
## 고른 사람은 발밑 빨간 원(TargetRing)·머리 위 체력 막대가 늘 보이고, 쏘기·주먹은 커서·부채꼴 대신 그 사람을 향한다.
## 기절하거나 멀어지거나(SELECT_DROP) 차에 타면 풀린다.

## 커서가 사람 몸(발끝~머리, 화면 px·줌 1)에서 이만큼 안이면 그 사람을 겨눈다
const AIM_PICK := 9.0
const HELI_PICK := 1.0     ## 커서가 헬기 그림 몸통에서 맞는 반지름 × 이 안이면 그 헬기를 겨눈다
## 마우스로 겨눈 뒤 걸어도 커서 쪽을 바라보는 시간
const AIM_HOLD := 0.35
## 마우스 드라이브바이: 차 옆 방향에서 앞뒤로 틀 수 있는 각도
const DRIVE_BY_SPREAD := 0.6
## 헬기에서 키보드로 쏠 때 표적이 없으면 앞으로 사거리의 이만큼 떨어진 땅
const HELI_AUTO_REACH := 0.5
const SELECT_RANGE := 520.0    ## Tab으로 고를 수 있는 거리
const SELECT_DROP := 760.0     ## 고른 사람이 이만큼 멀어지면 풀린다
const SELECT_PICK := 14.0      ## 오른쪽 클릭: 사람 그림(발끝~머리)에서 이만큼(화면 px·줌 1) 안이면 그 사람

var director: Director
var player: Player
var combat: Combat
var pedestrians: PedestrianManager
var vehicles: Array[Vehicle] = []
var _side := 1.0
var _mounted_cooldown := 0.0
## 마우스로 겨누는 중 (마우스를 움직이거나 누르면 켜지고, 쏘기 키·패드로 쏘면 꺼진다)
var _fire_held := false
var _fire_event_tick := -1
var _punch_active := false
var _punch_queued := false
var _punch_elapsed := 0.0
var _punch_index := -1
var _combo_left := 0.0
var _punch_hit := false
var _punch_dir := Vector2.UP
var _punch_spec: Dictionary = {}
var _stance_left := 0.0
const STANCE_HOLD := 2.0   ## 마지막 공격이 끝나고 이만큼(초) 서 있으면 싸움 자세를 풀고 평소 서 있기로 돌아간다

var mouse_aim := false
var selected: Pedestrian = null   ## 고른 표적 (오른쪽 클릭·Tab)
var _cross := false
const MOUNTED: Array[WeaponType] = [preload("res://data/weapons/water_cannon.tres"),
	preload("res://data/weapons/tank_cannon.tres"), preload("res://data/weapons/jeep_mg.tres")]


func _ready() -> void:
	player.control.action_requested.connect(request_action)


func _aiming() -> bool:
	return mouse_aim if player.control.is_local() else player.control.read().aim_enabled


func _physics_process(delta: float) -> void:
	player.arsenal.update(delta)
	_check_selected()
	_mounted_cooldown = maxf(_mounted_cooldown - delta, 0.0)
	var v := director.current_vehicle
	if v and v.stats.turret_rate > 0.0 and not v.wrecked and not player.is_dead():
		_steer_turret(v, delta)
	_step_punch(delta)
	var held := player.control.read(player.screen_walk).fire
	var edge := held and not _fire_held
	_fire_held = held
	if player.arsenal.current() == Player.FIST and v == null:
		if edge and _fire_event_tick != Engine.get_physics_frames():
			shoot()
		return
	if held:
		if director.current_vehicle == null and player.input_enabled and not player.is_dead():
			if locked():
				player.face(_lock_dir(player.global_position), AIM_HOLD)   # 고른 사람을 계속 본다
			elif _aiming():
				player.face(mouse_dir(player.global_position), AIM_HOLD)   # 연사 사이에도 커서를 따라 돈다
		shoot()


func _process(_delta: float) -> void:
	# 도보·떠 있는 헬기에서 마우스 조준 중이면 십자 커서
	var v := director.current_vehicle
	var cross := player.control.is_local() and mouse_aim and (v == null or _heli_gun(v)) and not player.is_dead()
	if cross != _cross:
		_cross = cross
		Input.set_default_cursor_shape(Input.CURSOR_CROSS if cross else Input.CURSOR_ARROW)


func _exit_tree() -> void:
	if _cross:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


## 조준 방식만 고른다 (GUI가 먹은 클릭도 보도록 _input에서)
func _input(event: InputEvent) -> void:
	if not player.control.is_local():
		return
	if event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length_squared() > 4.0:
			mouse_aim = true
	elif event is InputEventMouseButton:
		if event.pressed:
			mouse_aim = true
	elif event.is_action_pressed("fire"):
		mouse_aim = false


func _unhandled_input(event: InputEvent) -> void:
	if not player.control.is_local():
		return
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		if director.current_vehicle == null:
			var vp := player.get_viewport()
			select(pick_person(vp.get_mouse_position(), vp.canvas_transform))
		return
	for action: StringName in [&"fire", &"weapon_next", &"weapon_prev", &"target_select"]:
		if event.is_action_pressed(action):
			player.control.request_action(action)
			return


## 로컬 이벤트 또는 외부 제어 객체에서 요청한 한 번의 동작.
func request_action(action: StringName) -> void:
	var v := director.current_vehicle
	if action == &"target_select":
		cycle_target()
		return
	if action == &"fire" and v == null and player.arsenal.current() == Player.FIST:
		_fire_event_tick = Engine.get_physics_frames()
		_fire_held = true
		shoot()
		return
	if v and v.stats.blade and action == &"fire":
		v.blade_up = not v.blade_up
		return
	if v and v.stats.turret_rate > 0.0:
		return
	if action == &"weapon_next":
		player.arsenal.cycle(1)
	elif action == &"weapon_prev":
		player.arsenal.cycle(-1)


## 지금 무기로 한 번 쏜다. 못 쐈으면(연사 대기·차 안 주먹·조종 불가) false
func shoot() -> bool:
	var arsenal := player.arsenal
	var w := arsenal.current()
	var v := director.current_vehicle
	if player.is_dead() or director.is_entering() or (v == null and player.jumping()):
		return false   # 뛰는 동안은 쏘지도 지르지도 않는다 (점프 그림에 무기 자세가 없다)
	if v and v.stats.arm_reach.y > 0.0:
		return v.start_dig()
	if v and v.stats.blade:
		return false   # 블레이드는 누를 때 한 번씩 (_unhandled_input)
	if v and _mounted(v) and not v.wrecked:
		return _fire_mounted(v, _mounted(v))
	if w == Player.FIST and v == null:
		return _request_punch()
	if _punch_active:
		_cancel_punch()
	if not arsenal.can_fire():
		return false
	if v == null and (not player.input_enabled or w.vehicle_only):
		return false
	if v and _heli_gun(v):
		return _fire_from_heli(v, w)
	if v and not w.drive_by:
		return false
	var from: Vector2
	var dir: Vector2
	var exclude: Array[RID] = []
	if v and w.forward:
		exclude.append(v.get_rid())
		dir = v.motor.forward()
		from = v.global_position + dir * (v.stats.size.y * 0.5 + 6.0)
	elif v:
		exclude.append(v.get_rid())
		dir = _drive_by_dir(v, w)
		from = v.global_position + dir * (v.stats.size.x * 0.5 + 6.0)
	else:
		exclude.append(player.get_rid())
		from = player.global_position
		if locked():
			dir = _lock_dir(from)
			player.face(dir, AIM_HOLD)
		elif _aiming():
			dir = mouse_dir(from)
			player.face(dir, AIM_HOLD)
		else:
			dir = aim(from, Vector2.UP.rotated(player.facing), w.max_range + 10.0, null)
			player.facing = Vector2.UP.angle_to(dir)
		if not w.melee:
			from += dir * w.muzzle
	arsenal.fire()
	if v == null and w.pose != &"":
		# 총구 좌표도 이번 발사의 첫 장에서 잰다. 직전 발사 반동이나 다른 총의 장면을 쓰지 않는다.
		player.set_meta(&"shot_at", Time.get_ticks_msec() / 1000.0)
		player.set_meta(&"shot_weapon", w.id)
	var shown: Variant = null
	var rear: Variant = null
	if v == null:
		var speed := player.velocity.length()
		var gait := 0.0 if speed < 1.0 else (2.0 if speed > Player.WALK_SPEED + 20.0 else 1.0)
		shown = PersonRig.gun_muzzle(player, player.facing, 1.0, gait, w)
		rear = PersonRig.gun_breech(player, player.facing, 1.0, gait, w)   # 로켓포 발사관 뒤끝 — 후폭풍
	combat.fire(from, dir, w, true, exclude, 0.0, v.level if v else player.level, shown, rear)
	if w.melee and v == null:
		player.punch()
	return true


## 떠 있는 헬기라 내려쏘기를 한다
func _heli_gun(v: Vehicle) -> bool:
	return v.stats.flies and v.airborne() and not v.wrecked


## 떠 있는 헬기에서 내려쏜다: 마우스면 커서가 있는 땅, 아니면 앞쪽 부채꼴 안의 표적 (없으면 앞으로)
func _fire_from_heli(v: Vehicle, w: WeaponType) -> bool:
	if w.melee or w.projectile != &"" or w.flame or w.water:
		return false
	var base := v.global_position
	var at: Vector2
	if _aiming():
		at = mouse_point(base)
	else:
		var t: Variant = target(base, v.motor.forward(), w.max_range, v)
		at = t if t != null else base + v.motor.forward() * w.max_range * HELI_AUTO_REACH
	var rel := at - base
	if rel.length() < 4.0:
		rel = v.motor.forward() * 4.0
	at = base + rel.limit_length(w.max_range)
	player.arsenal.fire()
	combat.fire_down(v, at, w, true)
	return true


## 이 차에 달린 무기 (없으면 null)
func _mounted(v: Vehicle) -> WeaponType:
	for w in MOUNTED:
		if w.mounted_on.has(v.stats.id):
			return w
	return null


func _fire_mounted(v: Vehicle, w: WeaponType) -> bool:
	if v.stats.turret_rate > 0.0:
		return _fire_turret(v, w)
	if _mounted_cooldown > 0.0:
		return false
	_mounted_cooldown = w.fire_interval
	var dir := v.motor.forward()
	var exclude: Array[RID] = [v.get_rid()]
	combat.fire(v.global_position + dir * (v.stats.size.y * 0.5 + 4.0), dir, w, true, exclude, 0.0, v.level)
	return true


## 포탑을 겨눈다: Q·E로 돌린다. 포탑 무기가 달린 차(자주포·전술차량)는 마우스로 돌리지 않는다 — 곡사포는 커서까지 거리만 쓴다.
## 굴삭기는 마우스면 상부가 커서 쪽으로 돌고 팔이 커서까지 뻗는다
func _steer_turret(v: Vehicle, delta: float) -> void:
	var turn := player.control.read(player.screen_walk).turret
	if turn != 0.0:
		mouse_aim = false
		v.turret_goal = v.turret + turn * v.stats.turret_rate * delta * 1.5
	elif _aiming():
		var at: Vector2
		if player.control.is_local():
			var vp := player.get_viewport()
			at = vp.canvas_transform.affine_inverse() * vp.get_mouse_position() - IsoView.lift(IsoView.ground(v.global_position))
		else:
			at = player.control.read().aim_world
		var rel := at - v.global_position
		if _mounted(v):
			if v.stats.cannon_max > 0.0 and rel.length() > 4.0:
				v.aim_range = rel.length()
			return
		if rel.length() > 4.0:
			v.turret_goal = v.turret + angle_difference(v.turret, v.motor.forward().angle_to(rel))
			if v.stats.cannon_max > 0.0 or v.stats.arm_reach.y > 0.0:
				v.aim_range = rel.length()


## 포탑 무기를 포탑 방향으로 쏜다. 곡사포는 겨눈 땅으로 포탄 (장전 시간 = 무기 연사 간격)
func _fire_turret(v: Vehicle, w: WeaponType) -> bool:
	if v.gun_reload > 0.0:
		return false
	v.gun_reload = w.fire_interval
	var exclude: Array[RID] = [v.get_rid()]
	if w.projectile == &"shell":
		combat.fire_shell(v.muzzle(), v.gun_target(), w, true, v)
		v.recoil = 1.0
	else:
		var dir := v.gun_dir()
		combat.fire(v.global_position + dir * 8.0, dir, w, true, exclude, 0.0, v.level)
	return true


## 차 옆으로 쏠 방향: 표적이 있는 쪽(둘 다면 가까운 쪽)을 겨누고, 양쪽 다 없으면 번갈아
func _drive_by_dir(v: Vehicle, w: WeaponType) -> Vector2:
	var fwd := v.motor.forward()
	if _aiming():
		var to := mouse_dir(v.global_position)
		var side := Ballistics.side_dir(fwd, 1.0 if to.dot(Ballistics.side_dir(fwd, 1.0)) >= 0.0 else -1.0)
		return side.rotated(clampf(side.angle_to(to), -DRIVE_BY_SPREAD, DRIVE_BY_SPREAD))
	var best: Variant = null
	for side in [1.0, -1.0]:
		var t: Variant = target(v.global_position, Ballistics.side_dir(fwd, side), w.max_range, v)
		if t != null and (best == null or v.global_position.distance_to(t) < v.global_position.distance_to(best)):
			best = t
	if best != null:
		return (best - v.global_position).normalized()
	_side = -_side
	return Ballistics.side_dir(fwd, _side)


## from에서 dir 쪽으로 겨눌 방향: 부채꼴 안에 표적이 있으면 그쪽, 없으면 dir 그대로
func aim(from: Vector2, dir: Vector2, reach: float, own: Vehicle) -> Vector2:
	var t: Variant = target(from, dir, reach, own)
	return dir if t == null else (t - from).normalized()


## from에서 dir 쪽 부채꼴 안의 가장 겨누기 쉬운 표적(살아 있는 사람·멀쩡한 차) 위치. 없으면 null
func target(from: Vector2, dir: Vector2, reach: float, own: Vehicle) -> Variant:
	var targets: Array[Vector2] = []
	for p in pedestrians.peds:
		if p.active and not p.is_dead() and not p.npc.protected:
			targets.append(p.global_position)
	for v in vehicles:
		if v != own and not v.wrecked:
			targets.append(v.global_position)
	for h in _police_helis():
		targets.append(h.global_position)   # 떠 있어도 총알은 밑의 땅 점으로 잰다 (Combat._air_target)
	var k := Ballistics.pick_target(from, dir, targets, reach)
	return null if k < 0 else targets[k]


## from에서 마우스 커서 쪽 방향. 커서가 사람 그림(발끝~머리) 위에 있으면 그 사람의 발밑을 겨눈다 —
## 2.5D에서는 서 있는 사람이 땅에서 위로 그려져, 몸을 누르면 바닥 점은 그 사람 뒤가 된다.
func mouse_dir(from: Vector2) -> Vector2:
	if not player.control.is_local():
		var rel := player.control.read().aim_world - from
		return rel.normalized() if rel.length() > 2.0 else Vector2.UP.rotated(player.facing)
	var vp := player.get_viewport()
	return screen_dir(from, vp.get_mouse_position(), vp.canvas_transform)


## 마우스 커서가 가리키는 땅 점 (사람 그림 위면 그 사람의 발밑). from은 땅 높이를 잴 곳
func mouse_point(from: Vector2) -> Vector2:
	if not player.control.is_local():
		return player.control.read().aim_world
	var vp := player.get_viewport()
	return screen_point(from, vp.get_mouse_position(), vp.canvas_transform)


## 화면 점 m(캔버스 변환 ct)을 겨눌 때 from에서 나갈 방향
func screen_dir(from: Vector2, m: Vector2, ct: Transform2D) -> Vector2:
	var rel := screen_point(from, m, ct) - from
	return rel.normalized() if rel.length() > 2.0 else Vector2.UP.rotated(player.facing)


## 화면 점 m이 가리키는 땅 점: 사람 그림(발끝~머리) 가까이면 그 사람의 발밑, 아니면 from 높이의 땅
func screen_point(from: Vector2, m: Vector2, ct: Transform2D) -> Vector2:
	var zoom := (ct.basis_xform(IsoView.LIFT)).length() if IsoView.enabled else ct.x.length()
	var up := IsoView.PERSON_HEIGHT if IsoView.enabled else 0.0
	var best: Variant = null
	var best_d := AIM_PICK * zoom
	for p in pedestrians.peds:
		if not p.active or p.is_dead() or p.npc.protected:
			continue
		var g := IsoView.ground(p.global_position)
		var a := ct * (p.global_position + IsoView.lift(g))
		var b := ct * (p.global_position + IsoView.lift(g + up * p.npc.body_scale))
		var d := m.distance_to(Geometry2D.get_closest_point_to_segment(m, a, b))
		if d < best_d:
			best_d = d
			best = p.global_position
	# 떠 있는 헬기: 그림(밑의 땅 점에서 높이만큼 위) 몸통 둘레를 누르면 그 헬기를 겨눈다
	var air: Array[Node2D] = []
	air.assign(_police_helis())
	for v in vehicles:
		if v.stats.flies and v.airborne() and not v.wrecked and v != director.current_vehicle:
			air.append(v)
	for h in air:
		var body := ct * (h.global_position + IsoView.lift(Combat._air_height(h) if IsoView.enabled else 0.0))
		var r: float = (h as PoliceHeli).hit_radius() if h is PoliceHeli else (h as Vehicle).stats.size.y * Combat.AIR_HIT_RADIUS
		var d := m.distance_to(body) - r * zoom * HELI_PICK
		if d < best_d:
			best_d = d
			best = h.global_position
	return best if best != null else ct.affine_inverse() * m - IsoView.lift(IsoView.ground(from))


# ── 표적 고르기 ───────────────────────────────────────────

## 고른 사람이 있고 아직 칠 수 있다
func locked() -> bool:
	return selected != null and is_instance_valid(selected) and selectable(selected)


func selectable(p: Pedestrian) -> bool:
	return p.active and not p.is_dead() and not p.npc.protected


func _lock_dir(from: Vector2) -> Vector2:
	var rel := selected.global_position - from
	return rel.normalized() if rel.length() > 1.0 else Vector2.UP.rotated(player.facing)


## 고른다 (null이면 푼다). 고른 사람은 머리 위 체력 막대를 늘 띄운다 (Pedestrian.targeted)
func select(p: Pedestrian) -> void:
	if p == selected:
		return
	if selected != null and is_instance_valid(selected):
		selected.targeted = false
		selected.queue_redraw()
	selected = p
	if p != null:
		p.targeted = true
		p.queue_redraw()


## 기절·멀어짐·차 타기면 푼다
func _check_selected() -> void:
	if selected == null:
		return
	if not locked() or director.current_vehicle != null or player.is_dead() \
			or selected.global_position.distance_to(player.global_position) > SELECT_DROP:
		select(null)


## Tab: 가까운 사람부터 차례로 (마지막 다음은 처음). 고를 사람이 없으면 푼다
func cycle_target() -> void:
	if director.current_vehicle != null or player.is_dead():
		return
	var me := player.global_position
	var list: Array[Pedestrian] = []
	for p in pedestrians.peds:
		if selectable(p) and p.global_position.distance_to(me) < SELECT_RANGE:
			list.append(p)
	if list.is_empty():
		select(null)
		return
	list.sort_custom(func(a: Pedestrian, b: Pedestrian) -> bool:
		return a.global_position.distance_squared_to(me) < b.global_position.distance_squared_to(me))
	select(list[(list.find(selected) + 1) % list.size()])


## 화면 점 m(캔버스 변환 ct) 가까이 그려진 사람 (없으면 null) — 오른쪽 클릭으로 고르기
func pick_person(m: Vector2, ct: Transform2D) -> Pedestrian:
	var zoom := (ct.basis_xform(IsoView.LIFT)).length() if IsoView.enabled else ct.x.length()
	var up := IsoView.PERSON_HEIGHT if IsoView.enabled else 0.0
	var best: Pedestrian = null
	var best_d := SELECT_PICK * zoom
	for p in pedestrians.peds:
		if not selectable(p):
			continue
		var g := IsoView.ground(p.global_position, p.level) if IsoView.enabled else 0.0
		var a := ct * (p.global_position + IsoView.lift(g))
		var b := ct * (p.global_position + IsoView.lift(g + up * p.npc.body_scale))
		var d := m.distance_to(Geometry2D.get_closest_point_to_segment(m, a, b))
		if d < best_d:
			best_d = d
			best = p
	return best


## 떨어지지 않은 경찰·군 헬기 (자동 조준·커서 겨누기)
func _police_helis() -> Array:
	if combat == null or combat.police == null:
		return []
	return combat.police.helis.filter(func(h: PoliceHeli): return is_instance_valid(h) and not h.down)


## 한 번 누르면 한 공격, 진행 중에는 다음 공격 한 번만 예약한다.
func _request_punch() -> bool:
	if not player.input_enabled or player.is_dead() or player.knocked_down or director.is_entering():
		return false
	if _punch_active:
		_punch_queued = true
		return false
	if not player.arsenal.can_fire():
		return false
	var count := PersonRig.punch_attacks().size()
	_punch_index = (_punch_index + 1) % count if _combo_left > 0.0 else 0
	_punch_spec = PersonRig.punch_attacks()[_punch_index]
	_punch_dir = _lock_dir(player.global_position) if locked() else mouse_dir(player.global_position) if _aiming() else aim(player.global_position, Vector2.UP.rotated(player.facing), Player.FIST.max_range + 10.0, null)
	player.face(_punch_dir, float(_punch_spec["duration"]))
	_punch_active = true
	_punch_queued = false
	_punch_hit = false
	_punch_elapsed = 0.0
	player.arsenal.fire()
	player.set_meta(&"punch_state", {"index": _punch_index, "elapsed": 0.0, "facing": player.facing})
	player.set_meta(&"combat_stance", true)
	return true


## 그림과 피해가 같은 물리 시계를 쓴다. 타격 시점은 공격마다 한 번만 통과한다.
func _step_punch(delta: float) -> void:
	if player.is_dead() or player.knocked_down or not player.input_enabled or director.current_vehicle != null or director.is_entering() or player.arsenal.current() != Player.FIST:
		_cancel_punch()
		return
	if not _punch_active:
		_combo_left = maxf(0.0, _combo_left - delta)
		if _stance_left > 0.0:
			_stance_left -= delta
			if _stance_left <= 0.0 and player.has_meta(&"combat_stance"):
				player.remove_meta(&"combat_stance")
		return
	_punch_elapsed += delta
	player.facing = Vector2.UP.angle_to(_punch_dir)
	player.set_meta(&"punch_state", {"index": _punch_index, "elapsed": _punch_elapsed, "facing": player.facing})
	var duration := float(_punch_spec["duration"])
	var hit_at := duration * float(_punch_spec["hit_frame"]) / float(_punch_spec["frames"])
	if not _punch_hit and _punch_elapsed >= hit_at:
		_punch_hit = true
		combat.fire(player.global_position, _punch_dir, Player.FIST, true, [player.get_rid()], 0.0, player.level)
	if _punch_elapsed >= duration:
		_punch_active = false
		player.remove_meta(&"punch_state")
		_combo_left = Player.COMBO_GAP
		_stance_left = STANCE_HOLD
		if _punch_queued:
			_punch_queued = false
			_request_punch()


func _cancel_punch() -> void:
	_punch_active = false
	_punch_queued = false
	_combo_left = 0.0
	_punch_index = -1
	if player.has_meta(&"punch_state"):
		player.remove_meta(&"punch_state")
	if player.has_meta(&"combat_stance"):
		player.remove_meta(&"combat_stance")
