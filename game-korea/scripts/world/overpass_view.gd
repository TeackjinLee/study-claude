class_name OverpassView
extends RefCounted
## 2.5D 고가차도 (CityMap.OVERPASSES): 충돌 벽과 상판 그림.
## - 땅(Layers.WORLD): 경사로가 OVER_SWITCH보다 높은 곳부터 양옆 옹벽, 넘는 교차로 상자 양끝의 교대(밑으로 길이 지나는 상자는 비운다)
## - 고가 위(Layers.DECK): 입구부터 출구까지 양옆 난간 — 고가 위 차·사람은 이것에만 부딪힌다
## 상판은 진행 방향으로 STEP마다 조각을 내 깊이 정렬한다 — 밑을 지나는 차는 위 조각에 가리고,
## 고가 위의 차는 IsoView.z_at이 조각보다 앞에 그린다. 앞 난간은 고가 위 차보다도 앞이라 따로 조각을 둔다.

const STEP := 24.0              ## 상판 조각 길이 (월드 px)
const SLAB := 7.0               ## 상판 두께 (화면 px)
const RAIL_H := 7.0             ## 난간 높이
const WALL := 8.0               ## 충돌 벽 두께 (월드 px)
const CONCRETE := Color(0.52, 0.53, 0.57)
const UNDER := Color(0.0, 0.0, 0.03, 0.3)    ## 넘는 교차로 밑 그늘


static func build(parent: Node2D) -> void:
	for oi in CityMap.OVERPASSES.size():
		_walls(parent, CityMap.OVERPASSES[oi])
		_slices(parent, oi)


## 고가 o의 (진행 a0~a1, 가로 c0~c1) 사각형 → 월드 사각형
static func _rect(o: Vector4i, a0: float, a1: float, c0: float, c1: float) -> Rect2:
	var p := CityMap.over_point(o, minf(a0, a1), minf(c0, c1))
	var q := CityMap.over_point(o, maxf(a0, a1), maxf(c0, c1))
	return Rect2(p, q - p)


## 넘는 교차로 상자들의 진행 좌표 구간
static func cuts(o: Vector4i) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for n in range(o.z, o.w + 1):
		out.append(Vector2(n * City.PITCH, n * City.PITCH + City.ROAD))
	return out


static func _walls(parent: Node2D, o: Vector4i) -> void:
	var ground := StaticBody2D.new()
	ground.collision_layer = Layers.WORLD
	ground.collision_mask = 0
	parent.add_child(ground)
	var deck := StaticBody2D.new()
	deck.collision_layer = Layers.DECK
	deck.collision_mask = 0
	parent.add_child(deck)
	var ext := CityMap.over_extent(o)
	var rc := City.road_center(o.y)
	var hw := City.ROAD * 0.5
	for side in [-1.0, 1.0]:
		var c0: float = rc + side * hw
		var c1: float = rc + side * (hw - WALL)
		City._add_box(deck, _rect(o, ext.x, ext.y, c0, c1))
		var a := ext.x + CityMap.over_switch_distance()
		for cut in cuts(o):
			City._add_box(ground, _rect(o, a, cut.x, c0, c1))
			a = cut.y
		City._add_box(ground, _rect(o, a, ext.y - CityMap.over_switch_distance(), c0, c1))
	for cut in cuts(o):
		City._add_box(ground, _rect(o, cut.x - WALL, cut.x, rc - hw, rc + hw))
		City._add_box(ground, _rect(o, cut.y, cut.y + WALL, rc - hw, rc + hw))


static func _slices(parent: Node2D, oi: int) -> void:
	var o := CityMap.OVERPASSES[oi]
	var ext := CityMap.over_extent(o)
	var a := ext.x
	var i := 0
	while a < ext.y - 0.5:
		var b := minf(a + STEP, ext.y)
		for front in [false, true]:
			var s := Slice.new()
			s.oi = oi
			s.o = o
			s.a0 = a
			s.a1 = b
			s.index = i
			s.front = front
			parent.add_child(s)
		a = b
		i += 1


## 상판 한 조각 (front면 앞 난간만)
class Slice extends Node2D:
	var oi := 0
	var o: Vector4i
	var a0 := 0.0
	var a1 := 0.0
	var index := 0
	var front := false
	var _drawn := -1

	func _ready() -> void:
		z_as_relative = false
		_sort()

	func _process(_delta: float) -> void:
		var key := 1 if IsoView.enabled else 0
		if key != _drawn:
			_drawn = key
			_sort()
			queue_redraw()

	func _sort() -> void:
		var rc := City.road_center(o.y)
		var corner := CityMap.over_point(o, a1, rc + City.ROAD * 0.5)
		if not IsoView.enabled:
			z_index = -5          # 위에서 보기: 바닥 위, 차·사람 밑
		elif front:
			z_index = IsoView.deck_z(o, corner, IsoView.DECK_Z_AHEAD) + 2
		else:
			z_index = IsoView.z_of(corner)

	func _h(a: float) -> float:
		return CityMap.over_height(oi, CityMap.over_point(o, a, City.road_center(o.y)))

	## (진행, 가로, 높이) → 그릴 자리
	func _at(a: float, c: float, h: float) -> Vector2:
		return CityMap.over_point(o, a, c) + IsoView.lift(h)

	func _quad(p: Array, color: Color) -> void:
		draw_primitive(PackedVector2Array(p), PackedColorArray([color]), PackedVector2Array())

	func _draw() -> void:
		var rc := City.road_center(o.y)
		var hw := City.ROAD * 0.5
		var iso := IsoView.enabled
		var h0 := _h(a0) if iso else 0.0
		var h1 := _h(a1) if iso else 0.0
		if front:
			if iso:
				var c := rc + hw - 1.0
				_quad([_at(a0, c, h0), _at(a1, c, h1), _at(a1, c, h1 + RAIL_H), _at(a0, c, h0 + RAIL_H)],
					City.RAIL.darkened(0.2))
				draw_line(_at(a0, c, h0 + RAIL_H), _at(a1, c, h1 + RAIL_H), City.RAIL, 2.0)
			return
		var mid := (a0 + a1) * 0.5
		var span := false        # 넘는 교차로 위 — 상판만 떠 있다
		var abut := false        # 이 조각 끝이 넘는 교차로 상자에 닿는다 (교대 앞면이 보인다)
		for cut in OverpassView.cuts(o):
			span = span or (mid > cut.x and mid < cut.y)
			abut = abut or is_equal_approx(a1, cut.x)
		if iso:
			# 앞(남·동쪽) 옆면: 경사로·상판 구간은 땅까지 막힌 옹벽, 넘는 교차로 위는 상판 두께만
			var c := rc + hw
			var shade := CONCRETE.darkened(IsoView.face_shade(Vector2.DOWN if o.x == 1 else Vector2.RIGHT))
			var lo0 := maxf(h0 - SLAB, 0.0) if span else 0.0
			var lo1 := maxf(h1 - SLAB, 0.0) if span else 0.0
			_quad([_at(a0, c, lo0), _at(a1, c, lo1), _at(a1, c, h1), _at(a0, c, h0)], shade)
			if abut:
				var end_shade := CONCRETE.darkened(IsoView.face_shade(Vector2.RIGHT if o.x == 1 else Vector2.DOWN))
				_quad([_at(a1, rc - hw, 0.0), _at(a1, rc + hw, 0.0), _at(a1, rc + hw, h1), _at(a1, rc - hw, h1)], end_shade)
			if span:
				# 상판 밑면 그늘 (넘는 교차로 위를 지나는 보)
				_quad([_at(a0, rc - hw, h0 - SLAB), _at(a1, rc - hw, h1 - SLAB), _at(a1, c, h1 - SLAB), _at(a0, c, h0 - SLAB)],
					CONCRETE.darkened(0.55))
		# 상판 (아스팔트)
		_quad([_at(a0, rc - hw, h0), _at(a1, rc - hw, h1), _at(a1, rc + hw, h1), _at(a0, rc + hw, h0)], City.ASPHALT)
		# 차선: 가운데 노랑 겹선, 흰 점선
		for off in [-3.0, 3.0]:
			draw_line(_at(a0, rc + off, h0), _at(a1, rc + off, h1), City.LANE_YELLOW, 2.0)
		if index % 2 == 0:
			for lane in [-hw * 0.5, hw * 0.5]:
				draw_line(_at(a0, rc + lane, h0), _at(a1, rc + lane, h1), City.LANE_WHITE, 2.0)
		# 뒤(북·서쪽) 난간: 안쪽 면이 보인다. 위에서 보기면 양쪽 난간을 선으로
		var back := rc - hw + 3.0
		if iso:
			_quad([_at(a0, back, h0), _at(a1, back, h1), _at(a1, back, h1 + RAIL_H), _at(a0, back, h0 + RAIL_H)],
				City.RAIL.darkened(0.35))
			draw_line(_at(a0, back, h0 + RAIL_H), _at(a1, back, h1 + RAIL_H), City.RAIL, 2.0)
		else:
			for c in [back, rc + hw - 3.0]:
				draw_line(_at(a0, c, 0.0), _at(a1, c, 0.0), City.RAIL, 4.0)
