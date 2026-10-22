class_name SignalPole
extends Node2D
## 한국식 신호등 기둥 하나 (2.5D, 신호 교차로의 네 모서리에 하나씩 — TrafficSystem이 세운다).
## - 차량 신호: 기둥에서 차로 위로 내민 ㄱ자 팔 끝에 가로로 긴 4색 등(빨강 · 노랑 · 좌회전 화살표 · 초록, 운전자가 볼 때 왼쪽부터).
##   한국처럼 교차로 건너편에 서서, 교차로를 건너올 차(`dir` 방향으로 가는 차)를 본다. 초록이면 좌회전 화살표도 같이 켠다(동시 신호).
## - 보행 신호: 기둥 중간에 모서리가 닿은 횡단보도 둘을 건너편으로 보는 상자 (위 빨간 서 있는 사람 · 아래 초록 걷는 사람,
##   초록 끝 무렵 깜박인다 — `TrafficController.walk`).
## 서 있는 것이라 깊이 정렬한다. 불 켜진 등은 자식 `glow`가 건물 불빛 셰이더(UV 0 = 늘 켜짐)로 그려 밤에도 밝다.
## 등 상태가 바뀔 때만 다시 그린다. 위에서 보기(F9)에서는 숨고 TrafficSystem이 바닥 점을 그린다.

const POLE_H := 52.0          ## 기둥 높이 (화면 px)
const ARM_H := 49.0           ## 팔 높이
const ARM_LEN := 74.0         ## 팔 길이 (월드 px, 모서리에서 차로 위로)
const HEAD_W := 36.0          ## 차량 등 상자 가로 (월드 px)
const HEAD_D := 5.0           ## 상자 두께
const HEAD_H := 10.0          ## 상자 높이 (화면 px)
const LAMP_R := 3.2           ## 등 반지름
const WALK_H0 := 22.0         ## 보행 신호 상자 아래 높이
const WALK_H := 14.0          ## 보행 신호 상자 높이
const WALK_W := 9.0           ## 보행 신호 상자 가로 (월드 px)
const WALK_OUT := 7.0         ## 보행 신호를 기둥에서 횡단보도 쪽으로

const STEEL := Color(0.55, 0.57, 0.6)
const HOUSING := Color(0.1, 0.1, 0.11)
const OFF := Color(0.2, 0.21, 0.22)
const RED := Color(1.0, 0.18, 0.14)
const YELLOW := Color(1.0, 0.78, 0.1)
const GREEN := Color(0.15, 1.0, 0.55)

var controller: TrafficController
var cell := Vector2i.ZERO
var dir := Vector2.UP          ## 이 기둥의 차량 등을 보는 차가 가는 방향 (DIRS[d_in])
var d_in := 0
var legs: Array[int] = []      ## 이 모서리가 닿은 횡단보도 (그 길이 뻗은 방향 번호) — 보행 신호
var base := 0.0                ## 선 땅 높이
var glow: Node2D
var _state := -1
var _iso := true


func _ready() -> void:
	z_as_relative = false
	z_index = IsoView.z_of(position)
	glow = Node2D.new()
	glow.material = BuildingView.light_material()
	glow.draw.connect(_draw_glow)
	add_child(glow)
	_iso = not IsoView.enabled   # 첫 _process에서 맞춘다


func _process(_delta: float) -> void:
	if IsoView.enabled != _iso:
		_iso = IsoView.enabled
		visible = _iso
		base = IsoView.ground(position)
		_state = -1
	if not _iso:
		return
	var s := _key()
	if s != _state:
		_state = s
		queue_redraw()
		glow.queue_redraw()


## 지금 등 상태를 한 수로 (바뀌었는지만 본다)
func _key() -> int:
	var k := int(controller.light(cell, d_in))
	for leg in legs:
		k = k * 4 + _walk(leg)
	return k


## 보행 신호: 0 빨강 · 1 초록 · 2 깜박임에서 꺼진 때
func _walk(leg: int) -> int:
	match controller.walk(cell, leg):
		TrafficController.Light.GREEN:
			return 1
		TrafficController.Light.YELLOW:
			return 1 if fmod(controller.time, 0.6) < 0.3 else 2
	return 0


func _draw() -> void:
	if not IsoView.enabled:
		return
	draw_set_transform(IsoView.lift(base))
	var u := -LaneGraph.right_of(dir)   # 팔이 뻗는 쪽 (차로 위, 운전자 왼쪽)
	var tip := u * ARM_LEN
	# 기둥 (바닥 받침 + 가는 위쪽)
	draw_circle(Vector2.ZERO, 3.5, STEEL.darkened(0.45))
	draw_line(Vector2.ZERO, IsoView.lift(POLE_H), STEEL.darkened(0.15), 3.0)
	draw_line(IsoView.lift(POLE_H) + Vector2(-1, 0), IsoView.lift(POLE_H) + Vector2(1, 0), STEEL, 3.0)
	# ㄱ자 팔과 받침 줄
	draw_line(IsoView.lift(ARM_H), tip + IsoView.lift(ARM_H), STEEL, 2.0)
	draw_line(IsoView.lift(ARM_H - 10.0), u * 18.0 + IsoView.lift(ARM_H), STEEL.darkened(0.2), 1.0)
	# 차량 등 상자 (팔 끝 아래에 매단다)
	var c := tip - u * HEAD_W * 0.5
	_box(c, u, -dir, HEAD_W, HEAD_D, ARM_H - HEAD_H - 1.0, ARM_H - 1.0, HOUSING)
	if IsoView.faces_viewer(-dir):
		var face := c - dir * HEAD_D * 0.5
		for i in 4:
			_disc(self, _lamp_at(face, u, i), u, LAMP_R, OFF)
	# 보행 신호 상자 둘
	for leg in legs:
		var n := _walk_normal(leg)
		var at := _walk_at(leg)
		_box(at, LaneGraph.right_of(n), n, WALK_W, 4.0, WALK_H0, WALK_H0 + WALK_H, HOUSING.lightened(0.08))
		draw_line(IsoView.lift(WALK_H0 + WALK_H * 0.5), at + IsoView.lift(WALK_H0 + WALK_H * 0.5), STEEL.darkened(0.2), 1.5)
		if IsoView.faces_viewer(n):
			var face := at + n * 2.0
			for half in 2:
				var mid := face + IsoView.lift(WALK_H0 + WALK_H * (0.75 - half * 0.5))
				_cell(self, mid, LaneGraph.right_of(n), OFF)


func _draw_glow() -> void:
	if not IsoView.enabled:
		return
	glow.draw_set_transform(IsoView.lift(base))
	var u := -LaneGraph.right_of(dir)
	if IsoView.faces_viewer(-dir):
		var face := u * ARM_LEN - u * HEAD_W * 0.5 - dir * HEAD_D * 0.5
		var light := controller.light(cell, d_in)
		var lit: Array[int] = []
		match light:
			TrafficController.Light.RED:
				lit = [0]
			TrafficController.Light.YELLOW:
				lit = [1]
			_:
				lit = [2, 3]
		for i in lit:
			var col: Color = [RED, YELLOW, GREEN, GREEN][i]
			var p := _lamp_at(face, u, i)
			_disc(glow, p, u, LAMP_R * 2.4, Color(col, 0.18))
			if i == 2:
				_arrow(p, u, col)
			else:
				_disc(glow, p, u, LAMP_R, col)
	for leg in legs:
		var n := _walk_normal(leg)
		if not IsoView.faces_viewer(n):
			continue
		var w := _walk(leg)
		if w == 2:
			continue
		var side := LaneGraph.right_of(n)
		var mid := _walk_at(leg) + n * 2.0 + IsoView.lift(WALK_H0 + WALK_H * (0.25 if w == 1 else 0.75))
		var col := GREEN if w == 1 else RED
		_cell(glow, mid, side, col)
		_figure(mid, side, w == 1)


## 등 자리: 운전자가 볼 때 왼쪽(u 쪽)부터 빨강 · 노랑 · 화살표 · 초록
func _lamp_at(face: Vector2, u: Vector2, i: int) -> Vector2:
	return face + u * HEAD_W * (0.375 - 0.25 * i) + IsoView.lift(ARM_H - 1.0 - HEAD_H * 0.5)


## 보행 신호가 보는 쪽: 횡단보도 건너편 모서리 (그 길을 가로지르는 방향, 기둥에서 안쪽)
func _walk_normal(leg: int) -> Vector2:
	var along := LaneGraph.DIRS[leg]
	var across := LaneGraph.right_of(along)
	return -across if across.dot(position - LaneGraph.center(cell)) > 0.0 else across


## 보행 신호 상자 자리 (기둥 기준, 횡단보도 쪽으로 조금)
func _walk_at(leg: int) -> Vector2:
	return LaneGraph.DIRS[leg] * -2.0 + _walk_normal(leg) * WALK_OUT


## 세운 면 위 원 (가로축 u 월드 · 세로 화면)
func _disc(ci: CanvasItem, c: Vector2, u: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var t := TAU * k / 10.0
		pts.append(c + u * cos(t) * r + IsoView.lift(sin(t) * r))
	if ci == self:
		draw_colored_polygon(pts, col)
	else:
		_glow_poly(pts, col)


## 좌회전 화살표 (운전자 왼쪽 = u 쪽을 가리킨다)
func _arrow(c: Vector2, u: Vector2, col: Color) -> void:
	_disc(glow, c, u, LAMP_R, Color(col, 0.35))
	var tip := c + u * LAMP_R * 0.9
	var tail := c - u * LAMP_R * 0.8
	glow.draw_line(tail, tip, col, 1.5)
	glow.draw_line(tip, tip - u * 1.4 + IsoView.lift(1.2), col, 1.5)
	glow.draw_line(tip, tip - u * 1.4 + IsoView.lift(-1.2), col, 1.5)


## 보행 신호 한 칸 (네모)
func _cell(ci: CanvasItem, mid: Vector2, side: Vector2, col: Color) -> void:
	var a := side * (WALK_W * 0.5 - 1.0)
	var h := WALK_H * 0.25 - 0.8
	var pts := PackedVector2Array([mid - a + IsoView.lift(-h), mid + a + IsoView.lift(-h), mid + a + IsoView.lift(h), mid - a + IsoView.lift(h)])
	if ci == self:
		draw_primitive(pts, PackedColorArray([col]), PackedVector2Array())
	else:
		_glow_poly(pts, col)


## 칸 안의 사람 (서 있는 / 걷는) — 칸 색보다 어둡게
func _figure(mid: Vector2, side: Vector2, walking: bool) -> void:
	var ink := Color(0.05, 0.08, 0.06) if walking else Color(0.2, 0.03, 0.02)
	var head := mid + IsoView.lift(1.6)
	glow.draw_circle(head, 0.7, ink)
	var hip := mid + IsoView.lift(-0.6)
	glow.draw_line(head + IsoView.lift(-0.6), hip, ink, 0.9)
	var stride := 1.0 if walking else 0.3
	glow.draw_line(hip, hip + side * stride + IsoView.lift(-1.6), ink, 0.9)
	glow.draw_line(hip, hip - side * stride + IsoView.lift(-1.6), ink, 0.9)


func _glow_poly(pts: PackedVector2Array, col: Color) -> void:
	var uvs := PackedVector2Array()
	uvs.resize(pts.size())   # UV 0 — 불빛 셰이더가 늘 켜 두고 밤 화면 어둡기만 되돌린다
	if pts.size() == 4:
		glow.draw_primitive(pts, PackedColorArray([col]), uvs)
	else:
		glow.draw_polygon(pts, PackedColorArray([col]), uvs)


## 세운 상자: 바닥 가운데 c, 가로 u(w), 앞 n(d), 높이 h0~h1. 보이는 옆면과 윗면만
func _box(c: Vector2, u: Vector2, n: Vector2, w: float, d: float, h0: float, h1: float, col: Color) -> void:
	var a := u * w * 0.5
	var b := n * d * 0.5
	var corners := [c - a - b, c + a - b, c + a + b, c - a + b]
	for k in 4:
		var p0: Vector2 = corners[k]
		var p1: Vector2 = corners[(k + 1) % 4]
		var mid := (p0 + p1) * 0.5 - c
		if IsoView.faces_viewer(mid):
			draw_primitive(IsoView.wall(p0, p1, h0, h1), PackedColorArray([col.darkened(IsoView.face_shade(mid.normalized()) * 0.6)]), PackedVector2Array())
	var top := PackedVector2Array()
	for p: Vector2 in corners:
		top.append(p + IsoView.lift(h1))
	draw_primitive(top, PackedColorArray([col.lightened(0.12)]), PackedVector2Array())
