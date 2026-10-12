class_name BuildingView
extends Node2D
## 2.5D 건물 한 조각. 바닥 사각형(물리 충돌과 같은 자리)에서 화면을 향한 두 벽(동·남)을 세우고,
## 맨 앞 조각이 지붕 높이에 위에서 본 건물 그림(BuildingDrawer)을 올린다.
## 긴 건물은 정사각형에 가까운 조각으로 나눈다 — 조각 가운데의 깊이(x+y)로 정렬해야
## 옆 인도를 걷는 사람이 벽 뒤로 숨지 않는다.
## 그림은 높이를 월드 오프셋(IsoView.lift)으로 바꿔 그리므로 한 번만 그리면 된다.

const SHOP_BAND := 0.75        ## 1층 상가 띠 높이 (층 높이 배수)
const BAY := 34.0              ## 창 간격 (월드 px)

var city: City
var idx := -1                  ## city.buildings 번호
var rect: Rect2                ## 건물 전체
var part: Rect2                ## 이 조각
var roof := false              ## 지붕을 그리는 조각 (가장 앞)
var height := 72.0
var kind: BuildingType         ## null이면 특수 건물 (경찰서·병원·카센터)
var wall := Color(0.45, 0.45, 0.5)
var style: StringName = &"office"


func _ready() -> void:
	z_as_relative = false
	z_index = IsoView.z_of(part.get_center())


func _draw() -> void:
	if part.end.x >= rect.end.x - 0.5:
		_face(Vector2(rect.end.x, part.position.y), Vector2(rect.end.x, part.end.y), Vector2.RIGHT)
	if part.end.y >= rect.end.y - 0.5:
		_face(Vector2(part.position.x, rect.end.y), Vector2(part.end.x, rect.end.y), Vector2.DOWN)
	if roof:
		draw_set_transform(IsoView.lift(height), 0.0, Vector2.ONE)
		BuildingDrawer.shadows = false
		city._draw_building(self, rect, idx, ThemeDB.fallback_font)
		BuildingDrawer.shadows = true
		# 옥상 가장자리 (난간)
		var edge := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y), rect.position])
		draw_polyline(edge, wall.lightened(0.25), 3.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 벽 한 면: 바닥 선분 a→b, 바깥 법선 n
func _face(a: Vector2, b: Vector2, n: Vector2) -> void:
	var shade := IsoView.face_shade(n)
	draw_colored_polygon(IsoView.wall(a, b, 0.0, height), wall.darkened(shade))
	var floors := maxi(1, roundi(height / IsoView.FLOOR_HEIGHT))
	var fh := height / floors
	var length := a.distance_to(b)
	var along := (b - a) / length
	var bays := maxi(1, int(length / BAY))
	var step := length / bays
	var seed := idx * 17 + int(a.x + a.y)
	var shop_floor := style in [&"commercial", &"mixed", &"gosiwon", &"officetel"] or kind == null
	var glass := style in [&"office", &"officetel"]
	# 층마다 창
	for f in floors:
		var z0 := f * fh + fh * 0.3
		var z1 := f * fh + fh * 0.8
		if f == 0 and shop_floor:
			continue
		if glass:
			# 커튼월: 층마다 가로로 긴 유리 띠
			draw_colored_polygon(IsoView.wall(a + along * 3.0, b - along * 3.0, z0, z1), Color(0.16, 0.24, 0.32).darkened(shade * 0.5))
		for k in bays:
			var p := a + along * (k * step + step * 0.22)
			var q := a + along * (k * step + step * 0.78)
			var lit := posmod(seed + k * 7 + f * 13, 9) < 2
			var color := Color(0.95, 0.78, 0.45) if lit else Color(0.1, 0.13, 0.18)
			if glass and not lit:
				continue
			draw_colored_polygon(IsoView.wall(p, q, z0, z1), color.darkened(shade * 0.4))
	if shop_floor:
		_shops(a, b, along, length, fh, shade, seed)
	# 모서리 기둥
	draw_line(a, a + IsoView.lift(height), wall.darkened(shade + 0.15), 2.0)


## 1층 상가: 불 켜진 쇼윈도와 벽에 붙은 간판
func _shops(a: Vector2, b: Vector2, along: Vector2, length: float, fh: float, shade: float, seed: int) -> void:
	var shops := maxi(1, int(length / 90.0))
	var w := length / shops
	var font := ThemeDB.fallback_font
	for k in shops:
		var p := a + along * (k * w + 6.0)
		var q := a + along * ((k + 1) * w - 6.0)
		var neon: Color = City.NEON[posmod(seed + k, City.NEON.size())]
		draw_colored_polygon(IsoView.wall(p, q, 2.0, fh * SHOP_BAND), Color(0.95, 0.88, 0.7, 0.85).darkened(shade * 0.6))
		draw_colored_polygon(IsoView.wall(p.lerp(q, 0.4), p.lerp(q, 0.6), 0.0, fh * 0.55), Color(0.2, 0.18, 0.16))
		if kind == null or kind.signs.is_empty():
			continue
		# 간판: 벽 평면 좌표계 (x = 벽을 따라, y = 화면 아래로)
		var text := kind.signs[posmod(seed + k * 3, kind.signs.size())]
		var top := fh * SHOP_BAND + fh * 0.75
		# 화면에서 왼쪽→오른쪽으로 읽히게: 동쪽 벽은 거꾸로 따라간다
		var dir := along if IsoView.to_screen_dir(along).x > 0.0 else -along
		var start := p if dir == along else q
		var frame := Transform2D(dir, -IsoView.LIFT, start + IsoView.lift(top))
		draw_set_transform_matrix(frame)
		var tw := minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 10.0, w - 12.0)
		draw_rect(Rect2(0, 0, tw, fh * 0.6), neon.darkened(0.7))
		draw_rect(Rect2(0, 0, tw, fh * 0.6), neon, false, 1.5)
		draw_string(font, Vector2(5, fh * 0.6 - 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, tw - 6.0, 13, neon.lightened(0.5))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 화면에서 이 건물(전체)의 윤곽 — 사각형 바닥과 지붕을 감싼 육각형 (월드 좌표)
static func silhouette(r: Rect2, h: float) -> PackedVector2Array:
	var l := IsoView.lift(h)
	var ne := Vector2(r.end.x, r.position.y)
	var sw := Vector2(r.position.x, r.end.y)
	return PackedVector2Array([r.position + l, ne + l, ne, r.end, sw, sw + l])


## 조각으로 나눈다: 긴 변을 짧은 변 길이에 가깝게 자른다
static func split(r: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if r.size.x >= r.size.y:
		var n := maxi(1, roundi(r.size.x / r.size.y))
		for k in n:
			out.append(Rect2(r.position.x + r.size.x * k / n, r.position.y, r.size.x / n, r.size.y))
	else:
		var n := maxi(1, roundi(r.size.y / r.size.x))
		for k in n:
			out.append(Rect2(r.position.x, r.position.y + r.size.y * k / n, r.size.x, r.size.y / n))
	return out
