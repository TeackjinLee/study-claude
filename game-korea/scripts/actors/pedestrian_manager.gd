class_name PedestrianManager
extends Node2D
## 보행자 생성·감지·공포 전파·LOD.
## 배치와 행동 RNG는 고정 시드 하나에서 나온다 — 같은 입력이면 같은 결과.

signal pedestrian_hit(ped: Pedestrian, vehicle: Vehicle, speed: float)
signal person_hurt(ped: Pedestrian, by_player: bool, killed: bool)   ## 차·총·주먹·폭발 — 피해는 모두 damage()를 거친다

const COUNT := 24
const SEED := 20261011
## 거리에 나오는 종. 학생·어르신·아이는 뺐다 (사용자 요청 2026-10-16 — 데이터 파일은 남겨 둔다)
const NPC_TYPES: Array[NpcType] = [
	preload("res://data/npc/civ_m.tres"),
	preload("res://data/npc/civ_f.tres"),
	preload("res://data/npc/office.tres"),
	preload("res://data/npc/homeless.tres"),
	preload("res://data/npc/foreigner.tres"),
	preload("res://data/npc/merchant.tres"),
	preload("res://data/npc/dj.tres"),
	preload("res://data/npc/busker.tres"),
	preload("res://data/npc/flyer.tres"),
	preload("res://data/npc/traffic_cop.tres"),
]
const TALK_RANGE := 48.0         ## 주인공이 이 안에 TALK_DELAY초 서 있으면 말을 건다 (docs/02 §5.3)
const TALK_DELAY := 2.0
const TALK_COOLDOWN := 10.0

const SENSE_RANGE := 260.0
const HIT_SPEED := 80.0          ## 이보다 빠른 차와 겹치면 넘어진다
const DODGE_SPEED := 60.0        ## 이보다 빠른 차만 피한다
const DODGE_LOOKAHEAD := 1.2     ## 이 시간(초) 안에 닿을 차를 피한다
const DODGE_MARGIN := 22.0
const PANIC_SPEED := 300.0       ## 이보다 빠른 차가 나를 향해 오거나 바짝 스치면 공포
const PANIC_RANGE := 70.0
const PANIC_MARGIN := 60.0       ## 차 진행 경로에서 이만큼 안이면 '나를 향해 온다'

const FEAR_RADIUS := 160.0
const FEAR_HOPS := 2
const ACTIVE_RANGE := 1500.0
const LOD_INTERVAL := 0.25
const MAINTAIN_INTERVAL := 1.0
const BODY_TIME := 20.0          ## 시신은 이만큼 지나고 화면 밖이면 치운다
const OFFSCREEN := 950.0
const RESPAWN_DISTANCE := 1100.0 ## 죽은 시민 수만큼 카메라에서 이보다 먼 인도에 새로 걷게 한다
## 도시가 넓어서 시민은 카메라 둘레에만 둔다: 블록 가운데가 이 반경 안인 열린 블록에 생기고,
## DESPAWN_DISTANCE보다 멀어지면 치운다
const STREAM_RADIUS := 2400.0
const DESPAWN_DISTANCE := 3200.0

var vehicles: Array[Vehicle] = []
var peds: Array[Pedestrian] = []
var player: Player
## 게임 시각 (0~24). 시간대에 따라 나오는 사람이 다르다 (DayCycle이 정한다)
var hour := 12.0
var _still := 0.0
var _talked := {}                ## 보행자 → 다시 말할 수 있는 시각
## 카메라가 없을 때(시작 직후) 시민을 모아 둘 곳
var spawn_center := City.start_position()
var rng := RandomNumberGenerator.new()
var _lod_timer := 0.0
var _maintain_timer := MAINTAIN_INTERVAL


func _ready() -> void:
	rng.seed = SEED
	for i in COUNT:
		_spawn_on_sidewalk()


func _spawn_on_sidewalk() -> Pedestrian:
	var blocks := nearby_blocks(_center(), 0.0, STREAM_RADIUS)
	if blocks.is_empty():
		return null
	var block := blocks[rng.randi() % blocks.size()]
	var p := Pedestrian.new()
	p.setup(_pick_type(block), rng, _walk_loop(block), rng.randi_range(0, 3), rng.randf(),
		1 if rng.randf() < 0.5 else -1)
	add(p)
	return p


## 걷게 할 길: 보통은 블록 둘레 인도, 랜드마크 블록이면 셋 중 둘은 부지 안 공터(광장·골목·승강장)
## (무작위를 더 뽑지 않는다 — 같은 시드면 보행자 배치가 같다)
func _walk_loop(block: Vector2i) -> PackedVector2Array:
	var lots: Array = City.lot_loops.get(block, [])
	if lots.is_empty() or peds.size() % 3 == 0:
		return City.sidewalk_loop(block)
	return lots[peds.size() % lots.size()]


## 차에서 끌려 나온 운전자 등: pos에서 away 방향으로 도망치는 보행자를 만든다 (npc가 없으면 일반 시민)
func spawn_fleeing(pos: Vector2, away: Vector2, npc: NpcType = null) -> Pedestrian:
	if npc == null:
		npc = NPC_TYPES[0]
	var p := Pedestrian.new()
	p.setup(npc, rng, City.sidewalk_loop(City.nearest_block(pos)), 0, 0.0, 1)
	p.position = pos
	add(p)
	p.panic(away)
	return p


## 경찰 등 다른 시스템이 만든 사람도 여기 넣으면 차 회피·치임 감지를 똑같이 받는다
func add(p: Pedestrian) -> void:
	add_child(p)
	peds.append(p)


## 장이 바뀌었다: 통제 구역(담 안)에 남은 시민은 치운다
func on_map_changed() -> void:
	for p: Pedestrian in peds.duplicate():
		if is_alive_civilian(p) and not CityMap.is_open_block(City.nearest_block(p.global_position)):
			remove(p)


func remove(p: Pedestrian) -> void:
	peds.erase(p)
	p.queue_free()


## center에서 블록 가운데가 [near, far] 거리인 열린 땅 블록들
static func nearby_blocks(center: Vector2, near: float, far: float) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var c := CityMap.block_at(center)
	var reach := ceili(far / City.PITCH) + 1
	for j in range(c.y - reach, c.y + reach + 1):
		for i in range(c.x - reach, c.x + reach + 1):
			var b := Vector2i(i, j)
			if not CityMap.is_open_block(b):
				continue
			var d := City.block_rect(i, j).get_center().distance_to(center)
			if d >= near and d <= far:
				result.append(b)
	return result


func _center() -> Vector2:
	var camera := ChaseCamera.current_cam() if is_inside_tree() else null
	return camera.global_position if camera else spawn_center


## 그 블록 구역·지금 시각에 나올 수 있는 종 중에서 비중대로 고른다
func _pick_type(block := Vector2i.ZERO) -> NpcType:
	var dist := CityMap.district_of(block)
	var total := 0.0
	for t in NPC_TYPES:
		total += _weight(t, dist)
	var roll := rng.randf() * total
	for t in NPC_TYPES:
		roll -= _weight(t, dist)
		if roll <= 0.0 and _weight(t, dist) > 0.0:
			return t
	return NPC_TYPES[0]


func _weight(t: NpcType, dist: DistrictType) -> float:
	if not t.districts.is_empty() and (dist == null or not t.districts.has(dist.id)):
		return 0.0
	if not in_hours(t.hours, hour):
		return 0.0
	return t.spawn_weight


## h시가 [from, to) 안인가 (from > to면 자정을 넘긴다)
static func in_hours(range_: Vector2i, h: float) -> bool:
	if range_.x <= range_.y:
		return h >= range_.x and h < range_.y
	return h >= range_.x or h < range_.y


func _physics_process(delta: float) -> void:
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = LOD_INTERVAL
		_update_lod()
	_maintain_timer -= delta
	if _maintain_timer <= 0.0:
		_maintain_timer = MAINTAIN_INTERVAL
		_maintain()
	for p in peds:
		if p.active and not p.is_dead():
			_sense(p)
	_talk(delta)


## 주인공이 걸음을 멈추고 곁에 서 있으면 가까운 사람이 한마디 한다
func _talk(delta: float) -> void:
	if player == null or not player.visible or player.velocity.length() > 10.0:
		_still = 0.0
		return
	_still += delta
	if _still < TALK_DELAY:
		return
	var now := Time.get_ticks_msec() / 1000.0
	for p in peds:
		if p.active and not p.is_dead() and not p.npc.lines.is_empty() and p.state in [Pedestrian.State.WALK, Pedestrian.State.IDLE] \
				and p.global_position.distance_to(player.global_position) < TALK_RANGE and now >= _talked.get(p, 0.0):
			p.say(p.npc.lines[(p.get_instance_id() + int(now)) % p.npc.lines.size()], 3.0)
			_talked[p] = now + TALK_COOLDOWN
			_still = 0.0
			return

## 사람에게 피해를 준다 (차에 치임·총·주먹·폭발 공통). 넘어지거나 죽으면 주변이 겁먹는다.
func damage(p: Pedestrian, amount: float, away: Vector2, by_player: bool, knock: bool) -> void:
	if p.is_dead():
		return
	if p.npc.protected:
		p.hurt(amount, away, knock)   # 다치지 않고 도망만 친다
		return
	var killed := p.hurt(amount, away, knock)
	person_hurt.emit(p, by_player, killed)
	spread_fear(p, p.global_position - away.normalized() * 40.0)


## 총소리·폭발: pos 주변 radius 안의 사람들이 반대쪽으로 도망친다
func scare(pos: Vector2, radius: float) -> void:
	for p in peds:
		if p.active and not p.is_dead() and p.global_position.distance_to(pos) < radius:
			p.panic(p.global_position - pos)


func is_alive_civilian(p: Pedestrian) -> bool:
	return not p.is_dead() and not (p is PoliceOfficer) and not (p is GangMember)


## 오래된 시신을 치우고, 죽은 시민 수만큼 화면 밖에서 새로 걷게 한다
func _maintain() -> void:
	var camera := ChaseCamera.current_cam()
	var center := camera.global_position if camera else Vector2.ZERO
	var alive := 0
	var dropped := false
	for p: Pedestrian in peds.duplicate():
		if p.is_dead():
			var far := p.global_position.distance_to(center) > OFFSCREEN
			if far and (p.dead_time > BODY_TIME or not p.active):
				remove(p)
		elif is_alive_civilian(p):
			# 멀리 떨어진 시민은 하나씩 치우고 카메라 둘레에 새로 걷게 한다
			if not dropped and p.global_position.distance_to(center) > DESPAWN_DISTANCE and p.state != Pedestrian.State.FLEE:
				remove(p)
				dropped = true
			else:
				alive += 1
	if alive >= COUNT or camera == null:
		return
	var blocks := nearby_blocks(center, 0.0, STREAM_RADIUS)
	if blocks.is_empty():
		return
	for attempt in 10:
		var block := blocks[rng.randi() % blocks.size()]
		var loop := _walk_loop(block)
		var edge := rng.randi_range(0, 3)
		var t := rng.randf()
		var pos := loop[edge].lerp(loop[(edge + 1) % 4], t)
		if pos.distance_to(center) < RESPAWN_DISTANCE:
			continue
		var p := Pedestrian.new()
		p.setup(_pick_type(block), rng, loop, edge, t, 1 if rng.randf() < 0.5 else -1)
		add(p)
		return


func _sense(p: Pedestrian) -> void:
	for v in vehicles:
		var rel := p.global_position - v.global_position
		if rel.length() > SENSE_RANGE or v.airborne():   # 머리 위를 나는 헬기는 치지도, 피하지도 않는다
			continue
		var speed := v.speed()
		var local := v.to_local(p.global_position)
		var half := v.stats.size * 0.5 + Vector2(Pedestrian.RADIUS, Pedestrian.RADIUS)
		# 무한궤도는 느려도 밑에 든 사람을 깔아뭉갠다 (도는 중에도)
		var crushing := v.stats.tracked and (speed > Combat.CRUSH_MOVING or absf(v.motor.steer) > 0.2)
		if (speed > HIT_SPEED or crushing) and absf(local.x) < half.x and absf(local.y) < half.y:
			# 이미 넘어진 사람은 다시 치지 않는다 (한 번 부딪힌 걸 매 프레임 세지 않게). 아이는 늘 피한다
			if p.npc.protected:
				p.dodge(v.motor.velocity.orthogonal() * (1.0 if v.to_local(p.global_position).x >= 0.0 else -1.0))
			elif p.state != Pedestrian.State.KNOCKED:
				damage(p, p.npc.health * 2.0 if crushing else DamageModel.run_over_damage(speed), rel, v.controlled, true)
				pedestrian_hit.emit(p, v, speed)
			continue
		if speed < DODGE_SPEED:
			continue
		var heading := v.motor.velocity / speed
		var ahead := rel.dot(heading)
		var side := rel.dot(heading.orthogonal())
		var reach := speed * DODGE_LOOKAHEAD * p.npc.reaction
		if ahead > 0.0 and ahead < reach and absf(side) < v.stats.size.x * 0.5 + DODGE_MARGIN:
			p.dodge(heading.orthogonal() * (1.0 if side >= 0.0 else -1.0))
		var toward_me := ahead > 0.0 and ahead < reach and absf(side) < v.stats.size.x * 0.5 + PANIC_MARGIN
		if speed > PANIC_SPEED and (toward_me or rel.length() < PANIC_RANGE):
			if p.panic(rel):
				spread_fear(p, v.global_position)


## 겁먹은 보행자 주변으로 공포가 번진다 (FEAR_HOPS 단계까지)
func spread_fear(origin: Pedestrian, source: Vector2) -> void:
	var frontier: Array[Pedestrian] = [origin]
	for hop in FEAR_HOPS:
		var next: Array[Pedestrian] = []
		for from in frontier:
			for q in peds:
				if q == from or not q.active or q.state == Pedestrian.State.FLEE or q.is_dead():
					continue
				if q.global_position.distance_to(from.global_position) < FEAR_RADIUS:
					if q.panic(q.global_position - source):
						next.append(q)
		frontier = next


func _update_lod() -> void:
	var camera := ChaseCamera.current_cam()
	var center := camera.global_position if camera else Vector2.ZERO
	for p in peds:
		p.set_active(p.global_position.distance_to(center) < ACTIVE_RANGE)
