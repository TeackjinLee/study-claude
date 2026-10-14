class_name StreetBuilding
## 서울 거리 건물 10종 (docs/16). 참고 시트(교회·모텔·주유소·유흥·주차타워·학교·지하철·소방서·금융타워·인쇄골목)를
## 덩어리(BuildingModel.Piece)로 세운다. 좌표는 부지 비율, 높이는 월드 단위. 그림은 StreetDecor(sd_ 장식·지붕).
## 바닥에 선 덩어리만 막는다(LandmarkBuilding.collision_rects) — 마당·운동장·광장·골목은 바닥 그림이고 다닌다.
const STYLES := [&"church", &"motel", &"gas_station", &"nightlife", &"parking_tower", &"school", &"subway", &"fire_station", &"finance_tower", &"print_alley"]

const BRICK := Color("8e4a3c")
const BRICK_DARK := Color("5e4039")
const CONCRETE := Color("a9a69c")
const GRANITE := Color("c4c0b6")
const TEAL := Color("1c9a8c")
const SLATE := Color("343b44")
const GREEN_ROOF := Color("3f7a66")
const IRON := Color("2b2f33")
const FIRE_TRUCK := "res://data/vehicles/sp_fire.tres"
const PUMP_CAR := "res://data/vehicles/car_taxi.tres"


static func owns(style: StringName) -> bool:
	return style in STYLES


## 부지 비율 사각형 (x0, y0) ~ (x1, y1)
static func _f(r: Rect2, x0: float, y0: float, x1: float, y1: float) -> Rect2:
	return Rect2(r.position + r.size * Vector2(x0, y0), r.size * Vector2(x1 - x0, y1 - y0))


static func _add(out: Array[BuildingModel.Piece], rect: Rect2, h0: float, h1: float, wall: Color, windows := &"none",
		roof := &"flat", roof_color := Color(0, 0, 0, 0)) -> BuildingModel.Piece:
	var p := BuildingModel._box(rect, h0, h1, wall, roof, roof_color if roof_color.a > 0.0 else wall.darkened(0.18), windows, out.size() * 13 + 7)
	if h0 <= 0.0 and h1 <= 3.0:
		p.blocks_ground = false   # 3px 이하는 바닥 포장·표시
	out.append(p)
	return p


## 얹힌 덩어리 (parent 위, parent.h1부터)
static func _on(parent: BuildingModel.Piece, rect: Rect2, h: float, wall: Color, roof := &"flat", roof_color := Color(0, 0, 0, 0)) -> BuildingModel.Piece:
	var p := BuildingModel._box(rect, parent.h1, parent.h1 + h, wall, roof, roof_color if roof_color.a > 0.0 else wall.lightened(0.1), &"none", parent.seed + parent.on_top.size() * 7)
	parent.on_top.append(p)
	return p


static func _pine(out: Array[BuildingModel.Piece], at: Vector2, seed: int, s := 1.0) -> void:
	var p := _add(out, Rect2(at - Vector2(4, 4), Vector2(8, 8)), 0, 8 * s, BuildingModel.WOOD, &"none", &"sd_pine", Color("27512f"))
	p.rise = (26.0 + BuildingModel.hash01(seed, 3) * 10.0) * s
	p.seed = seed


static func _tree(out: Array[BuildingModel.Piece], at: Vector2, seed: int, s := 1.0, blossom := false) -> void:
	var p := BuildingModel._tree(at, seed, s)
	if blossom:
		p.roof_color = Color("e6a3c4")
	out.append(p)


static func _lamp(out: Array[BuildingModel.Piece], at: Vector2, h := 40.0) -> void:
	_add(out, Rect2(at - Vector2(2, 2), Vector2(4, 4)), 0, h, Color("2f3437"), &"none", &"lamp_pole")


static func _bollard(out: Array[BuildingModel.Piece], at: Vector2, color := Color("e3b023")) -> void:
	_add(out, Rect2(at - Vector2(2.5, 2.5), Vector2(5, 5)), 0, 11, color, &"none", &"sd_bollard")


## 낮은 담 한 줄 (a → b). 위에 쇠 울타리를 그린다.
## 짧은 토막으로 나눈다 — 긴 덩어리는 윗면을 맨 앞 조각 깊이에서 한 번에 그려, 옆 건물 지붕 위로 올라온다
static func _wall_run(out: Array[BuildingModel.Piece], a: Vector2, b: Vector2, color: Color, h := 9.0, rail := true) -> void:
	var n := maxi(1, ceili(a.distance_to(b) / 40.0))
	for k in n:
		var rect := Rect2(a.lerp(b, float(k) / n), Vector2.ZERO).expand(a.lerp(b, float(k + 1) / n)).grow(3.0)
		var p := _add(out, rect, 0, h, color)
		p.roof_color = color.lightened(0.15)
		if rail:
			p.deco = [&"sd_railing"]


static func build(out: Array[BuildingModel.Piece], r: Rect2, t: BuildingType, seed: int) -> void:
	match t.style:
		&"church": _church(out, r, seed)
		&"motel": _motel(out, r, seed)
		&"gas_station": _gas(out, r, seed)
		&"nightlife": _nightlife(out, r, seed)
		&"parking_tower": _parking(out, r, seed)
		&"school": _school(out, r, seed)
		&"subway": _subway(out, r, seed)
		&"fire_station": _fire(out, r, seed)
		&"finance_tower": _finance(out, r, seed)
		&"print_alley": _print_alley(out, r, seed)


# ── 교회: 벽돌 본당(박공)·앞 종탑(첨탑·붉은 네온 십자가)·담장과 침엽수 ─────────

static func _church_frame(r: Rect2) -> Dictionary:
	var nave := _f(r, 0.34, 0.16, 0.74, 0.64)
	var tw := clampf(r.size.x * 0.13, 46.0, 66.0)
	var cx := nave.get_center().x
	var tower := Rect2(cx - tw * 0.5, nave.end.y - tw * 0.35, tw, tw)
	return {"nave": nave, "tower": tower, "gate": Vector2(cx, r.end.y - r.size.y * 0.04)}


static func _church(out: Array[BuildingModel.Piece], r: Rect2, seed: int) -> void:
	var fr := _church_frame(r)
	var nave: Rect2 = fr.nave
	var tower: Rect2 = fr.tower
	# 뒤 부속실 (모임지붕)
	var apse := _add(out, Rect2(nave.position.x + nave.size.x * 0.18, nave.position.y - 26, nave.size.x * 0.64, 30), 0, 44, BRICK, &"none", &"hip", SLATE)
	apse.rise = 20
	apse.deco = [&"sd_brick", &"sd_lancets"]
	var hall := _add(out, nave, 0, 66, BRICK, &"none", &"gable", SLATE)
	hall.rise = 50
	hall.eave = 5
	hall.surface_detail = true
	hall.deco = [&"sd_brick", &"sd_lancets", &"sd_lancets_glow"]
	# 동쪽 벽 버팀벽
	var k := 0
	var y := nave.position.y + 28
	while y < nave.end.y - 30:
		var b := _add(out, Rect2(nave.end.x, y, 9, 12), 0, 46, BRICK.lightened(0.06), &"none", &"hip", GRANITE.darkened(0.2))
		b.rise = 6
		y += 52
		k += 1
	# 종탑: 몸통 → 종실(아치 창) → 첨탑 → 십자가
	var body := _add(out, tower, 0, 132, BRICK.lightened(0.04))
	body.deco = [&"sd_brick", &"sd_church_front", &"sd_church_front_glow"]
	body.roof_color = GRANITE.darkened(0.15)
	var bell := _on(body, tower.grow(-5), 30, BRICK.lightened(0.08))
	bell.deco = [&"sd_belfry"]
	var spire := _on(bell, tower.grow(-4), 0.5, SLATE, &"hip", SLATE)
	spire.rise = 86
	var top := spire.h1 + spire.rise
	var c := tower.get_center()
	var cross := BuildingModel._box(Rect2(c - Vector2(3, 3), Vector2(6, 6)), top - 4, top + 34, Color("ff2d4a"), &"sd_cross")
	spire.on_top.append(cross)
	# 본당 지붕 뒤쪽 작은 십자가
	var small := BuildingModel._box(Rect2(Vector2(nave.get_center().x, nave.position.y + 4) - Vector2(2, 2), Vector2(4, 4)), 66 + 46, 66 + 62, GRANITE, &"sd_cross")
	small.accent = GRANITE
	hall.on_top.append(small)
	# 현관 계단 (바닥 표시, 막지 않는다)
	for s in 3:
		_add(out, Rect2(tower.position.x - 8 + s * 3, tower.end.y + s * 5, tower.size.x + 16 - s * 6, 5), 0, 3 - s, GRANITE.darkened(0.05 * s))
	# 담장 (남쪽 가운데 대문만 비운다)
	var m := 8.0
	var gate: Vector2 = fr.gate
	_wall_run(out, Vector2(r.position.x + m, r.position.y + m), Vector2(r.end.x - m, r.position.y + m), GRANITE)
	_wall_run(out, Vector2(r.position.x + m, r.position.y + m), Vector2(r.position.x + m, r.end.y - m), GRANITE)
	_wall_run(out, Vector2(r.end.x - m, r.position.y + m), Vector2(r.end.x - m, r.end.y - m), GRANITE)
	_wall_run(out, Vector2(r.position.x + m, r.end.y - m), Vector2(gate.x - 34, r.end.y - m), GRANITE)
	_wall_run(out, Vector2(gate.x + 34, r.end.y - m), Vector2(r.end.x - m, r.end.y - m), GRANITE)
	for side in [-1.0, 1.0]:
		var post := _add(out, Rect2(Vector2(gate.x + side * 36, r.end.y - m) - Vector2(7, 7), Vector2(14, 14)), 0, 22, GRANITE.lightened(0.05))
		post.roof_color = GRANITE.lightened(0.2)
	var board := _add(out, Rect2(gate.x + 46, r.end.y - m - 26, 30, 4), 0, 30, Color("2c2f33"))
	board.text = "새빛교회"
	board.deco = [&"sd_notice"]
	# 나무: 담장 안쪽 침엽수, 마당에 둥근 나무
	var n := 0
	var x := r.position.x + 26
	while x < r.end.x - 20:
		if absf(x - gate.x) > 60 and (x < nave.position.x - 20 or x > nave.end.x + 30):
			_pine(out, Vector2(x, r.end.y - 30), seed + n, 0.9 + BuildingModel.hash01(seed, n) * 0.3)
		x += 34
		n += 1
	y = r.position.y + 30
	while y < r.end.y - 50:
		_pine(out, Vector2(r.position.x + 24, y), seed + n, 1.0)
		if y > nave.end.y or y < nave.position.y - 30:
			_pine(out, Vector2(r.end.x - 26, y), seed + n + 40, 1.1)
		y += 40
		n += 1
	_tree(out, r.position + r.size * Vector2(0.2, 0.72), seed + 3, 1.3)
	_tree(out, r.position + r.size * Vector2(0.86, 0.74), seed + 5, 1.2)
	_lamp(out, Vector2(gate.x - 22, tower.end.y + 40))
	_lamp(out, Vector2(gate.x + 22, tower.end.y + 40))


# ── 모텔: 벽돌 5층, 1층은 주차장 입구(기둥·커튼), 옥상 네온 간판과 세로 간판 ──────────

static func _motel(out: Array[BuildingModel.Piece], r: Rect2, seed: int) -> void:
	var foot := _f(r, 0.2, 0.14, 0.8, 0.74)
	var core := Rect2(foot.position, Vector2(foot.size.x, foot.size.y * 0.66))
	var lobby := _add(out, core, 0, 34, BRICK_DARK.darkened(0.2))
	lobby.deco = [&"sd_lobby", &"sd_lobby_glow"]
	for x in [foot.position.x, foot.end.x - 12]:
		var pillar := _add(out, Rect2(x, foot.end.y - 12, 12, 12), 0, 34, BRICK_DARK)
		pillar.deco = [&"sd_brick"]
	var body := _add(out, foot, 34, 34 + 5 * 28, Color("7a4b3f"), &"brick")
	body.floor_height = 28
	body.surface_detail = true
	body.deco = [&"sd_arrows", &"ac", &"fire_escape", &"sd_pipes"]
	body.z_at_end = true   # 1층 로비 위로 내민 윗층
	body.seed = seed
	# 주차장 커튼 (지나간다)
	var curtain := _add(out, Rect2(foot.position.x + 12, foot.end.y - 3, foot.size.x - 24, 2), 0, 30, Color("221d27"))
	curtain.blocks_ground = false
	curtain.deco = [&"sd_curtain"]
	# 세로 네온 간판 (남동 모서리에서 튀어나온다)
	var blade := BuildingModel._box(Rect2(foot.end.x - 40, foot.end.y, 26, 5), 70, 160, Color("221d27"))
	blade.text = "모텔"
	blade.accent = Color("ff3b6a")
	blade.deco = [&"street_vertical_neon"]
	body.on_top.append(blade)   # 내민 윗층 뒤에 가리지 않게 윗층 다음에 그린다
	# 옥상: 난간·물탱크·계단실·실외기·네온 간판
	_roof_kit(body, seed, true)
	var sign := _on(body, Rect2(foot.position.x + foot.size.x * 0.18, foot.end.y - 24, foot.size.x * 0.64, 6), 40, Color("221d27"))
	sign.text = "모텔"
	sign.accent = Color("ff2d4a")
	sign.deco = [&"sd_roof_sign"]
	for x in [0.25, 0.75]:
		_on(body, Rect2(sign.rect.position.x + sign.rect.size.x * x - 2, sign.rect.position.y - 8, 4, 8), 30, IRON)
	# 입구 화분·벽등
	for x in [foot.position.x - 16, foot.end.x + 6]:
		_add(out, Rect2(x, foot.end.y - 14, 10, 10), 0, 7, Color("6a5a4c"), &"none", &"sd_planter")


# ── 주유소: 흰 캐노피(청록 띠·로고)·주유기 섬·편의점동·세차동·가격 기둥 ─────────────

static func _gas_frame(r: Rect2) -> Dictionary:
	var canopy := _f(r, 0.1, 0.44, 0.7, 0.8)
	var islands: Array[Rect2] = []
	# 섬은 캐노피 앞쪽 절반에 둔다 — 높은 지붕 밑으로 주유기가 보인다
	for k in 2:
		var cx := lerpf(canopy.position.x, canopy.end.x, 0.3 + k * 0.4)
		islands.append(Rect2(cx - 11, canopy.end.y - 92, 22, 84))
	return {"canopy": canopy, "islands": islands}


static func _gas(out: Array[BuildingModel.Piece], r: Rect2, seed: int) -> void:
	var fr := _gas_frame(r)
	var canopy: Rect2 = fr.canopy
	# 편의점·사무동과 세차동
	var shop := _add(out, _f(r, 0.5, 0.08, 0.92, 0.32), 0, 40, Color("e9e5da"), &"none")
	shop.text = "한빛주유소"
	shop.accent = TEAL
	shop.deco = [&"sd_gas_shop", &"sd_gas_band"]
	shop.roof_color = Color("b9bcb4")
	_roof_kit(shop, seed, false)
	var wash := _add(out, _f(r, 0.22, 0.08, 0.5, 0.3), 0, 34, Color("d9dcd6"))
	wash.text = "자동세차"
	wash.accent = Color("2f7fc0")
	wash.deco = [&"sd_wash"]
	# 주유기 섬: 낮은 연석은 통과, 위의 주유기는 충돌
	for island: Rect2 in fr.islands:
		var curb := _add(out, island, 0, 5, Color("cfcabd"))
		curb.blocks_ground = false   # 주유기 주변 낮은 바닥 기단은 통행 가능
		curb.deco = [&"sd_curb"]
		for f in [0.12, 0.62]:
			var pump := _on(curb, Rect2(island.position.x + 4, island.position.y + island.size.y * f, island.size.x - 8, 12), 24, Color("f2f1ea"))
			pump.accent = TEAL
			pump.deco = [&"sd_pump"]
		var bin := _on(curb, Rect2(island.position.x + 6, island.end.y - 8, 7, 6), 9, Color("c8372c"))
		bin.deco = [&"sd_extinguisher"]
		# 캐노피 기둥
		var col := _add(out, Rect2(island.get_center() + Vector2(0, 4) - Vector2(5, 5), Vector2(10, 10)), 5, 48, Color("eeeee8"))
		col.deco = [&"sd_column"]
	var roof := _add(out, canopy, 48, 60, Color("f4f4ef"), &"none", &"flat", Color("d9dbd6"))
	roof.text = "한빛"
	roof.accent = TEAL
	roof.deco = [&"sd_fascia", &"sd_fascia_glow"]
	roof.z_at_end = true
	# 가격 기둥 (남동)
	var pylon := _add(out, Rect2(r.end.x - r.size.x * 0.12, r.end.y - r.size.y * 0.14, 30, 8), 0, 84, TEAL.darkened(0.25))
	pylon.text = "한빛주유소"
	pylon.deco = [&"sd_price"]
	# 공기 주입기·물통
	_add(out, Rect2(r.position.x + r.size.x * 0.06, r.position.y + r.size.y * 0.36, 8, 8), 0, 16, Color("2f6fb0"), &"none", &"sd_bollard")
	for k in 4:
		_bollard(out, Vector2(r.position.x + r.size.x * (0.52 + k * 0.03), r.position.y + r.size.y * 0.35))


# ── 유흥 건물: 좁고 높은 벽돌, 층마다 다른 네온(노래방·클럽·호프), 옥상 잡동사니 ───────

static func _nightlife(out: Array[BuildingModel.Piece], r: Rect2, seed: int) -> void:
	var foot := _f(r, 0.26, 0.2, 0.74, 0.68)
	var body := _add(out, foot, 0, 6 * 32, Color("5a4640"), &"brick")
	body.floor_height = 32
	body.surface_detail = true
	body.seed = seed
	body.deco = [&"sd_nightlife", &"sd_neon_trim", &"fire_escape", &"ac", &"sd_pipes"]
	var names := [["노래방", Color("ff3fb4")], ["호프", Color("ffa53e")]]
	for k in 2:
		var x := foot.position.x + 8 if k == 0 else foot.end.x - 34
		var blade := _add(out, Rect2(x, foot.end.y, 26, 5), 34 + k * 30, 180 - k * 40, Color("221d27"))
		blade.text = names[k][0]
		blade.accent = names[k][1]
		blade.deco = [&"street_vertical_neon"]
	_roof_kit(body, seed, true)
	var room := _on(body, Rect2(foot.position + foot.size * Vector2(0.52, 0.12), foot.size * Vector2(0.36, 0.34)), 26, Color("6a554c"))
	room.windows = &"glass"
	var mast := BuildingModel._box(Rect2(foot.position + foot.size * Vector2(0.15, 0.2), Vector2(6, 6)), body.h1, body.h1 + 46, Color("6a6f73"), &"mast")
	body.on_top.append(mast)
	for k in 3:
		var pot := _on(body, Rect2(foot.position + foot.size * Vector2(0.12 + k * 0.1, 0.78), Vector2(12, 12)), 6, Color("6a5a4c"), &"sd_planter")
		pot.seed = seed + k
	# 앞 인도: 쓰레기봉투·화분
	for k in 3:
		_add(out, Rect2(foot.position.x + 30 + k * 9, foot.end.y + 10, 8, 7), 0, 6, Color("2b2e33"), &"none", &"sd_bags")
	_add(out, Rect2(foot.end.x - 70, foot.end.y + 8, 12, 12), 0, 8, Color("6a5a4c"), &"none", &"sd_planter")


# ── 공영 주차타워: 열린 층(난간 띠·안쪽 차), 동쪽 계단 코어와 큰 P, 입구 부스와 차단기 ─────

const DECK := 30.0

static func _parking(out: Array[BuildingModel.Piece], r: Rect2, seed: int) -> void:
	var deck := _f(r, 0.1, 0.14, 0.8, 0.84)
	# 1층은 기둥만 막는다 (차·사람이 지나간다). 기둥 충돌은 보이지 않는 덩어리
	var ground := _add(out, deck, 0, DECK, Color("8f9592"))
	ground.blocks_ground = false
	ground.deco = [&"sd_deck_open", &"sd_deck_lamps", &"sd_deck_entry"]
	ground.seed = seed
	for fx in [0.0, 0.33, 0.66, 1.0]:
		for fy in [0.0, 0.5, 1.0]:
			var at := deck.position + deck.size * Vector2(fx, fy)
			at = at.clamp(deck.position + Vector2(5, 5), deck.end - Vector2(5, 5))
			_add(out, Rect2(at - Vector2(5, 5), Vector2(10, 10)), 0, DECK, Color(0, 0, 0, 0), &"none", &"sd_void")
	var below := ground
	for level in range(1, 5):
		var floor_p := BuildingModel._box(deck, level * DECK, (level + 1) * DECK, Color("a3a8a4"), &"flat", Color("8d918d"), &"none", seed + level)
		floor_p.deco = [&"sd_deck_open", &"sd_deck_lamps"]
		below.on_top.append(floor_p)
		below = floor_p
	below.roof = &"sd_deck_top"
	below.seed = seed
	var core := _add(out, _f(r, 0.8, 0.14, 0.93, 0.5), 0, 5 * DECK + 34, Color("9aa1a3"), &"slit")
	core.text = "P"
	core.deco = [&"sd_psign", &"sd_psign_glow"]
	core.floor_height = DECK
	BuildingModel._stair_house(core, seed, Color("8d9496"))
	var stair := _add(out, _f(r, 0.8, 0.5, 0.9, 0.84), 0, 4 * DECK + 6, Color("a7aca8"))
	stair.deco = [&"sd_ramp"]
	# 입구 부스·차단기·볼라드
	var booth := _add(out, Rect2(deck.position.x + deck.size.x * 0.36, deck.end.y + 8, 22, 16), 0, 24, Color("dfe3e0"))
	booth.deco = [&"sd_booth"]
	var arm := _add(out, Rect2(booth.rect.end.x + 4, booth.rect.position.y + 6, 60, 4), 0, 12, Color("d23a2f"), &"none", &"sd_barrier")
	arm.blocks_ground = false
	for k in 6:
		_bollard(out, Vector2(deck.position.x + 12 + k * 22, deck.end.y + 26))


# ── 학교: ㄱ자 벽돌 교사(초록 지붕)·가운데 시계탑·운동장·담장과 정문·벚꽃 ─────────────

static func _school_frame(r: Rect2) -> Dictionary:
	return {"main": _f(r, 0.08, 0.06, 0.92, 0.27), "wing": _f(r, 0.06, 0.27, 0.26, 0.64),
		"field": _f(r, 0.32, 0.36, 0.92, 0.88), "gate": Vector2(r.position.x + r.size.x * 0.18, r.end.y - 10)}


static func _school(out: Array[BuildingModel.Piece], r: Rect2, seed: int) -> void:
	var fr := _school_frame(r)
	var main: Rect2 = fr.main
	var hall := _add(out, main, 0, 4 * 24, BRICK.lightened(0.04), &"punched", &"hip", GREEN_ROOF)
	hall.floor_height = 24
	hall.rise = 16
	hall.eave = 3
	hall.surface_detail = true
	hall.deco = [&"sd_school_bands"]
	var wing := _add(out, fr.wing, 0, 3 * 24, BRICK, &"punched", &"hip", GREEN_ROOF)
	wing.floor_height = 24
	wing.rise = 14
	wing.surface_detail = true
	wing.deco = [&"sd_school_bands"]
	var tw := 54.0
	var cx := main.get_center().x + main.size.x * 0.08
	var tower := _add(out, Rect2(cx - tw * 0.5, main.end.y - 30, tw, 42), 0, 132, Color("d5c7a6"), &"punched", &"hip", GREEN_ROOF)
	tower.floor_height = 24
	tower.rise = 14
	tower.text = "한빛중학교"
	tower.deco = [&"sd_school_tower"]
	var porch := _add(out, Rect2(cx - 30, main.end.y + 12, 60, 18), 22, 26, Color("d5c7a6"))
	porch.roof_color = GREEN_ROOF
	porch.z_at_end = true
	var flag := BuildingModel._box(Rect2(Vector2(cx + 46, main.end.y + 20) - Vector2(1.5, 1.5), Vector2(3, 3)), 0, 70, Color("d8d8d8"), &"flag", Color(1, 1, 1))
	flag.blocks_ground = false
	out.append(flag)
	# 운동장: 골대 둘·철봉·스탠드 벤치
	var field: Rect2 = fr.field
	for side in [0, 1]:
		var y := field.position.y + 22 if side == 0 else field.end.y - 26
		var goal := _add(out, Rect2(field.get_center().x - 24, y, 48, 4), 0, 20, Color("e8e8e0"), &"none", &"sd_goal")
		goal.blocks_ground = false
	for k in 3:
		_add(out, Rect2(field.position.x + 30 + k * 60, field.position.y - 14, 44, 6), 0, 5, Color("6f8fb0"))
	# 담장과 정문
	var m := 7.0
	var gate: Vector2 = fr.gate
	_wall_run(out, Vector2(r.end.x - m, r.position.y + m), Vector2(r.end.x - m, r.end.y - m), BRICK)
	_wall_run(out, Vector2(r.position.x + m, main.end.y), Vector2(r.position.x + m, r.end.y - m), BRICK)
	_wall_run(out, Vector2(r.position.x + m, r.end.y - m), Vector2(gate.x - 30, r.end.y - m), BRICK)
	_wall_run(out, Vector2(gate.x + 30, r.end.y - m), Vector2(r.end.x - m, r.end.y - m), BRICK)
	for side in [-1.0, 1.0]:
		var post := _add(out, Rect2(Vector2(gate.x + side * 32, r.end.y - m) - Vector2(8, 8), Vector2(16, 16)), 0, 26, BRICK.lightened(0.05))
		post.roof_color = GRANITE
		if side > 0:
			post.text = "학교"
			post.deco = [&"sd_gate_plate"]
	# 나무: 벚꽃과 소나무, 화단
	var n := 0
	var x := field.position.x + 10
	while x < r.end.x - 20:
		_tree(out, Vector2(x, r.end.y - 24), seed + n, 1.05, n % 3 != 1)
		x += 44
		n += 1
	var y := field.position.y + 10
	while y < r.end.y - 50:
		_pine(out, Vector2(r.end.x - 22, y), seed + n, 1.0)
		y += 46
		n += 1
	for k in 3:
		_tree(out, Vector2(fr.wing.end.x + 18, fr.wing.position.y + 30 + k * 50), seed + 30 + k, 1.1, k == 1)


# ── 지하철 출입구: 곡면 유리 지붕·초록 띠·호선 기둥, 광장(벤치·나무·자전거·가판대·환기구·버스 정류장) ──

static func _subway_frame(r: Rect2) -> Dictionary:
	var w := clampf(r.size.x * 0.26, 70.0, 120.0)
	var cx := r.get_center().x
	return {"entry": Rect2(cx - w * 0.5, r.position.y + r.size.y * 0.42, w, r.size.y * 0.3)}


static func _subway(out: Array[BuildingModel.Piece], r: Rect2, seed: int) -> void:
	var entry: Rect2 = _subway_frame(r).entry
	# 계단 양옆 낮은 화강암 벽, 뒤 벽
	for x in [entry.position.x, entry.end.x - 8]:
		var side := _add(out, Rect2(x, entry.position.y, 8, entry.size.y), 0, 12, GRANITE)
		side.deco = [&"sd_glass_rail"]
	_add(out, Rect2(entry.position.x, entry.position.y - 8, entry.size.x, 8), 0, 40, GRANITE.darkened(0.08))
	var shell := _add(out, entry, 40, 46, Color("467a7e"), &"none", &"street_canopy", Color("658f98"))
	shell.rise = 26
	shell.z_at_end = true
	var band := _add(out, Rect2(entry.position.x + 6, entry.end.y - 3, entry.size.x - 12, 2), 28, 40, Color("1f9a55"))
	band.text = "지하철"
	band.accent = Color("1f9a55")
	band.deco = [&"sd_metro_band"]
	band.z_at_end = true
	for x in [entry.position.x + 2, entry.end.x - 6]:
		_add(out, Rect2(x, entry.end.y - 6, 4, 4), 0, 40, Color("3d4a4e"))
	var pillar := _add(out, Rect2(entry.end.x + 10, entry.end.y - 12, 14, 10), 0, 66, Color("2f3a3d"))
	pillar.text = "2"
	pillar.accent = Color("1f9a55")
	pillar.deco = [&"sd_line_pillar"]
	for k in 5:
		_bollard(out, Vector2(entry.position.x + entry.size.x * (k + 0.5) / 5.0, entry.end.y + 26), Color("3a4044"))
	# 자전거 거치대
	var bikes := _add(out, Rect2(entry.position.x - 70, entry.end.y + 6, 50, 10), 0, 12, Color("5b6266"), &"none", &"sd_bikes")
	bikes.blocks_ground = false
	# 환기구·가판대·버스 정류장
	var vent := _add(out, _f(r, 0.1, 0.12, 0.22, 0.24), 0, 38, GRANITE.darkened(0.12))
	vent.deco = [&"sd_louver"]
	var kiosk := _add(out, Rect2(r.end.x - r.size.x * 0.24, entry.position.y + 20, 40, 26), 0, 24, Color("2e7a55"))
	kiosk.deco = [&"sd_kiosk"]
	kiosk.roof_color = Color("e2dccb")
	var shelter := _f(r, 0.62, 0.86, 0.9, 0.93)
	for x in [shelter.position.x + 2, shelter.end.x - 6]:
		_add(out, Rect2(x, shelter.position.y + 2, 4, 4), 0, 26, Color("4a5357"))
	var shelter_roof := _add(out, shelter, 26, 30, Color("5d7f8a"))
	shelter_roof.text = "버스"
	shelter_roof.deco = [&"sd_shelter"]
	shelter_roof.z_at_end = true
	_add(out, Rect2(shelter.position.x + 10, shelter.position.y + 4, shelter.size.x - 20, 5), 0, 6, Color("8a6a4a"))
	# 광장 나무·둥근 벤치·가로등
	var n := 0
	for fy in [0.18, 0.86]:
		for fx in [0.36, 0.5, 0.64]:
			if fy > 0.5 and fx > 0.55:
				continue
			_tree(out, r.position + r.size * Vector2(fx, fy), seed + n, 1.2, n == 2)
			_add(out, Rect2(r.position + r.size * Vector2(fx, fy) + Vector2(-12, 10), Vector2(24, 5)), 0, 5, Color("8a6a4a"))
			n += 1
	for fy in [0.3, 0.6]:
		for fx in [0.12, 0.88]:
			_tree(out, r.position + r.size * Vector2(fx, fy), seed + n, 1.1)
			n += 1
	for at in [Vector2(0.24, 0.4), Vector2(0.76, 0.4), Vector2(0.24, 0.8)]:
		_lamp(out, r.position + r.size * at, 42)


# ── 소방서: 붉은 띠 '119 소방서' 본관(차고 셋, 안에 소방차), 훈련탑, 태극기 ─────────────

static func _fire_frame(r: Rect2) -> Dictionary:
	var main := _f(r, 0.08, 0.1, 0.74, 0.56)
	var bays: Array[float] = []
	for k in 3:
		bays.append(main.position.x + main.size.x * (k + 0.5) / 3.0)
	return {"main": main, "bays": bays}


static func _fire(out: Array[BuildingModel.Piece], r: Rect2, seed: int) -> void:
	var fr := _fire_frame(r)
	var main: Rect2 = fr.main
	var hall := _add(out, main, 0, 3 * 30, Color("cfc6b4"), &"punched")
	hall.floor_height = 30
	hall.surface_detail = true
	hall.text = "119 소방서"
	hall.deco = [&"sd_fire_bays", &"sd_fire_band", &"sd_pipes"]
	hall.seed = seed
	_roof_kit(hall, seed, false)
	var flag := BuildingModel._box(Rect2(main.position + Vector2(main.size.x * 0.16, main.size.y * 0.8), Vector2(3, 3)), hall.h1, hall.h1 + 46, Color("d8d8d8"), &"flag", Color(1, 1, 1))
	hall.on_top.append(flag)
	var tower := _add(out, _f(r, 0.78, 0.12, 0.92, 0.32), 0, 6 * 30 + 14, Color("b8b0a2"), &"slit")
	tower.floor_height = 30
	tower.text = "119"
	tower.deco = [&"sd_tower_119", &"fire_escape"]
	var hut := _on(tower, tower.rect.grow(-8), 16, Color("a59d90"))
	hut.deco = [&"door"]
	var mast := BuildingModel._box(Rect2(tower.rect.get_center() - Vector2(3, 3), Vector2(6, 6)), hut.h1, hut.h1 + 40, Color("6a6f73"), &"mast")
	hut.on_top.append(mast)
	# 옆 차고동(구급차)
	var side := _add(out, _f(r, 0.76, 0.36, 0.94, 0.56), 0, 34, Color("cfc6b4"))
	side.text = "구급"
	side.deco = [&"sd_fire_bays"]
	# 앞마당 볼라드
	for x: float in fr.bays:
		for s in [-1.0, 1.0]:
			_bollard(out, Vector2(x + s * main.size.x / 6.0, main.end.y + 6))


# ── 금융타워: 화강암 기단(유리 로비)·푸른 커튼월 타워·계단식 왕관과 첨탑 ─────────────

static func _finance(out: Array[BuildingModel.Piece], r: Rect2, seed: int) -> void:
	var podium_r := _f(r, 0.08, 0.1, 0.92, 0.78)
	var podium := _add(out, podium_r, 0, 46, GRANITE)
	podium.text = "한강금융센터"
	podium.deco = [&"sd_podium", &"sd_podium_glow"]
	podium.roof_color = Color("8c9295")
	var tr := Rect2(podium_r.position + podium_r.size * Vector2(0.12, 0.08), podium_r.size * Vector2(0.76, 0.66))
	var tower := BuildingModel._box(tr, 46, 400, Color("2f5f8c"), &"flat", Color("6f8ea0"), &"glass", seed)
	tower.deco = [&"street_mullions", &"sd_fins"]
	tower.floor_height = 20
	tower.surface_detail = true
	podium.on_top.append(tower)
	var crown1 := BuildingModel._box(tr.grow(-tr.size.x * 0.08), 400, 428, Color("3c6f99"), &"flat", Color("8fb0c0"), &"glass", seed + 1)
	crown1.floor_height = 14
	crown1.text = "한강금융"
	crown1.accent = Color("3fb7ff")
	crown1.deco = [&"street_mullions", &"sd_crown_sign"]
	tower.on_top.append(crown1)
	var crown2 := BuildingModel._box(tr.grow(-tr.size.x * 0.2), 428, 446, Color("5a8bab"), &"hip", Color("9fc0cf"), &"glass", seed + 2)
	crown2.rise = 22
	crown1.on_top.append(crown2)
	var spire := BuildingModel._box(Rect2(tr.get_center() - Vector2(2, 2), Vector2(4, 4)), 446 + 18, 540, RED_WHITE, &"antenna")
	crown2.on_top.append(spire)
	# 입구 캐노피·화단·깃대·분수
	var canopy := _add(out, Rect2(podium_r.get_center().x - 50, podium_r.end.y, 100, 22), 26, 30, Color("8c9295"))
	canopy.deco = [&"sd_canopy_edge"]
	canopy.z_at_end = true
	var n := 0
	for fx in [0.12, 0.88]:
		_add(out, Rect2(r.position + r.size * Vector2(fx, 0.86) - Vector2(16, 8), Vector2(32, 16)), 0, 6, GRANITE.darkened(0.1), &"none", &"sd_planter")
		_tree(out, r.position + r.size * Vector2(fx, 0.86), seed + n, 1.2)
		n += 1
	for k in 3:
		var flag := BuildingModel._box(Rect2(r.position + r.size * Vector2(0.3 + k * 0.06, 0.9), Vector2(3, 3)), 0, 60, Color("d8d8d8"), &"flag", [Color(1, 1, 1), Color("2f5f8c"), Color("3f9a6a")][k])
		flag.blocks_ground = false
		out.append(flag)
	var fountain := _add(out, Rect2(r.position + r.size * Vector2(0.62, 0.86) - Vector2(16, 12), Vector2(32, 24)), 0, 5, GRANITE, &"none", &"sd_fountain")
	fountain.blocks_ground = true
	for k in 5:
		_bollard(out, Vector2(podium_r.position.x + podium_r.size.x * (0.1 + k * 0.2), r.end.y - 8), Color("3a4044"))

const RED_WHITE := Color("c8372c")


# ── 인쇄·공구 골목: 가운데 골목 양쪽 2~4층 상가, 세로 간판·전선·적재물 ─────────────

const PRINT_SHOPS := [["인쇄", "제본", "출력"], ["공구", "철물", "전기"]]
const PRINT_WALLS := [Color("cdbf9f"), Color("8e5a48"), Color("b9b2a4"), Color("9a7058"), Color("d2c7b0"), Color("7f6a5a")]

static func _alley(r: Rect2) -> Rect2:
	var w := clampf(r.size.x * 0.16, 54.0, 70.0)
	return Rect2(r.get_center().x - w * 0.5, r.position.y, w, r.size.y)


static func _print_alley(out: Array[BuildingModel.Piece], r: Rect2, seed: int) -> void:
	var lane := _alley(r)
	var sides := [Rect2(r.position.x + 8, r.position.y, lane.position.x - r.position.x - 8, r.size.y),
		Rect2(lane.end.x, r.position.y, r.end.x - lane.end.x - 8, r.size.y)]
	var cuts := [0.06, 0.37, 0.66, 0.94]
	for side in 2:
		var s: Rect2 = sides[side]
		for k in 3:
			var y0: float = r.position.y + r.size.y * float(cuts[k])
			var y1: float = r.position.y + r.size.y * float(cuts[k + 1]) - 6
			var floors := 2 + posmod(seed + side * 3 + k * 5, 3)
			var i := side * 3 + k
			var shop := _add(out, Rect2(s.position.x, y0, s.size.x, y1 - y0), 0, floors * 22 + 6, PRINT_WALLS[posmod(seed + i, PRINT_WALLS.size())], &"brick" if i % 2 == 0 else &"punched")
			shop.floor_height = 22
			shop.surface_detail = true
			shop.signs = PackedStringArray(PRINT_SHOPS[side])
			shop.deco = [&"shops", &"awning", &"ac", &"sd_pipes"]
			shop.seed = seed + i * 11
			_roof_kit(shop, seed + i, i % 3 == 0)
			# 골목 쪽 세로 간판 (서쪽 줄은 골목으로, 동쪽 줄은 큰길 쪽으로)
			var bx := s.end.x if side == 0 else s.end.x
			var blade := _add(out, Rect2(bx, y0 + 18, 16, 4), 26, 26 + minf(66.0, floors * 22.0 - 10.0), Color("f2efe6"))
			blade.text = PRINT_SHOPS[side][k] if k < 3 else "인쇄"
			blade.accent = [Color("1d4fb5"), Color("c8372c"), Color("2e8b57")][k]
			blade.deco = [&"sd_blade"]
			# 가게 앞 적재물 (골목 가장자리, 가운데는 비운다)
			var edge := lane.position.x + 1 if side == 0 else lane.end.x - 10
			for j in 2:
				var stack := _add(out, Rect2(edge, y0 + 34 + j * 26, 9, 12), 0, 8 + posmod(seed + i + j, 3) * 4, Color("c9b48a"), &"none", &"sd_stack")
				stack.seed = seed + i * 5 + j
	# 골목 위 전선과 전봇대
	var pole := _add(out, Rect2(lane.position.x + 1, r.position.y + r.size.y * 0.52, 5, 5), 0, 78, Color("6d6a64"), &"none", &"sd_pole")
	pole.seed = seed
	for k in 4:
		var y := r.position.y + r.size.y * (0.14 + k * 0.22)
		var wire := _add(out, Rect2(lane.position.x - 10, y, lane.size.x + 20, 2), 64 + k * 3, 66 + k * 3, IRON, &"none", &"sd_wires")
		wire.seed = seed + k
		wire.z_at_end = true


## 옥상 설비: 난간 띠·계단실·실외기·(물탱크)
static func _roof_kit(p: BuildingModel.Piece, seed: int, tank: bool) -> void:
	if p.rect.size.x < 50.0 or p.rect.size.y < 50.0:
		return
	BuildingModel._stair_house(p, seed, Color("9d9888"))
	BuildingModel._units(p, seed, 3)
	if tank:
		BuildingModel._tank(p, seed)
	for edge in [Rect2(0, 0, 1, 0.015), Rect2(0, 0, 0.015, 1)]:
		BuildingModel._plant(p, edge.position, edge.size, 5, p.wall.lightened(0.08))


# ── 보행 길·세워 둔 차 ─────────────────────────────────────

## 공터를 오가는 보행자 길 (LandmarkBuilding.walk_loops가 부른다)
static func walk_loops(r: Rect2, t: BuildingType) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	match t.style:
		&"school":
			var f: Rect2 = _school_frame(r).field.grow(-30)
			out.append(_ring(f))
		&"subway":
			var e: Rect2 = _subway_frame(r).entry
			out.append(_ring(Rect2(e.position - Vector2(44, 70), e.size + Vector2(88, 116))))
		&"print_alley":
			var lane := _alley(r)
			var x := lane.get_center().x
			out.append(PackedVector2Array([Vector2(x - 4, r.position.y + 14), Vector2(x - 4, r.end.y - 14), Vector2(x + 4, r.end.y - 14), Vector2(x + 4, r.position.y + 14)]))
		&"church":
			var fr := _church_frame(r)
			var tower: Rect2 = fr.tower
			var y0 := tower.end.y + 26
			out.append(PackedVector2Array([Vector2(r.position.x + 44, y0), Vector2(r.end.x - 44, y0), Vector2(r.end.x - 44, r.end.y - 52), Vector2(r.position.x + 44, r.end.y - 52)]))
	return out


static func _ring(q: Rect2) -> PackedVector2Array:
	return PackedVector2Array([q.position, Vector2(q.end.x, q.position.y), q.end, Vector2(q.position.x, q.end.y)])


## 세워 둔 차 [위치, 방향, 차종 경로] — 소방차는 차고 앞에서 바깥(남쪽)을 본다, 주유소는 주유기 옆 택시
static func parking(r: Rect2, t: BuildingType) -> Array:
	var out := []
	match t.style:
		&"fire_station":
			var fr := _fire_frame(r)
			var main: Rect2 = fr.main
			for k in [0, 2]:
				out.append([Vector2(fr.bays[k], main.end.y + 62), PI, FIRE_TRUCK])
		&"gas_station":
			var island: Rect2 = _gas_frame(r).islands[0]
			out.append([Vector2(island.end.x + 24, island.get_center().y), 0.0, PUMP_CAR])
	return out


# ── 바닥 (청크가 그린다) ───────────────────────────────────

const GRASS := Color("4f7a3e")
const ASPHALT := Color("3c3d40")
const CONCRETE_FLOOR := Color("8f8d86")


static func draw_ground(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int) -> void:
	match t.style:
		&"church": _church_ground(ci, r, seed)
		&"motel", &"nightlife": _street_ground(ci, r, seed, t.style == &"motel")
		&"gas_station": _gas_ground(ci, r, seed)
		&"parking_tower": _parking_ground(ci, r, seed)
		&"school": _school_ground(ci, r, seed)
		&"subway": _subway_ground(ci, r, seed)
		&"fire_station": _fire_ground(ci, r, seed)
		&"finance_tower": _plaza_ground(ci, r, seed)
		&"print_alley": _alley_ground(ci, r, seed)
		_: BuildingModel._plinth(ci, r, seed)


static func _h(seed: int, k: int) -> float:
	return float(posmod(hash(Vector2i(seed, k)), 10007)) / 10007.0


static func _speckle(ci: CanvasItem, q: Rect2, seed: int, color: Color, n: int, size := 2.0) -> void:
	for k in n:
		# hash01은 k에 선형이라 x·y를 같이 뽑으면 점이 대각선 한 줄로 늘어선다 — 따로 섞는다
		var at := q.position + q.size * Vector2(_h(seed, k), _h(seed + 7919, k * 31 + 3))
		ci.draw_rect(Rect2(at, Vector2(size, size * 0.7)), color)


static func _tiles(ci: CanvasItem, q: Rect2, step: float, color: Color) -> void:
	var x := q.position.x + step
	while x < q.end.x:
		ci.draw_line(Vector2(x, q.position.y), Vector2(x, q.end.y), color, 1.0)
		x += step
	var y := q.position.y + step
	while y < q.end.y:
		ci.draw_line(Vector2(q.position.x, y), Vector2(q.end.x, y), color, 1.0)
		y += step


static func _church_ground(ci: CanvasItem, r: Rect2, seed: int) -> void:
	ci.draw_rect(r, GRASS)
	_speckle(ci, r, seed, GRASS.lightened(0.12), 160, 3.0)
	_speckle(ci, r, seed + 9, GRASS.darkened(0.15), 120, 3.0)
	var fr := _church_frame(r)
	var tower: Rect2 = fr.tower
	var gate: Vector2 = fr.gate
	var path := Rect2(gate.x - 22, tower.end.y, 44, r.end.y - tower.end.y)
	ci.draw_rect(path, Color("b9b2a2"))
	_tiles(ci, path, 11, Color("9c9584"))
	var court := Rect2(tower.position.x - 40, tower.end.y, tower.size.x + 80, 40)
	ci.draw_rect(court, Color("c2bba9"))
	_tiles(ci, court, 13, Color("a29b89"))
	ci.draw_rect((fr.nave as Rect2).grow(6), Color("8f8a7f"))
	# 화단
	for k in 4:
		var bed := Rect2(r.position.x + r.size.x * (0.1 + k * 0.08), r.position.y + r.size.y * 0.5, 22, 14)
		ci.draw_rect(bed, Color("6a4a33"))
		for j in 6:
			ci.draw_circle(bed.position + Vector2(3 + j * 3.3, 4 + (j % 2) * 5), 2.0, [Color("e0405a"), Color("f2c94c"), Color("f5f0e6")][j % 3])


static func _street_ground(ci: CanvasItem, r: Rect2, seed: int, drive: bool) -> void:
	ci.draw_rect(r, Color("4a4848"))
	_speckle(ci, r, seed, Color("565353"), 120, 3.0)
	BuildingModel._plinth_hedges(ci, r, seed)
	if drive:
		# 주차장 입구로 들어가는 진입로와 화살표
		var lane := _f(r, 0.26, 0.6, 0.74, 1.0)
		ci.draw_rect(lane, ASPHALT)
		for k in 3:
			var c := Vector2(lane.get_center().x, lane.end.y - 30 - k * 40)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -12), c + Vector2(7, 0), c + Vector2(2, 0), c + Vector2(2, 10), c + Vector2(-2, 10), c + Vector2(-2, 0), c + Vector2(-7, 0)]), Color("d9d4b8"))
		ci.draw_rect(Rect2(lane.position.x, lane.position.y, lane.size.x, 6), Color("e3b023"))
	else:
		var walk := _f(r, 0.2, 0.68, 0.8, 1.0)
		ci.draw_rect(walk, Color("6b6866"))
		_tiles(ci, walk, 14, Color("5a5756"))


static func _gas_ground(ci: CanvasItem, r: Rect2, seed: int) -> void:
	ci.draw_rect(r, Color("9b9890"))
	_tiles(ci, r, 40, Color("8a877f"))
	_speckle(ci, r, seed, Color(0.2, 0.2, 0.22, 0.35), 40, 6.0)   # 기름 얼룩
	var fr := _gas_frame(r)
	for island: Rect2 in fr.islands:
		ci.draw_rect(island.grow(10), Color("b2aea3"))
		ci.draw_rect(island.grow(10), Color("e3b023"), false, 2.0)
	# 들어오고 나가는 화살표
	for k in 2:
		var c := r.position + r.size * Vector2(0.2 + k * 0.4, 0.9)
		var d := -1.0 if k == 0 else 1.0
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -14 * d), c + Vector2(8, 0), c + Vector2(2.5, 0), c + Vector2(2.5, 12 * d), c + Vector2(-2.5, 12 * d), c + Vector2(-2.5, 0), c + Vector2(-8, 0)]), Color("f2f0e6"))
	ci.draw_rect(Rect2(r.position.x, r.end.y - 4, r.size.x, 4), Color("e3b023"))
	var drain := _f(r, 0.1, 0.84, 0.7, 0.85)
	ci.draw_rect(drain, Color("4b4d50"))


static func _parking_ground(ci: CanvasItem, r: Rect2, seed: int) -> void:
	ci.draw_rect(r, Color("55575a"))
	_speckle(ci, r, seed, Color("626468"), 100, 3.0)
	var deck := _f(r, 0.1, 0.14, 0.8, 0.84)
	ci.draw_rect(deck, Color("6a6c6e"))
	var x := deck.position.x + 6
	while x < deck.end.x - 30:
		ci.draw_line(Vector2(x, deck.position.y + 6), Vector2(x, deck.position.y + 50), Color("dedbd0"), 2.0)
		ci.draw_line(Vector2(x, deck.end.y - 50), Vector2(x, deck.end.y - 6), Color("dedbd0"), 2.0)
		x += 34
	for k in 2:
		var c := Vector2(deck.get_center().x + (k - 0.5) * 60, deck.end.y + 24)
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -12), c + Vector2(7, 0), c + Vector2(2, 0), c + Vector2(2, 10), c + Vector2(-2, 10), c + Vector2(-2, 0), c + Vector2(-7, 0)]), Color("e8e3c8"))
	for k in 8:
		var s := Rect2(deck.position.x + k * 18, deck.end.y + 2, 9, 4)
		ci.draw_rect(s, Color("e3b023"))


static func _school_ground(ci: CanvasItem, r: Rect2, seed: int) -> void:
	ci.draw_rect(r, GRASS.darkened(0.05))
	_speckle(ci, r, seed, GRASS.lightened(0.1), 140, 3.0)
	var fr := _school_frame(r)
	var field: Rect2 = fr.field
	ci.draw_rect(field.grow(14), Color("b39466"))
	ci.draw_rect(field, Color("c9a874"))
	_speckle(ci, field, seed + 3, Color("b5935f"), 120, 3.0)
	var line := Color("efe9d6")
	ci.draw_rect(field.grow(-10), line, false, 2.0)
	ci.draw_line(Vector2(field.position.x + 10, field.get_center().y), Vector2(field.end.x - 10, field.get_center().y), line, 2.0)
	ci.draw_arc(field.get_center(), minf(field.size.x, field.size.y) * 0.16, 0, TAU, 36, line, 2.0)
	for side in [0, 1]:
		var y := field.position.y + 10 if side == 0 else field.end.y - 10
		var box := Rect2(field.get_center().x - 60, y if side == 0 else y - 50, 120, 50)
		ci.draw_rect(box, line, false, 2.0)
	var walk := Rect2((fr.gate as Vector2).x - 22, (fr.main as Rect2).end.y, 44, r.end.y - (fr.main as Rect2).end.y)
	ci.draw_rect(walk, Color("b9b2a2"))
	_tiles(ci, walk, 11, Color("9c9584"))
	ci.draw_rect(Rect2((fr.main as Rect2).position.x, (fr.main as Rect2).end.y, (fr.main as Rect2).size.x, 26), Color("b9b2a2"))


static func _subway_ground(ci: CanvasItem, r: Rect2, seed: int) -> void:
	ci.draw_rect(r, Color("a8a397"))
	_tiles(ci, r, 26, Color("958f83"))
	_speckle(ci, r, seed, Color("b7b2a6"), 80, 4.0)
	var entry: Rect2 = _subway_frame(r).entry
	var stair := entry.grow_individual(-8, 0, -8, 0)
	ci.draw_rect(stair, Color("1a2127"))
	for j in 14:
		var y := stair.position.y + stair.size.y * j / 14.0
		ci.draw_line(Vector2(stair.position.x, y), Vector2(stair.end.x, y), Color("8a938e").darkened(0.08 + j * 0.05), 3.0)
	var tactile := Rect2(entry.position.x, entry.end.y + 2, entry.size.x, 9)
	ci.draw_rect(tactile, Color("e2c13c"))
	for j in int(tactile.size.x / 5):
		ci.draw_circle(tactile.position + Vector2(2.5 + j * 5, 4.5), 1.2, Color("a88c25"))
	# 점자 블록 줄: 출입구에서 남쪽 인도까지
	var guide := Rect2(entry.get_center().x - 4, tactile.end.y, 8, r.end.y - tactile.end.y)
	ci.draw_rect(guide, Color("e2c13c"))
	for j in int(guide.size.y / 6):
		ci.draw_line(guide.position + Vector2(1.5, 3 + j * 6), guide.position + Vector2(6.5, 3 + j * 6), Color("a88c25"), 1.0)
	# 화단
	for fx in [0.36, 0.5, 0.64]:
		var c := r.position + r.size * Vector2(fx, 0.18)
		ci.draw_circle(c, 16, Color("6a6458"))
		ci.draw_circle(c, 13, GRASS)


static func _fire_ground(ci: CanvasItem, r: Rect2, seed: int) -> void:
	ci.draw_rect(r, Color("8d8b85"))
	_tiles(ci, r, 32, Color("7f7d77"))
	var fr := _fire_frame(r)
	var main: Rect2 = fr.main
	for x: float in fr.bays:
		var apron := Rect2(x - main.size.x / 6.0 + 8, main.end.y, main.size.x / 3.0 - 16, r.end.y - main.end.y - 6)
		ci.draw_rect(apron, Color("9a978f"))
		var k := 0
		var y := apron.position.y + 4
		while y < apron.end.y - 6:
			ci.draw_colored_polygon(PackedVector2Array([Vector2(apron.position.x, y), Vector2(apron.position.x + 10, y), Vector2(apron.position.x, y + 10)]), Color("e3b023"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(apron.end.x, y), Vector2(apron.end.x - 10, y), Vector2(apron.end.x, y + 10)]), Color("e3b023"))
			y += 16
			k += 1
		ci.draw_rect(apron, Color("e3b023"), false, 2.0)
	var mark := Rect2(main.position.x, r.end.y - 22, main.size.x, 14)
	ci.draw_rect(mark, Color("b4332e"))
	ci.draw_string(ThemeDB.fallback_font, mark.position + Vector2(0, 11), "소방차 전용  주정차 금지", HORIZONTAL_ALIGNMENT_CENTER, mark.size.x, 11, Color("f5efe0"))


static func _plaza_ground(ci: CanvasItem, r: Rect2, seed: int) -> void:
	ci.draw_rect(r, Color("b5b0a6"))
	_tiles(ci, r, 30, Color("a29d93"))
	var c := r.get_center()
	for k in 3:
		ci.draw_rect(Rect2(r.position.x + 8, r.end.y - r.size.y * 0.18 + k * 14, r.size.x - 16, 7), Color("c9c4b8"))
	ci.draw_rect(_f(r, 0.4, 0.78, 0.6, 1.0), Color("8e8a82"))


static func _alley_ground(ci: CanvasItem, r: Rect2, seed: int) -> void:
	ci.draw_rect(r, Color("575552"))
	_speckle(ci, r, seed, Color("63605c"), 100, 4.0)
	var lane := _alley(r)
	ci.draw_rect(lane, Color("4b4a48"))
	_speckle(ci, lane, seed + 4, Color("3f3e3c"), 60, 5.0)
	ci.draw_line(Vector2(lane.get_center().x, lane.position.y), Vector2(lane.get_center().x, lane.end.y), Color("2f2e2c"), 3.0)
	for k in 4:
		var c := Vector2(lane.get_center().x, r.position.y + r.size.y * (0.12 + k * 0.25))
		ci.draw_rect(Rect2(c - Vector2(5, 3), Vector2(10, 6)), Color("33373a"))
