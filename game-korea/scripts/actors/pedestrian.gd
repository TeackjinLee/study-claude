class_name Pedestrian
extends CharacterBody2D
## 보행자 한 명. 블록 둘레 인도를 돌고, 모퉁이에서 가끔 멈춘다.
## 차 감지는 PedestrianManager가 하고 여기엔 dodge()/panic()/knock_down()/hurt()로 알려 준다.

enum State { WALK, IDLE, DODGE, FLEE, KNOCKED, DEAD }

const RADIUS := 6.0
const ARRIVE_DISTANCE := 4.0
const DODGE_TIME := 0.6
const FLEE_TIME := 3.0
const KNOCK_TIME := 2.5

var npc: NpcType
var rng: RandomNumberGenerator
var loop: PackedVector2Array      ## 인도 순환 경로 (블록 둘레 4꼭짓점)
var target_index := 0
var direction := 1                ## 1 = 시계 방향, -1 = 반시계
var walk_speed := 60.0
var state := State.WALK
var state_time := 0.0
var move_dir := Vector2.ZERO
var facing := 0.0
var walk_phase := 0.0
var active := true
var health := 20.0
var dead_time := 0.0

var shirt: Color
var pants: Color
var hair: Color
var look_seed := 0                ## 모자·소지품 유무를 정하는 값 (rng를 쓰지 않고 처음 자리로 정한다)
var speech := ""                  ## 말풍선 (speech_time 동안)
var speech_time := 0.0
var _drawn_key: Array = []        ## 마지막으로 그린 모습 — 같으면 다시 그리지 않는다


func setup(p_npc: NpcType, p_rng: RandomNumberGenerator, p_loop: PackedVector2Array,
		edge: int, t: float, p_direction: int) -> void:
	npc = p_npc
	rng = p_rng
	loop = p_loop
	direction = p_direction
	walk_speed = rng.randf_range(npc.walk_speed_min, npc.walk_speed_max)
	health = npc.health
	shirt = npc.shirt_colors[rng.randi() % npc.shirt_colors.size()]
	pants = npc.pants_colors[rng.randi() % npc.pants_colors.size()]
	hair = npc.hair_colors[rng.randi() % npc.hair_colors.size()]
	var next := wrapi(edge + 1, 0, loop.size())
	position = loop[edge].lerp(loop[next], t)
	target_index = next if direction == 1 else edge
	look_seed = hash(Vector2i(position.round()))


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR     # 인물 그림(PersonRig 스프라이트)을 줄여 그릴 때 깨지지 않게
	collision_layer = Layers.PEOPLE
	collision_mask = Layers.WORLD
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		dead_time += delta
		return
	state_time -= delta
	speech_time -= delta
	var vel := Vector2.ZERO
	match state:
		State.WALK:
			var to := loop[target_index] - global_position
			if to.length() < ARRIVE_DISTANCE:
				target_index = wrapi(target_index + direction, 0, loop.size())
				if rng.randf() < npc.idle_chance:
					_set_state(State.IDLE, rng.randf_range(1.0, 3.0))
			else:
				vel = to.normalized() * walk_speed
		State.IDLE:
			if state_time <= 0.0:
				_set_state(State.WALK, 0.0)
		State.DODGE, State.FLEE:
			vel = move_dir * npc.run_speed
			if state_time <= 0.0:
				resume_walking()
		State.KNOCKED:
			if state_time <= 0.0:
				if npc.fearless:
					resume_walking()
				else:
					panic(move_dir)
	velocity = vel
	if vel != Vector2.ZERO:
		facing = Vector2.UP.angle_to(vel)
		walk_phase += delta * vel.length() / 9.0
	move_and_slide()


## 다가오는 차 옆으로 비켜선다
func dodge(dir: Vector2) -> void:
	if state in [State.DODGE, State.FLEE, State.KNOCKED, State.DEAD]:
		return
	move_dir = dir.normalized()
	_set_state(State.DODGE, DODGE_TIME)


## 겁에 질려 away 방향으로 도망친다. 새로 겁먹었으면 true (공포 전파용)
## 넘어진 동안엔 겁먹지 않는다 — 다만 KNOCK_TIME이 끝나 일어날 때는 여기를 거쳐 도망친다
## (막으면 영영 일어나지 못하고 도로 위에 누운 채 교통을 막는다)
## 겁 없는 사람(노숙자)은 직접 맞았을 때(forced)만 도망친다
func panic(away: Vector2, forced := false) -> bool:
	if state == State.DEAD or (state == State.KNOCKED and state_time > 0.0):
		return false
	if npc.fearless and not forced:
		return false
	var was_fleeing := state == State.FLEE
	move_dir = away.normalized().rotated(rng.randf_range(-0.4, 0.4))
	_set_state(State.FLEE, FLEE_TIME * rng.randf_range(0.8, 1.2))
	# 셋 중 하나는 소리친다 (사람마다 정해져 있다 — 무작위를 쓰지 않아 다른 결과가 바뀌지 않는다)
	if not was_fleeing and get_instance_id() % 3 == 0:
		say("도망쳐!", 1.2)
	return not was_fleeing


## 말풍선을 띄운다
func say(text: String, seconds := 2.5) -> void:
	speech = text
	speech_time = seconds


## 차에 받히거나 주먹에 맞아 넘어진다
func knock_down(away: Vector2) -> void:
	if state == State.KNOCKED or state == State.DEAD:
		return
	move_dir = away.normalized()
	facing = Vector2.UP.angle_to(move_dir)
	_set_state(State.KNOCKED, KNOCK_TIME)


## 다친다. knock이면 넘어지고, 아니면 겁먹고 도망친다. 죽었으면 true
## (공포 전파·범죄 신고는 PedestrianManager.damage가 한다 — 피해는 거기를 거친다)
## 보호 대상(아이)은 다치지 않고 도망만 친다.
func hurt(amount: float, away: Vector2, knock: bool) -> bool:
	if state == State.DEAD:
		return false
	if npc.protected:
		panic(away, true)
		return false
	health -= amount
	if health <= 0.0:
		die(away)
		return true
	if knock:
		knock_down(away)
	else:
		panic(away, true)
	return false


func die(away: Vector2) -> void:
	health = 0.0
	if away != Vector2.ZERO:
		facing = Vector2.UP.angle_to(away)
	velocity = Vector2.ZERO
	collision_layer = 0          # 시신은 총알·차를 막지 않는다
	_set_state(State.DEAD, 0.0)
	dead_time = 0.0
	queue_redraw()


func is_dead() -> bool:
	return state == State.DEAD


func is_scared() -> bool:
	return state in [State.DODGE, State.FLEE, State.KNOCKED]


## 도망이 끝나면 가장 가까운 블록 인도로 돌아가 다시 걷는다
func resume_walking() -> void:
	loop = City.sidewalk_loop(City.nearest_block(global_position))
	var best := 0
	for i in loop.size():
		if loop[i].distance_squared_to(global_position) < loop[best].distance_squared_to(global_position):
			best = i
	target_index = best
	_set_state(State.WALK, 0.0)


## 2.5D: 깊이(월드 x+y)로 그리는 순서를 정한다
## 모습(걸음 24단계·방향·상태·말풍선)이 바뀔 때만 다시 그린다 — 물리 틱마다 그리면 사람 수만큼 비싸다
func _process(_delta: float) -> void:
	z_as_relative = not IsoView.enabled
	z_index = IsoView.z_of(global_position) if IsoView.enabled else 0
	var key := [int(walk_phase * 24.0 / TAU), snappedf(facing, 0.05), state, speech_time > 0.0, speech,
		IsoView.enabled, npc, shirt]
	if key != _drawn_key:
		_drawn_key = key
		queue_redraw()


func set_active(on: bool) -> void:
	if active == on:
		return
	active = on
	visible = on
	set_physics_process(on)


func _set_state(s: State, duration: float) -> void:
	state = s
	state_time = duration


func _draw() -> void:
	if state == State.DEAD:
		PersonDrawer.draw_blood(self, facing)
	var down := state == State.KNOCKED or state == State.DEAD
	if IsoView.enabled:
		# 2.5D: 4×2 스프라이트 시트(PersonRig)로 정지·걷기·달리기·쓰러짐을 그린다
		var gait: float = 0.0 if down or state == State.IDLE else (2.0 if state in [State.DODGE, State.FLEE] else 1.0)
		PersonRig.draw(self, facing, walk_phase, gait, shirt, pants, hair, npc.body_scale, npc, look_seed, null, down)
		if speech_time > 0.0 and speech != "" and state != State.DEAD:
			PersonDrawer.draw_speech(self, speech, npc.body_scale)
		return
	PersonDrawer.draw(self, facing, walk_phase, shirt, pants, hair, down, npc.body_scale, npc, look_seed)
	if speech_time > 0.0 and speech != "" and state != State.DEAD:
		var font := ThemeDB.fallback_font
		var w := font.get_string_size(speech, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12.0
		var box := Rect2(Vector2(-w * 0.5, -34), Vector2(w, 18))
		draw_rect(box, Color(1, 1, 1, 0.92))
		draw_rect(box, Color(0, 0, 0, 0.6), false, 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(-4, -16), Vector2(4, -16), Vector2(0, -10)]), Color(1, 1, 1, 0.92))
		draw_string(font, Vector2(box.position.x, box.end.y - 5), speech, HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(0.1, 0.1, 0.12))
