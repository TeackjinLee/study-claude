class_name StreetEvents
extends Node
## 랜덤 거리 이벤트 (docs/02 §랜덤 거리 이벤트): 주인공 근처에서 도둑이 가방을 낚아채거나 강도가 시민을 위협한다.
## 범인을 붙잡으면(넘어뜨리면) 보상 + 수배 −1, 기절시켜 막으면 보상 절반(구급대가 실어 간다), 놓치면 그만이다.
## 한 번에 하나만 벌어지고, 미션·부업 중이거나 수배 ★2 이상이면 벌어지지 않는다.
## 무작위는 자기 rng만 쓴다 — 보행자·경찰 rng를 뽑으면 다른 결과(★3 도주 등)가 바뀐다.

signal started(e: StreetEventType, criminal: StreetCriminal)   ## 범인이 저질렀다
signal resolved(e: StreetEventType, reward: int, alive: bool)  ## 주인공이 막았다
signal failed(e: StreetEventType)                              ## 놓쳤다

const EVENTS: Array[StreetEventType] = [
	preload("res://data/events/thief.tres"),
	preload("res://data/events/robber.tres"),
	preload("res://data/events/store_robbery.tres"),
]
## 피해자가 될 수 있는 사람 (교통경찰·노숙자·공연하는 사람은 빼다)
const VICTIMS: Array[StringName] = [&"CIV_M", &"CIV_F", &"OFFICE", &"FOREIGNER", &"MERCHANT", &"DELIVERY", &"STUDENT", &"FLYER"]
const SEED := 20261022
const FIRST_DELAY := 45.0          ## 시작하고 첫 이벤트까지 (초)
const INTERVAL := Vector2(70.0, 140.0)   ## 이벤트 사이 (초)
const RETRY := 8.0                 ## 조건이 안 맞으면 이만큼 뒤에 다시 본다
const VICTIM_RANGE := Vector2(180.0, 480.0)   ## 주인공에게서 이 거리의 사람을 고른다 (화면 안, 너무 가깝지 않게)
const SPAWN_BACK := 80.0           ## 범인은 피해자 뒤 인도 이만큼에서 나타난다
const CLEANUP_DISTANCE := 950.0    ## 끝난 범인은 카메라에서 이만큼 멀어지면 치운다
const CLEANUP_TIME := 30.0         ## 또는 이만큼 지나고 화면 밖이면
const SHOOT_RANGE := 220.0         ## 들킨 강도가 쏘는 거리
const SHOOT_DELAY := Vector2(1.3, 2.2)   ## 무기 발사 간격 배율 (강도는 조직원보다 굼뜨게)
const STORE_RANGE := Vector2(220.0, 800.0)   ## 편의점 강도: 주인공에게서 이 거리의 편의점을 고른다
const CONVENIENCE := &"CONVENIENCE"

var director: Director
var player: Player
var pedestrians: PedestrianManager
var police: PoliceDispatcher
var wallet: Wallet
var combat: Combat
var missions: MissionSystem
var jobs: SideJobs
var city: City                     ## 편의점 강도가 편의점 자리를 찾는다
var enabled := true
var rng := RandomNumberGenerator.new()
var criminal: StreetCriminal = null   ## 지금 벌어지는 이벤트의 범인 (없으면 null)
var _wait := FIRST_DELAY
var _done := {}                    ## 끝난 범인 → 끝난 뒤 지난 시간 (치울 때까지)


func _ready() -> void:
	rng.seed = SEED
	if pedestrians:
		pedestrians.person_hurt.connect(_on_person_hurt)


func _physics_process(delta: float) -> void:
	_cleanup(delta)
	if criminal != null:
		_run()
		return
	if not enabled:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = RETRY
	if can_start() and start(_pick_event()) != null:
		_wait = rng.randf_range(INTERVAL.x, INTERVAL.y)


func can_start() -> bool:
	if player == null or player.is_dead() or police == null or police.wanted.level > 1:
		return false
	return not (missions and missions.active()) and not (jobs and jobs.active())


## 지금 쫓는 범인 자리 (미니맵 표시 — 없으면 INF)
func target_position() -> Vector2:
	if criminal != null and is_instance_valid(criminal) and criminal.at_large():
		return criminal.global_position
	return Vector2.INF


## 이벤트를 시작한다: 피해자 뒤에 범인을 세운다 (victim이 없으면 주인공 근처에서 고른다). 못 세우면 null
func start(e: StreetEventType, victim: Pedestrian = null) -> StreetCriminal:
	if criminal != null:
		return null
	if victim == null:
		victim = _store_clerk(e) if e.store else _pick_victim()
	if victim == null:
		return null
	var c := StreetCriminal.new()
	c.setup(e.npc, rng, victim.loop, 0, 0.0, 1)
	c.position = _behind(victim, SPAWN_BACK)
	c.level = victim.level
	c.event = e
	c.victim = victim
	c.threat = _threat()
	c.acted.connect(func(): started.emit(e, c))
	pedestrians.add(c)
	criminal = c
	return c


## 편의점 강도: 주인공 근처(STORE_RANGE) 열린 블록의 편의점 앞 인도에 점원을 세운다. 없으면 null
func _store_clerk(e: StreetEventType) -> Pedestrian:
	var at := _threat()
	var best := -1
	var best_d := INF
	for idx in store_lots().size():
		var r: Rect2 = store_lots()[idx]
		var d := r.get_center().distance_to(at)
		if d >= STORE_RANGE.x and d <= STORE_RANGE.y and d < best_d and CityMap.is_open_block(CityMap.block_at(r.get_center())):
			best = idx
			best_d = d
	if best < 0:
		return null
	var lot: Rect2 = store_lots()[best]
	var loop := City.sidewalk_loop(CityMap.block_at(lot.get_center()))
	# 편의점 부지에서 가장 가까운 인도 변 위의 점
	var edge := 0
	var t := 0.0
	var near := INF
	for k in loop.size():
		var a := loop[k]
		var b := loop[(k + 1) % loop.size()]
		var q := Geometry2D.get_closest_point_to_segment(lot.get_center(), a, b)
		var dq := q.distance_to(lot.get_center())
		if dq < near:
			near = dq
			edge = k
			t = clampf(a.distance_to(q) / maxf(a.distance_to(b), 1.0), 0.1, 0.9)
	var clerk := Pedestrian.new()
	clerk.setup(e.clerk, rng, loop, edge, t, 1)
	pedestrians.add(clerk)
	clerk._set_state(Pedestrian.State.IDLE, 2.0)
	return clerk


## 도시의 편의점 부지 (기능 건물 겉모습 CONVENIENCE)
func store_lots() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if city == null:
		return out
	for idx: int in city.looks:
		var look: BuildingType = city.looks[idx]
		if look and look.id == CONVENIENCE:
			out.append(city.buildings[idx])
	return out


func _pick_event() -> StreetEventType:
	var total := 0.0
	for e in EVENTS:
		total += e.weight
	var roll := rng.randf() * total
	for e in EVENTS:
		roll -= e.weight
		if roll <= 0.0:
			return e
	return EVENTS[0]


func _pick_victim() -> Pedestrian:
	var at := _threat()
	var found: Array[Pedestrian] = []
	for p in pedestrians.peds:
		if p is StreetCriminal or not pedestrians.is_alive_civilian(p) or not p.active or p.npc.protected \
				or not VICTIMS.has(p.npc.id) or not p.state in [Pedestrian.State.WALK, Pedestrian.State.IDLE]:
			continue
		var d := p.global_position.distance_to(at)
		if d >= VICTIM_RANGE.x and d <= VICTIM_RANGE.y and _behind(p, SPAWN_BACK).distance_to(p.global_position) > SPAWN_BACK * 0.5:
			found.append(p)
	return null if found.is_empty() else found[rng.randi() % found.size()]


## 피해자가 걸어온 인도를 거슬러 dist만큼 (모퉁이를 넘지 않는다)
func _behind(p: Pedestrian, dist: float) -> Vector2:
	var prev := p.loop[wrapi(p.target_index - p.direction, 0, p.loop.size())]
	var back := prev - p.global_position
	if back.length() < 1.0:
		return p.global_position
	return p.global_position + back.normalized() * minf(dist, back.length())


func _threat() -> Vector2:
	return director.controlled_target().global_position if director else player.global_position


func _run() -> void:
	var c := criminal
	if not is_instance_valid(c):
		criminal = null
		return
	if c.phase == StreetCriminal.Phase.GONE:
		_end(c)        # 다가가다 그만뒀다 (피해자가 도망쳤다) — 알리지 않는다
		return
	if player.is_dead():
		_fail(c)
		return
	var at := _threat()
	c.threat = at
	var d := c.global_position.distance_to(at)
	if c.phase == StreetCriminal.Phase.ACT and d < c.event.alert_range:
		c.alerted = true
	if c.phase == StreetCriminal.Phase.ESCAPE:
		if d > c.event.give_up_distance or c.phase_time > c.event.escape_time:
			_fail(c)
			return
		if d < SHOOT_RANGE:
			c.alerted = true
		if c.alerted:
			_shoot(c, at)


## 들킨 강도는 달아나며 주인공을 쏜다 (조직원과 같은 규칙: 빨리 달아나는 차·건물 너머는 못 맞힌다)
func _shoot(c: StreetCriminal, target: Vector2) -> void:
	var w := c.npc.weapon
	if combat == null or w == null or w.melee or c.reload > 0.0 or c.state != Pedestrian.State.WALK:
		return
	var pcar := director.current_vehicle if director else null
	if pcar != null and (pcar.airborne() or pcar.speed() >= PoliceDispatcher.CAR_ESCAPE_SPEED):
		return
	var pos := c.global_position
	if pos.distance_to(target) > SHOOT_RANGE:
		return
	var space := c.get_world_2d().direct_space_state
	if not space.intersect_ray(PhysicsRayQueryParameters2D.create(pos, target, Layers.at(Layers.WORLD, c.level))).is_empty():
		return
	c.reload = w.fire_interval * rng.randf_range(SHOOT_DELAY.x, SHOOT_DELAY.y)
	var dir := (target - pos).normalized()
	var exclude: Array[RID] = [c.get_rid()]
	combat.fire(pos + dir * 10.0, dir, w, false, exclude, 0.0, c.level)


## 사람이 다쳤다: 주인공이 범인을 넘어뜨리거나 죽였으면 막은 것이다
func _on_person_hurt(p: Pedestrian, by_player: bool, killed: bool) -> void:
	if p != criminal or not is_instance_valid(p):
		return
	var c := criminal
	if c.phase == StreetCriminal.Phase.APPROACH:
		c.lose()        # 저지르기 전에 맞았다 — 이벤트는 없던 일
		_end(c)
		return
	if not by_player:
		if killed:
			_fail(c)     # 다른 사람(경찰·차)이 막았다 — 보상은 없다
		return
	if killed or c.state == Pedestrian.State.KNOCKED:
		_resolve(c, not killed)


func _resolve(c: StreetCriminal, alive: bool) -> void:
	var e := c.event
	var pay := e.reward if alive else roundi(e.reward * e.kill_reward_scale)
	wallet.earn(pay)
	if police and police.wanted.level > 0 and e.wanted_relief > 0:
		police.wanted.lower(e.wanted_relief)
	c.surrender()
	if is_instance_valid(c.victim) and not c.victim.is_dead():
		c.victim.say_line(&"thanks", 3.0)
	_end(c)
	resolved.emit(e, pay, alive)


func _fail(c: StreetCriminal) -> void:
	var acted := c.phase != StreetCriminal.Phase.APPROACH
	c.lose()
	_end(c)
	if acted:
		failed.emit(c.event)


func _end(c: StreetCriminal) -> void:
	if criminal == c:
		criminal = null
	_done[c] = 0.0


## 끝난 범인을 화면 밖에서 치운다 (시신은 PedestrianManager가 치운다)
func _cleanup(delta: float) -> void:
	if _done.is_empty():
		return
	var cam := ChaseCamera.current_cam()
	var center := cam.global_position if cam else _threat()
	for c: StreetCriminal in _done.keys():
		if not is_instance_valid(c):
			_done.erase(c)
			continue
		_done[c] += delta
		var far := c.global_position.distance_to(center)
		if far > CLEANUP_DISTANCE or (_done[c] > CLEANUP_TIME and far > CLEANUP_DISTANCE * 0.6):
			_done.erase(c)
			if not c.is_dead():
				pedestrians.remove(c)
