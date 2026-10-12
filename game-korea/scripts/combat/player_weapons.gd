class_name PlayerWeapons
extends Node
## 주인공의 무기 입력: 쏘기(Ctrl·J·마우스 왼쪽), 무기 바꾸기(Q·E).
## 도보는 바라보는 쪽으로 쏘되 앞쪽 부채꼴 안의 표적을 자동으로 겨눈다.
## 차 안에서는 드라이브바이 — 진행 방향 좌우 중 표적이 있는 쪽으로, 없으면 번갈아 쏜다.
## 차량 기관총은 차 안에서만 앞으로 쏜다. 소방차를 몰면 쏘기 버튼은 늘 물대포(앞으로).

const MUZZLE := 10.0

var director: Director
var player: Player
var combat: Combat
var pedestrians: PedestrianManager
var vehicles: Array[Vehicle] = []
var _side := 1.0
var _mounted_cooldown := 0.0
const MOUNTED: Array[WeaponType] = [preload("res://data/weapons/water_cannon.tres")]


func _physics_process(delta: float) -> void:
	player.arsenal.update(delta)
	_mounted_cooldown = maxf(_mounted_cooldown - delta, 0.0)
	if Input.is_action_pressed("fire"):
		shoot()


func _unhandled_input(event: InputEvent) -> void:
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
		dir = aim(from, Vector2.UP.rotated(player.facing), w.max_range + 10.0, null)
		player.facing = Vector2.UP.angle_to(dir)
		if not w.melee:
			from += dir * MUZZLE
	arsenal.fire()
	combat.fire(from, dir, w, true, exclude)
	return true


## 이 차에 달린 무기 (없으면 null)
func _mounted(v: Vehicle) -> WeaponType:
	for w in MOUNTED:
		if w.mounted_on.has(v.stats.id):
			return w
	return null


func _fire_mounted(v: Vehicle, w: WeaponType) -> bool:
	if _mounted_cooldown > 0.0:
		return false
	_mounted_cooldown = w.fire_interval
	var dir := v.motor.forward()
	var exclude: Array[RID] = [v.get_rid()]
	combat.fire(v.global_position + dir * (v.stats.size.y * 0.5 + 4.0), dir, w, true, exclude)
	return true


## 차 옆으로 쏠 방향: 표적이 있는 쪽(둘 다면 가까운 쪽)을 겨누고, 양쪽 다 없으면 번갈아
func _drive_by_dir(v: Vehicle, w: WeaponType) -> Vector2:
	var fwd := v.motor.forward()
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
