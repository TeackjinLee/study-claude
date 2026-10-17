class_name SpecialDecor
## 기능 건물(SpecialBuilding)의 벽 장식과 지붕을 BuildingView 안에서 그린다.
## BuildingView._deco·_top이 모르는 이름을 여기로 넘긴다 — 벽 좌표(_quad·_pt·_frame)는 BuildingView 것을 그대로 쓴다.
## 벽 장식은 조각(part) 구간으로 잘린다. 글자처럼 잘리지 않는 그림은 그 그림의 동쪽 끝이 든 조각이 그린다
## (서쪽으로 넘친 부분은 먼저 그려진 조각 위에 덮이고, 동쪽 조각이 뒤에 덮는 일이 없다).

const NAVY := SpecialBuilding.NAVY
const GREEN := SpecialBuilding.GREEN
const RED := SpecialBuilding.RED
const GOLD := SpecialBuilding.GOLD
const WHITE := Color(0.96, 0.96, 0.94)
const WARM := Color(1.0, 0.86, 0.55)
const IRON := Color(0.17, 0.16, 0.16)
## 벽 없이 지붕 그림만 있는 덩어리
const BARE: Array[StringName] = [&"mast", &"flag", &"pergola", &"stilt_tank", &"observation_ring", &"crane_brace", &"satellite_dish",
	&"antenna", &"lattice", &"tarp", &"lanterns", &"lamp_pole", &"hoist", &"pavilion", &"helipad", &"parasol", &"sauna_chimney"]


# ── 벽 장식 ───────────────────────────────────────────────

static func deco(v: BuildingView, d: StringName, south: bool) -> void:
	var p := v._p
	var h := p.h1 - p.h0
	var font := ThemeDB.fallback_font
	var L := v._len
	var sh := v._shade
	match d:
		&"police_band":
			v._quad(0.0, L, 0.0, 5.0, NAVY.darkened(sh * 0.5))
			v._quad(0.0, L, h - 8.0, h - 2.0, NAVY.lightened(0.15).darkened(sh * 0.5), 0.5)
			for f in range(1, v._floors):
				v._hline(f * v._fh, Color(0.4, 0.55, 0.85).darkened(sh * 0.5), 1.5)
		&"police_door":
			if not south:
				return
			var c := L * 0.5
			_doors(v, c, 22.0, v._fh * 0.85, Color(0.95, 0.86, 0.6))
			for side in [-1.0, 1.0]:
				var s: float = c + side * 28.0
				if v._in(s):
					v.draw_line(v._pt(s, 0.0, 14.0), v._pt(s, v._fh * 0.95, 14.0), Color(0.8, 0.82, 0.86).darkened(sh * 0.4), 2.5)
			_slab(v, c - 34.0, c + 34.0, v._fh * 0.98, 16.0, 3.5, NAVY)
		&"emblem_sign":
			if not south:
				return
			# 휘장판 하나와 글자판 하나를 나란히
			var hh := 30.0
			var ew := 36.0
			var gap := 6.0
			var tw := minf(104.0, L * 0.45)
			var w := ew + gap + tw
			var s0 := L * 0.5 - w * 0.5
			if _owns(v, s0 + w):
				v.draw_set_transform_matrix(v._frame(s0, w, h - 8.0))
				_metal(v, Rect2(0, 0, ew, hh), PLATE_BLUE, p.seed)
				_emblem(v, Vector2(ew * 0.5, hh * 0.54))
				_metal(v, Rect2(ew + gap, 3.0, tw, hh - 6.0), PLATE_BLUE, p.seed + 7)
				_bold(v, font, Vector2(ew + gap, hh * 0.5 + 6.0), p.text, tw, 17, WHITE)
				v.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		&"hospital_vsign":
			if not south:
				return
			# 초록 금속판: 위 흰 칸에 초록 십자, 아래 세로 글자
			if not _owns(v, L - 6.0):
				return
			var w := L - 12.0
			var n := p.text.length()
			var sq := Vector2(w - 8.0, (w - 8.0) * 0.87)   # 화면에서 정사각형 (간판 x 한 칸 = 화면 0.87px)
			var step := minf(38.0, (h - 26.0 - sq.y) / maxf(1.0, n))
			var hh := sq.y + 10.0 + n * step + 2.0
			v.draw_set_transform_matrix(v._frame(6.0, w, h - 6.0))
			_metal(v, Rect2(0, 0, w, hh), GREEN.lightened(0.06), p.seed)
			v.draw_rect(Rect2(Vector2(4, 4), sq), WHITE)
			var cc := Vector2(4, 4) + sq * 0.5
			var t := sq.x * 0.24
			v.draw_rect(Rect2(cc - Vector2(t * 0.5, sq.y * 0.36), Vector2(t, sq.y * 0.72)), GREEN.lightened(0.1))
			v.draw_rect(Rect2(cc - Vector2(sq.x * 0.36, t * 0.435), Vector2(sq.x * 0.72, t * 0.87)), GREEN.lightened(0.1))
			v.draw_line(Vector2(2, 6.0 + sq.y), Vector2(w - 2.0, 6.0 + sq.y), GREEN.darkened(0.5), 1.2)
			for i in n:
				_bold(v, font, Vector2(0, 8.0 + sq.y + (i + 1) * step - step * 0.2), p.text[i], w, int(step * 0.8), WHITE)
			v.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		&"er_band":
			if not south:
				return
			v._quad(0.0, L, h - 17.0, h - 1.0, RED.darkened(0.2 + sh * 0.3), 1.0)   # 차양 띠
			v._hline(h - 1.0, RED.lightened(0.3).darkened(sh * 0.3), 1.5, -INF, INF, 1.0)
			# 빨간 금속판: 왼쪽 칸 흰 십자, 칸막이, 글자
			var w := minf(122.0, L * 0.62)
			var s0 := L * 0.5 - w * 0.5
			var hh := 17.0
			if _owns(v, s0 + w):
				v.draw_set_transform_matrix(v._frame(s0, w, h - 0.5))
				_metal(v, Rect2(0, 0, w, hh), RED, p.seed)
				v.draw_rect(Rect2(10.5, 3.5, 3.4, hh - 7.0), WHITE)
				v.draw_rect(Rect2(5.5, hh * 0.5 - 1.5, 13.4, 3.0), WHITE)
				v.draw_line(Vector2(22, 2.5), Vector2(22, hh - 2.5), RED.darkened(0.55), 1.2)
				_bold(v, font, Vector2(23, hh * 0.5 + 5.5), p.text, w - 25.0, 14, WHITE)
				v.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		&"er_door":
			if south:
				_doors(v, L * 0.3, 22.0, h - 19.0, Color(0.92, 0.95, 0.9))
				v._quad(L * 0.62, L * 0.92, 4.0, h - 20.0, Color(0.9, 0.9, 0.82, 0.85).darkened(sh * 0.4))   # 접수 창
		&"gold_trim":
			var trim := GOLD.darkened(0.15 + sh * 0.5)
			v._quad(0.0, L, 0.0, 4.0, Color(0.08, 0.08, 0.09), 1.0)
			for f in range(1, v._floors):
				v._hline(f * v._fh, GOLD.darkened(0.45 + sh * 0.3), 1.0, -INF, INF, 0.5)
			for s in [1.6, L / 3.0, L * 2.0 / 3.0, L - 1.6]:
				v._quad(s - 1.6, s + 1.6, 0.0, h, trim, 1.5)
			v._quad(0.0, L, h - 6.0, h, GOLD.darkened(0.3 + sh * 0.4), 2.0)
			v._hline(h - 6.0, GOLD.lightened(0.2).darkened(sh * 0.4), 1.0, -INF, INF, 2.0)
		&"gold_door":
			if not south:
				return
			var c := L * 0.5
			_doors(v, c, 22.0, v._fh * 0.9, WARM)
			v._quad(c - 25.0, c - 22.0, 0.0, v._fh * 0.95, GOLD.darkened(sh * 0.4), 0.5)
			v._quad(c + 22.0, c + 25.0, 0.0, v._fh * 0.95, GOLD.darkened(sh * 0.4), 0.5)
			_slab(v, c - 38.0, c + 38.0, v._fh * 1.02, 18.0, 3.0, Color(0.1, 0.1, 0.11))
			v._hline(v._fh * 1.02 - 3.0, GOLD, 1.5, c - 38.0, c + 38.0, 18.0)
			for side in [-1.0, 1.0]:
				_lamp(v, c + side * 34.0, v._fh * 0.6, 2.0)
		&"office_plate":
			var w := minf(80.0, L * 0.5)
			var s0 := L * 0.5 - w * 0.5
			if south and _owns(v, s0 + w):
				v.draw_set_transform_matrix(v._frame(s0, w, h - 4.0))
				_metal(v, Rect2(0, 0, w, 20.0), RED, p.seed)
				_bold(v, font, Vector2(0, 16.0), p.text, w, 15, WHITE)
				v.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		&"striped_awning":
			if south:
				_awning(v, L * 0.5 - 20.0, L * 0.5 + 20.0, 19.0, 12.0, 10.0, [Color(0.85, 0.18, 0.18), Color(0.95, 0.93, 0.9)])
		&"fire_escape":
			if not south:
				_fire_escape(v)
		&"open_shutter":
			if south:
				_open_shutter(v, h)
		&"wall_lamps":
			var s := 30.0
			while s < L - 10.0:
				_lamp(v, s, minf(h - 8.0, 36.0), 1.5)
				s += 72.0
		&"container_doors":
			v._hline(2.0, Color(0, 0, 0, 0.35), 2.0)
			v._hline(h - 2.0, p.wall.lightened(0.2).darkened(sh), 2.0)
			if south:
				return
			for f in [0.25, 0.5, 0.75]:
				var s: float = L * f
				if v._in(s):
					v.draw_line(v._pt(s, 3.0, 0.8), v._pt(s, h - 3.0, 0.8), IRON.lightened(0.2), 1.2)
			v._quad(L * 0.47, L * 0.53, h * 0.4, h * 0.5, Color(0.7, 0.7, 0.68).darkened(sh), 1.0)
		&"repair_bays":
			if south:
				_repair_bays(v, h)
		&"repair_sign":
			if not south:
				return
			var w := minf(126.0, L * 0.42)
			var s0 := L * 0.25 - w * 0.5
			var top := h - 2.0
			var hh := minf(19.0, h - _bay_top(h) - 3.0)
			if _owns(v, s0 + w):
				v.draw_set_transform_matrix(v._frame(s0, w, top))
				_metal(v, Rect2(0, 0, w, hh), PLATE_BLUE, p.seed)
				_wrench(v, Vector2(14, hh * 0.5), hh * 0.34)
				_bold(v, font, Vector2(26, hh * 0.5 + hh * 0.3), p.text, w - 30.0, int(hh * 0.78), WHITE)
				v.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		&"tile_canopy":
			if south:
				var c := L * 0.4
				_doors(v, c, 15.0, v._fh * 0.85, Color(0.96, 0.74, 0.42))
				_tile_roof(v, c - 30.0, c + 30.0, v._fh * 1.08, v._fh * 0.78, 15.0)
		&"sauna_sign":
			if south:
				_sauna_sign(v, h, font)
		&"store_front":
			_store_front(v, h, south)
		&"store_band":
			_store_band(v, h, south, font)
		&"vending":
			if not south:
				var s := L * 0.78
				v._quad(s - 8.0, s + 8.0, 0.0, 21.0, Color(0.78, 0.14, 0.18).darkened(sh * 0.5), 5.0)
				v._quad(s - 6.0, s + 6.0, 10.0, 19.0, Color(0.96, 0.95, 0.86).darkened(sh * 0.3), 5.2)
				v._quad(s - 4.0, s + 4.0, 3.0, 5.0, Color(0.1, 0.1, 0.1), 5.2)
				v._quad(s + 9.0, s + 15.0, 0.0, 12.0, Color(0.85, 0.85, 0.82).darkened(sh * 0.5), 4.0)   # 박스 수거함


## 이 조각이 s(벽 거리)까지 그리는가 (잘리지 않는 그림은 동쪽 끝이 든 조각이 그린다)
static func _owns(v: BuildingView, s: float) -> bool:
	return v._in(clampf(s, 0.0, v._len - 0.01))


## 벽에서 튀어나온 판 (차양·현관 지붕): 윗면과 앞 두께
static func _slab(v: BuildingView, s0: float, s1: float, z: float, out: float, thick: float, color: Color) -> void:
	var a := maxf(s0, v._s0)
	var b := minf(s1, v._s1)
	if b - a < 0.3:
		return
	v.draw_colored_polygon(PackedVector2Array([v._pt(a, z), v._pt(b, z), v._pt(b, z, out), v._pt(a, z, out)]),
		color.lightened(0.12))
	v._quad(s0, s1, z - thick, z, color.darkened(0.2 + v._shade * 0.3), out)


## 불 켜진 유리문 두 짝 (가운데 c, 반폭 half, 높이 top)
static func _doors(v: BuildingView, c: float, half: float, top: float, glow: Color) -> void:
	v._quad(c - half, c + half, 0.0, top, glow.darkened(v._shade * 0.35))
	v._quad(c - half, c + half, top - 2.0, top, Color(0.2, 0.2, 0.22), 0.3)
	for s in [c - half, c, c + half]:
		v._quad(s - 0.8, s + 0.8, 0.0, top, Color(0.22, 0.22, 0.24), 0.3)
	v._quad(c - half * 0.6, c + half * 0.6, 0.0, top * 0.3, Color(1, 1, 1, 0.12), 0.2)


## 벽등 (불빛 번짐)
static func _lamp(v: BuildingView, s: float, z: float, out: float) -> void:
	if not v._in(s):
		return
	var at := v._pt(s, z, out)
	v._quad(s - 1.5, s + 1.5, z - 3.0, z + 1.0, Color(0.12, 0.12, 0.12), out * 0.5)
	v.draw_circle(at, 7.0, Color(1.0, 0.8, 0.4, 0.16))
	v.draw_circle(at, 2.4, WARM)


const PLATE_BLUE := Color(0.13, 0.27, 0.68)


## 녹슨 금속 간판판 (간판 좌표계): 어두운 테, 바탕, 위 빛·아래 그늘, 녹 얼룩, 네 귀 리벳
static func _metal(v: BuildingView, r: Rect2, bg: Color, seed: int) -> void:
	var dim := v._shade * 0.2
	if v.lights:
		v._glow_rect(r.grow(3.5), Color(bg.lightened(0.45), 0.22))   # 밤 간판 번짐
	v.draw_rect(r.grow(0.7), Color(0.12, 0.11, 0.11))
	v.draw_rect(r, Color(0.44, 0.42, 0.4).darkened(dim))
	var inner := r.grow(-1.8)
	v.draw_rect(inner, bg.darkened(dim))
	v.draw_rect(Rect2(inner.position, Vector2(inner.size.x, 1.0)), bg.lightened(0.22).darkened(dim))
	v.draw_rect(Rect2(inner.position + Vector2(0, inner.size.y - 1.0), Vector2(inner.size.x, 1.0)), bg.darkened(0.25 + dim))
	var n := clampi(int(r.size.x * r.size.y / 50.0), 3, 26)
	for k in n:
		# k*k로 섞는다 (k에 비례하면 점이 줄지어 늘어선다)
		var q := inner.position + inner.size * Vector2(BuildingModel.hash01(seed + k * k * 7, 1), BuildingModel.hash01(seed + k * k * 13 + k, 2))
		v.draw_rect(Rect2(q, Vector2(1.4, 1.0)), Color(0.58, 0.32, 0.12, 0.5))
	for c in [r.position + Vector2(2.4, 2.4), Vector2(r.end.x - 2.4, r.position.y + 2.4), r.end - Vector2(2.4, 2.4),
			Vector2(r.position.x + 2.4, r.end.y - 2.4)]:
		v.draw_circle(c, 1.1, Color(0.8, 0.77, 0.72))
		v.draw_circle(c + Vector2(0.3, 0.3), 0.5, Color(0.22, 0.2, 0.2))


## 굵은 간판 글씨 (반 칸 겹쳐 두 번, 어두운 테두리). at은 왼쪽 기준선, w 폭 안 가운데 정렬
static func _bold(v: BuildingView, font: Font, at: Vector2, text: String, w: float, size: int, color: Color,
		outline := Color(0, 0, 0, 0.35)) -> void:
	if outline.a > 0.0:
		v.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, w, size, 3, outline)
	v.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, w, size, color)
	v.draw_string(font, at + Vector2(0.7, 0), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, color)


## 흰 렌치 (가운데 c, 크기 r)
static func _wrench(v: BuildingView, c: Vector2, r: float) -> void:
	var tail := c + Vector2(-r, r)
	var head := c + Vector2(r * 0.6, -r * 0.6)
	v.draw_line(tail, head, WHITE, r * 0.55)
	v.draw_circle(tail, r * 0.32, WHITE)
	v.draw_circle(head, r * 0.6, WHITE)
	v.draw_circle(head + Vector2(r * 0.32, -r * 0.32), r * 0.34, PLATE_BLUE)   # 벌어진 입


## 날개 편 독수리 휘장 (경찰서 간판, 간판 좌표계). 실제 경찰 휘장을 본뜨지 않은 단순한 모양
static func _emblem(v: BuildingView, c: Vector2) -> void:
	var g := GOLD.lightened(0.12)
	var dark := GOLD.darkened(0.4)
	for side in [-1.0, 1.0]:
		v.draw_colored_polygon(PackedVector2Array([c + Vector2(side * 2, -3), c + Vector2(side * 13, -11), c + Vector2(side * 15, -6),
			c + Vector2(side * 13, -1), c + Vector2(side * 9, 3), c + Vector2(side * 3, 4)]), g)
		for k in 3:
			v.draw_line(c + Vector2(side * (5 + k * 3), 2.0 - k * 2.0), c + Vector2(side * (9 + k * 2), -3.0 - k * 2.5), dark, 0.8)
	v.draw_circle(c + Vector2(0, -8), 2.6, g)
	v.draw_colored_polygon(PackedVector2Array([c + Vector2(1.5, -9), c + Vector2(4.5, -8), c + Vector2(1.5, -7)]), Color(0.95, 0.6, 0.15))
	v.draw_colored_polygon(PackedVector2Array([c + Vector2(-3, 7), c + Vector2(3, 7), c + Vector2(0, 12)]), g)
	v.draw_circle(c + Vector2(0, 2.5), 5.6, g)
	v.draw_circle(c + Vector2(0, 2.5), 4.4, dark)
	v.draw_circle(c + Vector2(0, 2.5), 3.2, Color(0.15, 0.3, 0.75))
	var top := PackedVector2Array()
	for k in 9:
		top.append(c + Vector2(0, 2.5) + Vector2.from_angle(PI + k * PI / 8.0) * 3.2)
	v.draw_colored_polygon(top, Color(0.85, 0.15, 0.2))


## 줄무늬 차양 (s0~s1, 벽 높이 z0에서 out만큼 나와 z1까지 내려온다)
static func _awning(v: BuildingView, s0: float, s1: float, z0: float, z1: float, out: float, colors: Array) -> void:
	var w := 5.0
	var s := s0
	var k := 0
	while s < s1:
		var a := maxf(s, v._s0)
		var b := minf(minf(s + w, s1), v._s1)
		if b - a > 0.2:
			var c: Color = colors[k % colors.size()]
			v.draw_colored_polygon(PackedVector2Array([v._pt(a, z0), v._pt(b, z0), v._pt(b, z1, out), v._pt(a, z1, out)]),
				c.darkened(v._shade * 0.3))
			v._quad(a, b, z1 - 3.0, z1, c.darkened(0.15 + v._shade * 0.3), out)
		s += w
		k += 1


## 철제 비상계단 (동쪽 벽): 층마다 발판·난간, 발판 사이 사선 계단
static func _fire_escape(v: BuildingView) -> void:
	var sa := v._len * 0.48
	var sb := v._len * 0.92
	var out := 11.0
	var iron := Color(0.12, 0.12, 0.13)
	for f in range(1, v._floors + 1):
		var z := f * v._fh - 1.0
		if z > v._p.h1 - v._p.h0 - 2.0:
			break
		_slab(v, sa, sb, z, out, 2.0, iron)
		v._hline(z + 7.0, iron, 1.5, sa, sb, out)
		for s in [sa + 1.0, (sa + sb) * 0.5, sb - 1.0]:
			if v._in(s):
				v.draw_line(v._pt(s, z, out), v._pt(s, z + 7.0, out), iron, 1.0)
		# 아래층으로 내려가는 계단
		var z0 := z - v._fh
		if v._in((sa + sb) * 0.5):
			var top := v._pt(sa + 6.0, z, out * 0.6)
			var bottom := v._pt(sb - 4.0, maxf(z0, 0.0), out * 0.6)
			v.draw_line(top, bottom, iron, 3.0)
			for k in range(1, 7):
				var q := top.lerp(bottom, k / 7.0)
				v.draw_line(q + Vector2(-2.5, 0), q + Vector2(2.5, 0), iron.lightened(0.15), 1.0)
		# 층마다 비상문
		v._quad(sa + 3.0, sa + 12.0, z, minf(z + 13.0, v._p.h1 - v._p.h0 - 2.0), Color(0.3, 0.21, 0.15).darkened(v._shade), 0.2)


## 열린 셔터 (부두 창고): 불 켜진 안쪽, 짐 더미, 말린 셔터, 노랑·검정 기둥
static func _open_shutter(v: BuildingView, h: float) -> void:
	var c := v._len * 0.55
	var w := minf(96.0, v._len * 0.48)
	var a := c - w * 0.5
	var b := c + w * 0.5
	var top := minf(h - 9.0, 36.0)
	v._quad(a, b, 0.0, top, Color(0.92, 0.7, 0.38).darkened(v._shade * 0.3))
	v._quad(a, b, top * 0.55, top, Color(0.72, 0.5, 0.28).darkened(v._shade * 0.3))
	for k in int(w / 16.0):
		var s := a + 4.0 + k * 16.0
		var stack := 1 + posmod(v._p.seed + k, 3)
		for j in stack:
			v._quad(s, s + 12.0, j * 7.0, j * 7.0 + 6.0, Color(0.62, 0.44, 0.24).lightened(j * 0.06).darkened(v._shade * 0.3))
	v._quad(a + w * 0.7, a + w * 0.7 + 10.0, 0.0, 14.0, Color(0.95, 0.75, 0.15).darkened(v._shade * 0.3))   # 지게차
	v._quad(a - 2.0, b + 2.0, top, top + 6.0, Color(0.52, 0.55, 0.52).darkened(v._shade), 1.5)
	for z in [top + 1.5, top + 3.5]:
		v._hline(z, Color(0.3, 0.32, 0.3), 1.0, a - 2.0, b + 2.0, 1.6)
	for s in [a - 4.0, b]:
		var z := 0.0
		var k := 0
		while z < top:
			v._quad(s, s + 4.0, z, minf(z + 5.0, top), (Color(0.95, 0.78, 0.15) if k % 2 == 0 else Color(0.08, 0.08, 0.08)).darkened(v._shade * 0.3), 1.0)
			z += 5.0
			k += 1
	if v._len > 220.0:
		# 서쪽 닫힌 셔터
		var s0 := v._len * 0.12
		var s1 := s0 + minf(60.0, v._len * 0.22)
		v._quad(s0, s1, 0.0, top, Color(0.55, 0.57, 0.56).darkened(v._shade))
		var z := 2.0
		while z < top:
			v._hline(z, Color(0.36, 0.38, 0.37).darkened(v._shade), 1.0, s0, s1)
			z += 3.0


## 정비소 정비 칸 높이
static func _bay_top(h: float) -> float:
	return minf(h - 21.0, 34.0)


## 정비소: 리프트에 차가 올라간 열린 칸, 자동차 그림 닫힌 셔터, 사무실 문
static func _repair_bays(v: BuildingView, h: float) -> void:
	var L := v._len
	var sh := v._shade * 0.3
	var top := _bay_top(h)
	var a := L * 0.06
	var b := L * 0.44
	v._quad(a, b, 0.0, top, Color(0.86, 0.72, 0.48).darkened(sh))   # 불 켜진 작업장 안
	v._quad(a, b, top * 0.6, top, Color(0.62, 0.52, 0.38).darkened(sh))
	v._quad(a + 2.0, b - 2.0, top - 4.0, top - 2.0, Color(1.0, 0.97, 0.85))
	for s in [a + 8.0, b - 12.0]:
		v._quad(s, s + 4.0, 0.0, top - 5.0, Color(0.2, 0.36, 0.78).darkened(sh))
	v._hline(12.0, Color(0.95, 0.8, 0.2), 2.0, a + 12.0, b - 12.0)
	# 리프트 위 흰 승용차 (바퀴가 떠 있다)
	var car_a := lerpf(a, b, 0.22)
	var car_b := lerpf(a, b, 0.78)
	v._quad(car_a, car_b, 13.0, 19.0, Color(0.93, 0.93, 0.95).darkened(sh))
	v._quad(lerpf(car_a, car_b, 0.22), lerpf(car_a, car_b, 0.7), 19.0, 24.0, Color(0.4, 0.55, 0.7).darkened(sh))
	v._quad(car_a + 3.0, car_a + 10.0, 10.5, 14.5, Color(0.08, 0.08, 0.08))
	v._quad(car_b - 10.0, car_b - 3.0, 10.5, 14.5, Color(0.08, 0.08, 0.08))
	v._quad(a + 2.0, a + 7.0, 0.0, 11.0, RED.darkened(sh))   # 공구함
	v._quad(a - 2.0, a, 0.0, top + 2.0, Color(0.95, 0.78, 0.15).darkened(v._shade * 0.4), 0.5)
	v._quad(b, b + 2.0, 0.0, top + 2.0, Color(0.95, 0.78, 0.15).darkened(v._shade * 0.4), 0.5)
	# 닫힌 셔터와 자동차 그림
	var a2 := L * 0.5
	var b2 := L * 0.84
	v._quad(a2, b2, 0.0, top, Color(0.74, 0.76, 0.78).darkened(v._shade * 0.6))
	var z := 2.0
	while z < top:
		v._hline(z, Color(0.5, 0.52, 0.55).darkened(v._shade * 0.6), 1.0, a2, b2)
		z += 3.0
	var icon := minf(44.0, b2 - a2 - 8.0)
	if _owns(v, (a2 + b2) * 0.5 + icon * 0.5):
		v.draw_set_transform_matrix(v._frame((a2 + b2) * 0.5 - icon * 0.5, icon, top * 0.75))
		var car := NAVY.lightened(0.15)
		v.draw_colored_polygon(PackedVector2Array([Vector2(icon * 0.25, 4), Vector2(icon * 0.7, 4), Vector2(icon * 0.85, 9),
			Vector2(icon, 10), Vector2(icon, 15), Vector2(0, 15), Vector2(0, 10), Vector2(icon * 0.12, 9)]), car)
		v.draw_circle(Vector2(icon * 0.22, 15), 3.0, car.darkened(0.3))
		v.draw_circle(Vector2(icon * 0.78, 15), 3.0, car.darkened(0.3))
		v.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 사무실 문과 창
	v._quad(L * 0.88, L * 0.88 + 11.0, 0.0, 14.0, Color(0.32, 0.24, 0.18).darkened(sh))
	v._quad(L * 0.88 + 13.0, minf(L - 3.0, L * 0.88 + 30.0), 6.0, 15.0, WARM.darkened(sh))


## 기와 차양 (사우나 현관): 벽에서 나와 내려오는 기와면, 끝이 들린 처마
static func _tile_roof(v: BuildingView, s0: float, s1: float, z0: float, z1: float, out: float) -> void:
	var a := maxf(s0, v._s0)
	var b := minf(s1, v._s1)
	if b - a < 0.3:
		return
	var tile := Color(0.24, 0.25, 0.28)
	v.draw_colored_polygon(PackedVector2Array([v._pt(a, z0), v._pt(b, z0), v._pt(b, z1, out), v._pt(a, z1, out)]), tile)
	var s := s0 + 3.0
	while s < s1:
		if v._in(s):
			v.draw_line(v._pt(s, z0), v._pt(s, z1, out), tile.lightened(0.15), 1.0)
		s += 4.0
	v._quad(s0, s1, z1 - 2.5, z1, tile.darkened(0.3), out)
	v._hline(z0, tile.darkened(0.4), 2.5, s0, s1, 0.5)
	for end in [s0, s1]:
		if v._in(clampf(end, v._s0, v._s1 - 0.01)) and absf(end - clampf(end, v._s0, v._s1)) < 0.5:
			var tip := v._pt(end + (-4.0 if end == s0 else 4.0), z1 + 5.0, out + 2.0)
			v.draw_colored_polygon(PackedVector2Array([v._pt(end, z1, out), v._pt(end, z1 - 2.5, out), tip]), tile.darkened(0.2))


## 사우나 세로 간판: 흰 바탕에 빨강 '24시', 파랑 '사우나', 아래 ♨ (글꼴에 없을 수 있어 그린다)
static func _sauna_sign(v: BuildingView, h: float, font: Font) -> void:
	var w := 24.0
	var s := v._len - 18.0
	var top := h - 5.0
	var bottom := maxf(v._fh * 1.3, top - 132.0)
	if not _owns(v, s + w * 0.5):
		return
	# 한 칸에 한 글자 (붙은 숫자는 한 칸). 첫 낱말은 빨강, 나머지는 파랑
	var parts: Array[String] = []
	var colors: Array[Color] = []
	var words := v._p.text.split(" ", false)
	for wi in words.size():
		var word: String = words[wi]
		var i := 0
		while i < word.length():
			var j := i + 1
			while j < word.length() and word[i].is_valid_int() and word[j].is_valid_int():
				j += 1
			parts.append(word.substr(i, j - i))
			colors.append(RED if wi == 0 else Color(0.12, 0.3, 0.8))
			i = j
	var step := (top - bottom - 6.0) / (parts.size() + 1.2)
	v.draw_set_transform_matrix(v._frame(s - w * 0.5, w, top))
	_metal(v, Rect2(0, 0, w, top - bottom), WHITE, v._p.seed)
	for i in parts.size():
		var size := minf(step - 1.0, w * 0.75) if parts[i].length() == 1 else minf(step - 3.0, w * 0.55)
		_bold(v, font, Vector2(0, 3.0 + (i + 1) * step - 2.0), parts[i], w, int(size), colors[i], Color(0, 0, 0, 0))
	var y := 3.0 + (parts.size() + 0.9) * step
	v.draw_arc(Vector2(w * 0.5, y - step * 0.25), w * 0.28, 0.15, PI - 0.15, 10, RED, 2.0)
	for k in 3:
		var x := w * (0.3 + k * 0.2)
		v.draw_polyline(PackedVector2Array([Vector2(x, y - step * 0.3), Vector2(x - 1.5, y - step * 0.5),
			Vector2(x + 1.5, y - step * 0.7), Vector2(x, y - step * 0.9)]), RED, 1.5)
	v.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 편의점 통유리: 진열대 줄과 가운데 문 (동쪽 벽은 앞쪽 절반만)
static func _store_front(v: BuildingView, h: float, south: bool) -> void:
	var L := v._len
	var a := 4.0 if south else L * 0.08
	var b := L - 4.0 if south else L * 0.62
	var top := h - 13.0
	v._quad(a, b, 2.0, top, Color(0.98, 0.95, 0.84).darkened(v._shade * 0.35))
	for row in 3:
		var z := 5.0 + row * (top - 8.0) / 3.0
		var s := a + 2.0
		var k := 0
		while s < b - 4.0:
			var c: Color = [Color(0.85, 0.3, 0.3), Color(0.3, 0.55, 0.85), Color(0.95, 0.75, 0.25), Color(0.4, 0.7, 0.4)][
				posmod(v._p.seed + k + row * 3, 4)]
			v._quad(s, s + 5.0, z, z + 3.0, c.darkened(v._shade * 0.3))
			s += 6.0
			k += 1
		v._hline(z - 0.5, Color(0.55, 0.55, 0.55, 0.7), 1.0, a, b)
	var posts := maxi(2, int((b - a) / 40.0))
	for k in posts + 1:
		var s := lerpf(a, b, float(k) / posts)
		v._quad(s - 1.0, s + 1.0, 2.0, top, Color(0.78, 0.8, 0.8).darkened(v._shade * 0.5), 0.3)
	v._hline(2.0, Color(0.45, 0.47, 0.48), 2.0, a, b, 0.3)
	if south:
		var c := L * 0.5
		v._quad(c - 11.0, c + 11.0, 0.0, top - 2.0, Color(0.82, 0.92, 0.98, 0.75).darkened(v._shade * 0.3), 0.4)
		v._quad(c - 0.7, c + 0.7, 0.0, top - 2.0, Color(0.3, 0.32, 0.34), 0.5)
		for k in 2:   # 유리 광고 포스터
			var s := a + 8.0 + k * 22.0
			v._quad(s, s + 12.0, top - 14.0, top - 3.0, [Color(0.95, 0.4, 0.2), Color(0.25, 0.65, 0.75)][k], 0.4)


## 편의점 띠: 흰 바탕에 청록·주황·청록 줄, 남쪽 가운데 상호 간판
static func _store_band(v: BuildingView, h: float, south: bool, font: Font) -> void:
	var L := v._len
	var sh := v._shade * 0.3
	v._quad(0.0, L, h - 12.0, h, WHITE.darkened(sh), 1.0)
	v._quad(0.0, L, h - 9.5, h - 7.5, Color(0.1, 0.6, 0.6).darkened(sh), 1.1)
	v._quad(0.0, L, h - 7.5, h - 5.5, Color(0.98, 0.55, 0.15).darkened(sh), 1.1)
	v._quad(0.0, L, h - 5.5, h - 3.5, Color(0.1, 0.6, 0.6).darkened(sh), 1.1)
	if not south:
		return
	var w := minf(84.0, L * 0.62)
	var s0 := L * 0.5 - w * 0.5
	var hh := 17.0
	if _owns(v, s0 + w):
		v.draw_set_transform_matrix(v._frame(s0, w, h + 3.0))
		_metal(v, Rect2(0, 0, w, hh), WHITE, v._p.seed)
		var teal := Color(0.1, 0.6, 0.6)
		for side in [Vector2(2.5, w * 0.2), Vector2(w * 0.8, w - 2.5)]:
			v.draw_rect(Rect2(side.x, 4.0, side.y - side.x, 3.0), teal)
			v.draw_rect(Rect2(side.x, 7.0, side.y - side.x, 3.0), Color(0.98, 0.55, 0.15))
			v.draw_rect(Rect2(side.x, 10.0, side.y - side.x, 3.0), teal)
		v.draw_rect(Rect2(w * 0.2, 2.5, w * 0.6, hh - 5.0), Color(0.55, 0.55, 0.55), false, 0.8)
		# 앞 절반은 청록, 뒤 절반(숫자)은 주황빨강
		var text: String = v._p.text
		var cut := text.length() / 2
		var size := 14
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var x := (w - tw) * 0.5
		var lw := font.get_string_size(text.substr(0, cut), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		_bold(v, font, Vector2(x, hh * 0.5 + 5.0), text.substr(0, cut), lw, size, Color(0.05, 0.52, 0.56), Color(0, 0, 0, 0))
		_bold(v, font, Vector2(x + lw, hh * 0.5 + 5.0), text.substr(cut), tw - lw + 2.0, size, Color(0.95, 0.3, 0.12), Color(0, 0, 0, 0))
		v.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ── 지붕 ──────────────────────────────────────────────────

static func roof(v: BuildingView, p: BuildingModel.Piece) -> void:
	match p.roof:
		&"mast": _mast(v, p)
		&"flag": _flag(v, p)
		&"pergola": _pergola(v, p)
		&"stilt_tank": _stilt_tank(v, p)
		&"gable_sky":
			v._gable(p)
			_skylights(v, p)
		&"solar":
			v._flat(p)
			_solar(v, p)
		&"helipad": _helipad(v, p)
		&"parasol": _parasol(v, p)
		&"sauna_chimney":
			v._cylinder(p, true)
			_onsen_mark(v, p)
		_:
			LandmarkDecor.draw(v, p)   # 랜드마크 (타워·철탑·천막·크레인…)


## 병원 옥상 헬리패드: 짙은 바닥, 노란 테두리, 흰 원과 'H'.
## 글자는 바닥에 칠한 것이라 사선 화면에서 똑바로 읽히게 화면 오른쪽·위 방향(월드 (1,-1)·(-1,-1))을 글자의 가로·세로로 쓴다
static func _helipad(v: BuildingView, p: BuildingModel.Piece) -> void:
	var r := p.rect
	var l := IsoView.lift(p.h1 + 0.4)
	v.draw_colored_polygon(v._corners(r, p.h1), p.roof_color)
	var edge := v._corners(r.grow(-3.0), p.h1 + 0.4)
	edge.append(edge[0])
	v.draw_polyline(edge, Color(0.95, 0.78, 0.2), 1.3)
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y) * 0.5
	var ring := PackedVector2Array()
	for k in 29:
		ring.append(c + Vector2(cos(k * TAU / 28.0), sin(k * TAU / 28.0)) * s * 0.64 + l)
	v.draw_polyline(ring, Color(0.94, 0.94, 0.9, 0.9), 1.5)
	var right := Vector2(1, -1).normalized()
	var up := Vector2(-1, -1).normalized()
	var hx := s * 0.2
	var hy := s * 0.38
	for bar in [[Vector2(-hx, -hy), Vector2(-hx, hy)], [Vector2(hx, -hy), Vector2(hx, hy)], [Vector2(-hx, 0), Vector2(hx, 0)]]:
		var a: Vector2 = bar[0]
		var b: Vector2 = bar[1]
		v.draw_line(c + right * a.x + up * a.y + l, c + right * b.x + up * b.y + l, WHITE, 2.2)
	# 모서리 표시등
	for q in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var at: Vector2 = q + (c - q).normalized() * 6.0 + l
		v.draw_circle(at, 1.3, Color(1.0, 0.82, 0.4))


## 야외 파라솔: 기둥 하나와 줄무늬 우산 (뒤쪽 조각부터 그린다). wall = 첫 줄무늬, roof_color = 둘째 줄무늬
static func _parasol(v: BuildingView, p: BuildingModel.Piece) -> void:
	var c := p.rect.get_center()
	var rad := p.rect.size.x * 0.5
	var apex := c + IsoView.lift(p.h1)
	v.draw_line(c + IsoView.lift(0.0), apex, Color(0.32, 0.33, 0.35), 1.6)
	var n := 8
	var rim := PackedVector2Array()
	for k in n + 1:
		rim.append(c + Vector2(cos(k * TAU / n), sin(k * TAU / n)) * rad + IsoView.lift(p.h0))
	var order: Array = range(n)
	order.sort_custom(func(a: int, b: int): return rim[a].y + rim[a + 1].y < rim[b].y + rim[b + 1].y)
	for k: int in order:
		var col := p.wall if k % 2 == 0 else p.roof_color
		v.draw_primitive(PackedVector2Array([apex, rim[k], rim[k + 1]]), PackedColorArray([col]), PackedVector2Array())
	v.draw_circle(apex, 1.2, Color(0.25, 0.25, 0.27))


## 사우나 굴뚝의 온천 마크 ♨: 굴뚝 앞면의 붉은 동그라미 안에 김 세 줄과 그릇. BuildingView._cylinder 뒤에 부른다
static func _onsen_mark(v: BuildingView, p: BuildingModel.Piece) -> void:
	var rx := p.rect.size.x * 0.55
	var y := -p.h1 + 60.0           # 꼭대기 띠 둘 아래
	var cx := -rx * 0.12            # 밝은 쪽에 치우쳐 붙인다 (오른쪽 ¼은 그늘)
	var rad := rx * 0.72
	v.draw_set_transform_matrix(IsoView.screen_frame(p.rect.get_center()))
	v.draw_circle(Vector2(cx, y), rad + 1.2, Color(0.96, 0.95, 0.92))
	v.draw_circle(Vector2(cx, y), rad, RED)
	# 김 세 줄 (물결) 위, 그릇(아래쪽 반원) 아래 — 서로 떨어뜨려 ♨로 읽히게
	for i in [-1, 0, 1]:
		var x: float = cx + i * rad * 0.42
		v.draw_polyline(PackedVector2Array([Vector2(x, y - rad * 0.05), Vector2(x + 1.8, y - rad * 0.3), Vector2(x, y - rad * 0.55),
			Vector2(x + 1.8, y - rad * 0.8)]), WHITE, 1.1)
	v.draw_arc(Vector2(cx, y + rad * 0.3), rad * 0.5, 0.0, PI, 10, WHITE, 1.5)
	v.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 철골 통신탑: 네 다리가 위로 좁아지고, 앞 두 면에 X 버팀, 꼭대기 빨간 항공등, 중간 접시 안테나
static func _mast(v: BuildingView, p: BuildingModel.Piece) -> void:
	var r := p.rect
	var c := r.get_center()
	var legs := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var n := 7
	var steel := p.wall
	var prev: Array = []
	for k in n + 1:
		var f := float(k) / n
		var shrink := lerpf(1.0, 0.16, f)
		var ring: Array = []
		for q: Vector2 in legs:
			ring.append(c + (q - c) * shrink + IsoView.lift(lerpf(p.h0, p.h1, f)))
		if k > 0:
			for i in 4:
				v.draw_line(prev[i], ring[i], steel.lightened(0.1) if i == 2 else steel, 1.6 if i == 2 else 1.1)
			v.draw_line(prev[3], ring[2], steel.lightened(0.2), 0.8)
			v.draw_line(prev[2], ring[3], steel.lightened(0.2), 0.8)
			v.draw_line(prev[2], ring[1], steel.darkened(0.1), 0.8)
			v.draw_line(prev[1], ring[2], steel.darkened(0.1), 0.8)
		v.draw_polyline(PackedVector2Array([ring[3], ring[2], ring[1]]), steel, 1.0)
		prev = ring
	var tip := c + IsoView.lift(p.h1)
	v.draw_line(tip, tip + IsoView.lift(16.0), steel, 1.5)
	for f in [0.55, 1.0]:
		var at := c + IsoView.lift(lerpf(p.h0, p.h1 + 16.0, f))
		v.draw_circle(at, 6.0, Color(1.0, 0.2, 0.15, 0.22))
		v.draw_circle(at, 2.2, p.roof_color)
	for k in 2:
		var f := 0.32 + k * 0.24
		var g: Vector2 = c + (legs[2] - c) * lerpf(1.0, 0.16, f)
		v.draw_set_transform_matrix(IsoView.screen_frame(g, lerpf(p.h0, p.h1, f)))
		v.draw_line(Vector2.ZERO, Vector2(6, -1), steel, 1.2)
		v.draw_colored_polygon(BuildingView._ellipse(Vector2(7, -1), 3.5, 7.0), Color(0.9, 0.9, 0.88))
		v.draw_colored_polygon(BuildingView._ellipse(Vector2(7.8, -1), 2.0, 5.0), Color(0.68, 0.7, 0.7))
		v.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 깃대와 깃발 (roof_color 바탕. 흰 바탕이면 태극 문양)
static func _flag(v: BuildingView, p: BuildingModel.Piece) -> void:
	var base := p.rect.get_center()
	v.draw_line(base + IsoView.lift(p.h0), base + IsoView.lift(p.h1 + 2.0), p.wall, 1.6)
	v.draw_circle(base + IsoView.lift(p.h1 + 2.5), 1.6, GOLD)
	v.draw_set_transform_matrix(IsoView.screen_frame(base, p.h1))
	var cloth := Rect2(1, 0, 19, 12)
	v.draw_colored_polygon(PackedVector2Array([cloth.position, Vector2(cloth.end.x, 1.5), Vector2(cloth.end.x, cloth.end.y + 1.5),
		Vector2(cloth.position.x, cloth.end.y)]), p.roof_color)
	var c := cloth.get_center() + Vector2(0, 0.7)
	if p.roof_color.v > 0.9:
		v.draw_circle(c, 3.6, Color(0.1, 0.25, 0.65))
		v.draw_colored_polygon(PackedVector2Array([c + Vector2(-3.6, 0), c + Vector2(-2.5, -2.6), c + Vector2(0, -3.6),
			c + Vector2(2.5, -2.6), c + Vector2(3.6, 0)]), Color(0.82, 0.12, 0.18))
		for q in [Vector2(-7, -3.5), Vector2(7, -3.5), Vector2(-7, 3.5), Vector2(7, 3.5)]:
			v.draw_line(c + q - Vector2(1.2, 0), c + q + Vector2(1.2, 0), Color(0.1, 0.1, 0.1), 1.6)
	else:
		v.draw_circle(c, 3.0, GOLD)
	v.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 옥상 정원 퍼걸러: 나무 데크, 기둥, 격자 보, 전구 줄
static func _pergola(v: BuildingView, p: BuildingModel.Piece) -> void:
	var r := p.rect
	v.draw_colored_polygon(v._corners(r.grow(4.0), p.h0 + 0.5), Color(0.42, 0.3, 0.2))
	var y := r.position.y - 2.0
	while y < r.end.y + 4.0:
		v.draw_line(Vector2(r.position.x - 4.0, y) + IsoView.lift(p.h0 + 0.6), Vector2(r.end.x + 4.0, y) + IsoView.lift(p.h0 + 0.6),
			Color(0.32, 0.22, 0.14), 0.8)
		y += 6.0
	# 데크 위 탁자 둘
	for k in 2:
		var at := r.position + r.size * Vector2(0.3 + k * 0.4, 0.5)
		v.draw_colored_polygon(v._corners(Rect2(at - Vector2(7, 5), Vector2(14, 10)), p.h0 + 6.0), Color(0.82, 0.8, 0.76))
		v.draw_line(at + IsoView.lift(p.h0), at + IsoView.lift(p.h0 + 6.0), Color(0.2, 0.2, 0.2), 1.5)
	var wood := p.wall.lightened(0.15)
	var posts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y),
		Vector2(r.get_center().x, r.end.y), Vector2(r.end.x, r.get_center().y)]
	for q: Vector2 in posts:
		v.draw_line(q + IsoView.lift(p.h0), q + IsoView.lift(p.h1), wood, 2.2)
	var n := maxi(3, int(r.size.x / 14.0))
	for k in n + 1:
		var x := lerpf(r.position.x, r.end.x, float(k) / n)
		v.draw_line(Vector2(x, r.position.y) + IsoView.lift(p.h1), Vector2(x, r.end.y) + IsoView.lift(p.h1), wood, 1.4)
	for yy in [r.position.y, r.get_center().y, r.end.y]:
		v.draw_line(Vector2(r.position.x - 3.0, yy) + IsoView.lift(p.h1 + 1.0), Vector2(r.end.x + 3.0, yy) + IsoView.lift(p.h1 + 1.0),
			wood.darkened(0.15), 2.0)
	var x := r.position.x + 4.0
	while x < r.end.x:
		var sag := Vector2(x, r.end.y) + IsoView.lift(p.h1 - 3.0)
		v.draw_circle(sag, 3.0, Color(1.0, 0.8, 0.4, 0.2))
		v.draw_circle(sag, 1.2, WARM)
		x += 9.0


## 다리 위 녹슨 물탱크 (구도심 옥상)
static func _stilt_tank(v: BuildingView, p: BuildingModel.Piece) -> void:
	var r := p.rect
	var leg := (p.h1 - p.h0) * 0.42
	var inner := r.grow(-3.0)
	var feet := [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]
	for i in [0, 1, 3, 2]:
		var q: Vector2 = feet[i]
		v.draw_line(q + IsoView.lift(p.h0), q + IsoView.lift(p.h0 + leg), IRON, 2.0)
	v.draw_line(feet[3] + IsoView.lift(p.h0), feet[2] + IsoView.lift(p.h0 + leg), IRON, 1.0)
	v.draw_line(feet[2] + IsoView.lift(p.h0), feet[1] + IsoView.lift(p.h0 + leg), IRON, 1.0)
	var tank := BuildingModel.Piece.new()
	tank.rect = r
	tank.h0 = p.h0 + leg
	tank.h1 = p.h1 - 6.0
	tank.wall = p.wall
	tank.roof_color = p.roof_color
	v._cylinder(tank, false)
	# 원뿔 뚜껑과 테
	var c := r.get_center()
	var rx := r.size.x * 0.55
	v.draw_set_transform_matrix(IsoView.screen_frame(c))
	v.draw_colored_polygon(PackedVector2Array([Vector2(-rx, -tank.h1), Vector2(0, -p.h1 - 2.0), Vector2(rx, -tank.h1),
		Vector2(0, -tank.h1 + rx * 0.5)]), p.wall.darkened(0.3))
	for z in [tank.h0 + 4.0, (tank.h0 + tank.h1) * 0.5]:
		v.draw_line(Vector2(-rx, -z), Vector2(rx, -z), p.wall.darkened(0.45), 1.5)
	v.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 박공 지붕 앞 경사면의 채광창
static func _skylights(v: BuildingView, p: BuildingModel.Piece) -> void:
	var r := p.rect
	var h := p.h1 - 1.0
	var t := p.h1 + p.rise
	var glass := Color(0.38, 0.52, 0.62)
	if r.size.x >= r.size.y:
		var yc := r.get_center().y
		var y1 := r.end.y + p.eave
		var n := maxi(1, int(r.size.x / 90.0))
		for k in n:
			var x0 := lerpf(r.position.x, r.end.x, (k + 0.3) / n)
			var x1 := x0 + minf(34.0, r.size.x / n * 0.4)
			var q := func(x: float, u: float) -> Vector2: return Vector2(x, lerpf(yc, y1, u)) + IsoView.lift(lerpf(t, h, u))
			v.draw_colored_polygon(PackedVector2Array([q.call(x0, 0.22), q.call(x1, 0.22), q.call(x1, 0.55), q.call(x0, 0.55)]), glass)
			v.draw_line(q.call(x0 + 3.0, 0.27), q.call(x0 + 3.0, 0.5), Color(0.8, 0.9, 1.0, 0.5), 1.5)
	else:
		var xc := r.get_center().x
		var x1 := r.end.x + p.eave
		var n := maxi(1, int(r.size.y / 90.0))
		for k in n:
			var y0 := lerpf(r.position.y, r.end.y, (k + 0.3) / n)
			var y1 := y0 + minf(34.0, r.size.y / n * 0.4)
			var q := func(y: float, u: float) -> Vector2: return Vector2(lerpf(xc, x1, u), y) + IsoView.lift(lerpf(t, h, u))
			v.draw_colored_polygon(PackedVector2Array([q.call(y0, 0.22), q.call(y0, 0.55), q.call(y1, 0.55), q.call(y1, 0.22)]), glass)


## 태양광 판 격자
static func _solar(v: BuildingView, p: BuildingModel.Piece) -> void:
	var r := p.rect
	var l := IsoView.lift(p.h1 + 0.3)
	var line := Color(0.6, 0.7, 0.85, 0.55)
	var x := r.position.x + 8.0
	while x < r.end.x - 2.0:
		v.draw_line(Vector2(x, r.position.y) + l, Vector2(x, r.end.y) + l, line, 0.8)
		x += 8.0
	var y := r.position.y + r.size.y * 0.5
	v.draw_line(Vector2(r.position.x, y) + l, Vector2(r.end.x, y) + l, line, 0.8)
