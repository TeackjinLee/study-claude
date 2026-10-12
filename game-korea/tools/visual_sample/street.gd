extends Node2D
## 강남 교차로 주변의 시각 레이어. 기존 건물 사각형·도로 좌표를 사용하며 충돌·AI는 건드리지 않는다.

var city: City
var profile: Resource
var center := Vector2i(3, 3)
var glow: Texture2D
var grain: Texture2D
var lamps: Array[Vector2] = []
var lights: Array[Dictionary] = []
var light_layer: Node2D
var _font: Font


func _ready() -> void:
	z_index = -9
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_font = ThemeDB.fallback_font
	_make_textures()
	light_layer = Node2D.new()
	light_layer.z_index = 1
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	light_layer.material = blend
	light_layer.draw.connect(_draw_lights)
	add_child(light_layer)
	queue_redraw()


func _make_textures() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = profile.texture_seed
	var tex := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var value := rng.randf_range(0.2, 0.8)
			tex.set_pixel(x, y, Color(value, value, value, rng.randf_range(0.035, 0.16)))
	grain = ImageTexture.create_from_image(tex)
	var halo := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	for y in 96:
		for x in 96:
			var radius := Vector2(x - 47.5, y - 47.5).length() / 47.5
			halo.set_pixel(x, y, Color(1, 1, 1, pow(maxf(0.0, 1.0 - radius), 2.6)))
	glow = ImageTexture.create_from_image(halo)


func _draw() -> void:
	lamps.clear()
	lights.clear()
	var first := center - Vector2i.ONE
	var last := center + Vector2i.ONE
	var bounds := Rect2(Vector2(first) * City.PITCH, Vector2.ONE * City.PITCH * 3.0)
	draw_rect(bounds, profile.asphalt)
	draw_texture_rect(grain, bounds, true, Color(0.65, 0.7, 0.85, 0.36))
	for j in range(first.y, last.y + 1):
		for i in range(first.x, last.x + 1):
			var block := City.block_rect(i, j)
			_pavement(block, i + j * 13)
			city._draw_road_segment(self, i, j, true, [])
			city._draw_road_segment(self, j, i, false, [])
			_road_details(i, j)
	# 통행 가능한 공원은 바닥 레이어에 덮이지 않도록 원래 그림을 복원한다.
	for idx in city.parks.size():
		if bounds.encloses(city.parks[idx]):
			BuildingDrawer.draw(self, city.parks[idx], city.park_kinds[idx], idx, _font)
	for idx in city.buildings.size():
		var rect: Rect2 = city.buildings[idx]
		if bounds.encloses(rect):
			_building(rect, city.kinds[idx], idx)
	for pos in lamps:
		_lamp(pos)
	light_layer.queue_redraw()


func _pavement(r: Rect2, seed_value: int) -> void:
	draw_rect(r, profile.pavement)
	# 건물 밑까지 보도 패턴을 만들지 않고 바깥 통행 띠만 그린다.
	var strips: Array[Rect2] = [Rect2(r.position, Vector2(r.size.x, City.SIDEWALK)),
		Rect2(r.position + Vector2(0, r.size.y - City.SIDEWALK), Vector2(r.size.x, City.SIDEWALK)),
		Rect2(r.position, Vector2(City.SIDEWALK, r.size.y)),
		Rect2(r.position + Vector2(r.size.x - City.SIDEWALK, 0), Vector2(City.SIDEWALK, r.size.y))]
	for strip in strips:
		for y in range(int(strip.position.y), int(strip.end.y), 12):
			for x in range(int(strip.position.x), int(strip.end.x), 16):
				var tile := Rect2(x + 1, y + 1, minf(14, strip.end.x - x - 1), minf(10, strip.end.y - y - 1))
				var shade: Color = profile.pavement.lightened(float(posmod(x * 7 + y * 3 + seed_value, 9)) * 0.013)
				draw_rect(tile, shade)
	draw_rect(r, Color("87918b"), false, 2)
	draw_rect(r.grow(-4), Color("252c32"), false, 2)
	for edge in [0, 1]:
		for t in [0.18, 0.74]:
			var pos := r.position + (Vector2(r.size.x * t, 10) if edge == 0 else Vector2(10, r.size.y * t))
			lamps.append(pos)
			_tree(pos + (Vector2(34, 0) if edge == 0 else Vector2(0, 34)), seed_value + edge)


func _tree(pos: Vector2, seed_value: int) -> void:
	draw_rect(Rect2(pos - Vector2(8, 8), Vector2(16, 16)), Color("182c2a"))
	draw_circle(pos + Vector2(4, 5), 13, Color(0, 0, 0, 0.35))
	for k in 9:
		var offset := Vector2(cos(k * 2.4), sin(k * 2.4)) * (4 + k % 4)
		draw_circle(pos + offset, 6, Color("263d32").lightened(float(posmod(k + seed_value, 4)) * 0.035))
	draw_rect(Rect2(pos - Vector2(2, 1), Vector2(3, 5)), Color("6a6044"))


func _road_details(i: int, j: int) -> void:
	var at := Vector2(City.road_center(i), City.road_center(j))
	var manhole := at + Vector2(-24, 30)
	draw_circle(manhole + Vector2.ONE * 2, 10, Color("111720"))
	draw_circle(manhole, 9, Color("39434c"))
	draw_arc(manhole, 7, 0, TAU, 20, Color("647078"), 1)
	for k in range(-4, 5, 3):
		draw_line(manhole + Vector2(-5, k), manhole + Vector2(5, k), Color("242d36"), 1)
	# 배수로와 패치. 횡단보도와 차선을 덮지 않는다.
	for side in [-1, 1]:
		var drain := at + Vector2(side * 88, 155)
		draw_rect(Rect2(drain, Vector2(6, 25)), Color("111b22"))
		for k in 5:
			draw_line(drain + Vector2(0, k * 5), drain + Vector2(6, k * 5), Color("617079"), 1)
	var arrow := at + Vector2(24, 230)
	var paint := Color(0.72, 0.77, 0.73, 0.3)
	draw_line(arrow, arrow + Vector2(0, -30), paint, 4)
	draw_polyline(PackedVector2Array([arrow + Vector2(-9, -20), arrow + Vector2(0, -30), arrow + Vector2(9, -20)]), paint, 3)
	for k in 4:
		var p := at + Vector2(-70 + k * 39, 110 + k * 33)
		draw_line(p, p + Vector2(26, 2), Color(0.3, 0.4, 0.48, 0.12), 2)
	# 갓길 웅덩이는 교차로와 횡단보도를 피해서 배치한다.
	var puddle := at + Vector2(69, 235)
	draw_colored_polygon(PackedVector2Array([puddle + Vector2(-9, -37), puddle + Vector2(15, -44),
		puddle + Vector2(19, 15), puddle + Vector2(8, 40), puddle + Vector2(-12, 26)]), Color(0.06, 0.12, 0.18, 0.45))
	for k in 8:
		draw_line(puddle + Vector2(-7, -26 + k * 7), puddle + Vector2(10 + k % 4, -25 + k * 7), Color(profile.cyan, 0.09), 1)


func _building(r: Rect2, kind: BuildingType, idx: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = profile.texture_seed + idx * 131
	var base: Color = profile.roof
	if kind and not kind.roof_colors.is_empty():
		base = kind.roof_colors[idx % kind.roof_colors.size()].lerp(profile.roof, 0.55)
	var style: StringName = kind.style if kind else &"commercial"
	var shops := style in [&"commercial", &"mixed", &"gosiwon"]
	var business := style in [&"office", &"officetel"]
	var residential := style in [&"apt", &"villa", &"house", &"rowhouse", &"oneroom", &"jjokbang"]
	var facade := Color("232931")
	draw_rect(Rect2(r.position + Vector2(6, 7), r.size), Color(0, 0, 0, 0.4))
	draw_rect(r, facade)
	var roof := Rect2(r.position + Vector2(5, 5), r.size - Vector2(22, 42))
	draw_rect(roof, base)
	draw_texture_rect(grain, roof, true, Color(0.8, 0.9, 1, 0.65))
	# 지붕 패널·파라펫·방수 이음. 모든 입체 표현은 건물 충돌 범위 안에 둔다.
	for y in range(int(roof.position.y) + 16, int(roof.end.y), 38):
		draw_line(Vector2(roof.position.x + 3, y), Vector2(roof.end.x - 3, y), Color(0, 0, 0, 0.12), 1)
	for x in range(int(roof.position.x) + 16, int(roof.end.x), 64):
		draw_line(Vector2(x, roof.position.y + 3), Vector2(x, roof.end.y - 3), Color(0.65, 0.76, 0.74, 0.1), 1)
	draw_rect(roof.grow(-3), base.lightened(0.19), false, 3)
	draw_rect(roof.grow(-7), base.darkened(0.28), false, 2)
	for row in 3:
		for x in range(int(r.position.x) + 12, int(r.end.x) - 20, 24):
			var window := Rect2(x, roof.end.y + 4 + row * 10, 14, 6)
			var lit := rng.randf() > 0.45
			draw_rect(window, Color(profile.warm, rng.randf_range(0.18, 0.48)) if lit else Color("101c27"))
	for y in range(int(r.position.y) + 15, int(r.end.y) - 30, 22):
		draw_rect(Rect2(r.end.x - 13, y, 7, 12), Color(profile.cyan, 0.18) if rng.randf() > 0.55 else Color("131c28"))
	for k in 4:
		var p := roof.position + Vector2(rng.randf_range(22, roof.size.x - 70), rng.randf_range(22, roof.size.y - 60))
		_aircon(p, base)
	var hut := Rect2(roof.position + Vector2(20, 22), Vector2(minf(roof.size.x * 0.3, 88), 50))
	draw_rect(Rect2(hut.position + Vector2(5, 7), hut.size), Color(0, 0, 0, 0.25))
	draw_rect(hut, base.lightened(0.08))
	draw_rect(hut.grow(-4), base.darkened(0.18), false, 2)
	draw_rect(Rect2(hut.position + Vector2(7, 10), Vector2(16, 27)), Color("202b31"))
	var tank := roof.end - Vector2(45, 42)
	draw_circle(tank + Vector2(4, 5), 17, Color(0, 0, 0, 0.35))
	draw_circle(tank, 15, base.lightened(0.22))
	draw_arc(tank, 11, 0, TAU, 20, base.darkened(0.1), 2)
	draw_line(tank - Vector2(12, 2), tank + Vector2(12, -2), base.lightened(0.3), 2)
	_facade_details(r, roof, style, idx)
	var sign_text: String = profile.signs[idx % profile.signs.size()]
	if kind and not kind.signs.is_empty():
		sign_text = kind.signs[idx % kind.signs.size()]
	if kind and kind.style == &"apt":
		sign_text = "%s01동 · 아파트" % sign_text
	if r == city.hq:
		sign_text = "금강개발"
	elif r == city.hideout:
		sign_text = "은신처 · 오피스텔"
	var accent: Color = [profile.cyan, profile.pink, profile.warm][idx % 3]
	# 도로를 향한 두 면에 간판. 문·세이브 지점은 기존 위치를 그대로 사용한다.
	var road_middle := Vector2(City.road_center(center.x), City.road_center(center.y))
	var front_y := r.position.y + 9 if r.get_center().y > road_middle.y else r.end.y - 35
	var width := minf(r.size.x - 36, 170)
	_sign(Rect2(r.position.x + 18, front_y, width, 26), sign_text, accent)
	if shops and r.size.x > 360:
		_sign(Rect2(r.position.x + 205, front_y, 155, 26), profile.signs[(idx + 3) % profile.signs.size()], profile.warm)
	# 주거 건물에는 업소 간판 대신 건물 용도를 표시한다.
	var vert_text: String = profile.shop_vertical[idx % profile.shop_vertical.size()]
	if residential:
		vert_text = "주거"
	elif business:
		vert_text = "업무" if style == &"office" else "오피스텔"
	elif not shops:
		vert_text = "물류" if style == &"warehouse" else "공방"
	if r == city.hq:
		vert_text = "금강개발"
	elif r == city.hideout:
		vert_text = "은신처"
	var side_x := r.position.x + 6 if r.get_center().x > road_middle.x else r.end.x - 30
	var vertical := Rect2(side_x, r.position.y + 65, 24, 24 * vert_text.length() + 12)
	draw_rect(vertical.grow(2), Color("151923"))
	draw_rect(vertical, accent.darkened(0.65))
	draw_rect(vertical.grow(-2), accent, false, 1)
	for k in vert_text.length():
		draw_string(_font, vertical.position + Vector2(3, 24 + k * 24), vert_text[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, accent.lightened(0.6))
	lights.append({"pos": vertical.get_center(), "color": accent, "size": Vector2(110, 165), "strength": 0.5})
	# 빛은 도로 가까운 간판에서 보도로만 짧게 번진다.
	var reflection := Vector2(side_x - 49 if side_x < r.get_center().x else side_x + 67, vertical.get_center().y)
	lights.append({"pos": reflection, "color": accent, "size": Vector2(75, 190), "strength": 0.16})
	for k in 24:
		var p := reflection + Vector2(rng.randf_range(-12, 12), k * 5 - 55)
		draw_line(p, p + Vector2(rng.randf_range(3, 16), 0), Color(accent, 0.08 + rng.randf() * 0.12), 1)


func _facade_details(r: Rect2, roof: Rect2, style: StringName, idx: int) -> void:
	# 창·차양은 충돌 사각형 안에 배치해 보행 공간을 가리지 않는다.
	var band := Rect2(r.position.x + 7, roof.end.y + 2, r.size.x - 25, 32)
	if style in [&"commercial", &"mixed", &"gosiwon"]:
		for x in range(int(band.position.x), int(band.end.x) - 42, 58):
			var shop := Rect2(x, band.position.y, 52, 30)
			draw_rect(shop, Color("101b26"))
			draw_rect(shop.grow(-3), Color(profile.warm, 0.3))
			for pane in 3:
				draw_line(shop.position + Vector2(5 + pane * 16, 5), shop.position + Vector2(5 + pane * 16, 27), Color("273d48"), 2)
			var awning := Rect2(shop.position, Vector2(52, 7))
			draw_rect(awning, Color("6f3449") if idx % 2 == 0 else Color("356361"))
			for stripe in 6:
				draw_rect(Rect2(awning.position + Vector2(stripe * 9, 0), Vector2(3, 7)), Color("b5ac95"))
	elif style in [&"office", &"officetel"]:
		draw_rect(band, Color("19303f"))
		for x in range(int(band.position.x), int(band.end.x) - 10, 15):
			for row in 3:
				var tint := Color(profile.warm, 0.35) if (x / 15 + row + idx) % 5 == 0 else Color("365768")
				draw_rect(Rect2(x + 2, band.position.y + row * 10 + 2, 10, 7), tint)
		# 옥상 채광창으로 주거용 평지붕과 실루엣을 구분한다.
		var skylight := Rect2(roof.get_center() - Vector2(36, 22), Vector2(72, 44))
		draw_rect(skylight.grow(3), Color("14242d"))
		draw_rect(skylight, Color("385867"))
		for k in 5:
			draw_line(skylight.position + Vector2(k * 18, 0), skylight.position + Vector2(k * 18, 44), Color("8b9e9c"), 2)
	elif style in [&"apt", &"villa", &"house", &"rowhouse", &"oneroom", &"jjokbang"]:
		for x in range(int(band.position.x), int(band.end.x) - 30, 42):
			var balcony := Rect2(x, band.position.y + 3, 32, 25)
			draw_rect(balcony, Color("171f27"))
			draw_rect(Rect2(x + 5, band.position.y + 5, 20, 13), Color(profile.warm, 0.28))
			draw_line(balcony.position + Vector2(0, 19), balcony.position + Vector2(32, 19), Color("919b94"), 2)
			for rail in 5:
				draw_line(balcony.position + Vector2(rail * 7 + 2, 19), balcony.position + Vector2(rail * 7 + 2, 25), Color("677779"), 1)
	elif style in [&"warehouse", &"factory"]:
		for x in range(int(roof.position.x) + 10, int(roof.end.x) - 5, 12):
			draw_line(Vector2(x, roof.position.y + 8), Vector2(x, roof.end.y - 8), Color(0.7, 0.75, 0.8, 0.2), 2)
		var shutter := Rect2(band.get_center() - Vector2(35, 14), Vector2(70, 28))
		draw_rect(shutter, Color("53616b"))
		for k in 7:
			draw_line(shutter.position + Vector2(0, k * 4), shutter.position + Vector2(70, k * 4), Color("26333b"), 1)


func _aircon(p: Vector2, color: Color) -> void:
	draw_rect(Rect2(p + Vector2(3, 4), Vector2(33, 22)), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(p, Vector2(32, 20)), color.lightened(0.14))
	draw_rect(Rect2(p + Vector2.ONE * 2, Vector2(28, 16)), color.darkened(0.12))
	draw_circle(p + Vector2(10, 10), 6, Color("26333b"))
	draw_arc(p + Vector2(10, 10), 4, 0, TAU, 12, color.lightened(0.3), 1)
	for k in 5:
		draw_line(p + Vector2(20, 4 + k * 3), p + Vector2(28, 4 + k * 3), color.lightened(0.1), 1)


func _sign(r: Rect2, text: String, color: Color) -> void:
	draw_rect(r.grow(3), Color("101821"))
	draw_rect(r, color.darkened(0.78))
	draw_rect(r.grow(-2), color, false, 1)
	var font_size := 18 if text.length() < 9 else 15
	var text_width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(_font, Vector2(r.get_center().x - text_width * 0.5, r.position.y + 20), text,
		HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 6, font_size, color.lightened(0.7))
	lights.append({"pos": r.get_center(), "color": color, "size": r.size + Vector2(70, 65), "strength": 0.52})


func _lamp(p: Vector2) -> void:
	draw_line(p + Vector2(4, 4), p + Vector2(20, 10), Color(0, 0, 0, 0.3), 4)
	draw_circle(p, 3, Color("83938b"))
	draw_line(p, p + Vector2(0, -12), Color("626e73"), 2)
	draw_rect(Rect2(p + Vector2(-4, -15), Vector2(8, 4)), profile.warm.lightened(0.7))
	lights.append({"pos": p, "color": profile.warm, "size": Vector2(180, 180), "strength": 0.25})


func _draw_lights() -> void:
	for light in lights:
		var size: Vector2 = light.size
		light_layer.draw_texture_rect(glow, Rect2(light.pos - size * 0.5, size), false,
			Color(light.color, light.strength))
