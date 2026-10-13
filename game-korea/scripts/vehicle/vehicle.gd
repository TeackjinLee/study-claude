class_name Vehicle
extends CharacterBody2D
## 차 한 대. 물리 계산은 VehicleMotor가 하고, 이 노드는 입력·충돌·그리기만 맡는다.

signal impacted(strength: float)
signal bumped(other: Vehicle, strength: float)
signal caught_fire                           ## 체력이 0이 됐다 — burning초 뒤 터진다
signal exploded(by_player: bool)

const RESTITUTION := 0.35
const COLLISION_FRICTION := 0.8
const SKID_LATERAL_SPEED := 140.0
const PARKED_DRAG := 500.0   ## 아무도 조종하지 않는 차가 서는 감속 px/s²
const REDRAW_RANGE := 2400.0 ## 카메라에서 이보다 먼 차는 다시 그리지 않는다 (가장 멀리 줌아웃해도 화면 밖)

@export var stats: VehicleType
var controlled := false       ## 플레이어가 운전 중 (Director가 정한다)
var has_driver := false       ## NPC 운전자가 타고 있음 — 탈취하면 끌려 나와 도망친다
var ai: TrafficAI = null      ## 도로를 달리는 NPC 차의 운전자 (주차된 차는 null)
var pursuit: PursuitAI = null ## 추격 중인 경찰차의 운전자
var siren := false            ## 경광등 (경찰차)
var motor: VehicleMotor
var health := 0.0             ## 0이 되면 불이 붙는다 (최대 stats.durability)
var burning := -1.0           ## 불붙은 뒤 터지기까지 남은 시간. 음수면 불이 안 붙었다
var wrecked := false          ## 터져서 잔해만 남았다 — 탈 수도 움직일 수도 없다
var hit_by_player := false    ## 마지막 피해를 주인공이 줬다 (폭발 피해를 누구 탓으로 할지)
var paint := Color.WHITE      ## 차체 색 (카센터에서 다시 칠할 수 있다)
var beam := true              ## 2.5D에서 바닥에 전조등 빛을 그린다 (차량 도감에선 끈다)
var ground := 0.0             ## 2.5D 땅 높이 (다리 위·경사로). 그림만 올리고 물리는 평면 그대로다
## 차 category → 체력 배율 (부업 보너스: 택시·버스·오토바이 +50%). main이 정한다
static var durability_bonus := {}

var throttle_input := 0.0
var steer_input := 0.0
var handbrake_input := false

var _shape: CollisionShape2D
var _drawn_look: Array = []   ## 마지막으로 그린 모습 (같으면 다시 그리지 않는다)


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	z_as_relative = false
	z_index = 1
	collision_layer = Layers.VEHICLES
	collision_mask = Layers.WORLD | Layers.VEHICLES
	_shape = CollisionShape2D.new()
	add_child(_shape)
	apply_stats(stats)


## 차종 교체. 위치·방향은 유지하고 속도는 0으로 만든다.
func apply_stats(new_stats: VehicleType) -> void:
	stats = new_stats
	var heading := motor.heading if motor else rotation
	motor = VehicleMotor.new(stats)
	motor.heading = heading
	health = max_health()
	paint = stats.body_color
	var rect := RectangleShape2D.new()
	rect.size = stats.size
	_shape.shape = rect
	queue_redraw()


func place(pos: Vector2, heading: float) -> void:
	global_position = pos
	motor.heading = heading
	motor.velocity = Vector2.ZERO
	motor.steer = 0.0
	rotation = heading


func _physics_process(delta: float) -> void:
	if burning >= 0.0:
		burning -= delta
		if burning <= 0.0:
			_explode()
	if wrecked:
		throttle_input = 0.0
		steer_input = 0.0
		handbrake_input = false
	elif controlled:
		throttle_input = Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
		steer_input = Input.get_axis("steer_left", "steer_right")
		handbrake_input = Input.is_action_pressed("handbrake")
	elif pursuit and has_driver:
		pursuit.drive(delta)
	elif ai and has_driver:
		ai.drive(delta)
	else:
		throttle_input = 0.0
		steer_input = 0.0
		handbrake_input = false
	motor.step(throttle_input, steer_input, handbrake_input, delta)
	if wrecked or (not controlled and not (has_driver and (ai or pursuit))):
		motor.velocity = motor.velocity.move_toward(Vector2.ZERO, PARKED_DRAG * delta)
	rotation = motor.heading
	_move(delta)
	# 2.5D: 깊이(월드 x+y)로 그리는 순서를 정한다
	z_index = IsoView.z_of(global_position) if IsoView.enabled else 1
	ground = IsoView.ground(global_position)
	# 화면 밖(카메라에서 먼) 차는 다시 그리지 않는다 — 다가오면 그때 그린다.
	# 가까워도 모습이 그대로면(곧게 달리거나 서 있으면) 다시 그리지 않는다 — 노드가 움직이면 그림도 따라간다
	var cam := ChaseCamera.current_cam()
	if cam == null or global_position.distance_squared_to(cam.global_position) < REDRAW_RANGE * REDRAW_RANGE:
		var look := _look()
		if look != _drawn_look or _animated():
			_drawn_look = look
			queue_redraw()


## 그림을 바꾸는 상태: 방향·탑승·브레이크·후진·잔해·도색·경적·화면 방식
func _look() -> Array:
	return [snappedf(rotation, 0.002), occupied(), is_braking(), motor.forward_speed() < -5.0, wrecked, paint,
		ai != null and ai.honking, IsoView.enabled, snappedf(ground, 0.5)]


## 매 프레임 움직이는 그림 (경광등·불·연기, 위에서 보기의 레미콘 드럼·잔해 불씨)
func _animated() -> bool:
	if siren or burning >= 0.0 or health < max_health() * 0.35:
		return true
	return not IsoView.enabled and (wrecked or stats.category == &"mixer")


func _move(delta: float) -> void:
	var motion := motor.velocity * delta
	for i in 2:
		var col := move_and_collide(motion)
		if col == null:
			return
		var n := col.get_normal()
		var other := col.get_collider() as Vehicle
		if other:
			_bump(other, n)
		else:
			var vn := motor.velocity.dot(n)
			if vn < 0.0:
				motor.velocity -= n * vn * (1.0 + RESTITUTION)
				motor.velocity *= COLLISION_FRICTION
				impacted.emit(-vn)
				take_damage(DamageModel.crash_damage(-vn), controlled)
		motion = col.get_remainder().slide(n)


## 차끼리 부딪히면 질량비로 양쪽에 충격량을 나눈다. 무거운 차가 덜 밀린다.
## bumped는 충격량을 나누기 전에 낸다 — 받는 쪽이 부딪히기 직전 속도로 누가 들이받았는지 판단한다.
func _bump(other: Vehicle, n: Vector2) -> void:
	var vn := (motor.velocity - other.motor.velocity).dot(n)
	if vn >= 0.0:
		return
	bumped.emit(other, -vn)
	var j := -(1.0 + RESTITUTION) * vn / (1.0 / stats.mass + 1.0 / other.stats.mass)
	motor.velocity += n * j / stats.mass
	other.motor.velocity -= n * j / other.stats.mass
	impacted.emit(-vn)
	other.impacted.emit(-vn)
	# 같은 무게 차끼리 정면으로 부딪히면 벽에 절반 속도로 박은 것과 같다 — 가벼운 쪽이 더 다친다
	var by_player := controlled or other.controlled
	var total := stats.mass + other.stats.mass
	take_damage(DamageModel.crash_damage(-vn * other.stats.mass / total), by_player)
	other.take_damage(DamageModel.crash_damage(-vn * stats.mass / total), by_player)


## 피해를 입는다. 체력이 0이 되면 불이 붙고 fuse초 뒤 터진다 (이미 불타면 더 빨리 터질 뿐).
func take_damage(amount: float, by_player: bool, fuse := DamageModel.BURN_TIME) -> void:
	if wrecked or amount <= 0.0:
		return
	hit_by_player = by_player
	health = maxf(health - amount, 0.0)
	if health > 0.0:
		return
	if burning < 0.0:
		burning = fuse
		caught_fire.emit()
	else:
		burning = minf(burning, fuse)


func _explode() -> void:
	burning = -1.0
	wrecked = true
	has_driver = false
	siren = false
	queue_redraw()
	exploded.emit(hit_by_player)


func occupied() -> bool:
	return not wrecked and (controlled or has_driver)


## 최대 체력 (부업 보너스 포함)
func max_health() -> float:
	return stats.durability * durability_bonus.get(stats.category, 1.0)


## 사람이 탈 수 있는 차인지 (불타거나 터진 차는 안 된다)
func usable() -> bool:
	return not wrecked and burning < 0.0 and stats.enterable


## 운전석(왼쪽) 또는 조수석 문 바깥 지점
func door_position(passenger: bool) -> Vector2:
	var side := 1.0 if passenger else -1.0
	return to_global(Vector2(side * (stats.size.x * 0.5 + 12.0), -stats.size.y * 0.08))


func follow_velocity() -> Vector2:
	return motor.velocity


func zoom_ratio() -> float:
	return clampf(speed() / stats.max_speed, 0.0, 1.0)


func speed() -> float:
	return motor.velocity.length()


func is_braking() -> bool:
	return throttle_input < 0.0 and motor.forward_speed() > 10.0


func is_skidding() -> bool:
	return absf(motor.lateral_speed()) > SKID_LATERAL_SPEED \
		or (handbrake_input and speed() > 80.0) \
		or (is_braking() and motor.forward_speed() > stats.max_speed * 0.6)


func rear_wheel_positions() -> Array[Vector2]:
	var x := stats.size.x * 0.36
	var y := stats.size.y * 0.32
	return [to_global(Vector2(-x, y)), to_global(Vector2(x, y))]


func _draw() -> void:
	var w := stats.size.x
	var h := stats.size.y
	var top := -h * 0.5
	var left := -w * 0.5
	if IsoView.enabled:
		_draw_iso(w, h)
		return
	if wrecked:
		_draw_wreck(w, h)
		return

	# 헤드라이트 빛 (밤 분위기) — 사람이 타 있을 때만 켠다
	if occupied():
		draw_colored_polygon(PackedVector2Array([
			Vector2(left + 4, top), Vector2(-w * 1.6, top - h * 1.6),
			Vector2(w * 1.6, top - h * 1.6), Vector2(-left - 4, top)]),
			Color(1.0, 0.95, 0.7, 0.07))
	# 그림자
	draw_rect(Rect2(left + 3, top + 4, w, h), Color(0, 0, 0, 0.35))
	if stats.category == &"bike":
		_draw_bike(w, h)
		_draw_damage(w, h)
		return
	if stats.category == &"bicycle":
		_draw_bicycle(w, h)
		return
	# 바퀴
	for r in _wheels(w, h):
		draw_rect(r, Color(0.08, 0.08, 0.09))
	_draw_body(w, h)


func _wheels(w: float, h: float) -> Array[Rect2]:
	var wheel := Vector2(6, 12)
	var out: Array[Rect2] = []
	for sx in [-1.0, 1.0]:
		for wy in [-h * 0.5 + h * 0.12, -h * 0.5 + h * 0.70]:
			out.append(Rect2(Vector2(sx * (w * 0.5 + 1) - wheel.x * 0.5, wy), wheel))
	return out


## 위에서 본 차체 (2.5D에서는 지붕 높이로 올려 같은 그림을 쓴다)
func _draw_body(w: float, h: float) -> void:
	var top := -h * 0.5
	var left := -w * 0.5
	var body := Rect2(left, top, w, h)
	var glass := Color(0.12, 0.17, 0.26)
	if stats.category == &"bus":
		draw_rect(body, paint)
		draw_rect(Rect2(left + 3, top + 4, w - 6, h * 0.06), glass)
		var roof := Rect2(left + 4, top + h * 0.12, w - 8, h * 0.84)
		draw_rect(roof, stats.roof_color)
		for i in 3:
			draw_rect(Rect2(left + 8, roof.position.y + 10 + i * h * 0.27, w - 16, h * 0.12), stats.roof_color.darkened(0.15))
		draw_rect(Rect2(left + 1, top + h * 0.15, 3, h * 0.8), glass)
		draw_rect(Rect2(-left - 4, top + h * 0.15, 3, h * 0.8), glass)
	elif stats.category in TRUCKS:
		# 앞쪽은 캡, 나머지는 차종마다 다른 짐칸
		var cab_h := minf(h * 0.32, 26.0) if stats.category != &"truck" else h * 0.32
		draw_rect(Rect2(left, top, w, cab_h), paint)
		draw_rect(Rect2(left + 3, top + cab_h * 0.22, w - 6, cab_h * 0.28), glass)
		draw_rect(Rect2(left + 3, top + cab_h * 0.55, w - 6, cab_h * 0.38), stats.roof_color if stats.category == &"truck" else paint.darkened(0.15))
		var bed := Rect2(left, top + cab_h + 2, w, h - cab_h - 2)
		_draw_truck_bed(bed, w)
	elif stats.category == &"camper":
		# 캠핑카: 큰 상자형 차체, 지붕 창과 차양
		draw_rect(body, paint)
		draw_rect(Rect2(left + 3, top + h * 0.06, w - 6, h * 0.1), glass)
		var roof := Rect2(left + 3, top + h * 0.2, w - 6, h * 0.76)
		draw_rect(roof, paint.lightened(0.05))
		draw_rect(Rect2(left, top + h * 0.45, w, h * 0.07), stats.roof_color)
		draw_rect(Rect2(left + 8, top + h * 0.6, w - 16, h * 0.14), glass.lightened(0.2))
		draw_rect(Rect2(-left - 2, top + h * 0.3, 4, h * 0.5), Color(0.9, 0.5, 0.2))
	elif stats.category == &"ambulance" or stats.category == &"swat":
		# 승합형: 짧은 보닛, 긴 상자 지붕
		draw_rect(body, paint)
		draw_rect(Rect2(left + 3, top + h * 0.1, w - 6, h * 0.12), glass)
		var roof := Rect2(left + 3, top + h * 0.25, w - 6, h * 0.71)
		draw_rect(roof, paint.lightened(0.06))
		if stats.category == &"ambulance":
			draw_rect(Rect2(left, top + h * 0.5, w, h * 0.08), stats.roof_color)
			var c := roof.get_center()
			draw_rect(Rect2(c - Vector2(3, 9), Vector2(6, 18)), Color(0.9, 0.12, 0.15))
			draw_rect(Rect2(c - Vector2(9, 3), Vector2(18, 6)), Color(0.9, 0.12, 0.15))
		else:
			for i in 4:
				draw_line(Vector2(left + 6, roof.position.y + 8 + i * roof.size.y / 4.0),
					Vector2(-left - 6, roof.position.y + 8 + i * roof.size.y / 4.0), paint.darkened(0.3), 2.0)
			draw_rect(Rect2(left + 1, top + h * 0.3, 3, h * 0.6), Color(0.85, 0.85, 0.9, 0.7))
			draw_rect(Rect2(-left - 4, top + h * 0.3, 3, h * 0.6), Color(0.85, 0.85, 0.9, 0.7))
		_draw_lightbar(w, top + h * 0.26)
	else:
		draw_rect(body, paint)
		if stats.category == &"police":
			# 옆구리 파란 띠 + 노란 줄 (가상의 경찰차 도색)
			draw_rect(Rect2(left, top + h * 0.40, w, h * 0.22), stats.roof_color)
			draw_rect(Rect2(left, top + h * 0.62, w, h * 0.04), Color(0.95, 0.8, 0.15))
		draw_rect(Rect2(left + 4, top + h * 0.22, w - 8, h * 0.15), glass)
		draw_rect(Rect2(left + 4, top + h * 0.37, w - 8, h * 0.30), stats.roof_color)
		draw_rect(Rect2(left + 4, top + h * 0.67, w - 8, h * 0.10), glass)
		if stats.category == &"police":
			_draw_lightbar(w, top + h * 0.44)
		elif stats.category == &"suv":
			# 지붕 짐받이
			for x in [left + 7, -left - 7]:
				draw_line(Vector2(x, top + h * 0.38), Vector2(x, top + h * 0.66), paint.darkened(0.5), 2.0)
		elif stats.category == &"taxi":
			var lamp := Rect2(-7, top + h * 0.47, 14, 7)
			draw_rect(lamp, Color(1.0, 0.92, 0.4))
			draw_rect(lamp, Color(0.3, 0.2, 0.05), false, 1.0)
		elif stats.category == &"sport":
			# 보닛부터 트렁크까지 두 줄 스트라이프
			for x in [-4.0, 2.0]:
				draw_rect(Rect2(x, top + 2, 2, h * 0.2), Color(1, 1, 1, 0.8))
				draw_rect(Rect2(x, top + h * 0.78, 2, h * 0.2), Color(1, 1, 1, 0.8))
	draw_rect(body, paint.darkened(0.45), false, 2.0)
	if occupied() and stats.category != &"bus":
		draw_circle(Vector2(-w * 0.18, top + h * 0.33), 4.5, Color(0.06, 0.05, 0.05))

	# 전조등 · 후미등
	var head := Color(1.0, 0.95, 0.65)
	draw_rect(Rect2(left + 2, top + 1, 6, 3), head)
	draw_rect(Rect2(-left - 8, top + 1, 6, 3), head)
	var tail := Color(1.0, 0.15, 0.2) if is_braking() else Color(0.6, 0.05, 0.08)
	if motor.forward_speed() < -5.0:
		tail = Color(0.95, 0.95, 0.95)
	draw_rect(Rect2(left + 2, -top - 4, 6, 3), tail)
	draw_rect(Rect2(-left - 8, -top - 4, 6, 3), tail)
	if siren:
		# 경광등 불빛이 바닥에 번진다
		var red := _siren_phase()
		draw_circle(Vector2(0, top + h * 0.47), w * 1.3, Color(1.0, 0.1, 0.15, 0.10) if red else Color(0.15, 0.35, 1.0, 0.12))
	_draw_damage(w, h)
	if ai and ai.honking and not IsoView.enabled:
		draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
		draw_string(ThemeDB.fallback_font, Vector2(-20, -h * 0.5 - 10), "빵!",
			HORIZONTAL_ALIGNMENT_CENTER, 40, 16, Color(1.0, 0.9, 0.3))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ── 2.5D ──────────────────────────────────────────────────
## 바닥에 그림자·전조등 빛, 그 위에 차종별 입체 모형(VehicleModel, docs/12의 참고 그림을 보고 만든 것).

func _draw_iso(w: float, h: float) -> void:
	var top := -h * 0.5
	var left := -w * 0.5
	var two_wheel := stats.category in [&"bike", &"bicycle"]
	# 다리 위면 그 높이에서부터 그린다 (전조등 빛·그림자·모형 모두)
	_lift(0.0)
	if beam and occupied() and not wrecked and not two_wheel:
		draw_colored_polygon(PackedVector2Array([
			Vector2(left + 4, top), Vector2(-w * 1.6, top - h * 1.6),
			Vector2(w * 1.6, top - h * 1.6), Vector2(-left - 4, top)]),
			Color(1.0, 0.95, 0.7, 0.07))
	draw_rect(Rect2(left - 2, top - 2, w + 4, h + 4), Color(0, 0, 0, 0.35))
	# 차종별 입체 모형 (VehicleModel). 터진 차는 같은 모형을 그을려 그린다
	VehicleModel.draw(self, self)
	_lift(stats.height)
	_draw_damage(w, h)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if ai and ai.honking:
		draw_set_transform_matrix(_screen_local(stats.height + 14.0))
		draw_string(ThemeDB.fallback_font, Vector2(-20, 0), "빵!", HORIZONTAL_ALIGNMENT_CENTER, 40, 16, Color(1.0, 0.9, 0.3))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 노드가 회전해 있으므로, 높이 오프셋도 노드 좌표로 돌려 둔다
func _lift(height: float) -> void:
	draw_set_transform(IsoView.lift_local(height + ground, rotation), 0.0, Vector2.ONE)


## 화면 기준 좌표계 (회전한 노드 안에서): 차 위 글자를 세워 쓴다
func _screen_local(height: float) -> Transform2D:
	return Transform2D(-rotation, Vector2.ZERO) * IsoView.screen_frame(Vector2.ZERO, height + ground)


const TRUCKS := [&"truck", &"tanker", &"garbage", &"mixer", &"fire", &"tow", &"bigtruck", &"army"]


## 트럭 짐칸: 화물칸·탱크·청소 상자·믹서 드럼·소방 사다리·견인 크레인·컨테이너
func _draw_truck_bed(bed: Rect2, w: float) -> void:
	var left := bed.position.x
	match stats.category:
		&"tanker":
			draw_rect(bed.grow(-1), stats.body_color)
			draw_rect(Rect2(left + 3, bed.position.y + 3, w - 6, bed.size.y - 6), stats.body_color.darkened(0.08))
			draw_rect(Rect2(left, bed.get_center().y - 6, w, 12), stats.roof_color)
			draw_string(ThemeDB.fallback_font, Vector2(left, bed.get_center().y + 4), "SR", HORIZONTAL_ALIGNMENT_CENTER, w, 10, Color.WHITE)
			for k in 3:
				draw_circle(Vector2(0, bed.position.y + 10 + k * bed.size.y * 0.33), 3.0, Color(0.4, 0.4, 0.42))
		&"garbage":
			draw_rect(bed, paint)
			draw_rect(Rect2(left + 3, bed.position.y + 3, w - 6, bed.size.y * 0.7), paint.lightened(0.1))
			draw_rect(Rect2(left, bed.end.y - bed.size.y * 0.22, w, bed.size.y * 0.22), Color(0.3, 0.3, 0.32))
			draw_line(Vector2(left + 2, bed.get_center().y), Vector2(-left - 2, bed.get_center().y), paint.darkened(0.3), 2.0)
		&"mixer":
			draw_rect(bed, Color(0.4, 0.4, 0.42))
			var drum := Rect2(left + 3, bed.position.y + 4, w - 6, bed.size.y - 10)
			draw_rect(drum, stats.roof_color)
			var t := Time.get_ticks_msec() / 400.0
			for k in 5:
				var y := drum.position.y + fposmod(k * drum.size.y / 5.0 + t * 6.0, drum.size.y)
				draw_line(Vector2(drum.position.x, y), Vector2(drum.end.x, y - 6), stats.roof_color.darkened(0.3), 3.0)
		&"fire":
			draw_rect(bed, paint)
			draw_rect(Rect2(left + 6, bed.position.y + 4, w - 12, bed.size.y - 8), Color(0.75, 0.75, 0.78))
			var y := bed.position.y + 8
			while y < bed.end.y - 6:
				draw_line(Vector2(left + 8, y), Vector2(-left - 8, y), Color(0.5, 0.5, 0.52), 2.0)
				y += 7
			draw_circle(Vector2(0, bed.position.y + 6), 5.0, Color(0.85, 0.85, 0.2))
			_draw_lightbar(w, bed.position.y - 6)
		&"tow":
			draw_rect(bed, Color(0.3, 0.3, 0.32))
			draw_line(Vector2(0, bed.position.y + 4), Vector2(0, bed.end.y + 6), stats.body_color, 5.0)
			draw_line(Vector2(-6, bed.end.y + 2), Vector2(6, bed.end.y + 2), Color(0.15, 0.15, 0.16), 3.0)
			draw_rect(Rect2(-w * 0.5 + 4, bed.position.y - 4, w - 8, 4), Color(1.0, 0.6, 0.1))
		&"army":
			# 국방색 천막 짐칸과 늑골
			draw_rect(bed, stats.roof_color)
			for k in range(1, 6):
				var y := bed.position.y + bed.size.y * k / 6.0
				draw_line(Vector2(left + 2, y), Vector2(-left - 2, y), stats.roof_color.darkened(0.3), 2.0)
			draw_rect(bed, stats.body_color.darkened(0.4), false, 2.0)
			draw_string(ThemeDB.fallback_font, Vector2(left, bed.get_center().y + 5), "★", HORIZONTAL_ALIGNMENT_CENTER, w, 14, Color(0.95, 0.9, 0.6, 0.8))
		&"bigtruck":
			draw_rect(bed, stats.roof_color)
			for k in range(1, 8):
				var x := left + w * k / 8.0
				draw_line(Vector2(x, bed.position.y + 2), Vector2(x, bed.end.y - 2), stats.roof_color.darkened(0.25), 2.0)
			draw_rect(bed, stats.roof_color.darkened(0.45), false, 2.0)
		_:
			draw_rect(bed, Color(0.42, 0.44, 0.48))
			for i in range(1, 5):
				var y := bed.position.y + bed.size.y * i / 5.0
				draw_line(Vector2(left + 2, y), Vector2(-left - 2, y), Color(0.32, 0.33, 0.37), 2.0)
			draw_rect(bed, Color(0.25, 0.26, 0.29), false, 2.0)


## 자전거: 가는 몸체와 두 바퀴, 탄 사람
func _draw_bicycle(w: float, h: float) -> void:
	var top := -h * 0.5
	draw_rect(Rect2(-1.5, top, 3, 8), Color(0.08, 0.08, 0.09))
	draw_rect(Rect2(-1.5, -top - 8, 3, 8), Color(0.08, 0.08, 0.09))
	draw_line(Vector2(0, top + 6), Vector2(0, -top - 6), paint, 3.0)
	draw_line(Vector2(-w * 0.6, top + 7), Vector2(w * 0.6, top + 7), Color(0.2, 0.2, 0.22), 2.0)
	if occupied():
		draw_circle(Vector2(0, top + h * 0.45), 4.5, Color(0.3, 0.6, 0.9))
		draw_circle(Vector2(0, top + h * 0.4), 2.5, Color(0.08, 0.07, 0.07))


## 오토바이: 앞뒤 바퀴, 몸통, 배달 상자, 탄 사람(헬멧)
func _draw_bike(w: float, h: float) -> void:
	var top := -h * 0.5
	if occupied():
		draw_colored_polygon(PackedVector2Array([Vector2(-3, top), Vector2(-w * 2.5, top - h * 1.4),
			Vector2(w * 2.5, top - h * 1.4), Vector2(3, top)]), Color(1.0, 0.95, 0.7, 0.07))
	draw_rect(Rect2(-w * 0.5 + 2, top + 3, w, h), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(-2.5, top, 5, 9), Color(0.08, 0.08, 0.09))
	draw_rect(Rect2(-2.5, -top - 9, 5, 9), Color(0.08, 0.08, 0.09))
	draw_rect(Rect2(-w * 0.32, top + 6, w * 0.64, h - 14), paint)
	draw_line(Vector2(-w * 0.75, top + 8), Vector2(w * 0.75, top + 8), Color(0.2, 0.2, 0.22), 2.0)
	draw_rect(Rect2(-w * 0.55, top + h * 0.62, w * 1.1, h * 0.34), stats.roof_color)
	draw_rect(Rect2(-w * 0.55, top + h * 0.62, w * 1.1, h * 0.34), Color(0.3, 0.3, 0.32), false, 1.0)
	if occupied():
		draw_circle(Vector2(0, top + h * 0.42), 5.0, Color(0.95, 0.95, 0.95))
		draw_circle(Vector2(0, top + h * 0.38), 2.5, Color(0.1, 0.1, 0.12))
	draw_rect(Rect2(-2, top, 4, 2), Color(1.0, 0.95, 0.65))
	draw_rect(Rect2(-2, -top - 2, 4, 2), Color(1.0, 0.15, 0.2) if is_braking() else Color(0.6, 0.05, 0.08))


func _siren_phase() -> bool:
	return (Time.get_ticks_msec() / 180) % 2 == 0


## 지붕 경광등: 왼쪽 빨강 · 오른쪽 파랑. 사이렌이 켜지면 번갈아 깜빡인다.
func _draw_lightbar(w: float, y: float) -> void:
	var half := w * 0.5 - 5.0
	var red_on := siren and _siren_phase()
	var blue_on := siren and not _siren_phase()
	draw_rect(Rect2(-half, y, half, 5), Color(1.0, 0.15, 0.2) if red_on else Color(0.45, 0.08, 0.1))
	draw_rect(Rect2(0, y, half, 5), Color(0.25, 0.5, 1.0) if blue_on else Color(0.08, 0.12, 0.4))


## 터진 잔해: 시커멓게 그을린 차체와 빈 창틀, 남은 불씨
func _draw_wreck(w: float, h: float) -> void:
	var body := Rect2(-w * 0.5, -h * 0.5, w, h)
	draw_rect(Rect2(body.position + Vector2(3, 4), body.size), Color(0, 0, 0, 0.35))
	draw_rect(body, Color(0.11, 0.1, 0.1))
	draw_rect(body.grow(-4), Color(0.2, 0.17, 0.15), false, 2.0)
	draw_rect(Rect2(-w * 0.5 + 4, -h * 0.28, w - 8, h * 0.5), Color(0.05, 0.05, 0.05))
	var t := Time.get_ticks_msec() / 1000.0
	for i in 3:
		var p := Vector2(sin(i * 2.1) * w * 0.25, (i - 1) * h * 0.25)
		draw_circle(p, 2.5 + sin(t * 6.0 + i) * 1.0, Color(1.0, 0.45, 0.1, 0.7))


## 불타는 차는 불길이, 많이 부서진 차는 연기가 난다
func _draw_damage(w: float, h: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var hood := Vector2(0, -h * 0.3)
	if burning >= 0.0:
		draw_circle(hood, w * 1.1, Color(1.0, 0.4, 0.1, 0.15))
		for i in 6:
			var phase := t * 9.0 + i * 1.7
			var p := hood + Vector2(sin(phase) * w * 0.3, cos(phase * 0.7) * h * 0.15)
			draw_circle(p, 6.0 + sin(phase * 1.3) * 2.0, Color(1.0, 0.35 + 0.3 * (i % 2), 0.05, 0.85))
		draw_circle(hood, 5.0, Color(1.0, 0.9, 0.4))
	elif health < max_health() * 0.35:
		for i in 3:
			var k := fmod(t * 0.8 + i / 3.0, 1.0)
			draw_circle(hood + Vector2(sin(i * 2.0) * 6.0, -k * 30.0), 5.0 + k * 9.0, Color(0.45, 0.45, 0.47, 0.45 * (1.0 - k)))
