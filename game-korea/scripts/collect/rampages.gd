class_name Rampages
extends Node2D
## 광란 모드 (docs/05 §7, 아이콘 20개). 걸어서 빨간 해골 아이콘을 밟으면 시작한다:
## 그 무기를 받아 탄이 떨어지지 않고, time_limit 안에 목표(아무나·그 조직 조직원·차)를 count만큼 쓰러뜨리면 보상.
## 사람은 죽지 않으니 "쓰러뜨리기" = 기절시키기다. 끝나면(성공·실패) 원래 무기로 돌아간다.
## 끝낸 것은 저장되고(SaveGame.rampages) 아이콘이 사라진다. 실패하면 다시 밟아 또 할 수 있다.
## 미션·부업 중이거나 그 구역이 잠겨 있으면 아이콘이 꺼진다.

signal started(r: RampageType)
signal progressed(r: RampageType, n: int)
signal finished(r: RampageType, passed: bool, reward: int)

const REACH := 16.0
const RETRY_WAIT := 3.0              ## 끝난 뒤 이만큼은 다시 밟아도 시작하지 않는다 (서 있던 자리에서 바로 다시 켜지지 않게)

var director: Director
var player: Player
var wallet: Wallet
var pedestrians: PedestrianManager
var combat: Combat
var missions: MissionSystem
var jobs: SideJobs
var gangs: Array[GangType] = []
var done := {}                       ## 끝낸 id → true
var current: RampageType = null
var time_left := 0.0
var kills := 0
var _had := false                    ## 시작 전에 그 무기가 있었나
var _had_ammo := 0
var _held: WeaponType = null
var _wait := 0.0
var _t := 0.0


func _ready() -> void:
	z_index = -1
	material = Terrain.material()
	if pedestrians:
		pedestrians.person_hurt.connect(_on_person_hurt)
	if combat:
		combat.vehicle_exploded.connect(_on_vehicle_exploded)


func all() -> Array[RampageType]:
	return RampageList.ALL


func active() -> bool:
	return current != null


func restore(ids: Array) -> void:
	done.clear()
	for id in ids:
		done[StringName(id)] = true
	queue_redraw()


func available(r: RampageType) -> bool:
	return not done.has(r.id) and CityMap.is_open_block(r.block)


func gang_name(id: StringName) -> String:
	for g in gangs:
		if g.id == id:
			return g.display_name
	return String(id)


func title_text() -> String:
	var s := int(ceil(maxf(time_left, 0.0)))
	return Locale.t("광란!   %d:%02d") % [s / 60, s % 60]


func objective_text() -> String:
	return "%s   %d / %d" % [current.goal_text(gang_name(current.gang)), kills, current.count] if current else ""


func _physics_process(delta: float) -> void:
	_wait = maxf(_wait - delta, 0.0)
	if current:
		time_left -= delta
		if player.arsenal.has(current.weapon) and not current.weapon.infinite:
			player.arsenal.ammo[current.weapon] = current.weapon.max_ammo     # 하는 동안 탄이 떨어지지 않는다
		elif not player.arsenal.has(current.weapon):
			player.arsenal.give(current.weapon, current.weapon.max_ammo)
		if player.is_dead():
			_finish(false)
		elif time_left <= 0.0:
			_finish(kills >= current.count)
		return
	if _wait > 0.0 or director == null or director.current_vehicle or not player.visible or player.is_dead():
		return
	if (missions and missions.active()) or (jobs and jobs.active()):
		return
	for r in all():
		if available(r) and player.global_position.distance_to(r.position()) < REACH:
			start(r)
			return


func start(r: RampageType) -> void:
	if current:
		return
	current = r
	time_left = r.time_limit
	kills = 0
	var a := player.arsenal
	_held = a.current()
	_had = a.has(r.weapon)
	_had_ammo = a.ammo_of(r.weapon)
	a.give(r.weapon, r.weapon.max_ammo)
	a.index = a.weapons.find(r.weapon)
	a.changed.emit()
	started.emit(r)
	queue_redraw()


## 체포·기절: 실패로 끝낸다 (무기는 Main이 곧 압수한다)
func abort() -> void:
	if current:
		_finish(false)


func _on_person_hurt(p: Pedestrian, by_player: bool, killed: bool) -> void:
	if current == null or not by_player or not killed:
		return
	match current.target:
		RampageType.Target.CARS:
			return
		RampageType.Target.GANG:
			if not (p is GangMember) or (p as GangMember).gang == null or (p as GangMember).gang.id != current.gang:
				return
	_count()


func _on_vehicle_exploded(_v: Vehicle, by_player: bool) -> void:
	if current and by_player and current.target == RampageType.Target.CARS:
		_count()


func _count() -> void:
	kills += 1
	progressed.emit(current, kills)
	if kills >= current.count:
		_finish(true)


func _finish(passed: bool) -> void:
	var r := current
	current = null
	_wait = RETRY_WAIT
	# 무기 되돌리기: 없던 무기면 빼고, 있던 무기면 예전 탄으로
	var a := player.arsenal
	if a.has(r.weapon):
		if not _had:
			a.weapons.erase(r.weapon)
			a.ammo.erase(r.weapon)
		elif not r.weapon.infinite:
			a.ammo[r.weapon] = _had_ammo
	var back := a.weapons.find(_held)
	a.index = back if back >= 0 else 0
	a.changed.emit()
	var pay := 0
	if passed:
		done[r.id] = true
		pay = r.reward
		if wallet:
			wallet.earn(pay)
	finished.emit(r, passed, pay)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## 빨간 해골 아이콘 — 바닥에서 숨 쉬듯 깜박인다
func _draw() -> void:
	if current:
		return
	var cam := ChaseCamera.current_cam()
	var near := cam.global_position if cam else Vector2.ZERO
	var pulse := 0.6 + 0.4 * sin(_t * 4.0)
	for r in all():
		if not available(r):
			continue
		var p := r.position()
		if cam and p.distance_squared_to(near) > 1400.0 * 1400.0:
			continue
		FireFx.circle(self, p, 22.0, Color(0.9, 0.1, 0.1, 0.2 + 0.15 * pulse))
		var bone := Color(0.96, 0.93, 0.86)
		draw_circle(p + Vector2(0, -2), 10.0, bone)
		draw_rect(Rect2(p + Vector2(-6, 5), Vector2(12, 6)), bone)
		draw_circle(p + Vector2(-3.8, -2.5), 2.8, Color(0.8, 0.05, 0.05, 0.6 + 0.4 * pulse))
		draw_circle(p + Vector2(3.8, -2.5), 2.8, Color(0.8, 0.05, 0.05, 0.6 + 0.4 * pulse))
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, 1), p + Vector2(-1.6, 4), p + Vector2(1.6, 4)]), Color(0.25, 0.05, 0.05))
		for x in [-3.0, 0.0, 3.0]:
			draw_line(p + Vector2(x, 7), p + Vector2(x, 11), Color(0.25, 0.05, 0.05), 1.0)
