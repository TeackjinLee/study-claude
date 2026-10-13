class_name SpecialBuilding
## 2.5D 기능 건물 8종: 경찰서·병원·강남 조직 사옥·구도심 건달파 사무실·외곽 밀수단 거점·정비소·24시 사우나·편의점.
## 참고 그림은 assets/buildings/special_concepts_v1 시안이다 (그림 파일은 쓰지 않고 코드로 짓는다).
## BuildingModel과 같은 덩어리(Piece)로 짓고, 새 벽 장식·지붕은 SpecialDecor가 그린다.
## 시안 속 경찰차·구급차·검은 세단은 그리지 않는다 — 탈 수 있는 진짜 차와 헷갈린다. 세우는 칸만 바닥에 그린다.
## 본채 자리(_body_*)는 바닥 그림(draw_ground)도 같이 쓴다 — 계단·주차 칸이 본채 앞에 맞는다.

const STYLES: Array[StringName] = [&"police", &"hospital", &"gang_tower", &"gang_office", &"gang_dock",
	&"car_center", &"sauna", &"convenience"]
const FH := IsoView.FLOOR_HEIGHT
const NAVY := Color(0.1, 0.2, 0.5)
const GREEN := Color(0.16, 0.46, 0.36)
const RED := Color(0.82, 0.12, 0.14)
const GOLD := Color(0.86, 0.66, 0.26)
const STEEL := Color(0.3, 0.31, 0.33)
const LINE := Color(0.92, 0.92, 0.88, 0.75)


static func owns(style: StringName) -> bool:
	return style in STYLES


static func build(out: Array[BuildingModel.Piece], r: Rect2, t: BuildingType, seed: int, height: float) -> void:
	match t.style:
		&"police": _police(out, r, t, seed, height)
		&"hospital": _hospital(out, r, t, seed, height)
		&"gang_tower": _gang_tower(out, r, t, seed, height)
		&"gang_office": _gang_office(out, r, t, seed, height)
		&"gang_dock": _gang_dock(out, r, t, seed, height)
		&"car_center": _car_center(out, r, t, seed, height)
		&"sauna": _sauna(out, r, t, seed, height)
		&"convenience": _convenience(out, r, t, seed, height)


static func _box(r: Rect2, h0: float, h1: float, wall: Color, roof: StringName, roof_color: Color, windows: StringName,
		seed: int) -> BuildingModel.Piece:
	return BuildingModel._box(r, h0, h1, wall, roof, roof_color, windows, seed)


static func _sign(t: BuildingType, k := 0) -> String:
	return t.signs[k] if t.signs.size() > k else ""


## 부지 안 본채 자리: 최대 크기 size, 남는 땅에서 at 비율 위치
static func _fit(r: Rect2, size: Vector2, at: Vector2, margin := BuildingModel.INSET) -> Rect2:
	var inner := r.grow(-margin)
	var s := Vector2(minf(size.x, inner.size.x), minf(size.y, inner.size.y))
	return Rect2(inner.position + (inner.size - s) * at, s)


## 나무 (부지 비율 자리)
static func _trees(out: Array[BuildingModel.Piece], r: Rect2, seed: int, spots: Array, s := 1.0) -> void:
	for k in spots.size():
		out.append(BuildingModel._tree(r.position + r.size * (spots[k] as Vector2), seed + k * 5, s))


# ── 경찰서: 흰 타일 4층, 파란 띠와 독수리 휘장 간판, 옥상 통신탑, 정문 계단과 깃대 셋 ──

static func _body_police(r: Rect2) -> Rect2:
	return _fit(r, Vector2(280, 190), Vector2(0.5, 0.14))


static func _police(out: Array[BuildingModel.Piece], r: Rect2, t: BuildingType, seed: int, height: float) -> void:
	var b := _body_police(r)
	var h := maxf(height, FH * 3.0)
	var body := _box(b, 0.0, h, t.wall_color, &"flat", BuildingModel.top_color(t, seed), &"punched", seed)
	body.deco = [&"police_band", &"police_door", &"emblem_sign"]
	body.text = _sign(t)
	body.accent = t.accent
	BuildingModel._stair_house(body, seed)
	BuildingModel._units(body, seed, 3)
	body.on_top.append(_box(Rect2(b.position + b.size * Vector2(0.74, 0.14), Vector2(28, 28)), h, h + 92.0, STEEL,
		&"mast", RED, &"none", seed))
	out.append(body)
	# 정문 왼쪽 깃대 셋 (국기·경찰기·시기)
	for k in 3:
		var at := Vector2(b.position.x + 22.0 + k * 20.0, b.end.y + 34.0)
		var flag := _box(Rect2(at - Vector2(2, 2), Vector2(4, 4)), 0.0, 74.0, Color(0.86, 0.86, 0.84), &"flag",
			[Color.WHITE, NAVY, Color(0.25, 0.55, 0.3)][k], &"none", seed + k)
		out.append(flag)
	_trees(out, r, seed, [Vector2(0.06, 0.62), Vector2(0.94, 0.6), Vector2(0.94, 0.9)], 1.15)


# ── 병원: 흰 6층 본관, 초록 계단탑(십자·세로 '병원'), 앞쪽 빨간 응급실 동 ──

static func _body_hospital(r: Rect2) -> Rect2:
	return _fit(r, Vector2(320, 200), Vector2(0.3, 0.1))


static func _hospital(out: Array[BuildingModel.Piece], r: Rect2, t: BuildingType, seed: int, height: float) -> void:
	var b := _body_hospital(r)
	var h := maxf(height, FH * 4.0)
	var core_w := 66.0
	var main_r := b
	var main := _box(main_r, 0.0, h, t.wall_color, &"flat", BuildingModel.top_color(t, seed), &"punched", seed)
	main.accent = GREEN
	BuildingModel._stair_house(main, seed)
	BuildingModel._units(main, seed, 4)
	BuildingModel._plant(main, Vector2(0.06, 0.62), Vector2(0.22, 0.22), 4.0, BuildingModel.HEDGE)   # 옥상 화단
	out.append(main)
	# 초록 계단탑: 본관 남동쪽 모서리에서 남쪽으로 조금 나오고, 본관보다 한 층 높다 (본관보다 앞이라 나중에 그려진다)
	var core := _box(Rect2(Vector2(b.end.x - core_w, b.end.y - 36.0), Vector2(core_w, 50.0)), 0.0, h + FH,
		GREEN, &"flat", GREEN.darkened(0.25), &"slit", seed + 1)
	core.deco = [&"hospital_vsign"]
	core.text = _sign(t)
	BuildingModel._units(core, seed + 3, 1)
	out.append(core)
	# 응급실 동 (본관 앞 1층)
	var er := _box(Rect2(b.position.x + 26.0, b.end.y, b.size.x - core_w - 40.0, 58.0), 0.0, FH * 1.9,
		t.wall_color.darkened(0.04), &"flat", Color(0.6, 0.6, 0.6), &"none", seed + 2)
	er.deco = [&"er_door", &"er_band"]
	er.text = _sign(t, 1)
	er.accent = RED
	out.append(er)
	_trees(out, r, seed, [Vector2(0.05, 0.12), Vector2(0.05, 0.9), Vector2(0.95, 0.88)], 1.1)


# ── 강남 조직 사옥: 검은 석재와 금색 기둥, 통유리, 옥상 정원 퍼걸러 ──

static func _body_tower(r: Rect2) -> Rect2:
	return _fit(r, Vector2(210, 190), Vector2(0.5, 0.22))


static func _gang_tower(out: Array[BuildingModel.Piece], r: Rect2, t: BuildingType, seed: int, height: float) -> void:
	var b := _body_tower(r)
	var h := maxf(height, FH * 5.0)
	var body := _box(b, 0.0, h, t.wall_color, &"flat", BuildingModel.top_color(t, seed), &"glass", seed)
	body.deco = [&"gold_trim", &"gold_door"]
	body.accent = GOLD
	body.on_top.append(_box(Rect2(b.position + Vector2(14, 14), b.size * Vector2(0.52, 0.48)), h, h + 17.0,
		BuildingModel.WOOD, &"pergola", GOLD, &"none", seed))
	# 옥상 정원 화단 (남쪽 난간을 따라)
	var k := 0
	var x := 0.08
	while x < 0.86:
		var bush := BuildingModel._plant(body, Vector2(x, 0.86), Vector2(0.12, 0.08), 6.0, BuildingModel.HEDGE.lightened(0.05 * (k % 2)))
		bush.roof_color = BuildingModel.HEDGE.lightened(0.12)
		x += 0.16
		k += 1
	BuildingModel._units(body, seed, 2)
	out.append(body)
	_trees(out, r, seed, [Vector2(0.08, 0.84), Vector2(0.92, 0.84)], 1.2)


# ── 구도심 건달파 사무실: 낡은 붉은 벽돌 2층, 빨간 '사무실' 간판, 줄무늬 차양, 옆벽 철제 계단, 녹슨 물탱크 ──

static func _body_office(r: Rect2) -> Rect2:
	return _fit(r, Vector2(220, 170), Vector2(0.35, 0.3))


static func _gang_office(out: Array[BuildingModel.Piece], r: Rect2, t: BuildingType, seed: int, height: float) -> void:
	var b := _body_office(r)
	var h := maxf(height, FH * 2.0)
	var body := _box(b, 0.0, h, t.wall_color, &"flat", BuildingModel.top_color(t, seed), &"brick", seed)
	body.deco = [&"fire_escape", &"door", &"striped_awning", &"office_plate"]
	body.text = _sign(t)
	body.accent = RED
	body.on_top.append(_box(Rect2(b.position + b.size * Vector2(0.62, 0.14), Vector2(30, 30)), h, h + 46.0,
		BuildingModel.RUST, &"stilt_tank", BuildingModel.RUST.darkened(0.2), &"none", seed))
	BuildingModel._units(body, seed, 1)
	BuildingModel._plant(body, Vector2(0.08, 0.7), Vector2(0.14, 0.14), 5.0, BuildingModel.HEDGE)
	out.append(body)
	_trees(out, r, seed, [Vector2(0.08, 0.86)], 1.0)


# ── 외곽 밀수단 거점: 초록 골함석 부두 창고, 열린 셔터 안 짐 더미, 채광창, 앞마당 컨테이너 ──

static func _body_dock(r: Rect2) -> Rect2:
	var inner := r.grow(-BuildingModel.INSET)
	var depth := minf(200.0, inner.size.y - 76.0)
	var w := minf(330.0, inner.size.x)
	return Rect2(Vector2(inner.end.x - w, inner.position.y), Vector2(w, depth))


static func _gang_dock(out: Array[BuildingModel.Piece], r: Rect2, t: BuildingType, seed: int, height: float) -> void:
	var b := _body_dock(r)
	var h := maxf(height, FH * 2.0)
	var body := _box(b, 0.0, h, t.wall_color, &"gable_sky", t.roof_colors[0], &"metal", seed)
	body.rise = minf(minf(b.size.x, b.size.y) * 0.2, 40.0)
	body.eave = 6.0
	body.deco = [&"open_shutter", &"wall_lamps"]
	body.accent = t.accent
	out.append(body)
	# 앞마당 컨테이너 (서쪽)
	var inner := r.grow(-BuildingModel.INSET)
	var box_r := Rect2(Vector2(inner.position.x + 4.0, b.end.y + 16.0), Vector2(minf(124.0, inner.size.x * 0.45), 42.0))
	var box := _box(box_r, 0.0, 34.0, t.wall_color.darkened(0.2), &"flat", t.wall_color.darkened(0.1), &"metal", seed + 1)
	box.deco = [&"container_doors"]
	out.append(box)


# ── 정비소: 콘크리트 1층 차고, 파란 '정비소' 간판, 리프트 보이는 열린 칸과 닫힌 셔터, 옥상 태양광 ──

static func _body_garage(r: Rect2) -> Rect2:
	return _fit(r, Vector2(300, 160), Vector2(0.45, 0.14))


static func _car_center(out: Array[BuildingModel.Piece], r: Rect2, t: BuildingType, seed: int, height: float) -> void:
	var b := _body_garage(r)
	var h := maxf(height, FH * 2.0)
	var body := _box(b, 0.0, h, t.wall_color, &"flat", BuildingModel.top_color(t, seed), &"none", seed)
	body.deco = [&"repair_bays", &"repair_sign"]
	body.text = _sign(t)
	body.accent = NAVY
	# 태양광 판 (옥상 가운데 줄)
	var n := maxi(2, int(b.size.x / 90.0))
	for k in n:
		var panel := BuildingModel._plant(body, Vector2(0.08 + k * 0.84 / n, 0.18), Vector2(0.84 / n - 0.03, 0.34), 3.0,
			Color(0.16, 0.24, 0.42))
		panel.roof = &"solar"
		panel.roof_color = Color(0.2, 0.32, 0.56)
	BuildingModel._units(body, seed, 2)
	out.append(body)


# ── 24시 사우나: 갈색 타일 4층, 세로 '24시 사우나 ♨' 간판, 옆 은색 굴뚝, 기와 차양 현관, 옥상 파란 물탱크 ──

static func _body_sauna(r: Rect2) -> Rect2:
	var inner := r.grow(-BuildingModel.INSET)
	var w := minf(210.0, inner.size.x - 46.0)
	var d := minf(190.0, inner.size.y - 30.0)
	return Rect2(inner.position + Vector2(maxf(0.0, (inner.size.x - 46.0 - w) * 0.4), 6.0), Vector2(w, d))


static func _sauna(out: Array[BuildingModel.Piece], r: Rect2, t: BuildingType, seed: int, height: float) -> void:
	var b := _body_sauna(r)
	var h := maxf(height, FH * 3.0)
	var body := _box(b, 0.0, h, t.wall_color, &"flat", BuildingModel.top_color(t, seed), &"punched", seed)
	body.deco = [&"tile_canopy", &"sauna_sign"]
	body.text = _sign(t)
	body.accent = RED
	for k in 2:
		body.on_top.append(_box(Rect2(b.position + b.size * Vector2(0.18 + k * 0.24, 0.16), Vector2(28, 28)), h, h + 24.0,
			Color(0.2, 0.42, 0.8), &"tank", Color(0.2, 0.42, 0.8), &"none", seed + k))
	BuildingModel._units(body, seed, 2)
	out.append(body)
	# 은색 굴뚝: 땅에서 옥상 위로 (본채 동쪽 옆)
	var c := Vector2(b.end.x + 21.0, b.position.y + b.size.y * 0.55)
	out.append(_box(Rect2(c - Vector2(15, 15), Vector2(30, 30)), 0.0, h + 66.0, Color(0.7, 0.7, 0.68), &"chimney",
		Color(0.52, 0.5, 0.48), &"none", seed))


# ── 편의점 GO25: 흰 1층 상자, 청록·주황·빨강 띠와 상호, 불 켜진 통유리, 앞 파라솔 없는 플라스틱 탁자 ──

static func _body_store(r: Rect2) -> Rect2:
	return _fit(r, Vector2(200, 140), Vector2(0.5, 0.2))


static func _convenience(out: Array[BuildingModel.Piece], r: Rect2, t: BuildingType, seed: int, height: float) -> void:
	var b := _body_store(r)
	var h := maxf(height, FH * 1.6)
	var body := _box(b, 0.0, h, t.wall_color, &"flat", BuildingModel.top_color(t, seed), &"none", seed)
	body.deco = [&"store_front", &"store_band", &"vending"]
	body.text = _sign(t)
	body.accent = t.accent
	for k in 2:
		var unit := _box(Rect2(b.position + b.size * Vector2(0.18 + k * 0.4, 0.3), Vector2(30, 22)), h, h + 13.0,
			BuildingModel.UNIT, &"flat", BuildingModel.UNIT.lightened(0.15), &"none", seed + k)
		unit.deco = [&"fan"]
		body.on_top.append(unit)
	out.append(body)
	_trees(out, r, seed, [Vector2(0.92, 0.18)], 0.9)


# ── 바닥 (청크가 그린다: 사람·차보다 늘 밑) ────────────────

static func draw_ground(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int) -> void:
	match t.style:
		&"police": _ground_police(ci, r, seed)
		&"hospital": _ground_hospital(ci, r, seed)
		&"gang_tower": _ground_tower(ci, r, seed)
		&"gang_office": _ground_office(ci, r, seed)
		&"gang_dock": _ground_dock(ci, r, seed)
		&"car_center": _ground_garage(ci, r, seed)
		&"sauna": _ground_sauna(ci, r, seed)
		&"convenience": _ground_store(ci, r, seed)


## 주차 칸 n개 (가로로 늘어선 세로 칸)
static func _bays(ci: CanvasItem, at: Vector2, n: int, size: Vector2, color := LINE) -> void:
	for k in n + 1:
		var x := at.x + k * size.x
		ci.draw_line(Vector2(x, at.y), Vector2(x, at.y + size.y), color, 2.0)
	ci.draw_line(at, at + Vector2(n * size.x, 0), color, 2.0)


## 정문 앞 계단 (본채 남쪽 벽 가운데 c, 폭 w)
static func _steps(ci: CanvasItem, c: float, y: float, w: float, color: Color, n := 3) -> void:
	for k in n:   # 벽에 붙은 맨 위 단부터 (앞 단이 나중에 그려져 위를 덮는다)
		BuildingModel.low_box(ci, Rect2(c - w * 0.5 - k * 3.0, y + k * 6.0, w + k * 6.0, 6.0), float(n - k) * 3.0,
			color.lightened(k * 0.05))


## 낮은 철제 울타리 (선 위 기둥)
static func _fence(ci: CanvasItem, a: Vector2, b: Vector2, h: float, color: Color) -> void:
	var l := IsoView.lift(h)
	ci.draw_line(a + l, b + l, color, 1.5)
	ci.draw_line(a + IsoView.lift(h * 0.5), b + IsoView.lift(h * 0.5), color, 1.0)
	var n := maxi(1, int(a.distance_to(b) / 8.0))
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		ci.draw_line(p, p + l, color, 1.0)


static func _ground_police(ci: CanvasItem, r: Rect2, seed: int) -> void:
	var b := _body_police(r)
	ci.draw_rect(r, BuildingModel.PAVING)
	ci.draw_rect(Rect2(r.position.x, b.end.y, r.size.x, r.end.y - b.end.y), Color(0.27, 0.28, 0.3))   # 앞마당 아스팔트
	ci.draw_rect(r, BuildingModel.STONE.darkened(0.2), false, 2.0)
	# 순찰차 주차 칸 (동쪽)
	_bays(ci, Vector2(b.get_center().x + 50.0, b.end.y + 40.0), 3, Vector2(34, 66))
	ci.draw_string(ThemeDB.fallback_font, Vector2(b.get_center().x + 54.0, b.end.y + 120.0), "순찰차 전용",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.95, 0.9, 0.55))
	_steps(ci, b.get_center().x, b.end.y, 60.0, BuildingModel.STONE)
	# 앞 울타리 (정문 길은 비운다)
	var y := r.end.y - 6.0
	_fence(ci, Vector2(r.position.x + 4.0, y), Vector2(b.get_center().x - 40.0, y), 10.0, Color(0.18, 0.2, 0.26))
	_fence(ci, Vector2(b.get_center().x + 40.0, y), Vector2(r.end.x - 4.0, y), 10.0, Color(0.18, 0.2, 0.26))
	for k in 4:
		BuildingModel.low_box(ci, Rect2(r.position.x + 8.0 + k * 22.0, b.end.y + 4.0, 18.0, 8.0), 6.0, BuildingModel.HEDGE)
	BuildingModel.low_box(ci, Rect2(b.get_center().x + 36.0, b.end.y + 12.0, 6.0, 6.0), 9.0, Color(0.95, 0.45, 0.1))   # 라바콘


static func _ground_hospital(ci: CanvasItem, r: Rect2, seed: int) -> void:
	var b := _body_hospital(r)
	ci.draw_rect(r, BuildingModel.PAVING)
	ci.draw_rect(r, BuildingModel.STONE.darkened(0.2), false, 2.0)
	# 구급차 칸: 응급실 앞 노란 빗금
	var er_y := b.end.y + 58.0
	var bay := Rect2(Vector2(b.position.x + 50.0, er_y + 6.0), Vector2(110, 70))
	ci.draw_rect(bay, Color(0.25, 0.26, 0.28))
	ci.draw_rect(bay, Color(0.95, 0.8, 0.2), false, 2.0)
	var x := bay.position.x + 8.0
	while x < bay.end.x:
		ci.draw_line(Vector2(x, bay.position.y + 2.0), Vector2(minf(x + 14.0, bay.end.x), bay.position.y + 16.0),
			Color(0.95, 0.8, 0.2, 0.7), 2.0)
		x += 12.0
	ci.draw_string(ThemeDB.fallback_font, bay.position + Vector2(10, 50), "구급차", HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		Color(0.95, 0.95, 0.9, 0.7))
	_bays(ci, Vector2(bay.end.x + 30.0, er_y + 10.0), 4, Vector2(32, 62))
	BuildingModel.low_box(ci, Rect2(bay.position.x - 16.0, er_y + 4.0, 7.0, 7.0), 10.0, RED)   # 소화전
	for k in 6:
		BuildingModel.low_box(ci, Rect2(r.end.x - 30.0, b.position.y + 20.0 + k * 26.0, 16.0, 20.0), 6.0, BuildingModel.HEDGE)


static func _ground_tower(ci: CanvasItem, r: Rect2, seed: int) -> void:
	var b := _body_tower(r)
	ci.draw_rect(r, Color(0.2, 0.2, 0.22))
	ci.draw_rect(r.grow(-6.0), Color(0.28, 0.27, 0.26))
	ci.draw_rect(r, GOLD.darkened(0.4), false, 2.0)
	# 정문 길 (금색 테두리 석재)과 계단
	var c := b.get_center().x
	var walk := Rect2(c - 30.0, b.end.y, 60.0, r.end.y - b.end.y)
	ci.draw_rect(walk, Color(0.36, 0.34, 0.32))
	ci.draw_rect(walk, GOLD.darkened(0.25), false, 1.5)
	_steps(ci, c, b.end.y, 64.0, Color(0.32, 0.3, 0.3))
	# 화단과 금색 조명 기둥
	for side in [-1.0, 1.0]:
		BuildingModel.low_box(ci, Rect2(c + side * 70.0 - 24.0, b.end.y + 10.0, 48.0, 22.0), 9.0, Color(0.22, 0.22, 0.24))
		BuildingModel.low_box(ci, Rect2(c + side * 70.0 - 20.0, b.end.y + 13.0, 40.0, 16.0), 12.0, BuildingModel.HEDGE)
		var post := Vector2(c + side * 36.0, b.end.y + 40.0)
		BuildingModel.low_box(ci, Rect2(post - Vector2(2, 2), Vector2(4, 4)), 16.0, Color(0.15, 0.15, 0.16))
		ci.draw_circle(post + IsoView.lift(17.0), 3.0, Color(1.0, 0.85, 0.5))
		ci.draw_circle(post + IsoView.lift(17.0), 8.0, Color(1.0, 0.8, 0.4, 0.18))
	# 손님 차 대는 칸 (동쪽, 금색 선)
	_bays(ci, Vector2(c + 110.0, b.end.y + 30.0), 2, Vector2(38, 70), GOLD.darkened(0.1))


static func _ground_office(ci: CanvasItem, r: Rect2, seed: int) -> void:
	var b := _body_office(r)
	ci.draw_rect(r, BuildingModel.PAVING.darkened(0.08))
	ci.draw_rect(r, BuildingModel.STONE.darkened(0.3), false, 2.0)
	for k in 5:
		var c := r.position + r.size * Vector2(BuildingModel.hash01(seed, k), BuildingModel.hash01(seed, k + 9))
		ci.draw_circle(c, 6.0 + BuildingModel.hash01(seed, k + 3) * 8.0, Color(0.1, 0.1, 0.1, 0.2))   # 얼룩
	# 동쪽 벽 아래 쓰레기통·재활용 통, 정문 옆 화분
	var y := b.end.y - 26.0
	for k in 3:
		BuildingModel.low_box(ci, Rect2(b.end.x + 6.0, y - k * 16.0, 12.0, 12.0), 13.0,
			[Color(0.2, 0.4, 0.7), Color(0.25, 0.5, 0.3), Color(0.55, 0.55, 0.5)][k])
	for k in 2:
		BuildingModel.low_box(ci, Rect2(b.position.x + 10.0 + k * 14.0, b.end.y + 4.0, 10.0, 10.0), 6.0, Color(0.55, 0.32, 0.2))
		ci.draw_circle(Vector2(b.position.x + 15.0 + k * 14.0, b.end.y + 9.0) + IsoView.lift(10.0), 5.0, BuildingModel.HEDGE.lightened(0.1))
	BuildingModel.low_box(ci, Rect2(b.end.x - 40.0, b.end.y + 8.0, 18.0, 14.0), 10.0, Color(0.6, 0.45, 0.28))   # 나무 상자


static func _ground_dock(ci: CanvasItem, r: Rect2, seed: int) -> void:
	var b := _body_dock(r)
	BuildingModel._yard_concrete(ci, r, seed, false)
	# 하역장 끝 노랑·검정 경고 띠
	var y := b.end.y + 4.0
	var x := b.position.x
	var k := 0
	while x < b.end.x:
		ci.draw_rect(Rect2(x, y, minf(10.0, b.end.x - x), 6.0), Color(0.95, 0.78, 0.15) if k % 2 == 0 else Color(0.08, 0.08, 0.08))
		x += 10.0
		k += 1
	# 셔터 앞 팔레트·나무 상자·방수포 더미
	var c := b.get_center().x
	for i in 4:
		var at := Vector2(c + 50.0 + (i % 2) * 26.0, b.end.y + 16.0 + (i / 2) * 22.0)
		BuildingModel.low_box(ci, Rect2(at, Vector2(22, 18)), 4.0, Color(0.55, 0.4, 0.24))
		BuildingModel.low_box(ci, Rect2(at + Vector2(3, 2), Vector2(16, 13)), 9.0 + (i % 3) * 4.0, Color(0.72, 0.56, 0.36))
	BuildingModel.low_box(ci, Rect2(c - 96.0, b.end.y + 30.0, 44.0, 28.0), 14.0, Color(0.18, 0.32, 0.6))
	for i in 3:
		BuildingModel.low_box(ci, Rect2(b.end.x - 30.0, b.end.y + 14.0 + i * 13.0, 10.0, 10.0), 12.0, Color(0.25, 0.42, 0.3))   # 드럼통


static func _ground_garage(ci: CanvasItem, r: Rect2, seed: int) -> void:
	var b := _body_garage(r)
	ci.draw_rect(r, BuildingModel.CONCRETE)
	ci.draw_rect(r, BuildingModel.STONE.darkened(0.2), false, 2.0)
	# 열린 칸 앞 기름 얼룩과 배수 홈
	var bay_c := b.position.x + b.size.x * 0.27
	ci.draw_circle(Vector2(bay_c, b.end.y + 30.0), 18.0, Color(0.05, 0.05, 0.06, 0.35))
	ci.draw_rect(Rect2(b.position.x + 20.0, b.end.y + 60.0, b.size.x * 0.75, 4.0), Color(0.15, 0.15, 0.16))
	# 타이어 더미 (서쪽 끝), 공구함, 드럼통
	for k in 4:
		var at := Vector2(b.position.x - 2.0 + (k % 2) * 14.0, b.end.y + 8.0 + (k / 2) * 14.0)
		for s in 3:
			BuildingModel.low_box(ci, Rect2(at, Vector2(12, 12)), 3.0 + s * 3.0, Color(0.1, 0.1, 0.11).lightened(s * 0.03))
	BuildingModel.low_box(ci, Rect2(b.position.x + b.size.x * 0.5 - 8.0, b.end.y + 6.0, 14.0, 9.0), 14.0, RED.darkened(0.1))
	BuildingModel.low_box(ci, Rect2(b.end.x - 22.0, b.end.y + 8.0, 10.0, 10.0), 12.0, Color(0.2, 0.35, 0.6))


static func _ground_sauna(ci: CanvasItem, r: Rect2, seed: int) -> void:
	var b := _body_sauna(r)
	BuildingModel._plinth(ci, r, seed)
	# 현관 앞 등불 둘과 화분
	var c := b.position.x + b.size.x * 0.4
	for side in [-1.0, 1.0]:
		var at := Vector2(c + side * 30.0, b.end.y + 10.0)
		BuildingModel.low_box(ci, Rect2(at - Vector2(5, 5), Vector2(10, 10)), 8.0, Color(0.32, 0.3, 0.3))
		ci.draw_circle(at + IsoView.lift(12.0), 4.0, Color(1.0, 0.75, 0.4))
		ci.draw_circle(at + IsoView.lift(12.0), 9.0, Color(1.0, 0.7, 0.35, 0.2))
	BuildingModel.low_box(ci, Rect2(b.end.x - 14.0, b.end.y + 4.0, 12.0, 12.0), 12.0, Color(0.3, 0.33, 0.38))   # 실외기


static func _ground_store(ci: CanvasItem, r: Rect2, seed: int) -> void:
	var b := _body_store(r)
	ci.draw_rect(r, BuildingModel.PAVING.lightened(0.04))
	ci.draw_rect(r, BuildingModel.STONE.darkened(0.2), false, 2.0)
	ci.draw_rect(Rect2(b.position.x, b.end.y, b.size.x, 10.0), Color(1.0, 0.95, 0.75, 0.12))   # 가게 불빛
	# 앞 플라스틱 탁자·의자 (파랑), 아이스크림 냉동고, 박스
	for k in 2:
		var at := Vector2(b.position.x + 40.0 + k * 70.0, b.end.y + 28.0)
		BuildingModel.low_box(ci, Rect2(at - Vector2(9, 7), Vector2(18, 14)), 9.0, Color(0.2, 0.4, 0.8))
		for side in [-1.0, 1.0]:
			BuildingModel.low_box(ci, Rect2(at + Vector2(side * 16.0 - 4.0, -4.0), Vector2(8, 8)), 6.0, Color(0.25, 0.48, 0.85))
	BuildingModel.low_box(ci, Rect2(b.end.x - 30.0, b.end.y + 6.0, 24.0, 12.0), 11.0, Color(0.9, 0.92, 0.95))
	BuildingModel.low_box(ci, Rect2(b.position.x + 4.0, b.end.y + 6.0, 12.0, 10.0), 8.0, Color(0.68, 0.55, 0.36))
