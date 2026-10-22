class_name MapView
extends Control
## 일시정지 메뉴의 서울 지도: 위에서 본 도시 전체(북쪽이 위). 구역마다 색, 잠긴 구역은 어둡게, 한강은 파랗게.
## 표시: 주인공(흰 화살) · 산 은신처(초록 집) · 공중전화(조직 색 점, 열린 구역만) · 미션 목표(노란 고리) · 쫓는 범인(빨간 점).
## 비밀 패키지·광란 아이콘은 지도에 없다 (찾는 재미).

var main: Node2D
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## 월드 → 이 칸 안 좌표 (비율 유지, 가운데 맞춤)
func _xf() -> Transform2D:
	var w := City.world_rect()
	var k := minf(size.x / w.size.x, size.y / w.size.y)
	var off := (size - w.size * k) * 0.5 - w.position * k
	return Transform2D(0.0, Vector2(k, k), 0.0, off)


func _draw() -> void:
	var xf := _xf()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.08))
	var font := ThemeDB.fallback_font
	draw_set_transform_matrix(xf)
	for j in range(CityMap.MIN.y, CityMap.MAX.y + 1):
		for i in range(CityMap.MIN.x, CityMap.MAX.x + 1):
			var cell := Vector2i(i, j)
			var d := CityMap.district_of(cell)
			if d == null:
				continue
			var c := d.color.darkened(0.35)
			if not CityMap.is_open_block(cell):
				c = c.darkened(0.7)
			draw_rect(City.block_rect(i, j).grow(-City.SIDEWALK), c)
	for r in City.water_rects():
		draw_rect(r, Color(0.12, 0.3, 0.5))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# 구역 이름
	for d in CityMap.DISTRICTS:
		var a := City.block_rect(d.blocks.position.x, d.blocks.position.y)
		var b := City.block_rect(d.blocks.end.x - 1, d.blocks.end.y - 1)
		var at := xf * ((a.position + b.end) * 0.5)
		var open := d.chapter <= CityMap.chapter
		var name := Locale.t(d.display_name) if open else Locale.t("%d장에 열림") % d.chapter
		draw_string(font, at + Vector2(-80, 6), name, HORIZONTAL_ALIGNMENT_CENTER, 160, 15,
			Color(1, 1, 1, 0.85 if open else 0.45))
	if main == null:
		return
	# 공중전화
	for q: Dictionary in main.missions.phones:
		if CityMap.is_open_block(City.nearest_block(q.pos)):
			draw_circle(xf * (q.pos as Vector2), 3.5, (q.gang as GangType).color)
	# 산 은신처
	for h in main.hideouts:
		if h.owned:
			var p: Vector2 = xf * (h.type.door as Vector2)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -8), p + Vector2(7, -2), p + Vector2(5, 6),
				p + Vector2(-5, 6), p + Vector2(-7, -2)]), Color(0.35, 1.0, 0.5))
	# 미션 목표
	var goal: Variant = main.missions.objective_position()
	if goal is Vector2:
		draw_arc(xf * (goal as Vector2), 9.0 + 2.0 * sin(_t * 5.0), 0.0, TAU, 24, Color(1, 0.85, 0.2), 2.5)
	var crook: Vector2 = main.street_events.target_position()
	if crook != Vector2.INF:
		draw_circle(xf * crook, 5.0, Color(1, 0.2, 0.2))
	# 주인공
	var me: Node2D = main.director.controlled_target()
	var p: Vector2 = xf * me.global_position
	var dir := Vector2.UP.rotated(me.rotation if main.director.current_vehicle else main.player.facing)
	var tri := PackedVector2Array([p + dir * 10.0, p + dir.rotated(2.5) * 7.0, p + dir.rotated(-2.5) * 7.0])
	draw_colored_polygon(tri, Color.WHITE)
	tri.append(tri[0])
	draw_polyline(tri, Color(0, 0, 0), 1.5)
	# 범례
	var y := size.y - 14.0
	var x := 12.0
	for item in [[Color.WHITE, "나"], [Color(0.35, 1.0, 0.5), "은신처"], [Color(1, 0.6, 0.2), "공중전화"], [Color(1, 0.85, 0.2), "미션 목표"]]:
		draw_circle(Vector2(x + 5, y - 5), 5.0, item[0])
		var text: String = Locale.t(item[1])
		draw_string(font, Vector2(x + 14, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))
		x += 26.0 + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
