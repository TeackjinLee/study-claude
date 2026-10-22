class_name OverpassView
extends RefCounted
## 2.5D 고가차도 (CityMap.OVERPASSES): 충돌 벽과 상판 그림.
## - 땅(Layers.WORLD): 경사로가 OVER_SWITCH보다 높은 곳부터 양옆 옹벽, 넘는 교차로 상자 양끝의 교대(밑으로 길이 지나는 상자는 비운다)
## - 고가 위(Layers.DECK): 입구부터 출구까지 양옆 난간 — 고가 위 차·사람은 이것에만 부딪힌다
## 상판은 진행 방향으로 STEP마다 조각을 내 깊이 정렬한다 — 밑을 지나는 차는 위 조각에 가리고,
## 고가 위의 차는 IsoView.z_at이 조각보다 앞에 그린다. 앞 난간은 고가 위 차보다도 앞이라 따로 조각을 둔다.

const STEP := 24.0              ## 상판 조각 길이 (월드 px)
const SLAB := 7.0               ## 상판 두께 (화면 px)
const RAIL_H := 7.0             ## 방호벽(콘크리트) 높이
const PIPE := 4.0               ## 방호벽 위 손잡이 난간 높이
const WALL := 8.0               ## 충돌 벽 두께 (월드 px)
const LAMP_EVERY := 4           ## 가로등 간격 (조각 수)
const LAMP_H := 34.0            ## 가로등 높이
const CONCRETE := Color(0.52, 0.53, 0.57)
const BARRIER := Color(0.68, 0.69, 0.72)      ## 방호벽 (밝은 콘크리트)
const BEAM := Color(0.62, 0.63, 0.66)         ## 상판 끝 보 (옹벽보다 밝다)
const STEEL := Color(0.42, 0.45, 0.5)
const LAMP := Color(1.0, 0.9, 0.62)
const DECK_ASPHALT := Color(0.19, 0.2, 0.25)  ## 땅 도로보다 조금 밝게 — 고가인 것이 보이게
const UNDER := Color(0.0, 0.0, 0.03, 0.3)    ## 넘는 교차로 밑 그늘 (가장자리)
const UNDER_CORE := 0.12        ## 안쪽으로 한 겹마다 더 짙게
const UNDER_OUT := 0.09         ## 열린 변 밖 반그늘 한 겹
const UNDER_BAND := 7.0         ## 그늘 겹 간격 (월드 px)


static func build(parent: Node2D, presentation_enabled := true) -> void:
	for oi in CityMap.OVERPASSES.size():
		_walls(parent, CityMap.OVERPASSES[oi])
		if presentation_enabled:
			_slices(parent, oi)


## 넘는 교차로 box 밑 그늘 (바닥 층). 상판이 상자를 다 덮고, 빛은 밑을 지나는 길이 드나드는
## 두 변(고가 진행 방향과 나란한 변)으로만 들어오므로 그 두 변에서 안쪽으로 갈수록 짙어진다
static func draw_under(ci: CanvasItem, box: Rect2, axis: int) -> void:
	# 열린 두 변 밖으로 옅은 반그늘 (상판 밑을 들여다볼 때 보이는 길 입구)
	for k in range(6, 0, -1):
		var g := UNDER_BAND * k
		var out := box.grow_individual(0.0, g, 0.0, g) if axis == 1 else box.grow_individual(g, 0.0, g, 0.0)
		ci.draw_rect(out, Color(UNDER, UNDER_OUT))
	ci.draw_rect(box, UNDER)
	var color := Color(UNDER, UNDER_CORE)
	for k in range(1, 5):
		var inset := UNDER_BAND * k
		var r := box.grow_individual(0.0, -inset, 0.0, -inset) if axis == 1 else box.grow_individual(-inset, 0.0, -inset, 0.0)
		if r.size.x > 0.0 and r.size.y > 0.0:
			ci.draw_rect(r, color)


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
	var _outline := PackedVector2Array()   ## 이 조각이 화면에서 차지하는 자리 (땅~난간 꼭대기) — 가림 검사용
	var _glow: Node2D                       ## 가로등 불빛 (건물 불빛 셰이더 — 밤에 켜지고 어두운 화면에서도 밝다)

	func _ready() -> void:
		z_as_relative = false
		_sort()
		if not front and index % LAMP_EVERY == 1:
			_glow = Node2D.new()
			_glow.material = BuildingView.light_material()
			_glow.draw.connect(_draw_glow)
			add_child(_glow)

	func _process(delta: float) -> void:
		var key := 1 if IsoView.enabled else 0
		if key != _drawn:
			_drawn = key
			_sort()
			queue_redraw()
			if _glow:
				_glow.queue_redraw()
		# 땅에 있는 주인공(또는 탄 차)을 가리면 건물처럼 흐린다 (City.FADE_ALPHA)
		var goal := 1.0
		if IsoView.enabled and _hides_target():
			goal = City.FADE_ALPHA
		if not is_equal_approx(modulate.a, goal):
			modulate.a = move_toward(modulate.a, goal, delta * 3.0)

	func _hides_target() -> bool:
		var cam := ChaseCamera.current_cam()
		if cam == null or cam.target == null or not is_instance_valid(cam.target):
			return false
		var t := cam.target
		var lv = t.get("level")
		if lv != null and int(lv) != 0:
			return false         # 고가 위는 가리지 않는다
		var p := t.global_position
		if p.distance_squared_to(CityMap.over_point(o, (a0 + a1) * 0.5, City.road_center(o.y))) > 360.0 * 360.0:
			return false
		if z_index <= IsoView.z_at(p, 0):
			return false         # 이 조각이 주인공보다 먼저(뒤에) 그려진다
		p += IsoView.lift(Terrain.height(p))
		return Geometry2D.is_point_in_polygon(p + IsoView.lift(14.0), _outline) \
			or Geometry2D.is_point_in_polygon(p, _outline)

	func _sort() -> void:
		var rc := City.road_center(o.y)
		var corner := CityMap.over_point(o, a1, rc + City.ROAD * 0.5)
		if not IsoView.enabled:
			z_index = -5          # 위에서 보기: 바닥 위, 차·사람 밑
		elif front:
			z_index = IsoView.deck_z(o, corner, IsoView.DECK_Z_AHEAD) + 2
		else:
			z_index = IsoView.z_of(corner)
		var hw := City.ROAD * 0.5
		var pts := PackedVector2Array()
		if IsoView.enabled:
			for a in [a0, a1]:
				var h := _h(a) + RAIL_H + PIPE
				for c in [rc - hw, rc + hw]:
					pts.append(_at(a, c, 0.0))
					pts.append(_at(a, c, h))
		_outline = Geometry2D.convex_hull(pts) if pts.size() >= 3 else PackedVector2Array()

	func _h(a: float) -> float:
		return CityMap.over_height(oi, CityMap.over_point(o, a, City.road_center(o.y)))

	## (진행, 가로, 높이) → 그릴 자리. 높이는 고가 둘레를 고른 땅(Terrain.overpass_height)부터
	func _at(a: float, c: float, h: float) -> Vector2:
		return CityMap.over_point(o, a, c) + IsoView.lift(h + Terrain.overpass_height(oi))

	func _quad(p: Array, color: Color) -> void:
		draw_primitive(PackedVector2Array(p), PackedColorArray([color]), PackedVector2Array())

	## 방호벽 한 토막 (가로 c, 높이 h0~h1 바닥에서): 면 + 윗면 띠 + 손잡이 난간·기둥
	func _barrier(c: float, h0: float, h1: float, face: Color) -> void:
		_quad([_at(a0, c, h0), _at(a1, c, h1), _at(a1, c, h1 + RAIL_H), _at(a0, c, h0 + RAIL_H)], face)
		# 아래쪽 비탈면(저지 방호벽)과 윗면 띠
		draw_line(_at(a0, c, h0 + 2.0), _at(a1, c, h1 + 2.0), face.darkened(0.12), 1.0)
		draw_line(_at(a0, c, h0 + RAIL_H), _at(a1, c, h1 + RAIL_H), BARRIER.lightened(0.15), 2.0)
		draw_line(_at(a0, c, h0 + RAIL_H), _at(a0, c, h0 + RAIL_H + PIPE), STEEL, 1.0)
		draw_line(_at(a0, c, h0 + RAIL_H + PIPE), _at(a1, c, h1 + RAIL_H + PIPE), STEEL.lightened(0.2), 1.5)

	func _draw() -> void:
		var rc := City.road_center(o.y)
		var hw := City.ROAD * 0.5
		var iso := IsoView.enabled
		var h0 := _h(a0) if iso else 0.0
		var h1 := _h(a1) if iso else 0.0
		if front:
			if iso:
				_barrier(rc + hw - 1.0, h0, h1, BARRIER.darkened(IsoView.face_shade(Vector2.DOWN if o.x == 1 else Vector2.RIGHT)))
			return
		var mid := (a0 + a1) * 0.5
		var span := false        # 넘는 교차로 위 — 상판만 떠 있다
		var abut := false        # 이 조각 끝이 넘는 교차로 상자에 닿는다 (교대 앞면이 보인다)
		for cut in OverpassView.cuts(o):
			span = span or (mid > cut.x and mid < cut.y)
			abut = abut or is_equal_approx(a1, cut.x)
		if iso:
			# 앞(남·동쪽) 옆면: 경사로·상판 구간은 땅까지 막힌 옹벽, 넘는 교차로 위는 상판 끝 보만
			var c := rc + hw
			var side := IsoView.face_shade(Vector2.DOWN if o.x == 1 else Vector2.RIGHT)
			var wall := CONCRETE.darkened(side)
			var beam := BEAM.darkened(side)
			var b0 := maxf(h0 - SLAB, 0.0)
			var b1 := maxf(h1 - SLAB, 0.0)
			if not span:
				_quad([_at(a0, c, 0.0), _at(a1, c, 0.0), _at(a1, c, b1), _at(a0, c, b0)], wall)
				# 아래 굽(물 얼룩 진 띠)·옹벽 판 이음줄
				var f0 := minf(3.0, b0)
				var f1 := minf(3.0, b1)
				_quad([_at(a0, c, 0.0), _at(a1, c, 0.0), _at(a1, c, f1), _at(a0, c, f0)], wall.darkened(0.25))
				if b0 > 4.0:
					draw_line(_at(a0, c, 0.0), _at(a0, c, b0), wall.darkened(0.18), 1.0)
					if index % 3 == 1:
						# 보 밑으로 흘러내린 빗물 자국
						var sa := lerpf(a0, a1, 0.4)
						var sh := lerpf(b0, b1, 0.4)
						_quad([_at(sa, c, sh * 0.45), _at(sa + 5.0, c, sh * 0.45), _at(sa + 5.0, c, sh), _at(sa, c, sh)],
							wall.darkened(0.1))
			_quad([_at(a0, c, b0), _at(a1, c, b1), _at(a1, c, h1), _at(a0, c, h0)], beam)
			draw_line(_at(a0, c, b0), _at(a1, c, b1), beam.darkened(0.4), 1.0)
			if abut:
				# 교대 앞면: 콘크리트 + 상판이 얹힌 줄과 받침
				var end_shade := CONCRETE.darkened(IsoView.face_shade(Vector2.RIGHT if o.x == 1 else Vector2.DOWN))
				_quad([_at(a1, rc - hw, 0.0), _at(a1, rc + hw, 0.0), _at(a1, rc + hw, h1), _at(a1, rc - hw, h1)], end_shade)
				_quad([_at(a1, rc - hw, h1 - SLAB), _at(a1, rc + hw, h1 - SLAB), _at(a1, rc + hw, h1), _at(a1, rc - hw, h1)],
					BEAM.darkened(IsoView.face_shade(Vector2.RIGHT if o.x == 1 else Vector2.DOWN)))
				draw_line(_at(a1, rc - hw, h1 - SLAB), _at(a1, rc + hw, h1 - SLAB), end_shade.darkened(0.45), 1.0)
				for k in 5:
					var cc := lerpf(rc - hw + 6.0, rc + hw - 6.0, k / 4.0)
					draw_line(_at(a1, cc, 0.0), _at(a1, cc, h1 - SLAB), end_shade.darkened(0.12), 1.0)
					draw_line(_at(a1, cc, h1 - SLAB - 2.0), _at(a1, cc, h1 - SLAB), STEEL.darkened(0.3), 4.0)
			if span:
				# 상판 밑면 그늘 (넘는 교차로 위를 지나는 보)
				_quad([_at(a0, rc - hw, h0 - SLAB), _at(a1, rc - hw, h1 - SLAB), _at(a1, c, h1 - SLAB), _at(a0, c, h0 - SLAB)],
					CONCRETE.darkened(0.55))
		# 상판 (아스팔트)
		_quad([_at(a0, rc - hw, h0), _at(a1, rc - hw, h1), _at(a1, rc + hw, h1), _at(a0, rc + hw, h0)],
			DECK_ASPHALT if iso else City.ASPHALT)
		# 차선: 가운데 노랑 겹선, 흰 점선, 양쪽 끝 흰 실선
		for off in [-3.0, 3.0]:
			draw_line(_at(a0, rc + off, h0), _at(a1, rc + off, h1), City.LANE_YELLOW, 2.0)
		if index % 2 == 0:
			for lane in [-hw * 0.5, hw * 0.5]:
				draw_line(_at(a0, rc + lane, h0), _at(a1, rc + lane, h1), City.LANE_WHITE, 2.0)
		if iso:
			for edge in [rc - hw + 9.0, rc + hw - 7.0]:
				draw_line(_at(a0, edge, h0), _at(a1, edge, h1), City.LANE_WHITE, 1.5)
		# 뒤(북·서쪽) 방호벽: 안쪽 면이 보인다. 위에서 보기면 양쪽 난간을 선으로
		var back := rc - hw + 3.0
		if iso:
			_barrier(back, h0, h1, BARRIER.darkened(0.3))
			if _glow:
				# 가로등: 뒤 방호벽에서 서서 상판 쪽으로 팔을 내민다
				var la := (a0 + a1) * 0.5
				var lh := (h0 + h1) * 0.5 + RAIL_H
				draw_line(_at(la, back, lh), _at(la, back, lh + LAMP_H), STEEL, 2.0)
				draw_line(_at(la, back, lh + LAMP_H), _at(la, back + 12.0, lh + LAMP_H - 1.0), STEEL, 2.0)
				_quad(_lamp_head(la, back, lh), LAMP.darkened(0.25))
		else:
			for c in [back, rc + hw - 3.0]:
				draw_line(_at(a0, c, 0.0), _at(a1, c, 0.0), City.RAIL, 4.0)

	## 가로등 머리 (팔 끝 밑면)
	func _lamp_head(la: float, back: float, lh: float, grow := 0.0) -> Array:
		var z := lh + LAMP_H - 2.0
		return [_at(la - 3.0 - grow, back + 10.0 - grow, z), _at(la + 3.0 + grow, back + 10.0 - grow, z),
			_at(la + 3.0 + grow, back + 16.0 + grow, z), _at(la - 3.0 - grow, back + 16.0 + grow, z)]

	## 불빛 조각: 등 머리·번짐·상판에 떨어진 빛. UV (2, 2 + 차례) — 불빛 셰이더가 lights_on이 차례를 넘으면 켠다
	func _draw_glow() -> void:
		if not IsoView.enabled:
			return
		var back := City.road_center(o.y) - City.ROAD * 0.5 + 3.0
		var la := (a0 + a1) * 0.5
		var lh := (_h(a0) + _h(a1)) * 0.5 + RAIL_H
		var order := 0.08 + 0.1 * float(index % 3) / 2.0    # 해 질 녘 하나둘 켜진다
		var uv := Vector2(2.0, 2.0 + order)
		var pool_c := back + 14.0
		for ring in [[13.0, 14.0, 0.07], [8.0, 9.0, 0.11]]:
			var pool := PackedVector2Array()
			for k in 12:
				var t := TAU * k / 12.0
				pool.append(_at(la + cos(t) * ring[0], pool_c + sin(t) * ring[1], lh - RAIL_H))
			_glow_poly(pool, Color(1.0, 0.78, 0.42, ring[2]), uv)
		_glow_poly(PackedVector2Array(_lamp_head(la, back, lh, 3.0)), Color(LAMP, 0.3), uv)
		_glow_poly(PackedVector2Array(_lamp_head(la, back, lh)), Color(1.0, 0.97, 0.85), uv)

	func _glow_poly(pts: PackedVector2Array, color: Color, uv: Vector2) -> void:
		var cols := PackedColorArray()
		var uvs := PackedVector2Array()
		for i in pts.size():
			cols.append(color)
			uvs.append(uv)
		if pts.size() <= 4:
			_glow.draw_primitive(pts, cols, uvs)
		else:
			_glow.draw_polygon(pts, cols, uvs)
