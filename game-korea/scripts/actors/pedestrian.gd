class_name Pedestrian
extends CharacterBody2D
## 보행자 한 명. 블록 둘레 인도를 돌고, 모퉁이에서 가끔 멈춘다.
## 차 감지는 PedestrianManager가 하고 여기엔 dodge()/panic()/knock_down()/hurt()로 알려 준다.
## 사람은 죽지 않는다: 체력이 0이 되면 기절(DEAD — 이름만 예전 그대로)해 누운 채 일어나지 않고,
## 구급대(EmsDispatcher)가 들것·구급헬기로 실어 간다.

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
var dead_time := 0.0               ## 기절한 뒤 지난 시간
var rescuer: Object = null        ## 이 기절한 사람을 맡은 구급대 (구급차·구급헬기) — 맡은 사람은 치우지 않는다
var targeted := false             ## 주인공이 고른 표적 (머리 위 체력 막대를 늘 띄운다 — PlayerWeapons.select)
var carried := false              ## 들것에 실려 가는 중 (들것을 밑에 그린다)

var shirt: Color
var pants: Color
var hair: Color
var look_seed := 0                ## 모자·소지품 유무를 정하는 값 (rng를 쓰지 않고 처음 자리로 정한다)
var speech := ""                  ## 말풍선 (speech_time 동안)
var speech_time := 0.0
var _drawn_key: Array = []        ## 마지막으로 그린 모습 — 같으면 다시 그리지 않는다
var level := 0                    ## 고가차도 층 (CityMap.level_zone) — 충돌 비트를 Layers.at으로 옮긴다
var _col_base := Vector2i(Layers.PEOPLE, Layers.WORLD)


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
	_track_level()
	_set_collision(Layers.PEOPLE, Layers.WORLD)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)


func _physics_process(delta: float) -> void:
	_track_level()
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
		say_line(&"flee", 1.2)
		Sfx.play(VoiceSynth.scream_of(npc), global_position)
	return not was_fleeing


## 말풍선을 띄운다
func say(text: String, seconds := 2.5) -> void:
	speech = text
	speech_time = seconds


## 이 사람의 그 상황 대사(data/dialogue/lines.csv)로 말풍선을 띄운다. 대사가 있었으면 true
func say_line(situation: StringName, seconds := 2.5, salt := 0) -> bool:
	var text := Dialogue.pick(npc.id, situation, get_instance_id() + salt)
	if text == "":
		return false
	say(text, seconds)
	return true


## 차에 받히거나 주먹에 맞아 넘어진다
func knock_down(away: Vector2) -> void:
	if state == State.KNOCKED or state == State.DEAD:
		return
	move_dir = away.normalized()
	facing = Vector2.UP.angle_to(move_dir)
	_set_state(State.KNOCKED, KNOCK_TIME)


## 다친다. knock이면 넘어지고, 아니면 겁먹고 도망친다. 기절했으면 true
## (공포 전파·범죄 신고는 PedestrianManager.damage가 한다 — 피해는 거기를 거친다)
## 보호 대상(아이)은 다치지 않고 도망만 친다.
func hurt(amount: float, away: Vector2, knock: bool) -> bool:
	if state == State.DEAD:
		return false
	if npc.protected:
		panic(away, true)
		return false
	health -= amount
	queue_redraw()     # 머리 위 체력 막대
	if health <= 0.0:
		die(away)
		return true
	if knock:
		knock_down(away)
	else:
		panic(away, true)
	return false


## 기절한다 (일어나지 않는다 — 구급대가 실어 간다)
func die(away: Vector2) -> void:
	health = 0.0
	if away != Vector2.ZERO:
		facing = Vector2.UP.angle_to(away)
	velocity = Vector2.ZERO
	_set_collision(0, _col_base.y)          # 기절한 사람은 총알·차를 막지 않는다
	_set_state(State.DEAD, 0.0)
	dead_time = 0.0
	queue_redraw()


## 고가차도 층을 정한다 (차에서 내린 사람은 차의 층)
func set_level(l: int) -> void:
	if l != level:
		level = l
		_set_collision(_col_base.x, _col_base.y)


func _track_level() -> void:
	var z := CityMap.level_zone(global_position)
	if z >= 0:
		set_level(z)


## 땅 기준 충돌을 정하고 지금 층으로 옮겨 넣는다 (값이 바뀔 때만)
func _set_collision(layer: int, mask: int) -> void:
	_col_base = Vector2i(layer, mask)
	var l := Layers.at(layer, level)
	var m := Layers.at(mask, level)
	if collision_layer != l:
		collision_layer = l
	if collision_mask != m:
		collision_mask = m


## 기절했다 (예전 이름 그대로 — 죽음은 없다)
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
	z_index = IsoView.z_at(global_position, level) if IsoView.enabled else 0
	var key := [int(walk_phase * 24.0 / TAU), snappedf(facing, 0.05), state, speech_time > 0.0, speech,
		IsoView.enabled, npc, shirt, snappedf(IsoView.ground(global_position, level), 0.5), carried,
		PersonRig.ko_frame(self, npc)]
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
	if carried:
		_draw_stretcher()
	var down := state == State.KNOCKED or state == State.DEAD
	if IsoView.enabled:
		# 2.5D: 4×2 스프라이트 시트(PersonRig)로 정지·걷기·달리기·쓰러짐을 그린다
		PersonRig.draw(self, facing, walk_phase, _draw_gait(), shirt, pants, hair, npc.body_scale, npc, look_seed, _drawn_weapon(), down)
		_draw_head_tag()
		if speech_time > 0.0 and speech != "" and state != State.DEAD:
			PersonDrawer.draw_speech(self, speech, npc.body_scale)
		if state == State.DEAD:
			_draw_out_stars()
		return
	PersonDrawer.draw(self, facing, walk_phase, shirt, pants, hair, down, npc.body_scale, npc, look_seed)
	_draw_head_tag()
	if state == State.DEAD:
		_draw_out_stars()
	if speech_time > 0.0 and speech != "" and state != State.DEAD:
		var font := ThemeDB.fallback_font
		var w := font.get_string_size(speech, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12.0
		var box := Rect2(Vector2(-w * 0.5, -34), Vector2(w, 18))
		draw_rect(box, Color(1, 1, 1, 0.92))
		draw_rect(box, Color(0, 0, 0, 0.6), false, 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(-4, -16), Vector2(4, -16), Vector2(0, -10)]), Color(1, 1, 1, 0.92))
		draw_string(font, Vector2(box.position.x, box.end.y - 5), speech, HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(0.1, 0.1, 0.12))


## 그림 걸음: 0 서 있기 · 1 걷기 · 2 달리기
func _draw_gait() -> float:
	if state == State.KNOCKED or state == State.DEAD or state == State.IDLE:
		return 0.0
	return 2.0 if state in [State.DODGE, State.FLEE] else 1.0


## 그림에 든 총 (그 사람의 총 자세 그림이 있을 때만 쓴다 — PersonRig._gun_pose)
func _drawn_weapon() -> WeaponType:
	return null


const TAG_SIZE := Vector2(16, 3)   ## 머리 위 체력 막대


## 머리 위 표시 (몸을 가리지 않게 머리보다 위): 다쳤으면 체력 막대, 소속 색(tag_color)이 있으면 그 색 작은 삼각형.
## 쓰러져 있으면 그리지 않는다.
func _draw_head_tag() -> void:
	if state == State.KNOCKED or state == State.DEAD:
		return
	var tag := tag_color()
	var hurt_ratio := health / npc.health if npc.health > 0.0 else 1.0
	if tag.a <= 0.0 and hurt_ratio >= 1.0 and not targeted:
		return
	if IsoView.enabled:
		draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, IsoView.PERSON_HEIGHT * npc.body_scale + 7.0 + IsoView.ground(global_position, level)))
	else:
		draw_set_transform(Vector2(0, -20), 0.0, Vector2.ONE)
	var y := 0.0
	if hurt_ratio < 1.0 or targeted:
		var r := Rect2(Vector2(-TAG_SIZE.x * 0.5, -TAG_SIZE.y), TAG_SIZE)
		draw_rect(r.grow(1.0), Color(0, 0, 0, 0.75))
		draw_rect(r, Color(0.35, 0.08, 0.08))
		var fill := Color(0.95, 0.25, 0.2).lerp(Color(0.4, 0.95, 0.4), clampf(hurt_ratio * 1.4 - 0.3, 0.0, 1.0))
		draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(hurt_ratio, 0.0, 1.0), r.size.y)), fill)
		y = -TAG_SIZE.y - 3.0
	if tag.a > 0.0:
		var tri := PackedVector2Array([Vector2(-3.5, y - 5.0), Vector2(3.5, y - 5.0), Vector2(0, y - 0.5)])
		draw_colored_polygon(tri, tag)
		tri.append(tri[0])
		draw_polyline(tri, Color(0, 0, 0, 0.7), 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 머리 위 소속 색 (없으면 투명 — 조직원은 조직 색)
func tag_color() -> Color:
	return Color(0, 0, 0, 0)


## 들것: 누운 사람 밑에 주황 틀과 흰 매트 (진행 방향으로 길게, 바닥보다 조금 위)
func _draw_stretcher() -> void:
	var up := IsoView.lift(IsoView.ground(global_position, level) + 5.0) if IsoView.enabled else Vector2.ZERO
	draw_set_transform(up, facing, Vector2.ONE)
	draw_rect(Rect2(-7, -17, 14, 34), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(-6, -16, 12, 32), Color(0.95, 0.5, 0.12))
	draw_rect(Rect2(-4.5, -14, 9, 28), Color(0.94, 0.95, 0.97))
	for x: float in [-6.0, 6.0]:
		draw_line(Vector2(x, -20), Vector2(x, 20), Color(0.55, 0.57, 0.6), 1.5)   # 손잡이 막대
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 기절 표시: 누운 사람 머리 위에 노란 별 셋 (들것에 실리면 그리지 않는다)
func _draw_out_stars() -> void:
	if carried:
		return
	if IsoView.enabled and not has_meta(&"ko_head") and PersonRig.dir8_for(npc).has("ko_tex"):
		return   # 넘어짐 그림이 있으면 다 누운 뒤에 (쓰러지는 동안은 없다)
	var at := Vector2.ZERO
	if IsoView.enabled:
		draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, 10.0 + IsoView.ground(global_position, level)))
		if has_meta(&"ko_head"):   # 넘어짐 그림(PersonRig._draw_dir8_fall)이 잰 누운 머리 자리 위
			draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, IsoView.ground(global_position, level)))
			at = get_meta(&"ko_head") + Vector2(0, 3)
	else:
		draw_set_transform(Vector2(0, -12), 0.0, Vector2.ONE)
	for k in 3:
		var c := at + Vector2(-8.0 + k * 8.0, -2.0 - (k % 2) * 4.0)
		var pts := PackedVector2Array()
		for i in 10:
			pts.append(c + Vector2.UP.rotated(i * PI / 5.0) * (3.2 if i % 2 == 0 else 1.4))
		draw_colored_polygon(pts, Color(1.0, 0.86, 0.2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
