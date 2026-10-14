class_name CheckpointVisual
extends Node2D
## 기존 ★4 다리 검문소 수명에 종속되는 초소와 차단봉. 차단은 기존 경찰차가 담당한다.
## 차단봉은 그림만 있다(충돌 없음): 주인공이 다가오면 내려가고, 달리는 차가 들이받으면 부러져 날아간다.
## 무작위를 쓰지 않아 경찰 rng·도주 결과에 영향이 없다.

const CLOSE_RANGE := 560.0     ## 주인공이 이 안에 오면 봉을 내린다
const ARM_LENGTH := 70.0       ## 초소 옆에서 도로 가운데 쪽으로
const ARM_HEIGHT := 12.0       ## 봉 높이
const ARM_UP := 1.35           ## 올렸을 때 각도 (라디안)
const MOVE_SPEED := 1.1        ## 초당 여닫는 비율
const BREAK_SPEED := 60.0      ## 이보다 빠른 차가 닿으면 부러진다
const STUB := 10.0             ## 부러진 뒤 남는 길이

var spot := Vector2.ZERO
var across := Vector2.RIGHT
var dir := Vector2.DOWN        ## 다리 쪽 방향 (봉은 초소에서 반대쪽, 땅 쪽으로 조금 앞에 둔다)
var views: Array[BuildingView] = []
var open := 1.0                ## 1 = 올림, 0 = 내림
var broken := false
var pivot := Vector2.ZERO      ## 봉 축 (바닥 위치)
var reach := Vector2.LEFT      ## 내렸을 때 봉이 뻗는 방향

var _booth := Vector2.ZERO
var _time := 0.0
var _arm: Arm
var _lamp: Lamp
var _piece: Piece


## 봉과 기둥 (봉 가운데 깊이에 그린다)
class Arm extends Node2D:
	var cp: CheckpointVisual

	func _draw() -> void:
		var g := IsoView.ground(cp.pivot)
		var p := cp.pivot
		if not IsoView.enabled:
			draw_circle(p, 3.0, Color("3a3f45"))
			var tip := p + cp.reach * (CheckpointVisual.STUB if cp.broken else CheckpointVisual.ARM_LENGTH * cos(cp.open * CheckpointVisual.ARM_UP))
			draw_line(p, tip, Color("d23a2f"), 3.0)
			return
		# 기둥과 받침
		draw_line(p + IsoView.lift(g), p + IsoView.lift(g + CheckpointVisual.ARM_HEIGHT + 2.0), Color("3a3f45"), 4.0)
		draw_rect(Rect2(p + IsoView.lift(g + CheckpointVisual.ARM_HEIGHT - 3.0) - Vector2(3.5, 2.5), Vector2(7, 5)), Color("e3b023"))
		var length := CheckpointVisual.STUB if cp.broken else CheckpointVisual.ARM_LENGTH
		CheckpointVisual.draw_bar(self, p, cp.reach, cp.open * CheckpointVisual.ARM_UP, g + CheckpointVisual.ARM_HEIGHT, length, 1.0)
		if not cp.broken:
			# 끝을 받치는 작은 받침대 (내렸을 때만 닿는다)
			var end := p + cp.reach * CheckpointVisual.ARM_LENGTH
			draw_line(end + IsoView.lift(g), end + IsoView.lift(g + CheckpointVisual.ARM_HEIGHT - 2.0), Color("5a6066"), 2.0)


## 초소 지붕 경광등 (봉이 내려가 있으면 깜빡인다)
class Lamp extends Node2D:
	var cp: CheckpointVisual

	func _draw() -> void:
		if not IsoView.enabled:
			return
		var top := cp._booth + IsoView.lift(IsoView.ground(cp._booth) + 37.0)
		draw_rect(Rect2(top - Vector2(3, 3), Vector2(6, 4)), Color("2c3034"))
		var on := cp.open < 0.5 and fmod(cp._time, 0.8) < 0.4
		var col := Color(1.0, 0.25, 0.2) if on else Color(0.45, 0.12, 0.1)
		if on:
			draw_circle(top - Vector2(0, 2), 7.0, Color(col, 0.25))
		draw_circle(top - Vector2(0, 2), 2.6, col)


## 부러져 날아가는 봉 토막
class Piece extends Node2D:
	var cp: CheckpointVisual
	var at := Vector2.ZERO       ## 바닥 위치
	var h := 0.0
	var vel := Vector2.ZERO
	var vh := 0.0
	var turn := 0.0              ## 봉 방향 각
	var spin := 0.0
	var age := 0.0

	func step(delta: float) -> void:
		age += delta
		if h > 0.5 or vh > 0.0:
			at += vel * delta
			h += vh * delta
			vh -= 420.0 * delta
			turn += spin * delta
			if h <= 0.5:
				h = 0.5
				vh = 0.0
				vel = Vector2.ZERO
		modulate.a = clampf(8.0 - age, 0.0, 1.0)
		z_index = IsoView.z_of(at)
		queue_redraw()

	func _draw() -> void:
		var length := CheckpointVisual.ARM_LENGTH - CheckpointVisual.STUB
		var axis := Vector2.RIGHT.rotated(turn)
		var g := IsoView.ground(at) + h
		if not IsoView.enabled:
			draw_line(at - axis * length * 0.5, at + axis * length * 0.5, Color("d23a2f"), 3.0)
			return
		CheckpointVisual.draw_bar(self, at - axis * length * 0.5, axis, 0.0, g, length, 1.0)


func _ready() -> void:
	_booth = spot + across * (City.ROAD * 0.5 - 15.0)
	var piece := BuildingModel._box(Rect2(_booth - Vector2(12, 12), Vector2(24, 24)), 0, 35, Color("aeb4af"), &"flat", Color("7f8988"), &"punched", 1)
	piece.deco = [&"landmark_sign"]
	piece.text = "검문"
	var holder := Node2D.new()
	holder.position = IsoView.lift(CityMap.ground_height(_booth))
	add_child(holder)
	views = BuildingView.make(holder, null, -1, piece)
	var body := StaticBody2D.new()
	add_child(body)
	City._add_box(body, piece.rect)
	pivot = _booth - across * 13.0 - dir * 20.0
	reach = -across
	_arm = Arm.new()
	_arm.cp = self
	_arm.z_as_relative = false
	_arm.z_index = IsoView.z_of(pivot + reach * ARM_LENGTH * 0.5)
	add_child(_arm)
	_lamp = Lamp.new()
	_lamp.cp = self
	_lamp.z_as_relative = false
	_lamp.z_index = IsoView.z_of(_booth) + 1
	add_child(_lamp)
	_update_visibility()


func _process(delta: float) -> void:
	_time += delta
	var near := false
	var parent := get_parent()
	if parent and parent.has_method("_player_pos"):
		near = (parent._player_pos() as Vector2).distance_to(pivot) < CLOSE_RANGE
	open = move_toward(open, 0.0 if near else 1.0, MOVE_SPEED * delta)
	check_hits()
	if _piece:
		_piece.step(delta)
	_arm.queue_redraw()
	_lamp.queue_redraw()
	_update_visibility()


## 내려간 봉에 달리는 차가 닿았으면 부러뜨린다
func check_hits() -> void:
	if broken or open > 0.5:
		return
	var cars = get_parent().get("vehicles") if get_parent() else null
	if cars == null:
		return
	var a := pivot + reach * STUB
	var b := pivot + reach * ARM_LENGTH
	for car: Vehicle in cars:
		if not is_instance_valid(car) or car.speed() < BREAK_SPEED:
			continue
		var at := car.global_position
		var near := Geometry2D.get_closest_point_to_segment(at, a, b)
		if near.distance_to(at) < car.stats.size.x * 0.5 + 6.0:
			snap(car.motor.velocity, near)
			return


## 봉을 부러뜨려 토막을 차가 달리던 쪽으로 날린다
func snap(velocity: Vector2, at: Vector2) -> void:
	broken = true
	_piece = Piece.new()
	_piece.cp = self
	_piece.z_as_relative = false
	_piece.at = pivot + reach * (STUB + (ARM_LENGTH - STUB) * 0.5)
	_piece.h = ARM_HEIGHT
	_piece.vel = velocity * 0.55 + (_piece.at - at).normalized() * 40.0
	_piece.vh = 120.0
	_piece.turn = reach.angle()
	_piece.spin = 7.0 if velocity.cross(reach) > 0.0 else -7.0
	add_child(_piece)


## 빨강·흰 줄무늬 봉: 축 p에서 바닥 방향 u로, 수직면에서 angle만큼 들어 올린 길이 length
static func draw_bar(ci: CanvasItem, p: Vector2, u: Vector2, angle: float, h: float, length: float, width_k: float) -> void:
	var n := 7
	for k in n:
		var s0 := length * k / n
		var s1 := length * (k + 1) / n
		var a := p + u * s0 * cos(angle) + IsoView.lift(h + s0 * sin(angle))
		var b := p + u * s1 * cos(angle) + IsoView.lift(h + s1 * sin(angle))
		ci.draw_line(a, b, Color("d23a2f") if k % 2 == 0 else Color("f1eee6"), 3.2 * width_k)
	var tip := p + u * length * cos(angle) + IsoView.lift(h + length * sin(angle))
	ci.draw_line(p + IsoView.lift(h) + Vector2(0, 1.6), tip + Vector2(0, 1.6), Color(0, 0, 0, 0.25), 1.0)


func _update_visibility() -> void:
	for view in views:
		view.visible = IsoView.enabled
	queue_redraw()


func _draw() -> void:
	if not IsoView.enabled:
		draw_rect(Rect2(_booth - Vector2(12, 12), Vector2(24, 24)), Color("67778e"))
