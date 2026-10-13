class_name BuildingModel
## 2.5D 건물 모양: 건물 종류(style)마다 덩어리(Piece) 몇 개로 짓는다 — 본채, 그 위에 얹힌 윗층·옥상 소품, 마당의 나무·카라반·판잣집.
## 참고 그림 '서울의 다양한 집들'(docs/10 3번)의 종류별 차이를 따른다: 빌라 붉은 벽돌·필로티, 연립 붉은 기와 박공,
## 한옥 처마, 아파트 동 번호, 공장 굴뚝, 창고 박공 지붕과 셔터, 쪽방촌 판잣집, 캠핑장 카라반·텐트.
## 노드 없는 계산이다. City가 덩어리마다 BuildingView를 세우고, 사람 키보다 낮은 것(담장·화단·마당·팔레트)은
## 청크가 바닥에 그린다(draw_ground) — 바닥 것은 늘 사람·차 밑에 깔린다.
## 충돌은 부지 사각형 그대로다. 본채는 부지 안쪽(INSET)에 세워 화단 띠가 보이게 한다.
## seed는 건물 번호: 같은 건물은 늘 같은 모양.

const FH := IsoView.FLOOR_HEIGHT
const INSET := 10.0                        ## 부지 가장자리 → 본채 벽 (화단·포장 띠)
const UNIT := Color(0.64, 0.65, 0.64)      ## 실외기·옥탑 콘크리트
const PAVING := Color(0.36, 0.35, 0.34)
const GRASS := Color(0.2, 0.3, 0.17)
const EARTH := Color(0.46, 0.4, 0.3)
const STONE := Color(0.6, 0.58, 0.53)
const HEDGE := Color(0.15, 0.33, 0.16)
const WOOD := Color(0.36, 0.22, 0.12)
const CONCRETE := Color(0.37, 0.37, 0.36)
const TENTS := [Color(0.92, 0.5, 0.18), Color(0.22, 0.5, 0.85), Color(0.9, 0.78, 0.25), Color(0.3, 0.62, 0.36)]
const TARP := Color(0.22, 0.36, 0.62)       ## 쪽방촌 지붕을 덮은 파란 방수포
const RUST := Color(0.5, 0.3, 0.18)


## 덩어리 하나: 바닥 사각형 rect 위에 h0~h1 높이로 세운 벽과 지붕
class Piece extends RefCounted:
	var rect: Rect2
	var h0 := 0.0                           ## 벽 바닥 높이 (얹힌 것은 아래 덩어리의 h1)
	var h1 := 18.0                          ## 벽 위 높이
	var wall := Color(0.5, 0.5, 0.5)
	## 지붕: flat 평지붕 / gable 박공 / hip 모임 / hanok 한옥 처마 / art 위에서 본 그림(특수 건물)
	## / tree 나무 / chimney 굴뚝 / tank 물탱크 / tent 텐트 / none
	var roof := &"flat"
	var roof_color := Color(0.3, 0.3, 0.32)
	var rise := 0.0                         ## 경사 지붕 높이 (나무는 수관 반지름)
	var eave := 0.0                         ## 처마가 벽 밖으로 나온 길이
	## 창: none / punched 보통 창 / brick 벽돌+창 / glass 커튼월 / officetel / slit 고시원 / apt
	## / ribbon 공장 띠창 / metal 골함석 / hanok 창살 / shack 판잣집 / caravan
	var windows := &"none"
	var deco: Array = []                    ## 벽 장식 (BuildingView._deco)
	var text := ""                          ## 대표 간판·동 번호
	var signs := PackedStringArray()        ## 1층 가게 간판 후보
	var accent := Color.WHITE
	var on_top: Array = []                  ## 이 덩어리 위에 얹혀 같이 그리는 덩어리 (윗층·옥상 소품·굴뚝)
	var seed := 0
	var floor_height := FH
	var surface_detail := false

	func top() -> float:
		var h := h1 + rise
		for p in on_top:
			h = maxf(h, p.top())
		return h


static func _box(r: Rect2, h0: float, h1: float, wall: Color, roof := &"flat", roof_color := Color(0.3, 0.3, 0.32),
		windows := &"none", seed := 0) -> Piece:
	var p := Piece.new()
	p.rect = r
	p.h0 = h0
	p.h1 = h1
	p.wall = wall
	p.roof = roof
	p.roof_color = roof_color
	p.windows = windows
	p.seed = seed
	return p


## seed·k로 정해지는 0~1 값 (같은 건물은 늘 같은 값)
static func hash01(seed: int, k: int) -> float:
	return float(posmod(seed * 2654435761 + k * 40503 + 7919, 1000)) / 1000.0


static func _pick(t: BuildingType, seed: int, k := 0) -> String:
	return t.signs[posmod(seed + k, t.signs.size())] if not t.signs.is_empty() else ""


## 2.5D 평지붕 색 (top_color가 비어 있으면 위에서 보기 지붕 색)
static func top_color(t: BuildingType, seed: int) -> Color:
	if t.top_color.a > 0.0:
		return t.top_color
	return t.roof_colors[posmod(seed, t.roof_colors.size())]


# ── 종류별 덩어리 ─────────────────────────────────────────

static func build(r: Rect2, t: BuildingType, seed: int, height: float) -> Array[Piece]:
	var out: Array[Piece] = []
	height *= t.visual_floor_scale
	match t.style:
		&"apt": _apt(out, r, t, seed, height)
		&"house": _house(out, r, t, seed, height)
		&"hanok": _hanok(out, r, t, seed)
		&"jjokbang": _jjokbang(out, r, t, seed)
		&"campsite": _campsite(out, r, t, seed)
		&"warehouse": _warehouse(out, r, t, seed, height)
		&"factory": _factory(out, r, t, seed, height)
		&"rowhouse": _rowhouse(out, r, t, seed, height)
		&"mixed": _mixed(out, r, t, seed, height)
		_:
			if LandmarkBuilding.owns(t.style):
				LandmarkBuilding.build(out, r, t, seed)
			elif SpecialBuilding.owns(t.style):
				SpecialBuilding.build(out, r, t, seed, height)
			else:
				_tower(out, r, t, seed, height)
	# 주거/창고에도 이미지 간판을 한 곳만 배치한다. 나무·옥상 설비는 대상에서 제외.
	if t.style in [&"house", &"villa", &"apt", &"rowhouse", &"hanok", &"jjokbang", &"warehouse"]:
		for p in out:
			if p.windows != &"none" and p.h1 - p.h0 >= 14.0 and p.roof not in [&"tree", &"tent", &"chimney", &"tank"]:
				p.deco.append(&"rental_image")
				break
	for p in out:
		_set_detail(p, t)
	return out


static func _set_detail(p: Piece, t: BuildingType) -> void:
	p.floor_height = FH * t.visual_floor_scale
	p.surface_detail = t.surface_detail
	for child: Piece in p.on_top:
		_set_detail(child, t)


## 특수 건물(경찰서·병원·본부·은신처·카센터): 부지 꽉 찬 상자에 위에서 본 지붕 그림을 그대로 올린다
static func special(r: Rect2, height: float, wall: Color, windows: StringName, seed: int) -> Array[Piece]:
	var p := _box(r, 0.0, height, wall, &"art", wall, windows, seed)
	p.deco = [&"shops"]
	return [p]


## 상가·사무실·오피스텔·빌라·고시원·원룸: 화단 띠 안쪽의 상자 한 동과 옥상 소품
static func _tower(out: Array[Piece], r: Rect2, t: BuildingType, seed: int, height: float) -> void:
	var body := _box(r.grow(-INSET), 0.0, height, t.wall_color, &"flat", top_color(t, seed), &"punched", seed)
	body.signs = t.signs
	body.accent = t.accent
	body.text = _pick(t, seed)
	match t.style:
		&"office":
			body.windows = &"glass"
			body.deco = [&"top_sign", &"entrance"]
			_stair_house(body, seed)
			_plant(body, Vector2(0.3, 0.25), Vector2(0.4, 0.4), 14.0, UNIT.darkened(0.15))   # 옥탑 기계실
			_units(body, seed, 2)
		&"officetel":
			body.windows = &"officetel"
			body.deco = [&"shops", &"vsign"]
			body.text = "오피스텔"
			_stair_house(body, seed)
			_units(body, seed, 3)
		&"villa":
			body.windows = &"brick"
			body.deco = [&"piloti", &"balcony", &"name"]
			_stair_house(body, seed)
			_units(body, seed, 2)
			_tank(body, seed)
		&"gosiwon":
			body.windows = &"slit"
			body.deco = [&"shops", &"vsign"]
			body.text = "고시원"
			_stair_house(body, seed, Color(0.6, 0.22, 0.2))
			_units(body, seed, 2)
		&"oneroom":
			body.deco = [&"plate", &"ac", &"door"]
			_stair_house(body, seed)
			_units(body, seed, 2)
		_:
			body.windows = &"brick" if seed % 2 == 0 else &"punched"
			body.deco = [&"shops", &"band_signs", &"vsign"]
			body.text = _pick(t, seed, 1)
			_units(body, seed, 3)
			_tank(body, seed)
			if t.style == &"commercial":
				_stair_house(body, seed)
				body.deco.append(&"awning")
	out.append(body)


## 상가주택: 1층 가게(차양)는 부지를 꽉 채우고, 윗층은 남·동쪽으로 한 발 물러나 있다
static func _mixed(out: Array[Piece], r: Rect2, t: BuildingType, seed: int, height: float) -> void:
	var base := r.grow(-INSET)
	var roof := top_color(t, seed)
	var lower := _box(base, 0.0, FH, t.wall_color, &"flat", roof.darkened(0.1), &"none", seed)
	lower.signs = t.signs
	lower.deco = [&"shops", &"awning"]
	var upper := _box(Rect2(base.position, base.size - Vector2(20, 20)), FH, maxf(height, FH * 3.0), t.wall_color,
		&"flat", roof, &"brick", seed)
	upper.deco = [&"vsign"]
	upper.text = _pick(t, seed, 1)
	upper.accent = City.NEON[posmod(seed, City.NEON.size())]
	_units(upper, seed, 2)
	lower.on_top.append(upper)
	out.append(lower)


## 아파트 단지: 판상형 동 한두 개(동 번호가 옆벽에), 옥상 계단실, 동 사이 나무
static func _apt(out: Array[Piece], r: Rect2, t: BuildingType, seed: int, height: float) -> void:
	var n := 2 if r.size.y >= 400.0 else 1
	var depth := minf(120.0, r.size.y - 70.0)
	var ys := [r.get_center().y - depth * 0.5]
	if n == 2:
		ys = [r.position.y + 34.0, r.end.y - 40.0 - depth]
	var h := maxf(height, FH * 9.0)
	for k in n:
		var slab := _box(Rect2(r.position.x + 30.0, float(ys[k]), r.size.x - 64.0, depth), 0.0, h, t.wall_color,
			&"flat", top_color(t, seed), &"apt", seed + k)
		slab.deco = [&"number", &"entrance"]
		slab.text = "%s0%d" % [_pick(t, seed), k + 1]
		slab.accent = t.accent
		var towers := maxi(1, int(slab.rect.size.x / 150.0))
		for i in towers:
			var cx := (i + 0.5) / towers
			_plant(slab, Vector2(cx - 0.05, 0.2), Vector2(0.1, 0.45), 16.0, t.wall_color.darkened(0.08))
		_units(slab, seed + k, 2)
		out.append(slab)
	# 동 사이 마당과 앞마당 가장자리 나무
	var gap_y: float = (ys[0] + depth + ys[-1]) * 0.5 if n == 2 else r.end.y - 22.0
	var x := r.position.x + 44.0
	var k := 0
	while x < r.end.x - 30.0:
		out.append(_tree(Vector2(x + hash01(seed, k) * 16.0, gap_y + (hash01(seed, k + 50) - 0.5) * 20.0), seed + k, 0.9))
		x += 78.0
		k += 1


## 단독주택: 담장 두른 마당(바닥), 북서쪽에 모임지붕 한 채, 마당 나무
static func _house(out: Array[Piece], r: Rect2, t: BuildingType, seed: int, height: float) -> void:
	var size := Vector2(minf(r.size.x * 0.66, 300.0), minf(r.size.y * 0.56, 170.0))
	var home := _box(Rect2(r.position + Vector2(r.size.x * 0.12, r.size.y * 0.12), size), 0.0, maxf(height, FH),
		t.wall_color, &"hip", t.roof_colors[posmod(seed, t.roof_colors.size())], &"punched", seed)
	home.rise = minf(size.x, size.y) * 0.34
	home.eave = 7.0
	home.deco = [&"door", &"stone_base"]
	out.append(home)
	var spots := [Vector2(0.86, 0.22), Vector2(0.14, 0.84), Vector2(0.82, 0.78)]
	for k in spots.size():
		if k == 2 and seed % 2 == 0:
			continue
		out.append(_tree(r.position + r.size * spots[k], seed + k, 1.1))


## 한옥: 돌담 두른 마당(바닥), 처마가 휜 기와지붕 본채, 큰 부지면 옆채, 나무
static func _hanok(out: Array[Piece], r: Rect2, t: BuildingType, seed: int) -> void:
	var roof: Color = t.roof_colors[posmod(seed, t.roof_colors.size())]
	var wide := r.size.x >= r.size.y
	var hall_r: Rect2
	if wide:
		hall_r = Rect2(r.position.x + r.size.x * 0.16, r.position.y + r.size.y * 0.14, r.size.x * 0.68, minf(r.size.y * 0.42, 150.0))
	else:
		hall_r = Rect2(r.position.x + r.size.x * 0.14, r.position.y + r.size.y * 0.16, minf(r.size.x * 0.42, 150.0), r.size.y * 0.68)
	var hall := _box(hall_r, 0.0, 30.0 * t.visual_floor_scale, t.wall_color, &"hanok", roof, &"hanok", seed)
	hall.rise = minf(hall_r.size.x, hall_r.size.y) * 0.4
	hall.eave = 16.0
	hall.deco = [&"stone_base"]
	out.append(hall)
	if r.size.x > 400.0 and r.size.y > 400.0:
		# 서쪽 옆채 (ㄱ자)
		var wing := _box(Rect2(r.position.x + r.size.x * 0.1, hall_r.end.y + 40.0, 100.0, r.size.y * 0.3), 0.0, 26.0 * t.visual_floor_scale,
			t.wall_color, &"hanok", roof, &"hanok", seed + 1)
		wing.rise = 38.0
		wing.eave = 12.0
		wing.deco = [&"stone_base"]
		out.append(wing)
	var spots := [Vector2(0.12, 0.12), Vector2(0.88, 0.2), Vector2(0.84, 0.82)]
	for k in spots.size():
		out.append(_tree(r.position + r.size * spots[k], seed + k * 3, 1.2))


## 쪽방촌: 골목을 사이에 둔 판잣집이 빽빽하다 (지붕은 녹슨 함석·파란 방수포)
static func _jjokbang(out: Array[Piece], r: Rect2, t: BuildingType, seed: int) -> void:
	var cell := 66.0
	var cols := maxi(1, int(r.size.x / cell))
	var rows := maxi(1, int(r.size.y / cell))
	var w := r.size.x / cols
	var h := r.size.y / rows
	for j in rows:
		for i in cols:
			var k := j * cols + i
			if hash01(seed, k) < 0.08:
				continue   # 빈터
			var jitter := Vector2(hash01(seed, k + 100), hash01(seed, k + 200)) * 8.0
			var shack_r := Rect2(r.position + Vector2(i * w, j * h) + Vector2(5, 5) + jitter * 0.5,
				Vector2(w, h) - Vector2(12, 12) - jitter)
			var floors := 2.0 if hash01(seed, k + 300) < 0.25 else 1.0
			var colors := [t.roof_colors[posmod(k, t.roof_colors.size())], TARP, RUST]
			var shack := _box(shack_r, 0.0, FH * floors * 0.9, t.wall_color.darkened(hash01(seed, k + 400) * 0.25),
				&"gable", colors[posmod(seed + k * 7, colors.size())], &"shack", seed + k)
			shack.rise = 7.0 + hash01(seed, k + 500) * 5.0
			shack.eave = 3.0
			out.append(shack)


## 캠핑장 자리 (카라반·텐트 하나와 그 앞 모닥불)
static func camp_spots(r: Rect2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var cols := maxi(1, int((r.size.x - 40.0) / 120.0))
	var rows := maxi(1, int((r.size.y - 50.0) / 140.0))
	for j in rows:
		for i in cols:
			out.append(r.position + Vector2(36 + i * 120, 50 + j * 140))
	return out


## 캠핑장: 잔디(바닥) 위 카라반·텐트, 가장자리 나무
static func _campsite(out: Array[Piece], r: Rect2, t: BuildingType, seed: int) -> void:
	var spots := camp_spots(r)
	for k in spots.size():
		var p := spots[k]
		if posmod(k + seed, 3) == 0:
			var tent := _box(Rect2(p + Vector2(18, 8), Vector2(46, 46)), 0.0, 0.0, Color.WHITE, &"tent",
				TENTS[posmod(k + seed, TENTS.size())], &"none", seed + k)
			tent.rise = 28.0
			out.append(tent)
		else:
			var van := _box(Rect2(p, Vector2(82, 38)), 4.0, 28.0, Color(0.9, 0.89, 0.84), &"flat", Color(0.8, 0.8, 0.78),
				&"caravan", seed + k)
			van.accent = Color(0.3, 0.5, 0.75) if k % 2 == 0 else Color(0.75, 0.3, 0.28)
			out.append(van)
	var x := r.position.x + 24.0
	var k := 0
	while x < r.end.x - 20.0:
		out.append(_tree(Vector2(x, r.position.y + 20.0), seed + k, 1.0))
		x += 64.0 + hash01(seed, k) * 20.0
		k += 1
	var y := r.position.y + 80.0
	while y < r.end.y - 30.0:
		out.append(_tree(Vector2(r.position.x + 18.0, y), seed + k, 0.9))
		y += 76.0
		k += 1


## 창고: 골함석 벽, 긴 쪽으로 용마루가 난 박공 지붕, 앞마당(바닥)의 팔레트
static func _warehouse(out: Array[Piece], r: Rect2, t: BuildingType, seed: int, height: float) -> void:
	var body_r := Rect2(r.position + Vector2(INSET, INSET), r.size - Vector2(INSET * 2.0, INSET + 40.0))
	var body := _box(body_r, 0.0, maxf(height, FH * 2.0), t.wall_color, &"gable", t.roof_colors[0], &"metal", seed)
	body.rise = minf(minf(body_r.size.x, body_r.size.y) * 0.18, 40.0)
	body.eave = 5.0
	body.deco = [&"shutter", &"plate"]
	body.text = _pick(t, seed)
	body.accent = t.accent
	out.append(body)


## 공장: 띠창 두른 공장동, 북서쪽 사무동 한 층 더, 굴뚝 둘, 큰 간판
static func _factory(out: Array[Piece], r: Rect2, t: BuildingType, seed: int, height: float) -> void:
	var base := r.grow(-16.0)
	var h := maxf(height, FH * 2.0)
	var hall := _box(base, 0.0, h, t.wall_color, &"flat", t.roof_colors[posmod(seed, t.roof_colors.size())], &"ribbon", seed)
	hall.deco = [&"shutter", &"big_sign"]
	hall.text = _pick(t, seed)
	hall.accent = t.accent
	var office := _box(Rect2(base.position + Vector2(14, 14), base.size * Vector2(0.5, 0.42)), h, h + FH * 1.2,
		t.wall_color.lightened(0.08), &"flat", hall.roof_color.lightened(0.05), &"ribbon", seed + 1)
	_units(office, seed, 2)
	hall.on_top.append(office)
	for k in 2:
		var c := Vector2(base.end.x - 70.0 - k * 58.0, base.position.y + 60.0 + k * 16.0)
		var stack := _box(Rect2(c - Vector2(17, 17), Vector2(34, 34)), h, h + 150.0 - k * 24.0, Color(0.82, 0.8, 0.76),
			&"chimney", t.accent, &"none", seed + k)
		hall.on_top.append(stack)
	# 지붕 채광창
	var y := base.position.y + base.size.y * 0.55
	while y < base.end.y - 40.0:
		_plant(hall, Vector2(0.55, (y - base.position.y) / base.size.y), Vector2(0.38, 18.0 / base.size.y), 5.0,
			Color(0.5, 0.6, 0.66))
		y += 46.0
	out.append(hall)


## 연립주택: 붉은 기와 박공지붕 3층 한두 동, 현관 차양
static func _rowhouse(out: Array[Piece], r: Rect2, t: BuildingType, seed: int, height: float) -> void:
	var n := 2 if r.size.y > r.size.x * 0.8 else 1
	var gap := 22.0
	var inner := r.grow(-INSET)
	var depth := (inner.size.y - gap * (n - 1)) / n
	for k in n:
		var slab_r := Rect2(inner.position.x, inner.position.y + k * (depth + gap), inner.size.x, depth)
		var slab := _box(slab_r, 0.0, maxf(height, FH * 2.0), t.wall_color, &"gable",
			t.roof_colors[posmod(seed + k, t.roof_colors.size())], &"brick", seed + k)
		slab.rise = minf(minf(slab_r.size.x, slab_r.size.y) * 0.24, 34.0)
		slab.eave = 6.0
		slab.deco = [&"porches", &"name", &"balcony"]
		slab.text = _pick(t, seed, k)
		slab.accent = t.accent
		out.append(slab)


# ── 옥상 소품 ─────────────────────────────────────────────

## 부모 지붕 위 상자 하나 (at·size는 부모 사각형 비율)
static func _plant(parent: Piece, at: Vector2, size: Vector2, h: float, color: Color) -> Piece:
	var r := parent.rect
	var box := _box(Rect2(r.position + r.size * at, r.size * size), parent.h1, parent.h1 + h, color, &"flat",
		color.lightened(0.12), &"none", parent.seed)
	parent.on_top.append(box)
	return box


## 실외기 n개 (옥상 남동쪽 절반에 흩어 놓는다)
static func _units(parent: Piece, seed: int, n: int) -> void:
	var r := parent.rect
	if r.size.x < 60.0 or r.size.y < 60.0:
		return
	for k in n:
		var at := Vector2(0.5 + hash01(seed, k * 2) * 0.36, 0.45 + hash01(seed, k * 2 + 1) * 0.38)
		var size := Vector2(18, 14)
		var box := _box(Rect2(r.position + r.size * at, size), parent.h1, parent.h1 + 7.0, UNIT, &"flat",
			UNIT.lightened(0.15), &"none", seed + k)
		box.deco = [&"fan"]
		parent.on_top.append(box)


## 옥탑 계단실 (북서쪽, 남쪽 벽에 문)
static func _stair_house(parent: Piece, seed: int, color := UNIT) -> void:
	var r := parent.rect
	var size := Vector2(minf(48.0, r.size.x * 0.3), minf(34.0, r.size.y * 0.25))
	var at := r.position + Vector2(r.size.x * (0.1 + hash01(seed, 9) * 0.15), r.size.y * 0.12)
	var box := _box(Rect2(at, size), parent.h1, parent.h1 + 15.0, color, &"flat", color.darkened(0.15), &"none", seed)
	box.deco = [&"door"]
	parent.on_top.append(box)


## 물탱크
static func _tank(parent: Piece, seed: int) -> void:
	var r := parent.rect
	var c := r.position + r.size * Vector2(0.2 + hash01(seed, 11) * 0.2, 0.55)
	parent.on_top.append(_box(Rect2(c - Vector2(11, 11), Vector2(22, 22)), parent.h1, parent.h1 + 16.0,
		Color(0.35, 0.55, 0.75), &"tank", Color(0.35, 0.55, 0.75), &"none", seed))


## 나무 한 그루 (바닥 자리 at, 크기 배율 s)
static func _tree(at: Vector2, seed: int, s: float) -> Piece:
	var p := _box(Rect2(at - Vector2(4, 4), Vector2(8, 8)), 0.0, 14.0 * s, WOOD, &"tree", BuildingModel.HEDGE, &"none", seed)
	p.rise = (13.0 + hash01(seed, 3) * 5.0) * s
	return p


# ── 바닥 (청크가 그린다: 사람·차보다 늘 밑) ────────────────

static func draw_ground(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int) -> void:
	var style: StringName = t.style if t else &"special"
	match style:
		&"special":
			pass
		&"house":
			_yard(ci, r, seed, GRASS, Color(0.68, 0.64, 0.56), 9.0, Color(0.6, 0.56, 0.5))
		&"hanok":
			_yard(ci, r, seed, EARTH, Color(0.76, 0.72, 0.64), 13.0, Color(0.2, 0.21, 0.23))
		&"apt":
			_apt_ground(ci, r, seed)
		&"campsite":
			_camp_ground(ci, r, seed)
		&"jjokbang":
			ci.draw_rect(r, Color(0.23, 0.21, 0.19))
			for k in 6:
				var c := r.position + r.size * Vector2(hash01(seed, k * 3), hash01(seed, k * 3 + 1))
				ci.draw_circle(c, 6.0 + hash01(seed, k) * 6.0, Color(0.16, 0.2, 0.26, 0.8))   # 물웅덩이
		&"warehouse", &"factory":
			_yard_concrete(ci, r, seed, style == &"warehouse")
		_:
			if LandmarkBuilding.owns(style):
				LandmarkBuilding.draw_ground(ci, r, t, seed)
			elif SpecialBuilding.owns(style):
				SpecialBuilding.draw_ground(ci, r, t, seed)
			else:
				_plinth(ci, r, seed)


## 낮은 상자 (바닥에 그리는 화단·담장·팔레트): 남·동 옆면과 윗면
static func low_box(ci: CanvasItem, b: Rect2, h: float, top: Color) -> void:
	var l := IsoView.lift(h)
	var ne := Vector2(b.end.x, b.position.y)
	var sw := Vector2(b.position.x, b.end.y)
	ci.draw_colored_polygon(IsoView.wall(ne, b.end, 0.0, h), top.darkened(IsoView.face_shade(Vector2.RIGHT)))
	ci.draw_colored_polygon(IsoView.wall(sw, b.end, 0.0, h), top.darkened(IsoView.face_shade(Vector2.DOWN)))
	ci.draw_colored_polygon(PackedVector2Array([b.position + l, ne + l, b.end + l, sw + l]), top)


## 도시 건물 둘레: 포장 띠와 남·동쪽 화단 (입구 자리는 비운다)
static func _plinth(ci: CanvasItem, r: Rect2, seed: int) -> void:
	ci.draw_rect(r, PAVING)
	ci.draw_rect(r, STONE.darkened(0.2), false, 2.0)
	var x := r.position.x + 4.0
	var k := 0
	while x < r.end.x - 20.0:
		if absf(x + 9.0 - r.get_center().x) > 30.0 and hash01(seed, k) < 0.75:
			low_box(ci, Rect2(x, r.end.y - 8.0, 18.0, 6.0), 5.0, HEDGE.lightened(hash01(seed, k + 9) * 0.12))
		x += 24.0
		k += 1
	var y := r.position.y + 4.0
	while y < r.end.y - 20.0:
		if hash01(seed, k) < 0.6:
			low_box(ci, Rect2(r.end.x - 8.0, y, 6.0, 18.0), 5.0, HEDGE.lightened(hash01(seed, k + 9) * 0.12))
		y += 24.0
		k += 1


## 담장 두른 마당: 북·서 담 → 마당 → 남(대문)·동 담 순서
static func _yard(ci: CanvasItem, r: Rect2, seed: int, ground: Color, wall: Color, wall_h: float, cap: Color) -> void:
	ci.draw_rect(r, ground)
	# 대문에서 집까지 디딤돌
	var gate := r.get_center().x
	var y := r.end.y - 14.0
	while y > r.position.y + r.size.y * 0.55:
		ci.draw_rect(Rect2(gate - 9.0, y - 7.0, 18.0, 10.0), STONE.darkened(0.1))
		y -= 16.0
	# 꽃밭
	for k in 8:
		var c := r.position + Vector2(14.0 + hash01(seed, k) * (r.size.x - 28.0), r.size.y - 22.0 - hash01(seed, k + 20) * 18.0)
		ci.draw_circle(c, 3.0, [Color(0.9, 0.3, 0.35), Color(0.95, 0.85, 0.3), Color(0.95, 0.95, 0.9)][k % 3])
	var th := 6.0
	low_box(ci, Rect2(r.position, Vector2(r.size.x, th)), wall_h, wall)
	low_box(ci, Rect2(r.position, Vector2(th, r.size.y)), wall_h, wall)
	low_box(ci, Rect2(Vector2(r.end.x - th, r.position.y), Vector2(th, r.size.y)), wall_h, wall)
	low_box(ci, Rect2(Vector2(r.position.x, r.end.y - th), Vector2(gate - 20.0 - r.position.x, th)), wall_h, wall)
	low_box(ci, Rect2(Vector2(gate + 20.0, r.end.y - th), Vector2(r.end.x - gate - 20.0, th)), wall_h, wall)
	# 담 위 기와(한옥)·갓돌, 대문
	for seg in [Rect2(Vector2(r.position.x, r.end.y - th), Vector2(gate - 20.0 - r.position.x, th)),
			Rect2(Vector2(gate + 20.0, r.end.y - th), Vector2(r.end.x - gate - 20.0, th)),
			Rect2(Vector2(r.end.x - th, r.position.y), Vector2(th, r.size.y))]:
		var s: Rect2 = seg
		var l := IsoView.lift(wall_h + 1.0)
		ci.draw_colored_polygon(PackedVector2Array([s.position + l, Vector2(s.end.x, s.position.y) + l, s.end + l,
			Vector2(s.position.x, s.end.y) + l]), cap)
	low_box(ci, Rect2(gate - 20.0, r.end.y - 4.0, 40.0, 3.0), wall_h - 1.0, WOOD)


static func _apt_ground(ci: CanvasItem, r: Rect2, seed: int) -> void:
	ci.draw_rect(r, GRASS.lightened(0.04))
	# 동 둘레 보도와 앞쪽 주차장
	ci.draw_rect(Rect2(r.position + Vector2(18, 22), r.size - Vector2(40, 36)), PAVING.lightened(0.05))
	var park := Rect2(r.position.x + 30.0, r.end.y - 38.0, r.size.x - 64.0, 26.0)
	ci.draw_rect(park, Color(0.24, 0.25, 0.28))
	var x := park.position.x + 4.0
	while x < park.end.x:
		ci.draw_line(Vector2(x, park.position.y), Vector2(x, park.end.y), Color(0.85, 0.85, 0.85, 0.5), 1.0)
		x += 24.0
	_plinth_hedges(ci, r, seed)


static func _plinth_hedges(ci: CanvasItem, r: Rect2, seed: int) -> void:
	var x := r.position.x + 6.0
	var k := 0
	while x < r.end.x - 20.0:
		if absf(x - r.get_center().x) > 40.0:
			low_box(ci, Rect2(x, r.end.y - 8.0, 20.0, 6.0), 6.0, HEDGE.lightened(hash01(seed, k) * 0.1))
		x += 24.0
		k += 1


static func _camp_ground(ci: CanvasItem, r: Rect2, seed: int) -> void:
	ci.draw_rect(r, GRASS.lightened(0.06))
	ci.draw_rect(r.grow(-8.0), EARTH.darkened(0.1), false, 10.0)   # 둘레 흙길
	for p in camp_spots(r):
		ci.draw_rect(Rect2(p - Vector2(6, 6), Vector2(96, 56)), EARTH.lightened(0.05))
		var fire := p + Vector2(58, 92)
		ci.draw_circle(fire, 16.0, Color(1.0, 0.55, 0.15, 0.18))
		for k in 7:
			ci.draw_circle(fire + Vector2.from_angle(k * TAU / 7.0) * 8.0, 2.5, STONE)
		ci.draw_line(fire - Vector2(5, 3), fire + Vector2(5, 3), WOOD, 3.0)
		ci.draw_line(fire - Vector2(5, -3), fire + Vector2(5, -3), WOOD, 3.0)
		var flame := PackedVector2Array([fire + Vector2(-5, 0), fire + IsoView.lift(12.0), fire + Vector2(5, 0)])
		ci.draw_colored_polygon(flame, Color(1.0, 0.6, 0.15))
		ci.draw_colored_polygon(PackedVector2Array([fire + Vector2(-2.5, 0), fire + IsoView.lift(7.0), fire + Vector2(2.5, 0)]),
			Color(1.0, 0.92, 0.5))
		# 캠핑 의자 둘
		low_box(ci, Rect2(fire + Vector2(-22, -4), Vector2(7, 7)), 5.0, Color(0.3, 0.3, 0.34))
		low_box(ci, Rect2(fire + Vector2(14, 8), Vector2(7, 7)), 5.0, Color(0.55, 0.3, 0.2))


## 공장·창고 마당: 콘크리트, 노란 선, 기름 얼룩, 팔레트·드럼통
static func _yard_concrete(ci: CanvasItem, r: Rect2, seed: int, pallets: bool) -> void:
	ci.draw_rect(r, CONCRETE)
	ci.draw_rect(r.grow(-4.0), Color(0.9, 0.75, 0.2, 0.6), false, 2.0)
	for k in 5:
		var c := r.position + r.size * Vector2(hash01(seed, k), hash01(seed, k + 7))
		ci.draw_circle(c, 8.0 + hash01(seed, k + 3) * 10.0, Color(0.1, 0.1, 0.1, 0.25))
	var y := r.end.y - 34.0 if pallets else r.end.y - 14.0
	var x := r.position.x + 20.0
	var k := 0
	while x < r.end.x - 40.0:
		if hash01(seed, k + 40) < 0.5:
			if pallets:
				low_box(ci, Rect2(x, y, 22.0, 18.0), 4.0, Color(0.55, 0.4, 0.24))
				low_box(ci, Rect2(x + 3.0, y + 2.0, 16.0, 13.0), 13.0, Color(0.7, 0.55, 0.36))
			else:
				low_box(ci, Rect2(x, y, 9.0, 9.0), 12.0, [Color(0.2, 0.35, 0.6), Color(0.65, 0.25, 0.2)][k % 2])
		x += 34.0 + hash01(seed, k) * 20.0
		k += 1
