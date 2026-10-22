class_name Player
extends CharacterBody2D
## 도보 주인공. 차와 반대로 관성이 없다 — 누르면 즉시 움직이고 떼면 즉시 선다.
## 이동 방향은 화면 기준(W=위). 운전 키를 그대로 쓴다: 동시에 하나만 조종하므로 겹치지 않는다.
## 2.5D 화면에서는 화면 위가 월드 북서쪽이므로 입력을 IsoView.walk_dir로 돌린다.

signal died

const FIST: WeaponType = preload("res://data/weapons/fist.tres")
const MAX_HEALTH := 100.0
const WALK_SPEED := 110.0
const RUN_SPEED := 190.0
const RADIUS := 7.0

var control := PlayerControl.new()   ## 로컬 입력 또는 외부 입력을 이 플레이어에만 전달한다
var input_enabled := true
var health := MAX_HEALTH
var arsenal := Arsenal.new(FIST)
var facing := 0.0
var walk_phase := 0.0
var shirt := Color(0.12, 0.12, 0.13)   # 패키지 아트의 검은 재킷
var pants := Color(0.2, 0.22, 0.3)
var hair := Color(0.05, 0.05, 0.05)
## false면 2.5D 화면에서도 W가 월드 북쪽 (테스트가 월드 방향으로 걷게 할 때)
var screen_walk := true
## 이 시간(초) 동안은 걸어도 겨눈 쪽을 바라본다 (마우스 조준)
var _aim_hold := 0.0
## 경찰에게 맞아 쓰러졌다 — 체포 화면 직전 (그림은 넘어짐, 움직이지 못한다)
var knocked_down := false
var _stun := 0.0                 ## 맞아서 못 움직이는 남은 시간
var _push := Vector2.ZERO        ## 맞아서 밀려나는 속도
var _hurt := 0.0                 ## 맞은 뒤 붉게 번쩍이는 남은 시간
var level := 0                   ## 고가차도 층 (CityMap.level_zone)
var _col_base := Vector2i(Layers.PEOPLE, Layers.WORLD | Layers.VEHICLES)
## 제자리 점프 (Space·패드 A — 차에서는 핸드브레이크): 웅크림 JUMP_PRE · 공중 JUMP_AIR · 받으며 일어섬 JUMP_POST.
## 그림만 뜬다(PersonRig._draw_jump — 영상 점프의 장면과 떠오른 높이) — 충돌·층은 땅 그대로, 뛴 순간의 걸음 속도와 방향을 끝까지 지킨다
const JUMP_PRE := 0.16
const JUMP_AIR := 0.5
const JUMP_POST := 0.3
var _jump := -1.0                ## 점프가 시작된 뒤 지난 시간 (−1 = 점프 아님)
var _jump_vel := Vector2.ZERO
var _jump_key := false           ## 지난 틱에 점프 키를 누르고 있었는지 (누르는 순간에만 뛴다)


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR     # 인물 그림(PersonRig 스프라이트)을 줄여 그릴 때 깨지지 않게
	_set_collision(Layers.PEOPLE, Layers.WORLD | Layers.VEHICLES)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)


func _physics_process(delta: float) -> void:
	apply_movement(control.read(screen_walk), delta)


## 입력 출처와 무관한 도보 시뮬레이션. 외부 move_world는 화면 변환을 다시 하지 않는다.
func apply_movement(command: PlayerInputCommand, delta: float) -> void:
	var pressed := command.handbrake and not _jump_key   # 차에서 핸드브레이크를 누른 채 내려도 뛰지 않게 늘 잰다
	_jump_key = command.handbrake
	if input_enabled:
		_track_level()
	if not input_enabled or knocked_down or _stun > 0.0:
		_end_jump()
	if not input_enabled or knocked_down:
		velocity = Vector2.ZERO
		return
	if _stun > 0.0:
		# 맞고 비틀거린다: 입력을 받지 않고 맞은 쪽으로 조금 밀려난다
		_stun -= delta
		velocity = _push
		_push = _push.move_toward(Vector2.ZERO, 500.0 * delta)
		move_and_slide()
		_sort()
		return
	if _jump >= 0.0 or (pressed and not has_meta(&"punch_state")):
		_jump_step(command, delta)
		return
	# 주먹을 지르는 동안은 제자리 (영상 그림의 발이 땅에 붙어 있다 — 움직이면 발이 미끄러져 보인다)
	var dir := Vector2.ZERO if has_meta(&"punch_state") else command.move_world
	var speed := RUN_SPEED if command.sprint else WALK_SPEED
	velocity = dir * speed
	_aim_hold = maxf(_aim_hold - delta, 0.0)
	if dir != Vector2.ZERO:
		if _aim_hold <= 0.0 and not has_meta(&"punch_state"):
			facing = Vector2.UP.angle_to(dir)
		walk_phase += delta * velocity.length() / 9.0
	move_and_slide()
	_sort()


## 점프 한 틱: 처음이면 지금 걸음(입력 방향 × 걷기·달리기 속도)을 정하고, 끝날 때까지 그 속도로 간다
func _jump_step(command: PlayerInputCommand, delta: float) -> void:
	if _jump < 0.0:
		_jump = 0.0
		_jump_vel = command.move_world * (RUN_SPEED if command.sprint else WALK_SPEED)
		if _jump_vel != Vector2.ZERO and _aim_hold <= 0.0:
			facing = Vector2.UP.angle_to(_jump_vel)
	else:
		_jump += delta
	if _jump >= JUMP_PRE + JUMP_AIR + JUMP_POST:
		_jump = -1.0
		remove_meta(&"jump_state")
		return
	set_meta(&"jump_state", {"elapsed": _jump, "facing": facing})
	velocity = _jump_vel
	move_and_slide()
	_sort()


func jumping() -> bool:
	return _jump >= 0.0


func _process(delta: float) -> void:
	if _hurt > 0.0:
		_hurt = maxf(_hurt - delta, 0.0)
		self_modulate = Color(1.0, 0.55, 0.5) if _hurt > 0.0 else Color.WHITE
	queue_redraw()   # 그림은 화면 프레임마다 한 번
	_sort()


func _end_jump() -> void:
	_jump = -1.0
	if has_meta(&"jump_state"):
		remove_meta(&"jump_state")


## 2.5D: 깊이(월드 x+y)로 그리는 순서를 정한다
func _sort() -> void:
	z_as_relative = not IsoView.enabled
	z_index = IsoView.z_at(global_position, level) if IsoView.enabled else 0


## 차에 타면 숨기고 충돌을 끈다. 내리면 되돌린다.
func set_in_vehicle(inside: bool) -> void:
	visible = not inside
	input_enabled = not inside
	_end_jump()
	_set_collision(0 if inside else Layers.PEOPLE, 0 if inside else Layers.WORLD | Layers.VEHICLES)


## 고가차도 층 (0 땅 · 1 고가 위). 차에 탔다 내리면 차의 층을 받는다
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


## 그 자리에 서면 벽이나 차와 겹치는지
func blocked_at(pos: Vector2) -> bool:
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, pos)
	query.collision_mask = Layers.at(Layers.WORLD | Layers.VEHICLES, level)
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


## 총·폭발에 맞는다 (차 안에서는 차가 대신 맞는다). 0이 되면 died
func take_damage(amount: float) -> void:
	if health <= 0.0 or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	queue_redraw()
	if health <= 0.0:
		input_enabled = false
		died.emit()


## 경찰 곤봉에 맞는다: 체력이 줄고(매로는 죽지 않는다 — 1은 남는다) 잠깐 비틀거리며 밀려난다
func beaten(amount: float, push_dir: Vector2, stun_time: float) -> void:
	if is_dead() or knocked_down:
		return
	health = maxf(health - amount, 1.0)
	_stun = maxf(_stun, stun_time)
	_push = push_dir.normalized() * 80.0
	_hurt = 0.18
	queue_redraw()


## 잠깐 못 움직인다 (차에서 끌려 나올 때)
func stun(seconds: float) -> void:
	_stun = maxf(_stun, seconds)


## 맞아 쓰러진다 (체포 직전)
func knock_down() -> void:
	knocked_down = true
	input_enabled = false          # 차 타기·총 쏘기도 막는다 (체포 뒤 Main._respawn이 되돌린다)
	velocity = Vector2.ZERO
	queue_redraw()


## 주먹을 한 번 지를 때 (그림만): COMBO_GAP초 안에 이어 지르면 잽 → 스트레이트 → 훅 → 다시 잽
const COMBO_GAP := 0.7
var _combo := -1
var _combo_at := -100.0

func punch() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_combo = (_combo + 1) % PersonRig.PUNCH_SEGS.size() if now - _combo_at <= COMBO_GAP else 0
	_combo_at = now
	set_meta(&"punch", [_combo, now])


## dir 쪽을 바라보고, hold초 동안은 걷는 방향으로 돌지 않는다
func face(dir: Vector2, hold := 0.0) -> void:
	if has_meta(&"punch_state"):
		return
	if dir != Vector2.ZERO:
		facing = Vector2.UP.angle_to(dir)
	_aim_hold = maxf(_aim_hold, hold)


func is_dead() -> bool:
	return health <= 0.0


## 구급상자·구급차: 체력을 조금 채운다
func heal(amount: float) -> void:
	if is_dead():
		return
	health = minf(health + amount, MAX_HEALTH)


## 병원에서 다시 시작할 때
func revive() -> void:
	health = MAX_HEALTH
	knocked_down = false
	_stun = 0.0
	_push = Vector2.ZERO
	queue_redraw()


func follow_velocity() -> Vector2:
	return velocity


func zoom_ratio() -> float:
	return 0.0


func _draw() -> void:
	if is_dead() or knocked_down:
		if is_dead():
			PersonDrawer.draw_blood(self, facing)
		if IsoView.enabled:
			PersonRig.draw(self, facing, walk_phase, 0.0, shirt, pants, hair, 1.0, null, 0, null, true)
		else:
			PersonDrawer.draw(self, facing, walk_phase, shirt, pants, hair, true)
		return
	# 보행자 사이에서 주인공을 찾기 쉽게 발밑에 노란 고리
	draw_arc(PersonDrawer._base(self), 11.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.2, 0.55), 2.0)   # 비탈·다리 위면 땅 높이에
	if IsoView.enabled:
		var gait: float = 0.0 if velocity.length_squared() < 1.0 else (2.0 if velocity.length() > WALK_SPEED + 20.0 else 1.0)
		PersonRig.draw(self, facing, walk_phase, gait, shirt, pants, hair, 1.0, null, 0, arsenal.current(), false)
		if _hurt > 0.0:
			_draw_hit_burst()
		return
	PersonDrawer.draw(self, facing, walk_phase, shirt, pants, hair)
	var w := arsenal.current()
	if not w.melee:
		# 손에 든 총
		draw_set_transform(Vector2.ZERO, facing, Vector2.ONE)
		draw_rect(Rect2(5.5, -10 - w.slot, 2.5, 8 + w.slot), Color(0.12, 0.12, 0.14))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 맞은 순간 가슴께에 하얀 충격 (곤봉) — 맞은 직후 커졌다가 사라진다
func _draw_hit_burst() -> void:
	var t := 1.0 - _hurt / 0.18
	draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, PersonDrawer._ground(self)))
	var c := Vector2(0.0, -17.0)
	var col := Color(1.0, 0.97, 0.85, 0.9 * (1.0 - t))
	for i in 6:
		var d := Vector2.RIGHT.rotated(i * TAU / 6.0 + 0.3)
		draw_line(c + d * (2.0 + 3.0 * t), c + d * (5.0 + 4.0 * t), col, 1.4)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
