class_name StreetCriminal
extends Pedestrian
## 랜덤 거리 이벤트의 범인 (도둑·강도). StreetEvents가 세우고 잡혔는지·놓쳤는지를 맡는다.
## 다가가기 → 저지르기(도둑은 낚아채기, 강도는 act_time 동안 위협) → 달아나기. 달아나는 동안은 겁먹지 않는다.
## 달아날 때는 인도 모퉁이를 따라 주인공에게서 먼 쪽으로 가고, 모퉁이에서는 길 건너 옆 블록으로도 넘어간다
## (똑바로 달리면 건물 벽에 막힌다).

signal acted                       ## 저지르기 시작했다 (StreetEvents가 알린다)

enum Phase { APPROACH, ACT, ESCAPE, CAUGHT, GONE }

const REACH := 18.0                ## 피해자에게 이만큼 다가가면 저지른다
const APPROACH_TIME := 10.0        ## 이 안에 못 닿으면 그만둔다 (피해자가 도망쳤다)
const APPROACH_SPEED := 1.5        ## 다가갈 때 걷는 빠르기 배율
const CORNER := 8.0                ## 모퉁이에 닿았다고 보는 거리
const BACKTRACK := 120.0           ## 방금 지난 모퉁이로 되돌아가는 것을 이만큼 덜 친다

var event: StreetEventType
var victim: Pedestrian
var phase := Phase.APPROACH
var phase_time := 0.0
var threat := Vector2.ZERO         ## 주인공(탄 차) 자리 — StreetEvents가 매 틱 넣는다
var alerted := false               ## 주인공에게 들켰다 (무기가 있으면 쏜다)
var reload := 0.0
var _goal := Vector2.INF           ## 지금 달려가는 모퉁이
var _prev := Vector2.INF           ## 방금 지난 모퉁이


func _physics_process(delta: float) -> void:
	if state == State.DEAD or state == State.DODGE:
		super._physics_process(delta)
		return
	_track_level()
	reload -= delta
	phase_time += delta
	speech_time -= delta
	if state == State.KNOCKED:
		# 차에 받혀 넘어졌다 — 잡힌 게 아니면 일어나 다시 달아난다
		state_time -= delta
		velocity = Vector2.ZERO
		if phase == Phase.CAUGHT or state_time > 0.0:
			return
		_set_state(State.WALK, 0.0)
	var vel := Vector2.ZERO
	match phase:
		Phase.APPROACH:
			if not is_instance_valid(victim) or victim.is_dead() or phase_time > APPROACH_TIME:
				_set_phase(Phase.GONE)
			else:
				var to := victim.global_position - global_position
				if to.length() < REACH:
					_act()
				else:
					var speed := event.flee_speed if victim.is_scared() else walk_speed * APPROACH_SPEED
					vel = to.normalized() * speed
		Phase.ACT:
			if is_instance_valid(victim) and not victim.is_dead():
				facing = Vector2.UP.angle_to(victim.global_position - global_position)
				_hold_victim()
			if phase_time >= event.act_time or alerted:
				_escape()
		Phase.ESCAPE, Phase.GONE:
			vel = _flee_step() * event.flee_speed
	velocity = vel
	if vel != Vector2.ZERO:
		facing = Vector2.UP.angle_to(vel)
		walk_phase += delta * vel.length() / 9.0
	move_and_slide()


## 범죄를 저지르는 중이거나 달아나는 중 — 이때 다치게 해도 범죄가 아니다 (PoliceDispatcher)
func offender() -> bool:
	return phase in [Phase.ACT, Phase.ESCAPE, Phase.CAUGHT]


## 저지르고 달아나는 중 (StreetEvents가 쫓는 대상)
func at_large() -> bool:
	return phase in [Phase.ACT, Phase.ESCAPE] and not is_dead()


## 잡혔다: 엎드려 항복한다 (StreetEvents가 치울 때까지)
func surrender() -> void:
	_set_phase(Phase.CAUGHT)
	if is_dead():
		return
	velocity = Vector2.ZERO
	_set_state(State.KNOCKED, INF)
	say_line(&"caught", 3.0)


## 놓쳤다: 계속 달아나다 화면 밖에서 치워진다
func lose() -> void:
	_set_phase(Phase.GONE)


## 달아나는 범인은 겁먹지 않는다 (총소리에 흩어지지 않고 제 길로 간다)
func panic(away: Vector2, forced := false) -> bool:
	if phase == Phase.CAUGHT or is_dead():
		return false
	if phase == Phase.APPROACH and forced:
		_escape()       # 다가가다 맞으면 그냥 달아난다
	return false


func knock_down(away: Vector2) -> void:
	super.knock_down(away)
	if phase == Phase.APPROACH:
		_set_phase(Phase.GONE)


func _act() -> void:
	_set_phase(Phase.ACT)
	var line := &"snatch" if event.act_time <= 0.0 else &"threat"
	say_line(line, maxf(event.act_time, 2.0))
	if is_instance_valid(victim):
		victim.say_line(event.victim_situation, maxf(event.act_time, 2.5) + 0.5)
		_hold_victim()
	acted.emit()
	if event.act_time <= 0.0:
		_escape()


func _escape() -> void:
	if phase == Phase.ESCAPE:
		return
	_set_phase(Phase.ESCAPE)
	if speech_time <= 0.0 or alerted:
		say_line(&"escape", 2.0)
	if is_instance_valid(victim) and not victim.is_dead():
		if event.act_time > 0.0:
			victim.panic(victim.global_position - global_position, true)   # 강도가 떠나자 피해자도 달아난다
		else:
			victim._set_state(State.IDLE, 2.5)   # 가방을 뺏긴 사람은 멍하니 서서 외친다
			victim.facing = Vector2.UP.angle_to(global_position - victim.global_position)


## 강도에게 붙잡힌 사람은 꼼짝 못 하고 강도를 본다
func _hold_victim() -> void:
	if event.act_time <= 0.0 or victim.is_dead() or victim.state == State.KNOCKED:
		return
	victim._set_state(State.IDLE, 0.3)
	victim.velocity = Vector2.ZERO
	victim.facing = Vector2.UP.angle_to(global_position - victim.global_position)


func _set_phase(p: Phase) -> void:
	phase = p
	phase_time = 0.0
	_drawn_key = []    # 머리 위 표시가 바뀐다 — 다음 프레임에 다시 그린다
	if p == Phase.ESCAPE:
		_goal = Vector2.INF


## 달아날 방향: 다음 모퉁이로. 닿으면 주인공에게서 가장 먼 다음 모퉁이를 고른다
func _flee_step() -> Vector2:
	if _goal == Vector2.INF or global_position.distance_to(_goal) < CORNER:
		var next := _next_corner()
		_prev = _goal
		_goal = next
	var to := _goal - global_position
	return to.normalized() if to.length() > 0.5 else Vector2.ZERO


func _next_corner() -> Vector2:
	var here := global_position
	var b := City.nearest_block(here)
	var loop := City.sidewalk_loop(b)
	var order := [0, 1, 2, 3]
	order.sort_custom(func(x: int, y: int) -> bool: return loop[x].distance_squared_to(here) < loop[y].distance_squared_to(here))
	var options: Array[Vector2] = []
	var i: int = order[0]
	if loop[i].distance_to(here) < CORNER * 2.0:
		# 모퉁이: 같은 블록의 옆 모퉁이 둘 + 길 건너 옆 블록의 가까운 모퉁이
		options.append(loop[(i + 1) % 4])
		options.append(loop[(i + 3) % 4])
		var out := (loop[i] - City.block_rect(b.x, b.y).get_center()).sign()
		for nb: Vector2i in [b + Vector2i(int(out.x), 0), b + Vector2i(0, int(out.y))]:
			if CityMap.is_land(nb) and CityMap.is_open_block(nb):
				var other := City.sidewalk_loop(nb)
				var best := other[0]
				for p in other:
					if p.distance_squared_to(loop[i]) < best.distance_squared_to(loop[i]):
						best = p
				options.append(best)
	else:
		# 변 가운데: 그 변의 두 끝 모퉁이
		options.append(loop[order[0]])
		options.append(loop[order[1]])
	var pick := options[0]
	var best_score := -INF
	for o in options:
		var score := o.distance_to(threat) - (BACKTRACK if _prev != Vector2.INF and o.distance_to(_prev) < CORNER else 0.0)
		if score > best_score:
			best_score = score
			pick = o
	return pick


func _draw() -> void:
	super._draw()
	if not at_large():
		return
	# 쫓을 범인: 머리 위 빨간 표시 (말풍선이 떠 있으면 그 위)
	var talking := speech_time > 0.0 and speech != ""
	var top := -28.0 if talking else 0.0
	if IsoView.enabled:
		draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, IsoView.PERSON_HEIGHT * npc.body_scale + 8.0 + IsoView.ground(global_position, level)))
	else:
		top = -38.0 if talking else -14.0
	var tri := PackedVector2Array([Vector2(-5, top - 9), Vector2(5, top - 9), Vector2(0, top - 1)])
	draw_colored_polygon(tri, Color(1.0, 0.25, 0.2))
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0, 0, 0, 0.7), 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
