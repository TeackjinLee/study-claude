class_name PoliceHeli
extends Node2D
## 경찰 헬기 (수배 ★5~, docs/02 POLICE_HELI). 건물 위를 곧장 날아 주인공을 따라오고, 땅에 탐조등을 비춘다.
## 탐조등 안에 들면 경찰이 위치를 안다(시야 공유). 사수가 탐조등 안의 주인공에게 기관총을 쏜다.
## 총에 맞으면 체력이 깎이고, 0이 되면 떨어져 터진다 (Combat이 맞았는지 본다 — 공중이라 몸통 충돌체가 없다).
## 움직임 계산(steer)은 노드 없이 테스트할 수 있게 정적 함수로 둔다.

signal shot_down(by_player: bool)

const SPEED := 470.0              ## 빠른 차(720~)는 따돌릴 수 있다
const ACCEL := 380.0
const LIGHT_SPEED := 330.0        ## 탐조등이 땅을 훑는 속도 — 급하게 꺾으면 빛에서 벗어난다
const LIGHT_RADIUS := 95.0
const HOVER_RADIUS := 140.0       ## 표적 위에서 이만큼 원을 그리며 맴돈다
const HIT_RADIUS := 34.0          ## 총알이 이 안을 지나면 맞는다
const SHOOT_RANGE := 420.0        ## 헬기에서 표적까지 이보다 가까워야 쏜다
const MAX_HEALTH := 260.0
const SHADOW_OFFSET := Vector2(46, 60)

var gunner: NpcType               ## 사수 (무기는 gunner.weapon)
var target := Vector2.ZERO        ## 쫓는 곳 (경찰이 아는 주인공 위치)
var velocity := Vector2.ZERO
var light := Vector2.ZERO         ## 탐조등이 비추는 땅 위치
var health := MAX_HEALTH
var reload := 0.0
var down := false                 ## 격추됐다 (떨어지는 중)
var leaving := false              ## 수배가 내려가 돌아간다
var _rotor := 0.0
var _orbit := 0.0
var _fall := 0.0


func _ready() -> void:
	z_as_relative = false
	z_index = 20
	light = global_position


## 표적 위 맴돌 지점으로 향하는 새 속도 (노드 없는 계산)
static func steer(pos: Vector2, vel: Vector2, goal: Vector2, delta: float) -> Vector2:
	var want := (goal - pos).limit_length(SPEED * clampf(pos.distance_to(goal) / 200.0, 0.2, 1.0))
	return vel.move_toward(want, ACCEL * delta)


func _physics_process(delta: float) -> void:
	z_index = IsoView.Z_AIR if IsoView.enabled else 20
	_rotor += delta * 22.0
	reload = maxf(reload - delta, 0.0)
	if down:
		_fall += delta
		velocity *= 0.98
		global_position += velocity * delta
		queue_redraw()
		return
	_orbit += delta * 0.9
	var goal := target + Vector2.RIGHT.rotated(_orbit) * HOVER_RADIUS
	if leaving:
		goal = global_position + (global_position - target).normalized() * 1000.0
	velocity = steer(global_position, velocity, goal, delta)
	global_position += velocity * delta
	light = light.move_toward(target if not leaving else global_position, LIGHT_SPEED * delta)
	queue_redraw()


## pos가 탐조등 안인가
func lit(pos: Vector2) -> bool:
	return not down and not leaving and light.distance_to(pos) < LIGHT_RADIUS


## 총알 선분 a→b가 헬기를 지나는가
func hit_by(a: Vector2, b: Vector2) -> bool:
	return not down and Geometry2D.get_closest_point_to_segment(global_position, a, b).distance_to(global_position) < HIT_RADIUS


func take_damage(amount: float, by_player: bool) -> void:
	if down:
		return
	health -= amount
	if health <= 0.0:
		down = true
		shot_down.emit(by_player)


## 떨어지기 시작하고 이만큼 지나면 땅에 부딪힌다
func crashed() -> bool:
	return down and _fall > 1.4


## 2.5D: 몸통이 떠 있는 높이 (화면 px). 떨어질수록 낮아진다
const ALTITUDE := 120.0


func _body(t: float) -> Vector2:
	return IsoView.lift(ALTITUDE * maxf(1.0 - t, 0.0)) if IsoView.enabled else Vector2.ZERO


func _draw() -> void:
	var t := _fall / 1.4 if down else 0.0
	var spin := _fall * 6.0
	# 탐조등 (땅)
	if not down and not leaving:
		var at := light - global_position
		draw_circle(at, LIGHT_RADIUS, Color(1.0, 1.0, 0.85, 0.16))
		draw_circle(at, LIGHT_RADIUS * 0.6, Color(1.0, 1.0, 0.85, 0.12))
		draw_line(_body(t), at, Color(1.0, 1.0, 0.85, 0.08), 26.0)
	# 그림자 (떨어질수록 몸통에 가까워진다). 2.5D에서는 그림자가 바로 밑, 몸통이 공중에 뜬다
	var shadow := Vector2.ZERO if IsoView.enabled else SHADOW_OFFSET * (1.0 - t)
	draw_circle(shadow, 20.0, Color(0, 0, 0, 0.3))
	var turn := (Vector2.UP.angle_to(velocity) if velocity.length() > 20.0 else 0.0) + spin
	draw_set_transform(_body(t), turn, Vector2.ONE * (1.0 - 0.3 * t))
	var body := Color(0.12, 0.2, 0.45) if not down else Color(0.15, 0.13, 0.12)
	draw_rect(Rect2(-3, 8, 6, 34), body.darkened(0.2))
	draw_rect(Rect2(-9, 38, 18, 4), body.darkened(0.2))
	draw_circle(Vector2(0, 0), 15.0, body)
	draw_circle(Vector2(0, -6), 9.0, Color(0.5, 0.7, 0.95, 0.85))
	draw_rect(Rect2(-15, 2, 30, 4), Color(0.95, 0.95, 0.95))
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
