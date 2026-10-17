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


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR     # 인물 그림(PersonRig 스프라이트)을 줄여 그릴 때 깨지지 않게
	collision_layer = Layers.PEOPLE
	collision_mask = Layers.WORLD | Layers.VEHICLES
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)


func _physics_process(delta: float) -> void:
	if not input_enabled:
		velocity = Vector2.ZERO
		return
	var dir := Vector2(Input.get_axis("steer_left", "steer_right"), Input.get_axis("accelerate", "brake"))
	if dir.length() > 1.0:
		dir = dir.normalized()
	if IsoView.enabled and screen_walk:
		dir = IsoView.walk_dir(dir)
	var speed := RUN_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	velocity = dir * speed
	if dir != Vector2.ZERO:
		facing = Vector2.UP.angle_to(dir)
		walk_phase += delta * velocity.length() / 9.0
	move_and_slide()
	_sort()


func _process(_delta: float) -> void:
	queue_redraw()   # 그림은 화면 프레임마다 한 번
	_sort()


## 2.5D: 깊이(월드 x+y)로 그리는 순서를 정한다
func _sort() -> void:
	z_as_relative = not IsoView.enabled
	z_index = IsoView.z_of(global_position) if IsoView.enabled else 0


## 차에 타면 숨기고 충돌을 끈다. 내리면 되돌린다.
func set_in_vehicle(inside: bool) -> void:
	visible = not inside
	input_enabled = not inside
	collision_layer = 0 if inside else Layers.PEOPLE
	collision_mask = 0 if inside else Layers.WORLD | Layers.VEHICLES


## 그 자리에 서면 벽이나 차와 겹치는지
func blocked_at(pos: Vector2) -> bool:
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, pos)
	query.collision_mask = Layers.WORLD | Layers.VEHICLES
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
	queue_redraw()


func follow_velocity() -> Vector2:
	return velocity


func zoom_ratio() -> float:
	return 0.0


func _draw() -> void:
	if is_dead():
		PersonDrawer.draw_blood(self, facing)
		if IsoView.enabled:
			PersonRig.draw(self, facing, walk_phase, 0.0, shirt, pants, hair, 1.0, null, 0, null, true)
		else:
			PersonDrawer.draw(self, facing, walk_phase, shirt, pants, hair, true)
		return
	# 보행자 사이에서 주인공을 찾기 쉽게 발밑에 노란 고리
	draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.2, 0.55), 2.0)
	if IsoView.enabled:
		var gait: float = 0.0 if velocity.length_squared() < 1.0 else (2.0 if velocity.length() > WALK_SPEED + 20.0 else 1.0)
		PersonRig.draw(self, facing, walk_phase, gait, shirt, pants, hair, 1.0, null, 0, arsenal.current(), false)
		return
	PersonDrawer.draw(self, facing, walk_phase, shirt, pants, hair)
	var w := arsenal.current()
	if not w.melee:
		# 손에 든 총
		draw_set_transform(Vector2.ZERO, facing, Vector2.ONE)
		draw_rect(Rect2(5.5, -10 - w.slot, 2.5, 8 + w.slot), Color(0.12, 0.12, 0.14))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
