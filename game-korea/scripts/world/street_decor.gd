class_name StreetDecor
## 거리 건물(StreetBuilding) 전용 그림: 벽 장식(sd_*)·지붕 그림(sd_*)·밤 불빛. 월드 좌표에서 같은 투영을 쓴다.
## 간판·네온처럼 밤에 빛나는 벽 장식은 BuildingView.LIGHT_DECOS에 넣어 불빛 조각이 그린다(낮에는 똑같이 보인다).

## 벽 없이 지붕 그림에서 통째로 그리는 것
const BARE: Array[StringName] = [&"sd_pine", &"sd_bollard", &"sd_cross", &"sd_barrier", &"sd_void", &"sd_goal", &"sd_bikes",
	&"sd_bags", &"sd_stack", &"sd_pole", &"sd_wires", &"sd_fountain", &"sd_planter"]
## 불빛 조각에서 밤 불빛을 그리는 지붕
const GLOWS: Array[StringName] = [&"sd_cross", &"sd_deck_top"]
## 밤에 빛나는 벽 장식 (BuildingView.LIGHT_DECOS에 더한다)
const LIGHT: Array[StringName] = [&"sd_lancets_glow", &"sd_church_front_glow", &"sd_lobby_glow", &"sd_arrows", &"sd_roof_sign",
	&"sd_gas_band", &"sd_fascia_glow", &"sd_price", &"sd_nightlife", &"sd_neon_trim", &"sd_deck_lamps", &"sd_deck_entry",
	&"sd_psign", &"sd_metro_band", &"sd_line_pillar", &"sd_shelter", &"sd_fire_band", &"sd_tower_119", &"sd_podium_glow",
	&"sd_crown_sign", &"sd_blade", &"sd_notice", &"sd_kiosk"]

const IRON := Color("2b2f33")
const TEAL := Color("1c9a8c")
const AMBER := Color("f0b65a")
const CAR_COLORS := [Color("d8d8d4"), Color("2b2f36"), Color("8c9399"), Color("b23a34"), Color("2f5d95"), Color("e9e6dc"), Color("3d4a3f")]


# ── Codex 1차: 곡면 유리 캐노피·네온판 ─────────────────────

static func _arch(r: Rect2, height: float, rise: float, u: float, v: float) -> Vector2:
	return Vector2(lerpf(r.position.x,r.end.x,u),lerpf(r.position.y,r.end.y,v)) + IsoView.lift(height + sin(u*PI)*rise)

static func canopy(view: BuildingView, p: BuildingModel.Piece) -> void:
	var r := p.rect
	# Faceted glass shell, then ribs; panels stay above the walkable stair opening.
	for j in 8:
		var u0 := j/8.0
		var u1 := (j+1)/8.0
		var c := Color("547e88").lightened(.12*sin(u0*PI))
		view.draw_colored_polygon(PackedVector2Array([_arch(r,p.h1,p.rise,u0,0),_arch(r,p.h1,p.rise,u1,0),_arch(r,p.h1,p.rise,u1,1),_arch(r,p.h1,p.rise,u0,1)]),Color(c,.82))
		view.draw_line(_arch(r,p.h1,p.rise,u0,0),_arch(r,p.h1,p.rise,u0,1),Color("394f55"),2)
	for k in 7:
		var rib := PackedVector2Array()
		for j in 17:
			rib.append(_arch(r,p.h1,p.rise,j/16.0,k/6.0))
		view.draw_polyline(rib,Color("b0b9b5") if k==6 else Color("3d555d"),2.5)
	for j in [2,5]:
		view.draw_line(_arch(r,p.h1,p.rise,j/8.0,.12),_arch(r,p.h1,p.rise,j/8.0,.75),Color(.78,.91,.94,.45),3)

static func neon(view: BuildingView, text: String, center: float, top: float, width: float, height: float, color: Color, vertical := false) -> void:
	if text.is_empty() or width < 8 or height < 8:
		return
	# Ownership at the right edge avoids a later wall segment painting over the plate.
	if not view._in(minf(view._len-.01,center+width*.5)):
		return
	view.draw_set_transform_matrix(view._frame(center-width*.5,width,top))
	var box := Rect2(0,0,width,height)
	view.draw_rect(box,Color("232831"))
	for stroke in [9.0,5.0,2.0]:
		view.draw_rect(box.grow(1),Color(color,.07 if stroke>2 else .95),false,stroke)
	var font := ThemeDB.fallback_font
	if vertical:
		var cell := (height-8)/text.length()
		var size := maxi(8,int(minf(width*.74,cell*.78)))
		for i in text.length():
			SpecialDecor._bold(view,font,Vector2(0,4+cell*(i+.76)),text[i],width,size,Color("ffe8e6"))
	else:
		var size := maxi(8,int(height*.57))
		var tw := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
		if tw>width-8:
			size=maxi(7,int(size*(width-8)/tw))
		SpecialDecor._bold(view,font,Vector2(0,height*.5+size*.35),text,width,size,Color("ffe8e6"))
	view.draw_set_transform(Vector2.ZERO,0,Vector2.ONE)


# ── 공용 ──────────────────────────────────────────────────

## 벽 판 좌표계 시작 (s0~s0+w, 위 z). 이 조각이 오른쪽 끝을 가질 때만 그린다
static func _begin(v: BuildingView, s0: float, w: float, z: float) -> bool:
	if not SpecialDecor._owns(v, s0 + w):
		return false
	v.draw_set_transform_matrix(v._frame(s0, w, z))
	return true


static func _end(v: BuildingView) -> void:
	v.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _text(v: BuildingView, at: Vector2, text: String, w: float, size: int, color: Color, outline := Color(0, 0, 0, 0.35)) -> void:
	SpecialDecor._bold(v, ThemeDB.fallback_font, at, text, w, size, color, outline)


## 밤에만 보이는 삼각형 (뾰족 아치 머리). 점은 벽 위 (s, z)
static func _glow_tri(v: BuildingView, a: Vector2, b: Vector2, c: Vector2, color: Color, turn := 0.0) -> void:
	if not (v._in(a.x) or v._in(b.x)):
		return
	var uv := Vector2(2.0, 2.0 + turn)
	v.draw_primitive(PackedVector2Array([v._pt(a.x, a.y), v._pt(b.x, b.y), v._pt(c.x, c.y)]), PackedColorArray([color]), PackedVector2Array([uv, uv, uv]))


static func _tri(v: BuildingView, a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	if not (v._in(a.x) or v._in(b.x)):
		return
	v.draw_primitive(PackedVector2Array([v._pt(a.x, a.y), v._pt(b.x, b.y), v._pt(c.x, c.y)]), PackedColorArray([color]), PackedVector2Array())


## 작은 상자 (남·동 면과 윗면) — 지붕 그림 안의 소품
static func _box3(v: BuildingView, q: Rect2, h0: float, h1: float, top: Color) -> void:
	var sw := Vector2(q.position.x, q.end.y)
	var se := q.end
	var ne := Vector2(q.end.x, q.position.y)
	v.draw_colored_polygon(PackedVector2Array([sw + IsoView.lift(h0), se + IsoView.lift(h0), se + IsoView.lift(h1), sw + IsoView.lift(h1)]), top.darkened(0.18))
	v.draw_colored_polygon(PackedVector2Array([se + IsoView.lift(h0), ne + IsoView.lift(h0), ne + IsoView.lift(h1), se + IsoView.lift(h1)]), top.darkened(0.32))
	v.draw_colored_polygon(v._corners(q, h1), top)


## 로고: 흰 원에 청록 테두리, 주황 물방울 (판 좌표계)
static func _logo(v: BuildingView, c: Vector2, r: float) -> void:
	v.draw_circle(c, r, Color("f6f6f0"))
	v.draw_arc(c, r, 0, TAU, 20, TEAL, maxf(1.5, r * 0.22))
	v.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.62), c + Vector2(r * 0.36, r * 0.1), c + Vector2(0, r * 0.5), c + Vector2(-r * 0.36, r * 0.1)]), Color("ef6b2a"))
	v.draw_circle(c + Vector2(0, r * 0.12), r * 0.34, Color("ef6b2a"))


# ── 벽 장식 ───────────────────────────────────────────────

static func deco(v: BuildingView, d: StringName, south: bool) -> void:
	var p := v._p
	var h := p.h1 - p.h0
	var L := v._len
	var sh := v._shade
	match d:
		&"sd_brick":
			var z := 4.0
			while z < h - 1.0:
				v._hline(z, p.wall.darkened(0.16 + sh * 0.2), 0.8)
				z += 4.0
			v._quad(0, L, 0, 4, p.wall.darkened(0.3))
			for zz in range(6, int(h) - 4, 10):
				v._quad(0, 5, zz, zz + 6, p.wall.lightened(0.14).darkened(sh))
				v._quad(L - 5, L, zz, zz + 6, p.wall.lightened(0.14).darkened(sh))
		&"sd_lancets", &"sd_lancets_glow":
			var glow := d == &"sd_lancets_glow"
			var n := maxi(1, int(L / 44.0))
			for k in n:
				var c := (k + 0.5) * L / n
				var z0 := 12.0
				var z1 := h - 18.0
				if z1 - z0 < 12.0:
					continue
				var turn := BuildingModel.hash01(p.seed, k) * 0.4
				if glow:
					var cols := [Color("e8b45c"), Color("d9573f"), Color("4f7fd6"), Color("e8b45c")]
					var band := (z1 - z0) / 4.0
					for j in 4:
						v._glow(c - 6, c + 6, z0 + j * band, z0 + (j + 1) * band, (cols[j] as Color).darkened(sh * 0.3), turn)
					_glow_tri(v, Vector2(c - 6, z1), Vector2(c + 6, z1), Vector2(c, z1 + 9), Color("e8b45c").darkened(sh * 0.3), turn)
				else:
					v._quad(c - 8, c + 8, z0 - 2, z1, Color("c9b79c").darkened(sh))
					_tri(v, Vector2(c - 8, z1), Vector2(c + 8, z1), Vector2(c, z1 + 12), Color("c9b79c").darkened(sh))
					v._quad(c - 6, c + 6, z0, z1, Color("2b2f3c").darkened(sh * 0.4))
					_tri(v, Vector2(c - 6, z1), Vector2(c + 6, z1), Vector2(c, z1 + 9), Color("2b2f3c").darkened(sh * 0.4))
					v._quad(c - 0.6, c + 0.6, z0, z1 + 6, Color("6d6250"))
					v._hline(lerpf(z0, z1, 0.5), Color("6d6250"), 1.0, c - 6, c + 6)
		&"sd_church_front", &"sd_church_front_glow":
			if not south:
				# 옆면: 좁은 창 두 줄
				for z in [40.0, 84.0]:
					var c := L * 0.5
					if d == &"sd_church_front_glow":
						v._glow(c - 3, c + 3, z, z + 18, AMBER.darkened(sh * 0.3), 0.1)
					else:
						v._quad(c - 4, c + 4, z - 1, z + 19, Color("c9b79c").darkened(sh))
						v._quad(c - 3, c + 3, z, z + 18, Color("2b2f3c"))
				return
			var c := L * 0.5
			if d == &"sd_church_front_glow":
				# 장미창과 문 위 창이 밤에 빛난다
				if v._in(c):
					var at := v._pt(c, 74)
					v.draw_set_transform_matrix(IsoView.screen_frame(at))
					var uv := Vector2(2.0, 2.05)
					var pts := PackedVector2Array()
					for j in 14:
						pts.append(Vector2.from_angle(TAU * j / 14.0) * 10.0)
					var uvs := PackedVector2Array()
					uvs.resize(14)
					uvs.fill(uv)
					v.draw_polygon(pts, PackedColorArray([Color("e9a04c")]), uvs)
					_end(v)
				v._glow(c - 9, c + 9, 30, 38, AMBER, 0.05)
				return
			# 돌 문틀과 아치 나무문
			v._quad(c - 16, c + 16, 0, 40, Color("c9b79c").darkened(sh))
			v._quad(c - 11, c + 11, 0, 28, Color("4a2c1c"))
			v._quad(c - 0.6, c + 0.6, 0, 28, Color("2c1a10"))
			_tri(v, Vector2(c - 11, 28), Vector2(c + 11, 28), Vector2(c, 38), Color("4a2c1c"))
			v._quad(c - 9, c + 9, 30, 36, Color("2b2f3c"))
			for s in [c - 7, c + 7]:
				v._quad(s - 1, s + 1, 10, 14, Color("c8a24a"))   # 문고리
			# 장미창
			if v._in(c):
				var at := v._pt(c, 74)
				v.draw_set_transform_matrix(IsoView.screen_frame(at))
				v.draw_circle(Vector2.ZERO, 13.0, Color("c9b79c").darkened(sh))
				v.draw_circle(Vector2.ZERO, 10.0, Color("2b2f3c"))
				for j in 8:
					v.draw_line(Vector2.ZERO, Vector2.from_angle(TAU * j / 8.0) * 10.0, Color("6d6250"), 1.0)
				v.draw_circle(Vector2.ZERO, 3.0, Color("6d6250"))
				_end(v)
			# 위쪽 쌍둥이 좁은 창
			for s in [c - 8, c + 8]:
				v._quad(s - 3, s + 3, 98, 120, Color("2b2f3c"))
				_tri(v, Vector2(s - 3, 120), Vector2(s + 3, 120), Vector2(s, 125), Color("2b2f3c"))
			v._quad(0, L, 128, 132, Color("c9b79c").darkened(sh))   # 처마 돌띠
		&"sd_belfry":
			var n := 2
			for k in n:
				var c := (k + 0.5) * L / n
				v._quad(c - 6, c + 6, 4, h - 8, Color("1d1f24"))
				_tri(v, Vector2(c - 6, h - 8), Vector2(c + 6, h - 8), Vector2(c, h - 2), Color("1d1f24"))
				for z in range(8, int(h) - 9, 4):
					v._hline(z, Color("4a4038"), 1.0, c - 6, c + 6)
			v._quad(0, L, h - 2, h, Color("c9b79c").darkened(sh))
		&"sd_railing":
			var s := floorf(v._s0 / 6.0) * 6.0
			while s < v._s1:
				if v._in(s):
					v.draw_line(v._pt(s, h), v._pt(s, h + 11), IRON, 1.0)
				s += 6.0
			v._hline(h + 11, IRON, 1.2)
			v._hline(h + 4, IRON, 1.0)
		&"sd_notice":
			if south and _begin(v, 0, L, h):
				var font := ThemeDB.fallback_font
				SpecialDecor._metal(v, Rect2(0, 0, L, 18), Color("1d3b6a"), p.seed)
				_text(v, Vector2(0, 13), p.text, L, 10, Color.WHITE)
				v.draw_line(Vector2(L * 0.3, 18), Vector2(L * 0.3, h), Color("3a3f45"), 2.0)
				v.draw_line(Vector2(L * 0.7, 18), Vector2(L * 0.7, h), Color("3a3f45"), 2.0)
				_end(v)
		&"sd_lobby", &"sd_lobby_glow":
			if not south:
				return
			var c := L * 0.5
			if d == &"sd_lobby_glow":
				v._glow(c - 30, c + 30, 2, 24, Color(1.0, 0.82, 0.55), 0.0)
				v._glow(c - 70, c - 40, 26, 32, Color("ff5aa0"), 0.0)
				return
			v._quad(0, L, 0, h, Color("201b22"))
			v._quad(c - 34, c + 34, 0, 26, Color("8a7a66"))
			v._quad(c - 30, c + 30, 2, 24, Color("d9c08a").darkened(0.4))
			v._quad(c - 0.8, c + 0.8, 2, 24, Color("3a2e26"))
			v._quad(c - 72, c - 38, 25, 33, Color("3a1f2c"))
		&"sd_arrows":
			if not south:
				return
			var w := minf(L * 0.82, 260.0)
			if _begin(v, L * 0.5 - w * 0.5, w, 18):
				v.draw_rect(Rect2(0, 0, w, 16), Color("1c1820"))
				v.draw_rect(Rect2(0, 0, w, 16).grow(1), Color("ff3b6a", 0.9), false, 1.5)
				var chev := Color("3fa9ff")
				for side in [0, 1]:
					for k in 3:
						var x := 10.0 + k * 9.0 if side == 0 else w - 10.0 - k * 9.0
						var dir := -1.0 if side == 0 else 1.0
						v.draw_polyline(PackedVector2Array([Vector2(x - dir * 3, 3), Vector2(x + dir * 3, 8), Vector2(x - dir * 3, 13)]), chev, 2.0)
				_text(v, Vector2(0, 13), "모 텔", w, 12, Color("ffd2dd"), Color(0, 0, 0, 0))
				_end(v)
		&"sd_pipes":
			if south:
				return
			for f in [0.18, 0.82]:
				var s: float = L * f
				if v._in(s):
					v.draw_line(v._pt(s, 0), v._pt(s, h - 2), Color("6c7173").darkened(sh * 0.4), 2.2)
					for z in range(10, int(h), 24):
						v.draw_line(v._pt(s - 2, z), v._pt(s + 2, z), Color("4a4f51"), 1.5)
		&"sd_curtain":
			if not south:
				return
			v._quad(0, L, h - 4, h, Color("2a2430"))
			var cols := [Color("3a6fd8"), Color("d23a5a"), Color("e8e4dc"), Color("2fb38f")]
			var k := 0
			var s := 1.0
			while s < L - 4:
				v._quad(s, s + 4.2, 2 + (k % 3), h - 4, (cols[posmod(k * 7 + int(s / 9.0), cols.size())] as Color).darkened(0.12), 0.5)
				s += 5.0
				k += 1
		&"sd_roof_sign":
			if not south:
				return
			if _begin(v, 0, L, h - 2):
				var box := Rect2(0, 0, L, h - 6)
				v.draw_rect(box, Color("1c1820"))
				for stroke in [8.0, 4.0, 2.0]:
					v.draw_rect(box.grow(1), Color(p.accent, 0.1 if stroke > 2 else 1.0), false, stroke)
				# 왕관
				var c := Vector2(box.size.y * 0.7, box.size.y * 0.5)
				var s := box.size.y * 0.3
				v.draw_colored_polygon(PackedVector2Array([c + Vector2(-s, s * 0.6), c + Vector2(-s, -s * 0.4), c + Vector2(-s * 0.5, s * 0.05),
					c + Vector2(0, -s * 0.7), c + Vector2(s * 0.5, s * 0.05), c + Vector2(s, -s * 0.4), c + Vector2(s, s * 0.6)]), Color("ffd24a"))
				var size := int(box.size.y * 0.66)
				_text(v, Vector2(box.size.y * 1.2, box.size.y * 0.5 + size * 0.36), p.text, box.size.x - box.size.y * 1.4, size, Color("ffe1e6"), Color(p.accent, 0.6))
				_end(v)
		&"sd_gas_shop":
			if south:
				var w := L * 0.62
				v._quad(8, 8 + w, 0, 26, Color("2e3a3f"))
				v._quad(10, 6 + w, 2, 24, Color("cfe4e6").darkened(0.35))
				for k in 4:
					v._hline(6 + k * 5, Color(0.4, 0.3, 0.25, 0.6), 1.0, 12, 4 + w)
				v._quad(8 + w * 0.42, 8 + w * 0.58, 0, 22, Color("8fb7bd").darkened(0.2))
				v._quad(L - 30, L - 12, 0, 24, Color("4a5052"))   # 현금인출기
				v._quad(L - 28, L - 14, 14, 20, Color("2f6fb0"))
			else:
				for k in int(L / 30.0):
					v._quad(8 + k * 30, 24 + k * 30, 12, 24, Color("33454b"))
		&"sd_gas_band":
			if south:
				v._quad(0, L, h - 12, h - 1, TEAL.darkened(sh * 0.3), 1.0)
				v._hline(h - 12, Color("ef6b2a"), 1.5, 0, L, 1.0)
				if _begin(v, 0, L, h - 1):
					_logo(v, Vector2(12, 5.5), 5.0)
					_text(v, Vector2(14, 9.5), p.text, L - 14, 9, Color.WHITE, Color(0, 0, 0, 0))
					_end(v)
		&"sd_wash":
			if south:
				v._quad(10, L - 10, 0, 26, Color("1d2226"))
				for k in 3:
					var s := L * (0.3 + k * 0.2)
					v._quad(s - 3, s + 3, 2, 24, Color("2f7fc0").lightened(0.1 * k))
				if _begin(v, L * 0.2, L * 0.6, h - 1):
					v.draw_rect(Rect2(0, 0, L * 0.6, 7), p.accent)
					_text(v, Vector2(0, 6), p.text, L * 0.6, 6, Color.WHITE, Color(0, 0, 0, 0))
					_end(v)
		&"sd_curb":
			var s := floorf(v._s0 / 6.0) * 6.0
			while s < v._s1:
				v._quad(s, s + 3, 0, h, Color("1d1d1f"))
				s += 6.0
			v._quad(0, L, h - 1, h, Color("e3b023"))
		&"sd_pump":
			v._quad(0, L, 0, h * 0.35, p.accent.darkened(sh * 0.4))
			v._quad(1.5, L - 1.5, h * 0.58, h * 0.86, Color("1a2a2e"))
			v._quad(2.5, L - 2.5, h * 0.66, h * 0.8, Color("57e08f").darkened(0.35))
			v._quad(0, L, h - 2, h, p.accent.darkened(sh * 0.4))
			if south:
				var s := L - 2.0
				if v._in(s):
					v.draw_polyline(PackedVector2Array([v._pt(s, h * 0.5, 1), v._pt(s + 2, h * 0.3, 3), v._pt(s, h * 0.1, 3), v._pt(s - 2, h * 0.24, 2)]), Color("1e2124"), 1.6)
		&"sd_extinguisher":
			v._quad(0, L, h * 0.5, h * 0.7, Color("f2efe6"))
		&"sd_column":
			v._quad(0, L, 0, 9, TEAL.darkened(sh * 0.3))
			v._quad(0, L, 9, 10.5, Color("ef6b2a"))
		&"sd_fascia", &"sd_fascia_glow":
			if d == &"sd_fascia":
				v._quad(0, L, 0, h * 0.55, TEAL.darkened(sh * 0.3))
				v._quad(0, L, h * 0.55, h * 0.7, Color("ef6b2a"))
				return
			if south and _begin(v, L * 0.5 - 60, 120, h + 6):
				_logo(v, Vector2(14, (h + 6) * 0.5), (h + 6) * 0.5 - 0.5)
				_text(v, Vector2(26, h * 0.5 + 7), p.text, 90, int(h * 0.75), Color.WHITE, Color(0, 0, 0, 0.4))
				_end(v)
		&"sd_price":
			if not south:
				return
			if _begin(v, -3, L + 6, h):
				var w := L + 6
				SpecialDecor._metal(v, Rect2(0, 0, w, 22), TEAL, p.seed)
				_logo(v, Vector2(9, 11), 6.0)
				_text(v, Vector2(14, 15), "한빛", w - 14, 9, Color.WHITE, Color(0, 0, 0, 0))
				v.draw_rect(Rect2(0, 22, w, 40), Color("17191c"))
				var rows := [["휘발유", "1680"], ["경유", "1560"], ["LPG", "980"]]
				for k in 3:
					var y := 26.0 + k * 12.0
					_text(v, Vector2(1, y + 7), rows[k][0], w * 0.42, 6, Color("e8e6dc"), Color(0, 0, 0, 0))
					v.draw_rect(Rect2(w * 0.44, y, w * 0.54, 9), Color("2a0d0d"))
					_text(v, Vector2(w * 0.44, y + 8), rows[k][1], w * 0.54, 8, Color("ff4b3a"), Color(0, 0, 0, 0))
				_end(v)
		&"sd_nightlife":
			_nightlife(v, south)
		&"sd_neon_trim":
			if not south:
				var s := L - 1.5
				if v._in(s):
					v.draw_line(v._pt(s, 4), v._pt(s, h - 4), Color("38e0ff"), 1.6)
				return
			var cols := [Color("ff3fb4"), Color("4b7bff"), Color("ffa53e"), Color("38e0ff")]
			for f in range(1, v._floors):
				v._hline(f * v._fh + 1, cols[f % cols.size()], 1.4, L * 0.04, L * 0.96, 1.0)
			for s in [1.5, L - 1.5]:
				if v._in(s):
					v.draw_line(v._pt(s, 4), v._pt(s, h - 4), Color("38e0ff"), 1.6)
		&"sd_deck_open", &"sd_deck_lamps":
			_deck_face(v, d == &"sd_deck_lamps")
		&"sd_deck_entry":
			if south:
				var w := 110.0
				if _begin(v, L * 0.36 - w * 0.5, w, h - 1):
					v.draw_rect(Rect2(0, 0, w, 8), Color("1d4f9c"))
					v.draw_rect(Rect2(2, 1, 8, 6), Color.WHITE)
					_text(v, Vector2(2, 6.5), "P", 8, 7, Color("1d4f9c"), Color(0, 0, 0, 0))
					_text(v, Vector2(12, 7), "입구  IN ↑", w - 14, 7, Color.WHITE, Color(0, 0, 0, 0))
					_end(v)
				if _begin(v, L * 0.72 - 40, 80, h - 1):
					v.draw_rect(Rect2(0, 0, 80, 8), Color("2f3437"))
					_text(v, Vector2(0, 7), "출구  EXIT", 80, 7, Color("ffd24a"), Color(0, 0, 0, 0))
					_end(v)
		&"sd_psign":
			if not south:
				# 옆면 세로 '주차장'
				if _begin(v, L * 0.5 - 9, 18, h - 44):
					v.draw_rect(Rect2(0, 0, 18, 64), Color("1d4f9c"))
					for i in 3:
						_text(v, Vector2(0, 17 + i * 20), "주차장"[i], 18, 13, Color.WHITE, Color(0, 0, 0, 0))
					_end(v)
				return
			var w := minf(L - 6, 40.0)
			if _begin(v, L * 0.5 - w * 0.5, w, h - 4):
				v.draw_rect(Rect2(0, 0, w, w), Color("1d4f9c"))
				v.draw_rect(Rect2(0, 0, w, w).grow(-2), Color.WHITE, false, 2.0)
				_text(v, Vector2(0, w * 0.8), "P", w, int(w * 0.8), Color.WHITE, Color(0, 0, 0, 0))
				v.draw_rect(Rect2(0, w + 4, w, 14), Color("1d4f9c"))
				_text(v, Vector2(0, w + 15), "공영", w, 10, Color.WHITE, Color(0, 0, 0, 0))
				_end(v)
		&"sd_ramp":
			# 비탈 경사로가 비치는 열린 칸
			var k := 0
			for f in range(0, int(h / 30.0)):
				var z0 := f * 30.0 + 8
				v._quad(4, L - 4, z0, z0 + 16, Color("1c1f22"))
				var a := v._pt(4, z0 + (2.0 if f % 2 == 0 else 14.0))
				var b := v._pt(L - 4, z0 + (14.0 if f % 2 == 0 else 2.0))
				if v._in(L * 0.5):
					v.draw_line(a, b, Color("8f9592"), 3.0)
				k += 1
		&"sd_booth":
			v._quad(2, L - 2, 9, 20, Color("9fc8d4").darkened(0.25 + sh * 0.3))
			v._quad(0, L, h - 3, h, Color("1d4f9c"))
		&"sd_school_bands":
			v._quad(0, L, 0, 4, Color("d8cdb2").darkened(sh))
			for f in range(1, v._floors):
				v._quad(0, L, f * v._fh - 2, f * v._fh + 1, Color("e2d8bf").darkened(sh), 0.5)
			v._quad(0, L, h - 3, h, Color("e2d8bf").darkened(sh), 0.5)
		&"sd_school_tower":
			if not south:
				return
			var c := L * 0.5
			if v._in(c):
				var at := v._pt(c, h - 20, 1)
				v.draw_set_transform_matrix(IsoView.screen_frame(at))
				v.draw_circle(Vector2.ZERO, 12, Color("2b2f33"))
				v.draw_circle(Vector2.ZERO, 10.5, Color("f1ece0"))
				for j in 12:
					var u := Vector2.from_angle(TAU * j / 12.0)
					v.draw_line(u * 8.0, u * 10.0, Color("2b2f33"), 1.0)
				v.draw_line(Vector2.ZERO, Vector2(0, -7), Color("2b2f33"), 1.8)
				v.draw_line(Vector2.ZERO, Vector2(5, 2), Color("2b2f33"), 1.8)
				_end(v)
			if _begin(v, c - 10, 20, h - 38):
				v.draw_rect(Rect2(0, 0, 20, 2 + p.text.length() * 13), Color("efe8d6"))
				v.draw_rect(Rect2(0, 0, 20, 2 + p.text.length() * 13), Color("6d6250"), false, 1.0)
				for i in p.text.length():
					_text(v, Vector2(0, 13 + i * 13), p.text[i], 20, 11, Color("1d3b6a"), Color(0, 0, 0, 0))
				_end(v)
		&"sd_gate_plate":
			if south and _begin(v, 2, L - 4, h - 3):
				v.draw_rect(Rect2(0, 0, L - 4, h - 7), Color("d8d0bd"))
				for i in p.text.length():
					_text(v, Vector2(0, 9 + i * 9), p.text[i], L - 4, 8, Color("3a2e26"), Color(0, 0, 0, 0))
				_end(v)
		&"sd_glass_rail":
			v._quad(0, L, h, h + 14, Color(0.7, 0.85, 0.9, 0.35))
			v._hline(h + 14, Color("8a9aa0"), 1.5)
		&"sd_metro_band":
			if south and _begin(v, 0, L, h):
				v.draw_rect(Rect2(0, 0, L, h), p.accent)
				v.draw_rect(Rect2(0, h - 1.5, L, 1.5), Color.WHITE)
				v.draw_circle(Vector2(h * 0.7, h * 0.5), h * 0.36, Color.WHITE)
				v.draw_circle(Vector2(h * 0.7, h * 0.5), h * 0.28, p.accent)
				_text(v, Vector2(h * 1.3, h * 0.5 + h * 0.26), p.text, L - h * 1.6, int(h * 0.7), Color.WHITE, Color(0, 0, 0, 0))
				_text(v, Vector2(h * 0.7 - 5, h * 0.5 + h * 0.2), "2", 10, int(h * 0.5), Color.WHITE, Color(0, 0, 0, 0))
				_end(v)
		&"sd_line_pillar":
			if south and _begin(v, 0, L, h):
				v.draw_rect(Rect2(0, 0, L, h), Color("2f3a3d"))
				v.draw_circle(Vector2(L * 0.5, 9), 6.5, p.accent)
				_text(v, Vector2(0, 13), p.text, L, 10, Color.WHITE, Color(0, 0, 0, 0))
				var name := "한빛역"
				for i in name.length():
					_text(v, Vector2(0, 28 + i * 10), name[i], L, 9, Color.WHITE, Color(0, 0, 0, 0))
				v.draw_rect(Rect2(2, h - 16, L - 4, 10), Color("ffd24a"))
				_text(v, Vector2(0, h - 8), "1", L, 8, Color("1d1d1f"), Color(0, 0, 0, 0))
				_end(v)
		&"sd_louver":
			for z in range(10, int(h) - 4, 4):
				v._quad(4, L - 4, z, z + 2, Color("4b5154"))
			v._quad(0, L, h - 3, h, Color("d8d4c8").darkened(sh))
		&"sd_kiosk":
			if south:
				v._quad(3, L - 3, 2, 16, Color("d9cfae"))
				var cols := [Color("d23a2f"), Color("2f6fb0"), Color("ffd24a"), Color("3a9a5a"), Color("efefe6")]
				for k in int((L - 8) / 5.0):
					v._quad(4 + k * 5, 8 + k * 5, 4 + (k % 2) * 5, 10 + (k % 2) * 5, cols[k % cols.size()])
				v._quad(0, L, h - 4, h, Color("2e7a55").darkened(0.2), 4)
		&"sd_shelter":
			if south and _begin(v, 0, L, h):
				v.draw_rect(Rect2(0, 0, L, h), Color("1d4f9c"))
				_text(v, Vector2(2, h - 0.5), "버스  101  273  7016", L - 4, int(h * 0.9), Color.WHITE, Color(0, 0, 0, 0))
				_end(v)
		&"sd_fire_bays":
			_fire_bays(v, south)
		&"sd_fire_band":
			if south:
				var z0 := v._fh + 4
				var w := minf(L * 0.82, 280.0)
				v._quad(L * 0.5 - w * 0.5 - 6, L * 0.5 + w * 0.5 + 6, z0, z0 + 22, Color("b4332e").darkened(sh * 0.3), 1)
				if _begin(v, L * 0.5 - w * 0.5, w, z0 + 20):
					_text(v, Vector2(0, 16), p.text, w, 15, Color.WHITE, Color(0, 0, 0, 0.3))
					_end(v)
		&"sd_tower_119":
			if south and _begin(v, 0, L, h - 10):
				var font := ThemeDB.fallback_font
				for i in 3:
					_text(v, Vector2(0, 16 + i * 16), "119"[i], L, 16, Color("e0312a"), Color(1, 1, 1, 0.5))
				_end(v)
		&"sd_podium", &"sd_podium_glow":
			if not south:
				if d == &"sd_podium":
					for s in range(10, int(L) - 6, 24):
						v._quad(s, s + 3, 4, h - 6, Color("9a978f").darkened(sh))
				return
			var c := L * 0.5
			var w := minf(L * 0.6, 160.0)
			if d == &"sd_podium_glow":
				v._glow(c - w * 0.5, c + w * 0.5, 2, 30, Color(1.0, 0.9, 0.7), 0.0)
				return
			v._quad(c - w * 0.5 - 4, c + w * 0.5 + 4, 0, 34, Color("3a3f44"))
			v._quad(c - w * 0.5, c + w * 0.5, 2, 30, Color("9fc0cf").darkened(0.45))
			var s := c - w * 0.5
			while s <= c + w * 0.5:
				v._quad(s - 0.6, s + 0.6, 2, 30, Color("3a3f44"))
				s += 16.0
			v._quad(c - 9, c + 9, 0, 22, Color("6f8ea0").darkened(0.3))   # 회전문
			if _begin(v, c - w * 0.5, w, h - 2):
				_text(v, Vector2(0, 10), p.text, w, 10, Color("e9e5d8"), Color(0, 0, 0, 0.4))
				_end(v)
		&"sd_fins":
			v._quad(0, 3, 0, h, Color("a9c1cf").darkened(sh * 0.6))
			v._quad(L - 3, L, 0, h, Color("a9c1cf").darkened(sh * 0.6))
			var z := 60.0
			while z < h:
				v._quad(0, L, z, z + 2, Color("8fb0c0").darkened(sh * 0.5))
				z += 60.0
			if not v.lights:
				# 하늘 반사 띠 (비스듬한 밝은 면)
				for k in 2:
					var s0 := L * (0.2 + k * 0.45)
					if v._in(s0) and v._in(minf(s0 + 30, L - 1)):
						v.draw_colored_polygon(PackedVector2Array([v._pt(s0, 20 + k * 90), v._pt(s0 + 18, 20 + k * 90), v._pt(s0 + 30, 160 + k * 90), v._pt(s0 + 12, 160 + k * 90)]), Color(0.85, 0.93, 1.0, 0.12))
		&"sd_crown_sign":
			if south and _begin(v, L * 0.1, L * 0.8, h - 3):
				_text(v, Vector2(0, 14), p.text, L * 0.8, 14, Color("d8f2ff"), Color(p.accent, 0.5))
				_end(v)
		&"sd_canopy_edge":
			v._quad(0, L, 0, h, Color("6b7175").darkened(sh * 0.3))
			if south:
				for k in 5:
					v._quad(L * (k + 0.5) / 5.0 - 2, L * (k + 0.5) / 5.0 + 2, 0, 1, Color("fff4d8"))
		&"sd_blade":
			if south and _begin(v, 0, L, h):
				var n := p.text.length()
				SpecialDecor._metal(v, Rect2(0, 0, L, h), Color("f2efe6"), p.seed)
				var cell := (h - 6) / n
				for i in n:
					_text(v, Vector2(0, 4 + cell * (i + 0.78)), p.text[i], L, int(minf(L * 0.72, cell * 0.8)), p.accent, Color(0, 0, 0, 0))
				_end(v)


## 유흥 건물 앞면: 층마다 다른 네온 (호프·B1 / 노래방 / CLUB / BAR)
static func _nightlife(v: BuildingView, south: bool) -> void:
	var L := v._len
	var fh := v._fh
	var h := v._p.h1 - v._p.h0
	if not south:
		neon(v, "노래방", L * 0.5, h - 30, 26, 96, Color("ff3fb4"), true)
		return
	# 1층: 호프집 유리창, 지하 계단 입구와 B1
	v._quad(L * 0.08, L * 0.5, 2, fh * 0.8, Color(1.0, 0.72, 0.4).darkened(0.1))
	for k in 4:
		v._quad(L * 0.08 + k * (L * 0.42) / 4.0, L * 0.08 + k * (L * 0.42) / 4.0 + 1.2, 2, fh * 0.8, Color("3a2a22"))
	v._quad(L * 0.6, L * 0.78, 0, fh * 0.85, Color("140f18"))
	v._quad(L * 0.6, L * 0.78, 0, 4, Color("ff3fb4"))
	neon(v, "B1", L * 0.69, fh * 1.05, 26, 12, Color("38e0ff"))
	neon(v, "서울 호프", L * 0.29, fh * 0.98, minf(L * 0.4, 130), 13, Color("ffa53e"))
	# 맥주잔 그림
	var mug := L * 0.08 + 4
	if _begin(v, mug, 14, fh * 0.98 - 1):
		v.draw_rect(Rect2(1, 1, 8, 10), Color("ffc24a"))
		v.draw_rect(Rect2(1, 1, 8, 3), Color("fff4d8"))
		v.draw_arc(Vector2(10, 6), 3, -PI * 0.5, PI * 0.5, 6, Color("ffc24a"), 1.5)
		_end(v)
	# 2층 노래방, 3층 클럽(춤추는 사람), 4층 BAR
	neon(v, "별밤 노래방", L * 0.5, fh * 2 - 4, minf(L * 0.8, 230), 22, Color("ff3fb4"))
	var w := minf(L * 0.7, 200.0)
	neon(v, "CLUB 달", L * 0.5 + 10, fh * 3 - 4, w - 20, 22, Color("6b5bff"))
	if _begin(v, L * 0.5 - w * 0.5 - 6, 18, fh * 3 - 2):
		var c := Color("38e0ff")
		v.draw_circle(Vector2(9, 3), 2.2, c)
		v.draw_polyline(PackedVector2Array([Vector2(3, 6), Vector2(9, 9), Vector2(15, 4)]), c, 1.6)
		v.draw_line(Vector2(9, 5), Vector2(9, 14), c, 1.6)
		v.draw_polyline(PackedVector2Array([Vector2(4, 21), Vector2(9, 14), Vector2(14, 20)]), c, 1.6)
		_end(v)
	neon(v, "BAR", L * 0.3, fh * 4 - 6, 50, 16, Color("ffd24a"))
	neon(v, "노래연습장", L * 0.7, fh * 4 - 6, minf(L * 0.36, 110), 14, Color("4bff9a"))


## 주차 층의 앞·옆면: 난간 띠, 어두운 안쪽에 세운 차 옆모습, 기둥. lamps면 천장 불빛만 (불빛 조각)
static func _deck_face(v: BuildingView, lamps: bool) -> void:
	var p := v._p
	var L := v._len
	var h := p.h1 - p.h0
	var ground := p.h0 <= 0.0
	var open0 := 0.0 if ground else 11.0
	var open1 := h - 2.0
	if lamps:
		var s := 18.0
		while s < L - 10:
			v._glow(s - 5, s + 5, open1 - 2, open1 - 0.8, Color(0.95, 0.97, 1.0), 0.0)
			s += 40.0
		return
	v._quad(0, L, open0, open1, Color("1b1e21"))
	# 세운 차 (자리마다 있거나 없다)
	var slot := 34.0
	var k := 0
	var s := 10.0
	while s < L - slot:
		var key := p.seed * 31 + k * 7 + int(v._n.x) * 101 + int(p.h0)
		if BuildingModel.hash01(key, 2) < (0.55 if ground else 0.72):
			var col: Color = CAR_COLORS[posmod(key, CAR_COLORS.size())]
			col = col.darkened(0.25)
			var b := open0 + 1.0
			v._quad(s + 2, s + slot - 4, b + 2, b + 8, col)
			v._quad(s + 8, s + slot - 10, b + 8, b + 12, col.darkened(0.1))
			v._quad(s + 9, s + slot - 11, b + 8.5, b + 11.5, Color("4b6070").darkened(0.3))
			for wx in [s + 7, s + slot - 9]:
				v._quad(wx - 2, wx + 2, b, b + 3, Color("0c0d0e"))
		s += slot
		k += 1
	# 기둥
	for f in [0.0, 0.33, 0.66, 1.0]:
		var c := clampf(L * f, 3.0, L - 3.0)
		v._quad(c - 3, c + 3, 0, h, p.wall.lightened(0.05).darkened(v._shade))
	if not ground:
		# 바닥판 두께와 난간 띠, 빗물 자국
		v._quad(0, L, 0, 3, p.wall.darkened(0.25 + v._shade))
		v._quad(0, L, 3, open0, p.wall.darkened(v._shade))
		var t := 20.0
		while t < L:
			v._quad(t, t + 1.2, 3, open0 - 2, p.wall.darkened(0.15 + v._shade))
			t += 47.0
	v._quad(0, L, open1, h, p.wall.darkened(0.12 + v._shade))


## 소방서 차고: 열린 셔터 안에 소방차(또는 구급차) 앞모습, 문 사이 노랑·검정 기둥
static func _fire_bays(v: BuildingView, south: bool) -> void:
	if not south:
		return
	var p := v._p
	var L := v._len
	var ambulance := p.text == "구급"
	var n := 1 if ambulance else 3
	var top := minf(v._fh - 3.0, 28.0)
	for k in n:
		var c := (k + 0.5) * L / n
		var w := L / n - 18.0
		v._quad(c - w * 0.5, c + w * 0.5, 0, top, Color("191b1e"))
		v._quad(c - w * 0.5, c + w * 0.5, top - 4, top, Color("8d9396"))   # 말아 올린 셔터
		for j in 3:
			v._hline(top - 3.2 + j * 1.2, Color("5f6467"), 0.6, c - w * 0.5, c + w * 0.5)
		# 차 앞모습
		var tw := minf(w * 0.62, 46.0)
		var body := Color("f2efe6") if ambulance else Color("c8251f")
		v._quad(c - tw * 0.5, c + tw * 0.5, 2, 20, body.darkened(0.25))
		v._quad(c - tw * 0.42, c + tw * 0.42, 13, 19, Color("2c3e50").darkened(0.2))
		v._quad(c - tw * 0.5, c + tw * 0.5, 7, 9, Color("f2efe6") if not ambulance else Color("e86b24"))
		v._quad(c - tw * 0.3, c - tw * 0.05, 20, 22, Color("d23a2f"))
		v._quad(c + tw * 0.05, c + tw * 0.3, 20, 22, Color("2f6fd8"))
		for s in [c - tw * 0.38, c + tw * 0.38]:
			v._quad(s - 2, s + 2, 4, 6, Color("fff1c8"))
		# 문 번호
		if not ambulance and _begin(v, c - 8, 16, top + 9):
			v.draw_rect(Rect2(0, 0, 16, 8), Color("c8251f"))
			_text(v, Vector2(0, 7), "0%d" % (k + 1), 16, 7, Color.WHITE, Color(0, 0, 0, 0))
			_end(v)
		# 노랑·검정 문기둥
		for side in [-1.0, 1.0]:
			var s0: float = c + side * (w * 0.5 + 1.0) - 2.0
			var z := 0.0
			while z < top:
				v._quad(s0, s0 + 4, z, minf(z + 3, top), Color("e3b023") if int(z / 3.0) % 2 == 0 else Color("1d1d1f"))
				z += 3.0


# ── 지붕 그림 ─────────────────────────────────────────────

static func roof(v: BuildingView, p: BuildingModel.Piece) -> void:
	var r := p.rect
	var c := r.get_center()
	match p.roof:
		&"sd_void":
			pass
		&"sd_pine":
			v.draw_set_transform_matrix(IsoView.screen_frame(c) * Transform2D(0.0, Vector2(1.0, 0.5), 0.0, Vector2.ZERO))
			v.draw_circle(Vector2(4, 2), p.rise * 0.36, Color(0, 0, 0, 0.28))
			_end(v)
			v.draw_line(c, c + IsoView.lift(p.h1), p.wall, 2.5)
			v.draw_set_transform_matrix(IsoView.screen_frame(c, p.h1))
			var leaf := p.roof_color.lerp(Color("3a6b3a"), BuildingModel.hash01(p.seed, 2) * 0.5)
			var rr := p.rise * 0.4
			for k in 3:
				var y0 := -k * p.rise * 0.3
				var w := rr * (1.0 - k * 0.25)
				v.draw_colored_polygon(PackedVector2Array([Vector2(-w, y0), Vector2(w, y0), Vector2(0, y0 - p.rise * 0.48)]), leaf.darkened(0.1 * (2 - k)))
				v.draw_colored_polygon(PackedVector2Array([Vector2(0, y0), Vector2(w, y0), Vector2(0, y0 - p.rise * 0.48)]), leaf.darkened(0.28))
			_end(v)
		&"sd_bollard":
			v.draw_set_transform_matrix(IsoView.screen_frame(c))
			var hh := (p.h1 - p.h0) * 1.28
			v.draw_rect(Rect2(-2, -hh, 4, hh), p.wall.darkened(0.15))
			v.draw_rect(Rect2(-2, -hh, 2, hh), p.wall)
			if p.wall.r > 0.8:
				v.draw_rect(Rect2(-2, -hh * 0.6, 4, hh * 0.2), Color("1d1d1f"))
			v.draw_circle(Vector2(0, -hh), 2.0, p.wall.lightened(0.2))
			_end(v)
		&"sd_cross":
			_cross(v, p, false)
		&"sd_planter":
			_box3(v, r, 0, p.h1, p.wall)
			v.draw_set_transform_matrix(IsoView.screen_frame(c, p.h1 + 3))
			for k in 4:
				var at := Vector2((BuildingModel.hash01(p.seed, k) - 0.5) * r.size.x * 0.8, (BuildingModel.hash01(p.seed, k + 4) - 0.5) * 4.0)
				v.draw_circle(at, r.size.x * 0.28, Color("3d6b35").lightened(0.08 * k))
			_end(v)
		&"sd_bags":
			v.draw_set_transform_matrix(IsoView.screen_frame(c))
			v.draw_circle(Vector2(0, -4), 4.5, Color("23262b"))
			v.draw_circle(Vector2(-1.5, -6), 2.0, Color("3a3f46"))
			v.draw_line(Vector2(0, -8.5), Vector2(1.5, -11), Color("23262b"), 1.2)
			_end(v)
		&"sd_barrier":
			var pivot := Vector2(r.position.x, c.y)
			v.draw_line(pivot, pivot + IsoView.lift(14), Color("3a3f45"), 4.0)
			v.draw_rect(Rect2(pivot + IsoView.lift(9) - Vector2(4, 3), Vector2(8, 6)), Color("e3b023"))
			CheckpointVisual.draw_bar(v, pivot + Vector2(3, 0), Vector2.RIGHT, 0.0, 11.0, r.size.x - 4, 1.0)
		&"sd_goal":
			var along_x := r.size.x >= r.size.y
			var a := Vector2(r.position.x, c.y) if along_x else Vector2(c.x, r.position.y)
			var b := Vector2(r.end.x, c.y) if along_x else Vector2(c.x, r.end.y)
			var back := Vector2(0, -10) if along_x else Vector2(-10, 0)
			if c.y > r.position.y + 200 and along_x:
				back = Vector2(0, 10)
			var post := Color("f0f0ea")
			var net := Color(0.95, 0.95, 0.95, 0.35)
			for q in [a, b]:
				v.draw_line(q, q + IsoView.lift(p.h1), post, 2.0)
				v.draw_line(q + IsoView.lift(p.h1), q + back + IsoView.lift(4), net, 1.0)
			v.draw_line(a + IsoView.lift(p.h1), b + IsoView.lift(p.h1), post, 2.0)
			if p.h1 > 19.0:
				for k in 7:
					var f := k / 6.0
					v.draw_line(a.lerp(b, f) + IsoView.lift(p.h1), a.lerp(b, f) + back + IsoView.lift(2), net, 0.8)
				v.draw_line(a + back + IsoView.lift(3), b + back + IsoView.lift(3), net, 1.0)
		&"sd_bikes":
			v.draw_line(Vector2(r.position.x, c.y) + IsoView.lift(6), Vector2(r.end.x, c.y) + IsoView.lift(6), Color("8a9296"), 1.5)
			var x := r.position.x + 5
			var k := 0
			while x < r.end.x - 4:
				var col: Color = [Color("c8372c"), Color("2f6fb0"), Color("e8e4dc"), Color("3a3f45")][k % 4]
				var base := Vector2(x, c.y)
				v.draw_set_transform_matrix(IsoView.screen_frame(base))
				v.draw_arc(Vector2(-4, -3), 3.2, 0, TAU, 10, Color("1d1d1f"), 1.0)
				v.draw_arc(Vector2(4, -3), 3.2, 0, TAU, 10, Color("1d1d1f"), 1.0)
				v.draw_polyline(PackedVector2Array([Vector2(-4, -3), Vector2(-1, -8), Vector2(3, -8), Vector2(4, -3), Vector2(0, -3), Vector2(-1, -8)]), col, 1.2)
				v.draw_line(Vector2(3, -8), Vector2(2, -10), Color("1d1d1f"), 1.2)
				_end(v)
				x += 8
				k += 1
		&"sd_fountain":
			var pts := PackedVector2Array()
			var inner := PackedVector2Array()
			for k in 20:
				var u := Vector2.from_angle(TAU * k / 20.0)
				pts.append(c + Vector2(u.x * r.size.x * 0.5, u.y * r.size.y * 0.5) + IsoView.lift(p.h1))
				inner.append(c + Vector2(u.x * r.size.x * 0.42, u.y * r.size.y * 0.42) + IsoView.lift(p.h1 - 1))
			v.draw_colored_polygon(pts, GRANITE_TOP)
			v.draw_colored_polygon(inner, Color("4f8fb0"))
			for k in 5:
				var u := Vector2.from_angle(TAU * k / 5.0) * 4.0
				v.draw_line(c + IsoView.lift(p.h1), c + u + IsoView.lift(p.h1 + 14), Color(0.85, 0.95, 1.0, 0.7), 1.2)
		&"sd_stack":
			var kind := posmod(p.seed, 3)
			match kind:
				0:   # 종이 묶음
					var z := 0.0
					while z < p.h1:
						_box3(v, r, z, z + 3.6, Color("efebe0"))
						z += 4.0
					v.draw_line(Vector2(c.x, r.end.y) + IsoView.lift(0), Vector2(c.x, r.end.y) + IsoView.lift(p.h1), Color("c8372c"), 1.0)
				1:   # 상자
					_box3(v, r, 0, p.h1 * 0.55, Color("c19a64"))
					_box3(v, r.grow(-2), p.h1 * 0.55, p.h1, Color("b08a56"))
				_:   # 플라스틱 상자
					var z := 0.0
					var k := 0
					while z < p.h1:
						_box3(v, r, z, z + 4.5, [Color("2f6fb0"), Color("c8372c"), Color("3a9a5a")][k % 3])
						z += 5.0
						k += 1
		&"sd_pole":
			v.draw_line(c, c + IsoView.lift(p.h1), p.wall, 3.5)
			v.draw_line(c + Vector2(-9, 0) + IsoView.lift(p.h1 - 6), c + Vector2(9, 0) + IsoView.lift(p.h1 - 6), p.wall.darkened(0.2), 2.0)
			for x in [-8.0, 0.0, 8.0]:
				v.draw_circle(c + Vector2(x, 0) + IsoView.lift(p.h1 - 4), 1.3, Color("dfe2e0"))
			var tr := c + Vector2(4, 0) + IsoView.lift(p.h1 - 22)
			v.draw_rect(Rect2(tr - Vector2(3, 6), Vector2(6, 9)), Color("8e979a"))
			v.draw_rect(Rect2(tr + Vector2(-1, -9), Vector2(2, 3)), Color("5c6366"))
		&"sd_wires":
			for k in 3:
				var line := PackedVector2Array()
				for j in 11:
					var f := j / 10.0
					line.append(Vector2(lerpf(r.position.x, r.end.x, f), r.position.y + k * 3.0) + IsoView.lift(p.h0 - sin(f * PI) * (5.0 + k * 1.5)))
				v.draw_polyline(line, Color(0.08, 0.08, 0.09, 0.9), 1.0)
		&"sd_deck_top":
			_deck_top(v, p)

const GRANITE_TOP := Color("c4c0b6")


## 붉은 네온 십자가 (화면 좌표로 세워 그린다). glow면 불빛 조각의 밤 번짐
static func _cross(v: BuildingView, p: BuildingModel.Piece, glow: bool) -> void:
	var c := p.rect.get_center()
	var h := (p.h1 - p.h0) * 1.28
	var stone := p.accent == StreetBuilding.GRANITE
	v.draw_set_transform_matrix(IsoView.screen_frame(c, p.h0))
	var vbar := Rect2(-2.2, -h, 4.4, h)
	var hbar := Rect2(-h * 0.33, -h * 0.74, h * 0.66, 4.4)
	if glow:
		if not stone:
			var uv := Vector2(2.0, 2.0)
			for q in [vbar.grow(5.0), hbar.grow(5.0)]:
				var rr: Rect2 = q
				v.draw_primitive(PackedVector2Array([rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y)]),
					PackedColorArray([Color(1.0, 0.18, 0.26, 0.28)]), PackedVector2Array([uv, uv, uv, uv]))
			for q in [vbar, hbar]:
				var rr: Rect2 = q
				v.draw_primitive(PackedVector2Array([rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y)]),
					PackedColorArray([Color(1.0, 0.3, 0.36)]), PackedVector2Array([uv, uv, uv, uv]))
		_end(v)
		return
	var col := p.wall if not stone else Color("d8d2c4")
	v.draw_rect(vbar, col.darkened(0.3))
	v.draw_rect(hbar, col.darkened(0.3))
	v.draw_rect(Rect2(vbar.position.x + 1, vbar.position.y + 1, 1.6, vbar.size.y - 2), col.lightened(0.25))
	v.draw_rect(Rect2(hbar.position.x + 1, hbar.position.y + 1.4, hbar.size.x - 2, 1.6), col.lightened(0.25))
	_end(v)


## 주차타워 옥상 층: 콘크리트 바닥, 칸 선, 세운 차(위에서 본 모양), 가로등 기둥
static func _deck_top(v: BuildingView, p: BuildingModel.Piece) -> void:
	var r := p.rect
	v.draw_colored_polygon(v._corners(r, p.h1), p.roof_color)
	var z := IsoView.lift(p.h1)
	var x := r.position.x + 12
	var k := 0
	while x < r.end.x - 30:
		for row in [0, 1]:
			var y0 := r.position.y + 10 if row == 0 else r.end.y - 58
			v.draw_line(Vector2(x, y0) + z, Vector2(x, y0 + 48) + z, Color("e6e2d4"), 1.2)
			var key: int = p.seed * 13 + k * 5 + row
			if BuildingModel.hash01(key, 7) < 0.5:
				var car := Rect2(x + 5, y0 + 4, 22, 42)
				var col: Color = CAR_COLORS[posmod(key, CAR_COLORS.size())]
				v.draw_colored_polygon(v._corners(car, p.h1 + 5), col)
				v.draw_colored_polygon(v._corners(Rect2(car.position + Vector2(3, 10), Vector2(16, 20)), p.h1 + 8), col.darkened(0.15))
				v.draw_colored_polygon(v._corners(Rect2(car.position + Vector2(4, 8), Vector2(14, 4)), p.h1 + 7), Color("38495a"))
		x += 32
		k += 1
	# 가운데 통로 화살표
	var c := r.get_center()
	v.draw_line(c + Vector2(0, -40) + z, c + Vector2(0, 40) + z, Color("e6e2d4"), 2.0)
	# 가장자리 난간 (남·동)
	for q in [[Vector2(r.position.x, r.end.y), r.end], [r.end, Vector2(r.end.x, r.position.y)]]:
		var a: Vector2 = q[0]
		var b: Vector2 = q[1]
		v.draw_colored_polygon(PackedVector2Array([a + z, b + z, b + IsoView.lift(p.h1 + 6), a + IsoView.lift(p.h1 + 6)]), p.wall.darkened(0.08))
	for at in [r.position + Vector2(20, 20), Vector2(r.end.x - 20, r.position.y + 20), Vector2(r.position.x + 20, r.end.y - 20), r.end - Vector2(20, 20)]:
		var a: Vector2 = at
		v.draw_line(a + z, a + IsoView.lift(p.h1 + 30), Color("3a3f45"), 2.0)
		v.draw_rect(Rect2(a + IsoView.lift(p.h1 + 30) - Vector2(3, 1.5), Vector2(6, 3)), Color("cfd3d0"))


## 밤 불빛 (불빛 조각의 _top에서 부른다)
static func glow(v: BuildingView, p: BuildingModel.Piece) -> void:
	match p.roof:
		&"sd_cross":
			_cross(v, p, true)
		&"sd_deck_top":
			var z := IsoView.lift(p.h1 + 30)
			for at in [p.rect.position + Vector2(20, 20), Vector2(p.rect.end.x - 20, p.rect.position.y + 20), Vector2(p.rect.position.x + 20, p.rect.end.y - 20), p.rect.end - Vector2(20, 20)]:
				var a: Vector2 = at
				LandmarkDecor._halo(v, a + IsoView.lift(p.h1), 34.0, Color(1.0, 0.9, 0.7, 0.1), 0.02, true)
				LandmarkDecor._halo(v, a + IsoView.lift(p.h1 + 30), 6.0, Color(1.0, 0.95, 0.85, 0.5), 0.02)
