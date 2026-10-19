class_name PlayerWeapons
extends Node
## 주인공의 무기 입력: 쏘기(Ctrl·J·마우스 왼쪽), 무기 바꾸기(Q·E).
## 도보는 바라보는 쪽으로 쏘되 앞쪽 부채꼴 안의 표적을 자동으로 겨눈다.
## 차 안에서는 드라이브바이 — 진행 방향 좌우 중 표적이 있는 쪽으로, 없으면 번갈아 쏜다.
## 마우스를 쓰면(움직이거나 누르면) 커서 쪽으로 정확히 쏜다 — 부채꼴 자동 조준 없이, 커서가 사람 그림
## 위에 있을 때만 그 사람을 겨눈다. 드라이브바이는 커서가 있는 옆으로, 옆 방향에서 DRIVE_BY_SPREAD 안으로.
## 쏘기 키(Ctrl·J)·패드로 쏘면 다시 예전 방식이다.
## 차량 기관총은 차 안에서만 앞으로 쏜다. 소방차를 몰면 쏘기 버튼은 늘 물대포(앞으로).
## 포탑 달린 차(자주포·전술차량)를 몰면 포탑이 마우스 커서 쪽으로 돌고(Q·E는 포탑을 손으로 돌린다), 쏘기 버튼은 포탑 무기다.
## 자주포는 곡사포 — 커서가 있는 땅(사거리 안으로 당긴다)에 포탄이 떨어지고, 포신은 그 거리만큼 든다. 키보드만 쓰면 마지막 거리 그대로.
## 굴삭기는 상부가 커서 쪽으로 돌고 팔이 커서까지 뻗는다 — 쏘기 버튼은 퍼 올리기(찍은 곳의 차를 집고, 들고 있으면 놓는다).
## 불도저는 쏘기 버튼이 블레이드 올리기·내리기다.

const MUZZLE := 10.0
## 커서가 사람 몸(발끝~머리, 화면 px·줌 1)에서 이만큼 안이면 그 사람을 겨눈다
const AIM_PICK := 9.0
## 마우스로 겨눈 뒤 걸어도 커서 쪽을 바라보는 시간
const AIM_HOLD := 0.35
## 마우스 드라이브바이: 차 옆 방향에서 앞뒤로 틀 수 있는 각도
const DRIVE_BY_SPREAD := 0.6

var director: Director
var player: Player
var combat: Combat
var pedestrians: PedestrianManager
var vehicles: Array[Vehicle] = []
var _side := 1.0
var _mounted_cooldown := 0.0
## 마우스로 겨누는 중 (마우스를 움직이거나 누르면 켜지고, 쏘기 키·패드로 쏘면 꺼진다)
var mouse_aim := false
var _cross := false
const MOUNTED: Array[WeaponType] = [preload("res://data/weapons/water_cannon.tres"),
	preload("res://data/weapons/tank_cannon.tres"), preload("res://data/weapons/jeep_mg.tres")]


func _physics_process(delta: float) -> void:
	player.arsenal.update(delta)
	_mounted_cooldown = maxf(_mounted_cooldown - delta, 0.0)
	var v := director.current_vehicle
	if v and v.stats.turret_rate > 0.0 and not v.wrecked and not player.is_dead():
		_steer_turret(v, delta)
	if Input.is_action_pressed("fire"):
		if mouse_aim and director.current_vehicle == null and player.input_enabled and not player.is_dead():
			player.face(mouse_dir(player.global_position), AIM_HOLD)   # 연사 사이에도 커서를 따라 돈다
		shoot()


func _process(_delta: float) -> void:
	# 도보로 마우스 조준 중이면 십자 커서
	var cross := mouse_aim and director.current_vehicle == null and not player.is_dead()
	if cross != _cross:
		_cross = cross
		Input.set_default_cursor_shape(Input.CURSOR_CROSS if cross else Input.CURSOR_ARROW)


func _exit_tree() -> void:
	if _cross:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


## 조준 방식만 고른다 (GUI가 먹은 클릭도 보도록 _input에서)
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length_squared() > 4.0:
			mouse_aim = true
	elif event is InputEventMouseButton:
		if event.pressed:
			mouse_aim = true
	elif event.is_action_pressed("fire"):
		mouse_aim = false


func _unhandled_input(event: InputEvent) -> void:
	var v := director.current_vehicle
	if v and v.stats.blade and event.is_action_pressed("fire"):
		v.blade_up = not v.blade_up
		return
	if v and v.stats.turret_rate > 0.0:
		return   # 포탑 달린 차에서는 Q·E가 포탑을 돌린다 (_steer_turret)
	if event.is_action_pressed("weapon_next"):
		player.arsenal.cycle(1)
	elif event.is_action_pressed("weapon_prev"):
		player.arsenal.cycle(-1)


## 지금 무기로 한 번 쏜다. 못 쐈으면(연사 대기·차 안 주먹·조종 불가) false
func shoot() -> bool:
	var arsenal := player.arsenal
	var w := arsenal.current()
	var v := director.current_vehicle
	if player.is_dead() or director.is_entering():
		return false
	if v and v.stats.arm_reach.y > 0.0:
		return v.start_dig()
	if v and v.stats.blade:
		return false   # 블레이드는 누를 때 한 번씩 (_unhandled_input)
	if v and _mounted(v) and not v.wrecked:
		return _fire_mounted(v, _mounted(v))
	if not arsenal.can_fire():
		return false
	if v == null and (not player.input_enabled or w.vehicle_only):
		return false
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
		if mouse_aim:
			dir = mouse_dir(from)
			player.face(dir, AIM_HOLD)
		else:
			dir = aim(from, Vector2.UP.rotated(player.facing), w.max_range + 10.0, null)
			player.facing = Vector2.UP.angle_to(dir)
		if not w.melee:
			from += dir * MUZZLE
	arsenal.fire()
	combat.fire(from, dir, w, true, exclude, 0.0, v.level if v else player.level)
	if w.melee and v == null:
		player.punch()
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


## 포탑을 겨눈다: 마우스면 커서 쪽(곡사포는 커서까지 거리도), 아니면 Q·E로 돌린다
func _steer_turret(v: Vehicle, delta: float) -> void:
	var turn := Input.get_axis("weapon_prev", "weapon_next")
	if turn != 0.0:
		mouse_aim = false
		v.turret_goal = v.turret + turn * v.stats.turret_rate * delta * 1.5
	elif mouse_aim:
		var vp := player.get_viewport()
		var at := vp.canvas_transform.affine_inverse() * vp.get_mouse_position() - IsoView.lift(IsoView.ground(v.global_position))
		var rel := at - v.global_position
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
	if mouse_aim:
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
	var k := Ballistics.pick_target(from, dir, targets, reach)
	return null if k < 0 else targets[k]


## from에서 마우스 커서 쪽 방향. 커서가 사람 그림(발끝~머리) 위에 있으면 그 사람의 발밑을 겨눈다 —
## 2.5D에서는 서 있는 사람이 땅에서 위로 그려져, 몸을 누르면 바닥 점은 그 사람 뒤가 된다.
func mouse_dir(from: Vector2) -> Vector2:
	var vp := player.get_viewport()
	return screen_dir(from, vp.get_mouse_position(), vp.canvas_transform)


## 화면 점 m(캔버스 변환 ct)을 겨눌 때 from에서 나갈 방향
func screen_dir(from: Vector2, m: Vector2, ct: Transform2D) -> Vector2:
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
	var at: Vector2 = best if best != null else ct.affine_inverse() * m - IsoView.lift(IsoView.ground(from))
	var rel := at - from
	return rel.normalized() if rel.length() > 2.0 else Vector2.UP.rotated(player.facing)
