class_name BuildingDrawer
## 건물을 위에서 본 모습으로 그린다 (BuildingType.style마다 다른 지붕·간판). 노드 없는 그리기 함수 모음.
## seed는 건물 번호 — 같은 건물은 늘 같은 색·간판·소품.

const SHADOW := Color(0, 0, 0, 0.4)
## false면 건물 밑 그림자를 그리지 않는다 (2.5D 지붕은 공중에 그리므로)
static var shadows := true


static func draw(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int, font: Font) -> void:
	var roof: Color = t.roof_colors[seed % t.roof_colors.size()]
	if t.solid and shadows:
		ci.draw_rect(Rect2(r.position + Vector2(10, 12), r.size), SHADOW)
	match t.style:
		&"mixed": _mixed(ci, r, t, seed, font, roof)
		&"office": _office(ci, r, t, seed, font, roof)
		&"officetel": _officetel(ci, r, t, seed, font, roof)
		&"apt": _apt(ci, r, t, seed, font, roof)
		&"villa": _villa(ci, r, t, seed, font, roof)
		&"gosiwon": _gosiwon(ci, r, t, seed, font, roof)
		&"warehouse": _warehouse(ci, r, t, seed, font, roof)
		&"house": _house(ci, r, t, seed, font, roof)
		&"rowhouse": _rowhouse(ci, r, t, seed, font, roof)
		&"oneroom": _oneroom(ci, r, t, seed, font, roof)
		&"factory": _factory(ci, r, t, seed, font, roof)
		&"hanok": _hanok(ci, r, t, seed, font, roof)
		&"jjokbang": _jjokbang(ci, r, t, seed, font, roof)
		&"campsite": _campsite(ci, r, t, seed, font, roof)
		&"park": _park(ci, r, t, seed, font, roof)
		_: _commercial(ci, r, t, seed, font, roof)


static func _pick(t: BuildingType, seed: int, k := 0) -> String:
	return t.signs[(seed + k) % t.signs.size()] if not t.signs.is_empty() else ""


## 네온 간판 하나 (아래쪽 면 왼쪽부터 x만큼)
static func _sign(ci: CanvasItem, r: Rect2, font: Font, text: String, color: Color, x := 8.0, size := 15) -> void:
	var w := minf(r.size.x - 16, 18.0 * text.length() + 24)
	var sign := Rect2(r.position.x + x, r.end.y - 26, w, 20)
	ci.draw_rect(sign.grow(4), Color(color, 0.18))
	ci.draw_rect(sign, color.darkened(0.55))
	ci.draw_rect(sign, color, false, 2.0)
	ci.draw_string(font, Vector2(sign.position.x, sign.end.y - 4), text, HORIZONTAL_ALIGNMENT_CENTER, sign.size.x, size, color.lightened(0.5))


## 세로 간판 (오른쪽 면)
static func _vertical_sign(ci: CanvasItem, r: Rect2, font: Font, text: String, color: Color) -> void:
	var n := text.length()
	var sign := Rect2(r.end.x - 26, r.position.y + 16, 20, 18 * n + 8)
	ci.draw_rect(sign.grow(3), Color(color, 0.18))
	ci.draw_rect(sign, color.darkened(0.6))
	ci.draw_rect(sign, color, false, 2.0)
	for k in n:
		ci.draw_string(font, Vector2(sign.position.x, sign.position.y + 20 + k * 18), text[k],
			HORIZONTAL_ALIGNMENT_CENTER, sign.size.x, 15, color.lightened(0.5))


## 옥상 실외기·물탱크
static func _rooftop(ci: CanvasItem, r: Rect2, seed: int, roof: Color, n := 3) -> void:
	for k in n:
		var h := (seed * 31 + k * 17) % 100 / 100.0
		var v := (seed * 47 + k * 29) % 100 / 100.0
		var pos := r.position + Vector2(20 + h * (r.size.x - 60), 20 + v * (r.size.y - 70))
		ci.draw_rect(Rect2(pos, Vector2(22, 16)), roof.darkened(0.25))
		ci.draw_rect(Rect2(pos + Vector2(3, 3), Vector2(16, 10)), roof.lightened(0.15), false, 1.0)


## 상가 건물: 간판이 덕지덕지
static func _commercial(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int, font: Font, roof: Color) -> void:
	ci.draw_rect(r, roof)
	ci.draw_rect(r.grow(-6), roof.lightened(0.06), false, 2.0)
	ci.draw_rect(r, roof.darkened(0.45), false, 3.0)
	_rooftop(ci, r, seed, roof)
	var colors := City.NEON
	_sign(ci, r, font, _pick(t, seed), colors[seed % colors.size()])
	if r.size.x > 200:
		var second := _pick(t, seed, 3)
		_sign(ci, r, font, second, colors[(seed + 2) % colors.size()], r.size.x - 18.0 * second.length() - 34)
	_vertical_sign(ci, r, font, _pick(t, seed, 1), colors[(seed + 1) % colors.size()])


## 상가주택: 지붕 위 빨랫줄·장독, 1층 가게 간판 하나
static func _mixed(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int, font: Font, roof: Color) -> void:
	ci.draw_rect(r, roof)
	ci.draw_rect(Rect2(r.position + Vector2(10, 10), r.size * Vector2(0.55, 0.45)), roof.lightened(0.08))
	ci.draw_rect(r, roof.darkened(0.45), false, 3.0)
	var y := r.position.y + r.size.y * 0.62
	ci.draw_line(Vector2(r.position.x + 16, y), Vector2(r.end.x - 16, y), Color(0.85, 0.85, 0.8, 0.6), 1.0)
	for k in 4:
		ci.draw_circle(Vector2(r.position.x + 30 + k * 16, r.position.y + r.size.y * 0.25), 6.0, Color(0.35, 0.18, 0.1))
	_sign(ci, r, font, _pick(t, seed), t.accent)


## 사무실 건물: 유리 커튼월, 옥상 이름
static func _office(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int, font: Font, roof: Color) -> void:
	ci.draw_rect(r, roof)
	var step := 22.0
	var x := r.position.x + 10
	while x < r.end.x - 10:
		ci.draw_line(Vector2(x, r.position.y + 8), Vector2(x, r.end.y - 8), Color(t.accent, 0.18), 2.0)
		x += step
	var y := r.position.y + 10
	while y < r.end.y - 10:
		ci.draw_line(Vector2(r.position.x + 8, y), Vector2(r.end.x - 8, y), Color(0.05, 0.08, 0.12, 0.6), 1.0)
		y += step
	ci.draw_rect(r.grow(-6), Color(t.accent, 0.5), false, 2.0)
	ci.draw_rect(r, roof.darkened(0.5), false, 3.0)
	var name := _pick(t, seed)
	ci.draw_string(font, r.get_center() + Vector2(-r.size.x * 0.5, 10), name, HORIZONTAL_ALIGNMENT_CENTER,
		r.size.x, 28 if r.size.x > 300 else 20, Color(t.accent, 0.45))
	_sign(ci, r, font, name, t.accent)


## 오피스텔: 촘촘한 창, 세로 간판
static func _officetel(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int, font: Font, roof: Color) -> void:
	ci.draw_rect(r, roof)
	var cols := 3
	for row in 6:
		for col in cols:
			var cell := Rect2(r.position + Vector2(14 + col * (r.size.x - 40) / cols, 20 + row * (r.size.y - 80) / 6.0),
				Vector2((r.size.x - 40) / cols - 10, 16))
			ci.draw_rect(cell, roof.lightened(0.1))
	ci.draw_rect(r, roof.darkened(0.45), false, 3.0)
	_vertical_sign(ci, r, font, "오피스텔", t.accent)
	_sign(ci, r, font, _pick(t, seed), t.accent)


## 아파트 단지: 판상형 동 두세 개와 동 번호
static func _apt(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int, font: Font, roof: Color) -> void:
	ci.draw_rect(r, roof.darkened(0.35))
	var n := 3
	var gap := 14.0
	var h := (r.size.y - gap * (n + 1)) / n
	var block := _pick(t, seed)
	for k in n:
		var slab := Rect2(r.position.x + 14, r.position.y + gap + k * (h + gap), r.size.x - 28, h)
		ci.draw_rect(slab, roof)
		ci.draw_rect(Rect2(slab.position, Vector2(slab.size.x, 6)), roof.darkened(0.15))
		for x in range(int(slab.position.x) + 30, int(slab.end.x) - 30, 70):
			ci.draw_rect(Rect2(x, slab.position.y + 14, 30, 18), roof.darkened(0.12))
		ci.draw_rect(slab, roof.darkened(0.5), false, 2.0)
		ci.draw_string(font, Vector2(slab.position.x, slab.get_center().y + 12), "%s0%d동" % [block, k + 1],
			HORIZONTAL_ALIGNMENT_CENTER, slab.size.x, 30, t.accent)
	ci.draw_rect(r, roof.darkened(0.6), false, 3.0)


## 빌라: 붉은 벽돌, 아래쪽 필로티 주차칸
static func _villa(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int, font: Font, roof: Color) -> void:
	ci.draw_rect(r, roof)
	var y := r.position.y + 6
	var row := 0
	while y < r.end.y - 40:
		var off := 0.0 if row % 2 == 0 else 14.0
		var x := r.position.x + 6 + off
		while x < r.end.x - 20:
			ci.draw_rect(Rect2(x, y, 26, 10), roof.lightened(0.06), false, 1.0)
			x += 28
		y += 12
		row += 1
	var pilotis := Rect2(r.position.x, r.end.y - 38, r.size.x, 38)
	ci.draw_rect(pilotis, Color(0.18, 0.18, 0.2))
	var px := pilotis.position.x + 30
	while px < pilotis.end.x - 10:
		ci.draw_line(Vector2(px, pilotis.position.y + 4), Vector2(px, pilotis.end.y - 2), Color(0.85, 0.85, 0.85, 0.5), 2.0)
		px += 34
	ci.draw_rect(r, roof.darkened(0.45), false, 3.0)
	var name := _pick(t, seed)
	ci.draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.45), name,
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, Color(t.accent, 0.8))


## 고시원: 좁은 창이 다닥다닥, 세로 간판
static func _gosiwon(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int, font: Font, roof: Color) -> void:
	ci.draw_rect(r, roof)
	for row in 8:
		for col in 6:
			var cell := Rect2(r.position + Vector2(12 + col * (r.size.x - 50) / 6.0, 14 + row * (r.size.y - 60) / 8.0), Vector2(8, 10))
			ci.draw_rect(cell, Color(0.95, 0.9, 0.6, 0.35) if (row * 7 + col + seed) % 3 == 0 else roof.darkened(0.25))
	ci.draw_rect(r, roof.darkened(0.45), false, 3.0)
	_vertical_sign(ci, r, font, "고시원", t.accent)
	_sign(ci, r, font, _pick(t, seed), t.accent, 8.0, 13)


## 창고: 골함석 지붕, 위쪽 셔터
static func _warehouse(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int, font: Font, roof: Color) -> void:
	ci.draw_rect(r, roof)
	var x := r.position.x + 12
	while x < r.end.x - 8:
		ci.draw_line(Vector2(x, r.position.y + 6), Vector2(x, r.end.y - 6), roof.darkened(0.2), 3.0)
		x += 16
	ci.draw_rect(r, roof.darkened(0.5), false, 3.0)
	var doors := maxi(1, int(r.size.x / 180.0))
	for k in doors:
		var dx := r.position.x + r.size.x * (k + 0.5) / doors
		ci.draw_rect(Rect2(dx - 34, r.position.y, 68, 12), t.accent.darkened(0.1))
	_sign(ci, r, font, _pick(t, seed), t.accent)


## 단독주택: 마당과 담장, 기와(슬레이트) 지붕 한 채
static func _house(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int, font: Font, roof: Color) -> void:
	ci.draw_rect(r, Color(0.26, 0.32, 0.24))
	ci.draw_rect(r, Color(0.55, 0.52, 0.48), false, 5.0)
	var home := Rect2(r.position + r.size * Vector2(0.12, 0.1), r.size * Vector2(0.76, 0.55))
	ci.draw_rect(Rect2(home.position + Vector2(6, 8), home.size), SHADOW)
	ci.draw_rect(home, roof)
	ci.draw_line(Vector2(home.position.x, home.get_center().y), Vector2(home.end.x, home.get_center().y), roof.darkened(0.35), 3.0)
	var y := home.position.y + 8
	while y < home.end.y - 4:
		ci.draw_line(Vector2(home.position.x + 4, y), Vector2(home.end.x - 4, y), roof.lightened(0.08), 1.0)
		y += 9
	ci.draw_rect(home, roof.darkened(0.5), false, 2.0)
	# 마당의 나무 한 그루와 대문
	ci.draw_circle(r.position + r.size * Vector2(0.25, 0.82), minf(r.size.x, r.size.y) * 0.09, Color(0.18, 0.42, 0.2))
	ci.draw_rect(Rect2(r.get_center().x - 16, r.end.y - 6, 32, 6), Color(0.45, 0.3, 0.2))
	ci.draw_string(font, Vector2(r.position.x, r.end.y - 14), _pick(t, seed), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 10, 13, Color(t.accent, 0.8))


## 연립주택: 붉은 기와 3층 두 동, 가·나·다동
static func _rowhouse(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int, font: Font, roof: Color) -> void:
	ci.draw_rect(r, roof.darkened(0.3))
	var n := 2 if r.size.y > r.size.x * 0.8 else 1
	var gap := 12.0
	var h := (r.size.y - gap * (n + 1)) / n
	for k in n:
		var slab := Rect2(r.position.x + 10, r.position.y + gap + k * (h + gap), r.size.x - 20, h)
		ci.draw_rect(slab, roof)
		ci.draw_line(Vector2(slab.position.x, slab.get_center().y), Vector2(slab.end.x, slab.get_center().y), roof.darkened(0.35), 4.0)
		var x := slab.position.x + 6
		while x < slab.end.x - 6:
			ci.draw_line(Vector2(x, slab.position.y + 4), Vector2(x, slab.end.y - 4), roof.lightened(0.07), 1.0)
			x += 10
		ci.draw_rect(slab, roof.darkened(0.5), false, 2.0)
		ci.draw_string(font, Vector2(slab.position.x, slab.get_center().y + 8), _pick(t, seed, k),
			HORIZONTAL_ALIGNMENT_CENTER, slab.size.x, 18, t.accent)
	ci.draw_rect(r, roof.darkened(0.6), false, 3.0)


## 원룸: 4층 작은 건물, "원룸" 현수막과 실외기
static func _oneroom(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int, font: Font, roof: Color) -> void:
	ci.draw_rect(r, roof)
	for row in 4:
		for col in 3:
			var cell := Rect2(r.position + Vector2(14 + col * (r.size.x - 40) / 3.0, 16 + row * (r.size.y - 60) / 4.0),
				Vector2((r.size.x - 40) / 3.0 - 14, 14))
			ci.draw_rect(cell, roof.lightened(0.12))
	_rooftop(ci, r, seed, roof, 2)
	ci.draw_rect(r, roof.darkened(0.45), false, 3.0)
	var banner := Rect2(r.position.x + 8, r.get_center().y - 12, r.size.x - 16, 22)
	ci.draw_rect(banner, Color(0.95, 0.95, 0.9))
	ci.draw_string(font, Vector2(banner.position.x, banner.end.y - 5), _pick(t, seed), HORIZONTAL_ALIGNMENT_CENTER,
		banner.size.x, 14, Color(0.85, 0.15, 0.15))


## 공장: 톱날 지붕, 굴뚝, "OO공업" 간판
static func _factory(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int, font: Font, roof: Color) -> void:
	ci.draw_rect(r, roof)
	var y := r.position.y + 10
	while y < r.end.y - 60:
		ci.draw_rect(Rect2(r.position.x + 10, y, r.size.x - 20, 18), roof.lightened(0.08))
		ci.draw_rect(Rect2(r.position.x + 10, y + 18, r.size.x - 20, 8), Color(0.55, 0.7, 0.8, 0.5))
		y += 34
	ci.draw_rect(r, roof.darkened(0.5), false, 3.0)
	for k in 2:
		var c := r.position + Vector2(r.size.x * (0.72 + 0.14 * k), r.size.y * 0.2)
		ci.draw_circle(c, 22.0, Color(0.3, 0.3, 0.32))
		ci.draw_circle(c, 14.0, Color(0.08, 0.08, 0.08))
		ci.draw_arc(c, 22.0, 0, TAU, 20, Color(0.9, 0.35, 0.2), 4.0)
	_sign(ci, r, font, _pick(t, seed), t.accent, 8.0, 17)


## 한옥: 기와 지붕이 ㅁ자로 둘러싼 마당 (중정)
static func _hanok(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int, font: Font, roof: Color) -> void:
	ci.draw_rect(r, Color(0.62, 0.55, 0.45))
	var court := r.grow(-minf(r.size.x, r.size.y) * 0.3)
	var wing := minf(r.size.x, r.size.y) * 0.22
	var wings := [
		Rect2(r.position + Vector2(8, 8), Vector2(r.size.x - 16, wing)),
		Rect2(Vector2(r.position.x + 8, r.end.y - 8 - wing), Vector2(r.size.x - 16, wing)),
		Rect2(r.position + Vector2(8, 8), Vector2(wing, r.size.y - 16)),
		Rect2(Vector2(r.end.x - 8 - wing, r.position.y + 8), Vector2(wing, r.size.y - 16)),
	]
	for w: Rect2 in wings:
		ci.draw_rect(Rect2(w.position + Vector2(5, 6), w.size), SHADOW)
	for w: Rect2 in wings:
		ci.draw_rect(w, roof)
		var horizontal := w.size.x > w.size.y
		var along := w.size.x if horizontal else w.size.y
		var k := 6.0
		while k < along - 4:
			if horizontal:
				ci.draw_line(Vector2(w.position.x + k, w.position.y + 3), Vector2(w.position.x + k, w.end.y - 3), roof.lightened(0.12), 2.0)
			else:
				ci.draw_line(Vector2(w.position.x + 3, w.position.y + k), Vector2(w.end.x - 3, w.position.y + k), roof.lightened(0.12), 2.0)
			k += 8
		ci.draw_rect(w, Color(0.12, 0.12, 0.13), false, 2.0)
	ci.draw_rect(court, Color(0.7, 0.62, 0.48))
	ci.draw_circle(court.get_center(), minf(court.size.x, court.size.y) * 0.18, Color(0.25, 0.45, 0.22))
	_sign(ci, r, font, _pick(t, seed), t.accent, 8.0, 14)


## 쪽방촌: 낡은 판잣집 지붕이 빽빽하고, 사이로 좁은 골목
static func _jjokbang(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int, font: Font, roof: Color) -> void:
	ci.draw_rect(r, Color(0.2, 0.19, 0.18))
	var cell := 46.0
	var y := r.position.y + 4
	var row := 0
	while y < r.end.y - 10:
		var x := r.position.x + 4 + (row % 2) * 12.0
		var col := 0
		while x < r.end.x - 10:
			var w := minf(cell - 6 + float((seed + row * 5 + col * 3) % 3) * 4.0, r.end.x - 4 - x)
			var h := minf(cell - 8, r.end.y - 4 - y)
			var shade: Color = t.roof_colors[(seed + row + col) % t.roof_colors.size()]
			ci.draw_rect(Rect2(x, y, w, h), shade.darkened(float((row * 3 + col) % 4) * 0.06))
			ci.draw_line(Vector2(x + 2, y + h * 0.5), Vector2(x + w - 2, y + h * 0.5), shade.darkened(0.3), 1.0)
			# 지붕을 누르는 타이어·벽돌
			if (row + col + seed) % 4 == 0:
				ci.draw_circle(Vector2(x + w * 0.5, y + h * 0.35), 4.0, Color(0.08, 0.08, 0.08))
			x += w + 6
			col += 1
		y += cell
		row += 1
	ci.draw_rect(r, Color(0.1, 0.1, 0.1), false, 2.0)


## 캠핑장: 잔디 위 카라반·텐트·모닥불
static func _campsite(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int, font: Font, roof: Color) -> void:
	ci.draw_rect(r, roof)
	ci.draw_rect(r, Color(0.45, 0.4, 0.3), false, 4.0)
	var spots := int(r.size.x / 120.0) * int(r.size.y / 140.0)
	for k in spots:
		var cols := int(r.size.x / 120.0)
		var p := r.position + Vector2(20 + (k % cols) * 120, 24 + (k / cols) * 140)
		if (k + seed) % 3 == 0:
			# 텐트
			var tent := PackedVector2Array([p + Vector2(10, 56), p + Vector2(45, 6), p + Vector2(80, 56)])
			ci.draw_colored_polygon(tent, NEON_TENT[(k + seed) % NEON_TENT.size()])
			ci.draw_line(p + Vector2(45, 6), p + Vector2(45, 56), Color(0, 0, 0, 0.4), 2.0)
		else:
			# 카라반
			var van := Rect2(p, Vector2(84, 46))
			ci.draw_rect(Rect2(van.position + Vector2(4, 5), van.size), SHADOW)
			ci.draw_rect(van, Color(0.92, 0.9, 0.84))
			ci.draw_rect(Rect2(van.position + Vector2(6, 6), Vector2(72, 10)), Color(0.35, 0.55, 0.75))
			ci.draw_rect(van, Color(0.4, 0.4, 0.4), false, 2.0)
		var fire := p + Vector2(60, 90)
		ci.draw_circle(fire, 9.0, Color(0.25, 0.2, 0.15))
		ci.draw_circle(fire, 5.0, t.accent)
	_sign(ci, r, font, _pick(t, seed), t.accent, 8.0, 14)

const NEON_TENT := [Color(0.95, 0.45, 0.2), Color(0.25, 0.6, 0.95), Color(0.95, 0.85, 0.25)]


## 공원: 잔디, 산책로, 나무 (충돌 없음 — 걸어서·차로 지나간다)
static func _park(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int, font: Font, roof: Color) -> void:
	ci.draw_rect(r, roof)
	var path := Color(0.62, 0.58, 0.5)
	ci.draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), path, 14.0)
	ci.draw_line(Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y), path, 10.0)
	var n := int(r.size.x * r.size.y / 9000.0)
	for k in n:
		var h := float((seed * 31 + k * 57) % 100) / 100.0
		var v := float((seed * 17 + k * 83) % 100) / 100.0
		var c := r.position + Vector2(16 + h * (r.size.x - 32), 16 + v * (r.size.y - 32))
		if absf(c.y - r.get_center().y) < 22 or absf(c.x - r.get_center().x) < 20:
			continue
		ci.draw_circle(c + Vector2(4, 5), 15.0, SHADOW)
		ci.draw_circle(c, 15.0, Color(0.16, 0.42, 0.2))
		ci.draw_circle(c - Vector2(4, 4), 8.0, Color(0.24, 0.55, 0.28))
	if r.size.x > 200:
		ci.draw_string(font, r.get_center() + Vector2(-r.size.x * 0.5, -20), _pick(t, seed), HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x, 20, Color(1, 1, 1, 0.5))
