class_name PoliceHeli
extends Node2D
## 하늘을 나는 NPC 헬기 — 경찰 헬기(수배 ★5~, docs/02 POLICE_HELI)·군 기동헬기(★6)·119 구조헬기(큰불, Fires).
## 건물 위를 곧장 날아 표적을 따라가 그 위를 맴돈다. 경찰·군 헬기는 땅에 탐조등을 비추고, 탐조등 안에 들면
## 경찰이 위치를 안다(시야 공유). 사수가 탐조등 안의 주인공에게 기관총을 쏜다 (PoliceDispatcher).
## 총에 맞으면 체력이 깎이고, 0이 되면 돌며 떨어져 터진다 (Combat이 맞았는지 본다 — 공중이라 몸통 충돌체가 없다).
## 기체는 차처럼 입체 모형(VehicleModel, 그림이 있으면 VehicleSprite)으로 그린다 — 모형이 읽는 값(방향·기울기·높이·
## 경광등)을 담는 그릇으로 트리에 넣지 않은 Vehicle(_look)을 쓴다. 진행 방향으로 서서히 돌고, 돌면 기울고 속도를 올리면 숙인다.
## 움직임 계산(steer)은 노드 없이 테스트할 수 있게 정적 함수로 둔다.

signal shot_down(by_player: bool)

const POLICE_TYPE: VehicleType = preload("res://data/vehicles/police_heli.tres")
const SPEED := 470.0              ## 빠른 차(720~)는 따돌릴 수 있다 (경찰 헬기. 다른 헬기는 차종 max_speed)
const ACCEL := 380.0
const LIGHT_SPEED := 330.0        ## 탐조등이 땅을 훑는 속도 — 급하게 꺾으면 빛에서 벗어난다
const LIGHT_RADIUS := 95.0
const HOVER_RADIUS := 140.0       ## 표적 위에서 이만큼 원을 그리며 맴돈다
const HIT_RADIUS := 34.0          ## 총알이 이 안을 지나면 맞는다 (경찰 헬기 길이 80 기준 — 큰 헬기는 길이에 비례)
const SHOOT_RANGE := 420.0        ## 헬기에서 표적까지 이보다 가까워야 쏜다
const MAX_HEALTH := 260.0         ## 경찰 헬기 체력 (차종 durability가 정한다)
const SHADOW_OFFSET := Vector2(46, 60)
const FALL_TIME := 1.4
const TURN_SPEED := 2.4           ## 기수가 진행 방향을 따라 도는 빠르기 (rad/s)
const BANK_RATE := 1.4            ## 기울기·숙이기가 목표를 따라가는 빠르기 (rad/s)

var stats: VehicleType = POLICE_TYPE   ## 기체 (모양·체력·속도)
var gunner: NpcType               ## 사수 (무기는 gunner.weapon). 없으면 쏘지 않는다
var searchlight := true           ## 땅에 탐조등을 비춘다 (119 구조헬기는 끈다)
var beacons := true               ## 경광등을 깜빡인다 (군 헬기는 끈다)
var water := false                ## 밑으로 물을 쏟는다 (119 구조헬기가 불 위에서 — Fires)
var hover_radius := HOVER_RADIUS
var target := Vector2.ZERO        ## 쫓는 곳 (경찰이 아는 주인공 위치 · 불난 곳)
var velocity := Vector2.ZERO
var light := Vector2.ZERO         ## 탐조등이 비추는 땅 위치
var health := MAX_HEALTH
var reload := 0.0
var down := false                 ## 격추됐다 (떨어지는 중)
var leaving := false              ## 수배가 내려가(불이 꺼져) 돌아간다
var heading := 0.0                ## 기수 방향 (Vehicle.rotation과 같은 기준: 0 = 월드 −y)
var _rotor := 0.0
var _orbit := 0.0
var _fall := 0.0
var _turn := 0.0                  ## 지금 도는 빠르기 (rad/s, 기울기용)
var _last_speed := 0.0
var _look: Vehicle                ## 입체 모형이 읽는 값을 담는 그릇 (트리에 넣지 않는다)
var _body: Node2D                 ## 기체 모형을 그리는 층 (기수 방향으로 돈다). 모습이 바뀔 때만 다시 그린다
var _top: Node2D                  ## 그 위층: 도는 날개·추락 불꽃 (매 프레임)
var _drawn := []                  ## 마지막으로 그린 모습


func _ready() -> void:
	z_as_relative = false
	z_index = 20
	light = global_position
	health = stats.durability
	_look = Vehicle.new()
	_look.stats = stats
	_look.paint = stats.body_color
	_look.has_driver = true
	_look.siren = beacons
	_look.altitude = stats.fly_height
	_body = Node2D.new()
	_body.draw.connect(_draw_body)
	add_child(_body)
	_top = Node2D.new()
	_top.draw.connect(_draw_top)
	_body.add_child(_top)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_look):
		_look.free()


## 표적 위 맴돌 지점으로 향하는 새 속도 (노드 없는 계산)
static func steer(pos: Vector2, vel: Vector2, goal: Vector2, delta: float, speed := SPEED, accel := ACCEL) -> Vector2:
	var want := (goal - pos).limit_length(speed * clampf(pos.distance_to(goal) / 200.0, 0.2, 1.0))
	return vel.move_toward(want, accel * delta)


## 총알이 맞는 반경 (기체 길이에 비례)
func hit_radius() -> float:
	return HIT_RADIUS * stats.size.y / 80.0


func _physics_process(delta: float) -> void:
	z_index = IsoView.Z_AIR if IsoView.enabled else 20
	_rotor += delta * 22.0
	reload = maxf(reload - delta, 0.0)
	if down:
		_fall += delta
		velocity *= 0.98
		global_position += velocity * delta
		heading += delta * 6.0          # 꼬리 날개를 잃고 돈다
		_look.altitude = stats.fly_height * maxf(1.0 - _fall / FALL_TIME, 0.0)
		_sync()
		return
	_orbit += delta * 0.9
	var goal := target + Vector2.RIGHT.rotated(_orbit) * hover_radius
	if leaving:
		goal = global_position + (global_position - target).normalized() * 1000.0
	var speed := SPEED if stats == POLICE_TYPE else stats.max_speed
	var accel := ACCEL if stats == POLICE_TYPE else stats.acceleration
	velocity = steer(global_position, velocity, goal, delta, speed, accel)
	global_position += velocity * delta
	light = light.move_toward(target if not leaving else global_position, LIGHT_SPEED * delta)
	_fly(delta, speed, accel)
	_sync()


## 기수를 진행 방향으로 돌리고, 도는 만큼 기울고 속도를 올리는 만큼 숙인다 (Vehicle._tilt와 같은 느낌)
func _fly(delta: float, speed: float, accel: float) -> void:
	var v := velocity.length()
	var before := heading
	if v > 30.0:
		var want := Vector2.UP.angle_to(velocity)
		heading = rotate_toward(heading, want, TURN_SPEED * delta)
	_turn = angle_difference(before, heading) / delta
	var bank_goal := clampf(_turn / TURN_SPEED, -1.0, 1.0) * clampf(v / speed, 0.0, 1.0) * stats.bank_angle
	var pitch_goal := clampf((v - _last_speed) / delta / accel, -1.0, 1.0) * stats.pitch_angle
	_last_speed = v
	_look.bank = move_toward(_look.bank, bank_goal, BANK_RATE * delta)
	_look.pitch = move_toward(_look.pitch, pitch_goal, BANK_RATE * delta)


func _sync() -> void:
	_look.rotation = heading
	_look.wrecked = down
	_body.rotation = heading


## 모형(약 0.8ms)은 모습이 바뀔 때만 다시 그린다 — 방향은 Vehicle.ROT_STEP마다, 그 사이엔 층이 돌아 따라간다 (Vehicle._look과 같다)
func _process(_delta: float) -> void:
	queue_redraw()
	_top.queue_redraw()
	var look := [snappedf(heading, Vehicle.ROT_STEP), snappedf(_look.bank, 0.02), snappedf(_look.pitch, 0.02),
		snappedf(_look.altitude, 0.5), down, beacons and _look._siren_phase(), IsoView.enabled]
	if look != _drawn:
		_drawn = look
		_body.queue_redraw()


## pos가 탐조등 안인가
func lit(pos: Vector2) -> bool:
	return searchlight and not down and not leaving and light.distance_to(pos) < LIGHT_RADIUS


## 총알 선분 a→b가 헬기를 지나는가
func hit_by(a: Vector2, b: Vector2) -> bool:
	return not down and Geometry2D.get_closest_point_to_segment(global_position, a, b).distance_to(global_position) < hit_radius()


func take_damage(amount: float, by_player: bool) -> void:
	if down:
		return
	health -= amount
	if health <= 0.0:
		down = true
		shot_down.emit(by_player)


## 떨어지기 시작하고 이만큼 지나면 땅에 부딪힌다
func crashed() -> bool:
	return down and _fall > FALL_TIME


## 2.5D: 몸통이 떠 있는 높이 (화면 px). 떨어질수록 낮아진다
func altitude() -> float:
	return _look.altitude if _look else stats.fly_height


func _body_at(t: float) -> Vector2:
	return IsoView.lift(stats.fly_height * maxf(1.0 - t, 0.0)) if IsoView.enabled else Vector2.ZERO


func _draw() -> void:
	var t := _fall / FALL_TIME if down else 0.0
	# 탐조등 (땅)
	if searchlight and not down and not leaving:
		var at := light - global_position
		draw_circle(at, LIGHT_RADIUS, Color(1.0, 1.0, 0.85, 0.16))
		draw_circle(at, LIGHT_RADIUS * 0.6, Color(1.0, 1.0, 0.85, 0.12))
		draw_line(_body_at(t), at, Color(1.0, 1.0, 0.85, 0.08), 26.0)
	if water and not down:
		_draw_water()
	if IsoView.enabled:
		# 그림자: 바로 밑 땅에, 높이 뜰수록 옅다 (날개 원판 + 동체)
		var fade := 1.0 - 0.6 * clampf(altitude() / stats.fly_height, 0.0, 1.0)
		FireFx.circle(self, Vector2.ZERO, stats.size.y * 0.6, Color(0, 0, 0, 0.18 * fade))
		draw_set_transform(Vector2.ZERO, heading, Vector2.ONE)
		draw_rect(Rect2(-stats.size * 0.5, stats.size), Color(0, 0, 0, 0.3 * fade))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	_draw_flat(t)


## 2.5D: 기체 입체 모형 (떨어지는 중이면 그을린 모형)
func _draw_body() -> void:
	if not IsoView.enabled or _look == null:
		return
	_body.draw_set_transform(IsoView.lift_local(_look.altitude, heading), 0.0, Vector2.ONE)
	VehicleModel.draw(_body, _look)
	_body.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 위층: 도는 날개, 떨어지는 중이면 불꽃·연기
func _draw_top() -> void:
	if not IsoView.enabled or _look == null:
		return
	if not down:
		Vehicle.draw_rotor(_top, _look)
		return
	_top.draw_set_transform_matrix(Transform2D(-heading, Vector2.ZERO) * IsoView.screen_frame(Vector2.ZERO, _look.altitude + stats.height))
	var now := Time.get_ticks_msec() / 1000.0
	FireFx.smoke(_top, Vector2(0, -6), now, 0.9, 1.0, 0.8, 3.0, 5)
	FireFx.flame(_top, Vector2.ZERO, 14.0, now, 1.7)
	_top.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 쏟는 물: 기체 밑에서 땅까지 떨어지는 물줄기와 땅에 퍼지는 물보라
func _draw_water() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var top := _body_at(0.0)
	for i in 10:
		var k := fmod(now * 2.2 + i / 10.0, 1.0)
		var side := (fmod(i * 0.618, 1.0) - 0.5) * 22.0
		var p := top.lerp(Vector2.ZERO, k) + Vector2(side * (0.6 + k), 0.0)
		draw_circle(p, 3.0 + k * 5.0, Color(0.65, 0.85, 1.0, 0.5 * (1.0 - k * 0.4)))
	for i in 3:
		var k := fmod(now * 1.5 + i / 3.0, 1.0)
		draw_arc(Vector2.ZERO, 12.0 + k * 40.0, 0.0, TAU, 24, Color(0.75, 0.9, 1.0, 0.45 * (1.0 - k)), 2.0)


## 위에서 보기(F9): 예전 납작한 헬기 그림
func _draw_flat(t: float) -> void:
	var spin := _fall * 6.0
	draw_circle(SHADOW_OFFSET * (1.0 - t), 20.0, Color(0, 0, 0, 0.3))
	var turn := (Vector2.UP.angle_to(velocity) if velocity.length() > 20.0 else 0.0) + spin
	draw_set_transform(Vector2.ZERO, turn, Vector2.ONE * (1.0 - 0.3 * t))
	var body := stats.body_color if not down else Color(0.15, 0.13, 0.12)
	draw_rect(Rect2(-3, 8, 6, 34), body.darkened(0.2))
	draw_rect(Rect2(-9, 38, 18, 4), body.darkened(0.2))
	draw_circle(Vector2(0, 0), 15.0, body)
	draw_circle(Vector2(0, -6), 9.0, Color(0.5, 0.7, 0.95, 0.85))
	draw_rect(Rect2(-15, 2, 30, 4), stats.roof_color)
	if not down:
		for k in 2:
			var a := _rotor + k * PI * 0.5
			draw_line(Vector2.RIGHT.rotated(a) * -38.0, Vector2.RIGHT.rotated(a) * 38.0, Color(0.15, 0.15, 0.16, 0.8), 3.0)
		draw_circle(Vector2.ZERO, 3.0, Color(0.1, 0.1, 0.1))
		var blink := int(_rotor * 0.3) % 2 == 0
		draw_circle(Vector2(-10, 4), 2.5, Color(1, 0.2, 0.2) if blink else Color(0.25, 0.4, 1.0))
	else:
		for i in 4:
			draw_circle(Vector2(sin(_fall * 9.0 + i) * 8.0, cos(_fall * 7.0 + i) * 8.0), 7.0, Color(1.0, 0.45, 0.1, 0.8))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
