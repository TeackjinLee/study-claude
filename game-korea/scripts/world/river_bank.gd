class_name RiverBank
extends Node2D
## 2.5D 한강 둑: 수면이 도로보다 `HEIGHT`만큼 낮게 보이도록 강변에 옹벽을 세운다 (그림만 — 물리는 평면 그대로).
## 참고 그림 `output/imagegen/water/ref_riverbank_day.png` (요청서 `GPT_RIVERBANK_PROMPT.md`).
## - 보이는 둑 (물이 남·동쪽에 있는 북·서 둑): 땅 끝에서 물까지 떨어지는 옹벽 면 — 마감돌, 블록 이음, 배수구와 물때, 물에 닿는 젖은 이끼 띠
## - 앞 둑 (남·동 둑): 옹벽 면은 카메라 반대쪽이라 안 보인다 — 물 위에 둑이 드리운 그늘 띠만
## - 둑 위에는 서 있는 난간 (다리가 둑에 닿는 곳은 비운다 — 차가 지나간다)
## - 난간을 따라 `LAMP_EVERY`마다 가로등(`Lamp`, 깊이 정렬되는 노드). 밤 불빛은 건물 불빛 셰이더(`BuildingView.light_material`)로
##   등 머리·도로에 떨어진 빛·옹벽 면에 비친 빛·물 위로 길게 늘어진 반사를 그린다 — 해 질 녘 하나둘 켜진다
## 물거품은 물 셰이더(`RiverView`, `bank_drop`)가 옹벽 발치에 그린다. 위에서 보기(F9)에서는 숨고 물 셰이더가 평면 호안을 칠한다.
## 선분은 시작할 때 한 번 재고(`RiverView.shore_edges`), 다시 그리는 것은 2.5D를 켜고 끌 때뿐이다.

const HEIGHT := 48.0             ## 옹벽 높이 (화면 px) = 수면이 땅보다 낮은 만큼
const CAP := 4.0                 ## 맨 위 마감돌 두께
const COURSES := 4               ## 블록 줄 수
const STONE := 64.0              ## 블록 길이 (월드 px)
const WET := 0.3                 ## 아래에서 이만큼은 젖은 이끼 띠
const DRAIN_EVERY := 352.0       ## 배수구 사이
const SHADOW := 30.0             ## 앞 둑 그늘 띠 폭 (월드 px)
const RAIL_H := 8.0              ## 난간 높이
const POST_EVERY := 32.0         ## 난간 기둥 사이 (월드 px)
const RAIL_IN := 4.0             ## 난간을 땅 끝에서 안쪽으로
const LAMP_EVERY := 224.0        ## 가로등 사이 (월드 px)
const LAMP_IN := 10.0            ## 가로등을 땅 끝에서 안쪽으로
const LAMP_H := 40.0             ## 가로등 높이
const LAMP_ARM := 12.0           ## 도로 쪽으로 내민 팔
const LAMP_END := 40.0           ## 선분 끝(교차로·다리 어귀)에서 이만큼은 비운다

const CONCRETE := Color(0.56, 0.57, 0.56)
const CAP_COLOR := Color(0.72, 0.72, 0.69)
const JOINT := Color(0.3, 0.31, 0.31, 0.55)
const MOSS := Color(0.2, 0.24, 0.18)
const STAIN := Color(0.24, 0.27, 0.22, 0.35)
const RAIL := Color(0.62, 0.64, 0.7)
const STEEL := Color(0.36, 0.38, 0.42)
const LAMP_LIGHT := Color(1.0, 0.9, 0.62)

var _edges := []
var _iso := true


## 둑 가로등 하나: 서 있는 것이라 깊이 정렬한다 (도로 위 차·사람과 앞뒤가 맞게). 불빛은 자식 `glow`
class Lamp extends Node2D:
	var into := Vector2.DOWN      ## 땅 → 물 방향
	var dir := Vector2.RIGHT      ## 둑을 따라
	var glow: Node2D

	func _ready() -> void:
		z_as_relative = false
		z_index = IsoView.z_of(position)
		glow = Node2D.new()
		glow.material = BuildingView.light_material()
		glow.draw.connect(_draw_glow)
		add_child(glow)

	## 팔 끝 등 머리 (월드, 이 노드 기준)
	func _head(grow := 0.0) -> PackedVector2Array:
		var c := -into * LAMP_ARM
		var z := LAMP_H - 2.0
		var a := dir * (3.0 + grow)
		var b := into * (3.0 + grow)
		return PackedVector2Array([c - a - b + IsoView.lift(z), c + a - b + IsoView.lift(z),
			c + a + b + IsoView.lift(z), c - a + b + IsoView.lift(z)])

	func _draw() -> void:
		if not IsoView.enabled:
			return
		draw_circle(Vector2.ZERO, 3.0, STEEL.darkened(0.3))
		draw_line(Vector2.ZERO, IsoView.lift(LAMP_H), STEEL, 2.0)
		draw_line(IsoView.lift(LAMP_H), -into * LAMP_ARM + IsoView.lift(LAMP_H - 1.0), STEEL, 2.0)
		draw_primitive(_head(), PackedColorArray([LAMP_LIGHT.darkened(0.25)]), PackedVector2Array())

	## 불빛: UV (2, 2 + 차례) — 불빛 셰이더가 lights_on이 차례를 넘으면 켠다
	func _draw_glow() -> void:
		if not IsoView.enabled:
			return
		var order := 0.06 + 0.12 * RiverBank._hash(position)
		var uv := Vector2(2.0, 2.0 + order)
		# 도로에 떨어진 빛 웅덩이
		var c := -into * (LAMP_ARM + 4.0)
		for ring in [[30.0, 0.06], [18.0, 0.1]]:
			var pool := PackedVector2Array()
			for k in 14:
				var t := TAU * k / 14.0
				pool.append(c + Vector2(cos(t), sin(t)) * ring[0])
			_poly(pool, Color(1.0, 0.78, 0.42, ring[1]), uv)
		if IsoView.faces_viewer(into):
			# 옹벽 면에 비친 빛 (위가 밝다)과 물 위로 길게 늘어진 반사
			var foot := into * LAMP_IN
			var w := dir * 22.0
			var hi := Color(1.0, 0.8, 0.48, 0.16)
			var lo := Color(1.0, 0.8, 0.48, 0.03)
			_poly(PackedVector2Array([foot - w, foot + w, foot + w * 0.6 + IsoView.lift(-HEIGHT), foot - w * 0.6 + IsoView.lift(-HEIGHT)]),
				[hi, hi, lo, lo], uv)
			var top := foot + IsoView.lift(-HEIGHT)
			for band in [[11.0, 80.0, 0.12], [4.0, 60.0, 0.26]]:   # 넓고 옅은 번짐 + 가운데 밝은 줄
				var s: Vector2 = dir * band[0]
				var near := Color(1.0, 0.82, 0.5, band[2])
				var far := Color(1.0, 0.82, 0.5, 0.0)
				_poly(PackedVector2Array([top - s, top + s, top + s * 0.5 + IsoView.lift(-band[1]), top - s * 0.5 + IsoView.lift(-band[1])]),
					[near, near, far, far], uv)
		_poly(_head(3.0), Color(LAMP_LIGHT, 0.3), uv)
		_poly(_head(), Color(1.0, 0.97, 0.85), uv)

	func _poly(pts: PackedVector2Array, color, uv: Vector2) -> void:
		var cols := PackedColorArray()
		var uvs := PackedVector2Array()
		for i in pts.size():
			cols.append(color[i] if color is Array else color)
			uvs.append(uv)
		if pts.size() <= 4:
			glow.draw_primitive(pts, cols, uvs)
		else:
			glow.draw_polygon(pts, cols, uvs)


func _ready() -> void:
	_edges = RiverView.shore_edges()
	for e in _edges:
		if e.bridge:
			continue
		var len: float = e.a.distance_to(e.b)
		var dir: Vector2 = (e.b - e.a) / len
		var s := fposmod(-_along(e.a, dir) + LAMP_EVERY * 0.5, LAMP_EVERY)
		while s < len:
			if s > LAMP_END and s < len - LAMP_END:
				var lamp := Lamp.new()
				lamp.position = e.a + dir * s - e.into * LAMP_IN
				lamp.into = e.into
				lamp.dir = dir
				add_child(lamp)
			s += LAMP_EVERY


func _process(_delta: float) -> void:
	var on := IsoView.enabled
	if on != _iso:
		_iso = on
		queue_redraw()
		for lamp in get_children():
			lamp.visible = on
			lamp.queue_redraw()
			lamp.glow.queue_redraw()


func _draw() -> void:
	if not IsoView.enabled:
		return
	for e in _edges:
		if IsoView.faces_viewer(e.into):
			_wall(e.a, e.b, e.into)
		else:
			_shadow(e.a, e.b, e.into)
	for e in _edges:
		if not e.bridge:
			_rail(e.a - e.into * RAIL_IN, e.b - e.into * RAIL_IN)


## 옹벽 면: 땅 끝 a→b(높이 0)에서 수면(-HEIGHT)까지
func _wall(a: Vector2, b: Vector2, n: Vector2) -> void:
	var shade := 0.12 if n.x > n.y else 0.24   # 오른쪽(동)을 보는 면이 더 밝다
	var dry := CONCRETE.darkened(shade)
	var wet := dry.lerp(MOSS, 0.55)
	var foot := MOSS.darkened(0.35)
	var mid := -HEIGHT * (1.0 - WET)
	_quad(a, b, mid, 0.0, dry, dry)
	_quad(a, b, -HEIGHT, mid, foot, wet)
	_quad(a, b, -CAP, 0.0, CAP_COLOR.darkened(shade * 0.5), CAP_COLOR.darkened(shade * 0.5))
	draw_line(a + IsoView.lift(-CAP), b + IsoView.lift(-CAP), dry.darkened(0.35), 1.0)
	# 블록 이음: 가로 줄, 줄마다 반 칸씩 엇갈린 세로 이음
	var len := a.distance_to(b)
	var dir := (b - a) / len
	var row := (HEIGHT - CAP) / COURSES
	var lines := PackedVector2Array()
	for r in range(1, COURSES):
		var hr := -CAP - row * r
		lines.append_array([a + IsoView.lift(hr), b + IsoView.lift(hr)])
	for r in COURSES:
		var h0 := -CAP - row * r
		var h1 := h0 - row
		var s := fposmod(-_along(a, dir) + (STONE * 0.5 if r % 2 == 1 else 0.0), STONE)
		while s < len:
			var p := a + dir * s
			lines.append_array([p + IsoView.lift(h0), p + IsoView.lift(h1)])
			s += STONE
	draw_multiline(lines, JOINT, 1.0)
	# 배수구와 그 밑으로 흘러내린 물때
	var d := fposmod(-_along(a, dir) + DRAIN_EVERY * 0.5, DRAIN_EVERY)
	while d < len - 8.0:
		var p := a + dir * d
		if _hash(p) < 0.6:
			var hole := -HEIGHT * 0.42
			var w := dir * 5.0
			_quad(p - w, p + w, hole - 4.0, hole + 2.0, Color(0.1, 0.11, 0.11), Color(0.16, 0.17, 0.17))
			_quad(p - dir * 3.0, p + dir * 3.0, -HEIGHT, hole - 4.0, STAIN, STAIN)
		d += DRAIN_EVERY


## 앞 둑 그늘: 땅 끝에서 물 쪽으로 옅어진다
func _shadow(a: Vector2, b: Vector2, n: Vector2) -> void:
	var dark := Color(0.0, 0.02, 0.03, 0.5)
	var clear := Color(0.0, 0.02, 0.03, 0.0)
	draw_primitive(PackedVector2Array([a, b, b + n * SHADOW, a + n * SHADOW]),
		PackedColorArray([dark, dark, clear, clear]), PackedVector2Array())


## 둑 위 난간: 기둥 + 위·가운데 가로대
func _rail(a: Vector2, b: Vector2) -> void:
	var len := a.distance_to(b)
	var dir := (b - a) / len
	var posts := PackedVector2Array()
	var s := fposmod(-_along(a, dir), POST_EVERY)
	while s <= len:
		var p := a + dir * s
		posts.append_array([p, p + IsoView.lift(RAIL_H)])
		s += POST_EVERY
	if not posts.is_empty():
		draw_multiline(posts, RAIL.darkened(0.3), 1.5)
	draw_line(a + IsoView.lift(RAIL_H * 0.5), b + IsoView.lift(RAIL_H * 0.5), RAIL.darkened(0.2), 1.0)
	draw_line(a + IsoView.lift(RAIL_H), b + IsoView.lift(RAIL_H), RAIL, 2.0)


## 면 하나 (a→b를 높이 h0~h1로, 아래 색 c0 → 위 색 c1)
func _quad(a: Vector2, b: Vector2, h0: float, h1: float, c0: Color, c1: Color) -> void:
	draw_primitive(IsoView.wall(a, b, h0, h1), PackedColorArray([c0, c0, c1, c1]), PackedVector2Array())


## 선분 방향 좌표 (블록 이음·기둥이 이웃 선분과 같은 격자에 서게)
static func _along(p: Vector2, dir: Vector2) -> float:
	return p.dot(dir.abs())


static func _hash(p: Vector2) -> float:
	return fposmod(sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453, 1.0)
