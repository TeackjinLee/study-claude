class_name GangManager
extends Node
## 갱 조직원들: 구역에 조직원을 세우고, 누구와 싸울지 정하고, 쏜다(폭력배는 주먹).
## 싸우는 조건 — 미션 경호원(guard)이거나, 맞아서 화가 났거나(aggro), 그 갱 존경도가 적대 수준이다.
## 조직원을 죽이면 그 갱 존경도가 깎이고, 주변 동료가 화가 난다. 아군(존경도 높음)은 맞아도 참는다.

const SEED := 5151
const SIGHT := 420.0             ## 싸울 조직원이 주인공을 알아보는 거리 (건물에 가리면 못 본다)
const GIVE_UP := 700.0           ## 싸우다 이보다 멀어지면 그만둔다
const SHOOT_RANGE := 320.0
const SHOOT_DELAY := [1.0, 1.6]  ## 발포 간격 = 무기 연사 간격 × 이 범위의 무작위 배율
const AGGRO_TIME := 20.0
const AGGRO_RADIUS := 300.0      ## 동료가 맞으면 이 안의 같은 갱 조직원이 화가 난다
const MAINTAIN_INTERVAL := 1.0
const OFFSCREEN := 950.0
const RESPAWN_DISTANCE := 1100.0

var gangs: Array[GangType] = []
var respect: Respect
var director: Director
var player: Player
var combat: Combat
var pedestrians: PedestrianManager
var members: Array[GangMember] = []
var rng := RandomNumberGenerator.new()
var shoot_rng := RandomNumberGenerator.new()
var _maintain_timer := MAINTAIN_INTERVAL


func _ready() -> void:
	rng.seed = SEED
	shoot_rng.seed = SEED + 1
	pedestrians.person_hurt.connect(_on_person_hurt)
	for g in gangs:
		for i in g.member_count:
			_spawn_resident(g, false)


func gang(id: StringName) -> GangType:
	for g in gangs:
		if g.id == id:
			return g
	return null


## 미션 표적·경호원을 pos에 세운다. 자리를 지키다 주인공이 다가오면 싸운다.
func spawn_guard(npc: NpcType, pos: Vector2) -> GangMember:
	var m := GangMember.new()
	m.setup(npc, rng, City.sidewalk_loop(City.nearest_block(pos)), 0, 0.0, 1)
	m.position = pos
	m.gang = gang(npc.gang)
	m.guard = true
	m.home = pos
	m.facing = rng.randf() * TAU
	pedestrians.add(m)
	members.append(m)
	return m


## 미션이 끝났다: 남은 경호원은 평범한 조직원이 되어 걷다가 화면 밖에서 사라진다
func release(m: GangMember) -> void:
	if is_instance_valid(m):
		m.guard = false
		m.resume_walking()


func is_hostile(m: GangMember) -> bool:
	return m.guard or m.aggro > 0.0 or (m.gang != null and respect.is_hostile(m.gang))


## 체포·사망 후 다시 시작: 화난 조직원을 진정시킨다
func calm() -> void:
	for m in members:
		m.aggro = 0.0
		m.fighting = false


## 열린 구역의 집 블록 중 카메라 가까운 것 (가까운 게 없으면 열린 것 아무거나)
func _home_blocks(g: GangType, center: Vector2) -> Array[Vector2i]:
	var near: Array[Vector2i] = []
	var open: Array[Vector2i] = []
	for b in g.home_blocks:
		if not CityMap.is_open_block(b):
			continue
		open.append(b)
		if City.block_rect(b.x, b.y).get_center().distance_to(center) < PedestrianManager.STREAM_RADIUS:
			near.append(b)
	return near if not near.is_empty() else open


func _has_home_near(g: GangType, center: Vector2) -> bool:
	for b in g.home_blocks:
		if CityMap.is_open_block(b) and City.block_rect(b.x, b.y).get_center().distance_to(center) < PedestrianManager.STREAM_RADIUS:
			return true
	return false


func _spawn_resident(g: GangType, far: bool) -> GangMember:
	var center := _camera_center()
	var homes := _home_blocks(g, center)
	if homes.is_empty():
		return null
	for attempt in 10:
		var block: Vector2i = homes[rng.randi() % homes.size()]
		var loop := City.sidewalk_loop(block)
		var edge := rng.randi_range(0, 3)
		var t := rng.randf()
		var pos := loop[edge].lerp(loop[(edge + 1) % 4], t)
		if far and pos.distance_to(center) < RESPAWN_DISTANCE:
			continue
		var m := GangMember.new()
		m.setup(g.member, rng, loop, edge, t, 1 if rng.randf() < 0.5 else -1)
		m.gang = g
		m.resident = true
		pedestrians.add(m)
		members.append(m)
		return m
	return null


func _physics_process(delta: float) -> void:
	_maintain_timer -= delta
	if _maintain_timer <= 0.0:
		_maintain_timer = MAINTAIN_INTERVAL
		_maintain()
	var pcar := director.current_vehicle
	var ppos := director.controlled_target().global_position
	var space := get_viewport().world_2d.direct_space_state
	var in_air := pcar != null and pcar.airborne()   # 떠 있는 헬기는 건물 너머로도 보인다
	for m: GangMember in members.duplicate():
		if not is_instance_valid(m) or m.is_dead():
			members.erase(m)
			continue
		if not m.active or player.is_dead() or not is_hostile(m):
			m.fighting = false
			continue
		var d := m.global_position.distance_to(ppos)
		if m.fighting:
			m.fighting = d < GIVE_UP
		else:
			m.fighting = d < SIGHT and (in_air or _clear(space, m.global_position, ppos))
		if not m.fighting:
			continue
		m.goal = ppos
		# 경찰과 같은 규칙: 빨리 달아나는 차는 못 맞힌다
		if pcar == null or pcar.speed() < PoliceDispatcher.CAR_ESCAPE_SPEED:
			_shoot(m, space, ppos, in_air)


func _shoot(m: GangMember, space: PhysicsDirectSpaceState2D, target: Vector2, in_air := false) -> void:
	var w := m.npc.weapon
	if combat == null or w == null or m.reload > 0.0 or m.state != Pedestrian.State.WALK:
		return
	if in_air and w.melee:
		return      # 하늘의 헬기는 주먹·칼이 안 닿는다
	var pos := m.global_position
	var reach := w.max_range + Player.RADIUS if w.melee else SHOOT_RANGE
	if pos.distance_to(target) > reach or not (in_air or _clear(space, pos, target)):
		return
	m.reload = w.fire_interval * shoot_rng.randf_range(SHOOT_DELAY[0], SHOOT_DELAY[1])
	var dir := (target - pos).normalized()
	m.facing = Vector2.UP.angle_to(dir)
	var exclude: Array[RID] = [m.get_rid()]
	if w.melee and m.npc.stat_power > 0:
		# 공격 한 번의 사본에만 적용한다 — 플레이어와 다른 NPC의 무기는 그대로다.
		w = w.duplicate() as WeaponType
		w.damage *= m.npc.melee_multiplier()
	combat.fire(pos if w.melee else pos + dir * 10.0, dir, w, false, exclude, 0.0, m.level)


func _clear(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> bool:
	return space.intersect_ray(PhysicsRayQueryParameters2D.create(from, to, Layers.WORLD)).is_empty()


## 조직원이 다치거나 죽었다. 주인공 짓이면 존경도가 깎이고 동료가 화가 난다.
func _on_person_hurt(p: Pedestrian, by_player: bool, killed: bool) -> void:
	if not (p is GangMember) or not by_player:
		return
	var g: GangType = (p as GangMember).gang
	if g == null:
		return
	if killed:
		var penalty := g.mission_kill_penalty if (p as GangMember).guard else g.kill_penalty
		respect.change(g.id, -penalty)
		# 라이벌 갱은 반긴다
		for other in gangs:
			if other.rival == g.id:
				respect.change(other.id, roundi(penalty * 0.5))
	elif respect.is_ally(g):
		return
	for m in members:
		if m.gang == g and not m.is_dead() and m.global_position.distance_to(p.global_position) < AGGRO_RADIUS:
			m.aggro = AGGRO_TIME


## 죽은 조직원 수만큼 화면 밖에서 새로 세우고, 미션이 끝난 뒤 남은 사람은 화면 밖에서 치운다
func _maintain() -> void:
	var center := _camera_center()
	var counts := {}
	var dropped := false
	for m in members.duplicate():
		if not is_instance_valid(m):
			members.erase(m)   # 기절해 구급대가 실어 갔다
			continue
		var dist := (m as GangMember).global_position.distance_to(center)
		# 아주 멀리 남은 조직원은 하나씩 치우고, 주인공 가까이에 그 갱 집 블록이 있으면 거기 다시 세운다
		if m.resident and not dropped and m.aggro <= 0.0 and dist > PedestrianManager.DESPAWN_DISTANCE \
				and _has_home_near(m.gang, center):
			members.erase(m)
			pedestrians.remove(m)
			dropped = true
		elif m.resident:
			counts[m.gang] = counts.get(m.gang, 0) + 1
		elif not m.guard and dist > OFFSCREEN:
			members.erase(m)
			pedestrians.remove(m)
	for g in gangs:
		if counts.get(g, 0) < g.member_count:
			_spawn_resident(g, true)


func _camera_center() -> Vector2:
	var camera := ChaseCamera.current_cam()
	return camera.global_position if camera else Vector2.ZERO
