class_name LandmarkBuilding
## 랜드마크(타워 공원·고속버스터미널·재래시장·방송국·부두)와 소품. 참고 그림을 붙이지 않고 Piece로 짓는다 (docs/15).
## 부지 전체를 막지 않는다: 바닥에 선 덩어리(건물·기둥·좌판·컨테이너·나무 줄기)만 충돌하고(collision_rects),
## 나머지 공터(잔디·길·승강장·골목·하역장)는 사람과 차가 다닌다. 바닥 그림은 draw_ground가 청크에 그린다 — 사람·차보다 늘 밑.
## 공터에는 보행자가 걷는 길(walk_loops)과 세워 둔 차 자리(parking)를 둔다.
## 모든 위치는 부지 사각형에서 계산한다 (RNG 없이 — 늘 같은 도시).

const STYLES := [&"landmark_tower", &"terminal", &"market", &"dock_crane", &"broadcast", &"checkpoint", &"container", &"dock_warehouse", &"barrier", &"industrial_dock",
	&"sky_tower", &"lake_park", &"namsan_summit"]
const YELLOW := Color(0.88, 0.61, 0.12)
## 부두 헬기장에 세워 두는 헬기 (4장 부두가 열려야 생긴다)
const DOCK_HELI := "res://data/vehicles/sp_heli.tres"
## 부두 야적장에 세워 둔 군용 차량 (선적을 기다리는 자주포·전술차량 — 4장, 탈 수 있다)
const DOCK_SPG := "res://data/vehicles/army_spg.tres"
const DOCK_JEEP := "res://data/vehicles/army_jeep.tres"
const HELIPAD_RADIUS := 50.0
const STEEL := Color("3b4144")
const WOOD := Color("7a5536")
## 바닥에서 시작하지만 막지 않는 덩어리 (벽 없이 그림만)
const OPEN_ROOFS: Array[StringName] = [&"crane_brace", &"satellite_dish", &"lanterns", &"tarp", &"hoist"]
## 재래시장 가게 이름 (업종 낱말만 — 실존 상호 아님)
const MARKET_SIGNS := ["청과", "생선", "정육", "떡집", "반찬", "건어물", "분식", "잡화", "방앗간", "채소"]
const CONTAINER_COLORS := [Color("267360"), Color("3e657f"), Color("97513a"), Color("a8862f"), Color("6b4d7a"), Color("2f5b8f")]
const TARP_COLORS := [Color("c8372c"), Color("2e6fa8"), Color("e09a2a"), Color("2f8a57"), Color("c8372c"), Color("8a3fa0")]


static func owns(style: StringName) -> bool:
	return style in STYLES or StreetBuilding.owns(style)


static func box(out: Array[BuildingModel.Piece], r: Rect2, a: float, b: float, color: Color, windows := &"none", roof := &"flat") -> BuildingModel.Piece:
	var p := BuildingModel._box(r, a, b, color, roof, color.darkened(0.1), windows, 17 + out.size())
	out.append(p)
	return p


static func build(out: Array[BuildingModel.Piece], r: Rect2, t: BuildingType, seed: int) -> void:
	if StreetBuilding.owns(t.style):
		StreetBuilding.build(out, r, t, seed)
		return
	var c := r.get_center()
	var base := Rect2(r.position + r.size * 0.1, r.size * 0.8)
	match t.style:
		&"landmark_tower":
			if BuildingSprite.merged_lot(r):
				Namsan.build(out, r, seed)   # 합친 블록: 산 하나 (도감·가이드의 블록 하나 부지는 예전 타워 공원)
			else:
				_tower_park(out, r, seed)
		&"terminal": _terminal(out, r, seed)
		&"market": _market(out, r, seed)
		&"broadcast": _broadcast(out, r, seed)
		&"industrial_dock": _dock(out, r, seed)
		&"sky_tower": Lotte.build_tower(out, r, seed)
		&"lake_park": Lotte.build_park(out, r, seed)
		&"namsan_summit": Namsan.build_summit(out, r, seed)   # 남산 꼭대기 평지 (산 부지 안의 작은 부지 — 통째 그림이 붙는다)
		&"checkpoint":
			var booth := box(out, Rect2(c - Vector2(38, 30), Vector2(76, 60)), 0, 46, Color("b7b6a9"), &"punched")
			booth.deco = [&"landmark_sign", &"door"]
			booth.text = "검문"
			BuildingModel._units(booth, seed, 1)
			for side in [-1, 1]:
				box(out, Rect2(c + Vector2(side * 45, 20), Vector2(8, 8)), 0, 20, YELLOW)
		&"dock_crane":
			crane(out, base)
		&"container":
			_container(out, Rect2(c - Vector2(100, 42), Vector2(200, 84)), 0, Color("24705c"), true)
		&"dock_warehouse":
			warehouse(out, base)
		&"barrier":
			barrier(out, c)


# ── 타워 공원: 숲과 바위 사이 계단길, 가운데 광장의 전망 타워, 앞쪽 팔각정 ──

static func tower_center(r: Rect2) -> Vector2:
	return r.get_center() + Vector2(-24, -24)


static func pavilion_center(r: Rect2) -> Vector2:
	return r.position + r.size * Vector2(0.24, 0.74)


static func _tower_park(out: Array[BuildingModel.Piece], r: Rect2, seed: int) -> void:
	var c := tower_center(r)
	# 기단(매표소) 위에 탑신, 그 위에 전망층 셋과 송신 안테나를 차례로 얹는다 (같은 자리라 순서를 고정한다)
	var plinth := box(out, Rect2(c - Vector2(40, 40), Vector2(80, 80)), 0, 24, Color("e4dfd0"), &"punched")
	plinth.deco = [&"entrance"]
	plinth.roof_color = Color("cfc8b4")
	var shaft := BuildingModel._box(Rect2(c - Vector2(16, 16), Vector2(32, 32)), 24, 214, Color("ece8dc"), &"tank", Color("d9d3c2"), &"none", seed)
	plinth.on_top.append(shaft)
	var under := shaft
	for level in 3:
		var w := 104.0 - level * 20.0
		var deck := BuildingModel._box(Rect2(c - Vector2.ONE * w / 2, Vector2.ONE * w), 214 + level * 22, 234 + level * 22,
			Color("e2ddcd") if level != 1 else Color("c9c3b0"), &"observation_ring", Color("bdb6a0"), &"glass", seed + level)
		under.on_top.append(deck)
		under = deck
	under.on_top.append(BuildingModel._box(Rect2(c - Vector2(7, 7), Vector2(14, 14)), 280, 400, Color("c33a2c"), &"antenna", Color("ff3b2a"), &"none", seed))
	# 팔각정: 기둥만 막고 지붕 밑으로 지나간다
	var pc := pavilion_center(r)
	var pav := box(out, Rect2(pc - Vector2(26, 26), Vector2(52, 52)), 0, 26, Color("8b2b22"), &"none", &"pavilion")
	pav.roof_color = Color("4b5157")
	pav.accent = Color("3f7a5a")
	pav.rise = 16.0
	pav.eave = 11.0
	# 광장 벤치와 가로등
	box(out, Rect2(c + Vector2(52, 92), Vector2(22, 7)), 0, 6, WOOD)
	box(out, Rect2(c + Vector2(92, 52), Vector2(7, 22)), 0, 6, WOOD)
	for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		box(out, Rect2(c + d * 66.0 - Vector2(2, 2), Vector2(4, 4)), 0, 40, Color("2f3437"), &"none", &"lamp_pole")
	# 숲: 길(남쪽·동쪽 계단길, 팔각정 둘레)과 광장을 비우고 부지 둘레에 나무
	var k := 0
	for spot in _park_tree_spots(r):
		var tree := BuildingModel._tree(spot, seed + k * 7, 1.15 + BuildingModel.hash01(seed, k + 40) * 0.6)
		if BuildingModel.hash01(seed, k + 90) < 0.28:
			tree.roof_color = Color("e9a6bf")   # 벚꽃
		elif BuildingModel.hash01(seed, k + 91) < 0.4:
			tree.roof_color = Color("3f6f3a")
		out.append(tree)
		k += 1


static func _park_tree_spots(r: Rect2) -> Array[Vector2]:
	var c := tower_center(r)
	var pc := pavilion_center(r)
	var out: Array[Vector2] = []
	var step := 40.0
	var y := r.position.y + 22.0
	var row := 0
	while y < r.end.y - 16.0:
		var x := r.position.x + 22.0 + (row % 2) * step * 0.5
		while x < r.end.x - 16.0:
			var p := Vector2(x, y) + Vector2(BuildingModel.hash01(row, int(x)) - 0.5, BuildingModel.hash01(int(x), row) - 0.5) * 14.0
			var edge := minf(minf(p.x - r.position.x, r.end.x - p.x), minf(p.y - r.position.y, r.end.y - p.y))
			var keep := edge < 70.0 \
				and p.distance_to(c) > 150.0 \
				and absf(p.x - c.x) > 30.0 \
				and absf(p.y - c.y) > 30.0 \
				and p.distance_to(pc) > 60.0 \
				and not (p.y > pc.y - 12.0 and p.y < pc.y + 12.0 and p.x < c.x)
			if keep:
				out.append(p)
			x += step
		y += step * 0.8
		row += 1
	return out


# ── 고속버스터미널: 유리 본관과 계단 탑, 승강장 지붕 셋, 그 밑에 버스 ──

static func _terminal_frame(r: Rect2) -> Dictionary:
	var area := r.grow(-20.0)
	var hall := Rect2(area.position, Vector2(area.size.x - 58.0, area.size.y * 0.42))
	var y0 := hall.end.y + 30.0
	var bays: Array[Rect2] = []
	var w := (area.size.x - 40.0) / 3.0
	for k in 3:
		var xc := area.position.x + 20.0 + (k + 0.5) * w
		bays.append(Rect2(xc - 36.0, y0, 72.0, area.end.y - 12.0 - y0))
	return {"area": area, "hall": hall, "bays": bays}


static func _terminal(out: Array[BuildingModel.Piece], r: Rect2, seed: int) -> void:
	var f := _terminal_frame(r)
	var area: Rect2 = f.area
	var hall_r: Rect2 = f.hall
	var hall := box(out, hall_r, 0, 92, Color("cbc6b5"), &"glass")
	hall.deco = [&"top_sign", &"entrance"]
	hall.text = "고속버스터미널"
	hall.roof_color = Color("8d9391")
	hall.surface_detail = true
	for k in 5:
		BuildingModel._plant(hall, Vector2(0.06 + k * 0.18, 0.14), Vector2(0.1, 0.62), 4, Color("5f8496"))
	BuildingModel._units(hall, seed, 4)
	var tower := box(out, Rect2(Vector2(hall_r.end.x, area.position.y), Vector2(58, hall_r.size.y)), 0, 126, Color("bfb9a8"), &"glass")
	tower.roof_color = Color("7e8482")
	BuildingModel._stair_house(tower, seed)
	for bay: Rect2 in f.bays:
		var canopy := box(out, bay, 34, 39, Color("9aa1a6"), &"none", &"canopy")
		canopy.roof_color = Color("8a9298")
		for y in [bay.position.y + 10.0, bay.get_center().y, bay.end.y - 16.0]:
			for x in [bay.position.x + 1.0, bay.end.x - 7.0]:
				box(out, Rect2(x, y, 6, 6), 0, 34, Color("d6ccb5"))
	# 앞 보도 끝 볼라드 (승강장 사이)
	for k in 4:
		var x := area.position.x + 6.0 + k * (area.size.x - 12.0) / 3.0
		box(out, Rect2(x - 2.0, hall_r.end.y + 22.0, 4, 4), 0, 9, YELLOW)


# ── 재래시장: 십자 골목 양쪽 상가, 골목 안 좌판과 천막, 머리 위 전구 줄, 남쪽 입구 문 ──

static func _market_frame(r: Rect2) -> Dictionary:
	var area := r.grow(-14.0)
	var lane := 86.0
	var c := area.get_center()
	var quads: Array[Rect2] = [
		Rect2(area.position, Vector2(c.x - lane * 0.5 - area.position.x, c.y - lane * 0.5 - area.position.y)),
		Rect2(Vector2(c.x + lane * 0.5, area.position.y), Vector2(area.end.x - c.x - lane * 0.5, c.y - lane * 0.5 - area.position.y)),
		Rect2(Vector2(area.position.x, c.y + lane * 0.5), Vector2(c.x - lane * 0.5 - area.position.x, area.end.y - c.y - lane * 0.5)),
		Rect2(c + Vector2.ONE * lane * 0.5, area.end - c - Vector2.ONE * lane * 0.5),
	]
	return {"area": area, "lane": lane, "c": c, "quads": quads}


static func _market(out: Array[BuildingModel.Piece], r: Rect2, seed: int) -> void:
	var f := _market_frame(r)
	var area: Rect2 = f.area
	var lane: float = f.lane
	var c: Vector2 = f.c
	var walls := [Color("9a6a52"), Color("b9a58c"), Color("8a6d5c"), Color("c2b29a"), Color("a0705a")]
	var roofs := [Color("365a75"), Color("985231"), Color("466851"), Color("7a3b35"), Color("3f4f8a")]
	var n := 0
	for q: Rect2 in f.quads:
		var w := (q.size.x - 8.0) * 0.5
		for side in 2:
			var rr := Rect2(q.position + Vector2(side * (w + 8.0), 0), Vector2(w, q.size.y))
			var tall := BuildingModel.hash01(seed, n + 3) < 0.5
			var shop := box(out, rr, 0, 54 if tall else 36, walls[n % walls.size()], &"brick", &"gable" if n % 3 != 1 else &"hip")
			shop.roof_color = roofs[(n * 3 + 1) % roofs.size()]
			shop.rise = 16.0
			shop.eave = 5.0
			shop.surface_detail = true
			shop.deco = [&"shops", &"awning"]
			var signs := PackedStringArray()
			for k in 3:
				signs.append(MARKET_SIGNS[(n * 3 + k) % MARKET_SIGNS.size()])
			shop.signs = signs
			if side == 1 and tall:
				shop.deco.append(&"vsign")
				shop.text = "시장"
			BuildingModel._units(shop, seed + n, 1)
			n += 1
	# 골목 좌판 (막는다)과 그 위 천막 (막지 않는다). 가운데 길은 비운다
	var k := 0
	for stall in _market_stalls(f):
		var table := box(out, stall, 0, 9, WOOD, &"none", &"produce")
		table.seed = seed + k
		# 천막은 좌판과 같은 자리라 좌판 위에 얹어 그린다 (그리는 순서 고정, 충돌 없음)
		var tarp := BuildingModel._box(stall.grow(3.0), 0, 27, TARP_COLORS[k % TARP_COLORS.size()], &"tarp", TARP_COLORS[(k + 2) % TARP_COLORS.size()])
		table.on_top.append(tarp)
		k += 1
	# 전구 줄: 남북 골목을 가로질러
	var y := area.position.y + 40.0
	while y < area.end.y - 30.0:
		if absf(y - c.y) > lane * 0.6:
			box(out, Rect2(c.x - lane * 0.5, y, lane, 2), 40, 41, Color("2b2b2b"), &"none", &"lanterns")
		y += 64.0
	var x := area.position.x + 40.0
	while x < area.end.x - 30.0:
		if absf(x - c.x) > lane * 0.6:
			box(out, Rect2(x, c.y - lane * 0.5, 2, lane), 40, 41, Color("2b2b2b"), &"none", &"lanterns")
		x += 64.0
	# 남쪽 입구 문: 기둥 둘과 위 간판 (밑으로 지나간다)
	var gy := area.end.y - 8.0
	for gx in [c.x - lane * 0.5 + 2.0, c.x + lane * 0.5 - 10.0]:
		box(out, Rect2(gx, gy, 8, 8), 0, 44, Color("8b2b22"))
	var beam := box(out, Rect2(c.x - lane * 0.5, gy, lane, 8), 44, 58, Color("8b2b22"))
	beam.deco = [&"landmark_sign"]
	beam.text = "전통시장"
	beam.roof_color = Color("4b5157")


## 골목 좌판 자리: 양쪽 벽에 붙여 두고 가운데 44px는 길로 비운다. 십자 교차부와 입구도 비운다
static func _market_stalls(f: Dictionary) -> Array[Rect2]:
	var area: Rect2 = f.area
	var lane: float = f.lane
	var c: Vector2 = f.c
	var out: Array[Rect2] = []
	var y := area.position.y + 14.0
	while y + 30.0 < area.end.y - 40.0:
		if absf(y + 15.0 - c.y) > lane * 0.5 + 24.0:
			out.append(Rect2(c.x - lane * 0.5 + 3.0, y, 18, 30))
			out.append(Rect2(c.x + lane * 0.5 - 21.0, y, 18, 30))
		y += 40.0
	var x := area.position.x + 14.0
	while x + 30.0 < area.end.x - 14.0:
		if absf(x + 15.0 - c.x) > lane * 0.5 + 24.0:
			out.append(Rect2(x, c.y - lane * 0.5 + 3.0, 30, 18))
			out.append(Rect2(x, c.y + lane * 0.5 - 21.0, 30, 18))
		x += 40.0
	return out


# ── 방송국: 유리 본관(옥상 철탑·위성 접시), 옆 비상계단, 앞마당 나무와 중계차 ──

static func _broadcast_frame(r: Rect2) -> Dictionary:
	var area := r.grow(-16.0)
	var hall := Rect2(area.position, Vector2(area.size.x * 0.64, area.size.y * 0.58))
	return {"area": area, "hall": hall}


static func _broadcast(out: Array[BuildingModel.Piece], r: Rect2, seed: int) -> void:
	var f := _broadcast_frame(r)
	var area: Rect2 = f.area
	var hall_r: Rect2 = f.hall
	var hall := box(out, hall_r, 0, 124, Color("c3c6c2"), &"glass")
	hall.deco = [&"top_sign", &"entrance"]
	hall.text = "방송국"
	hall.roof_color = Color("777d7d")
	hall.surface_detail = true
	for k in 2:
		hall.on_top.append(BuildingModel._box(Rect2(hall_r.position + Vector2(40 + k * 80, 40), Vector2(30, 30)), 124, 154,
			Color.WHITE, &"satellite_dish", Color.WHITE, &"none", seed + k))
	BuildingModel._stair_house(hall, seed)
	BuildingModel._units(hall, seed, 4)
	hall.on_top.append(BuildingModel._box(Rect2(hall_r.get_center() + Vector2(10, -10), Vector2(40, 40)), 124, 262,
		Color("c8372c"), &"lattice", Color("ff3b2a"), &"none", seed))
	# 옆 동(낮은 스튜디오)과 그 벽의 비상계단
	var wing_r := Rect2(Vector2(hall_r.end.x + 22.0, area.position.y), Vector2(area.end.x - hall_r.end.x - 22.0, hall_r.size.y * 0.62))
	var wing := box(out, wing_r, 0, 58, Color("b5b9b6"), &"punched")
	wing.deco = [&"shutter"]
	wing.roof_color = Color("6f7575")
	BuildingModel._units(wing, seed + 5, 3)
	for floor_idx in 3:
		for step in 9:
			var z := floor_idx * 36.0 + step * 4.0
			box(out, Rect2(hall_r.end.x + 2.0, hall_r.position.y + 36.0 + step * 9.0, 18, 9), z, z + 3, Color("5e666b"))
		box(out, Rect2(hall_r.end.x + 2.0, hall_r.position.y + 117.0, 18, 20), (floor_idx + 1) * 36 - 3, (floor_idx + 1) * 36, Color("81898a"))
	# 중계차: 흰 상자 차에 접시 (막는다)
	var van_at := Vector2(wing_r.position.x + 30.0, wing_r.end.y + 30.0)
	var van := box(out, Rect2(van_at, Vector2(26, 54)), 0, 22, Color("e8e8e4"), &"none")
	van.roof_color = Color("d4d6d2")
	van.on_top.append(BuildingModel._box(Rect2(van_at + Vector2(5, 14), Vector2(16, 16)), 22, 34, Color.WHITE, &"satellite_dish", Color.WHITE, &"none", seed + 9))
	# 앞마당 가로수
	var k := 0
	var x := area.position.x + 18.0
	while x < area.end.x - 10.0:
		out.append(BuildingModel._tree(Vector2(x, area.end.y - 10.0), seed + k, 1.25))
		x += 52.0
		k += 1
	var y := wing_r.end.y + 100.0
	while y < area.end.y - 40.0:
		out.append(BuildingModel._tree(Vector2(area.end.x - 10.0, y), seed + k, 1.2))
		y += 52.0
		k += 1


# ── 부두: 레일 위 갠트리 크레인과 매달린 컨테이너, 쌓인 컨테이너, 창고, 지게차, 경비 초소 ──

static func _dock_frame(r: Rect2) -> Dictionary:
	var area := r.grow(-14.0)
	var crane_r := Rect2(area.position + Vector2(12, 12), Vector2(area.size.x * 0.56, area.size.y * 0.6))
	var shed := Rect2(Vector2(area.position.x + area.size.x * 0.64, area.position.y + 10.0), Vector2(area.size.x * 0.36 - 6.0, area.size.y * 0.4))
	# 헬기장: 창고 남쪽 빈 마당 (지게차·투광등·남쪽 컨테이너 더미·경비 초소 사이)
	var pad := Vector2(area.position.x + area.size.x * 0.82, area.position.y + area.size.y * 0.7)
	# 군용 차량: 창고 남쪽(지게차 동쪽)에 동쪽을 보는 자주포, 헬기장 서쪽에 전술차량
	var spg := Vector2(area.position.x + area.size.x * 0.83, area.position.y + area.size.y * 0.53)
	var jeep := Vector2(area.position.x + area.size.x * 0.62, area.position.y + area.size.y * 0.72)
	return {"area": area, "crane": crane_r, "shed": shed, "pad": pad, "spg": spg, "jeep": jeep}


static func _dock(out: Array[BuildingModel.Piece], r: Rect2, seed: int) -> void:
	var f := _dock_frame(r)
	var area: Rect2 = f.area
	var cr: Rect2 = f.crane
	crane(out, cr)
	# 크레인 밑 컨테이너 줄 (일부는 2단)
	var w := (cr.size.x - 60.0) * 0.5
	for row in 3:
		for col in 2:
			var at := Vector2(cr.position.x + 26.0 + col * (w + 8.0), cr.position.y + 34.0 + row * 46.0)
			var n := row * 2 + col
			_container(out, Rect2(at, Vector2(w, 28)), 0, CONTAINER_COLORS[n % CONTAINER_COLORS.size()], BuildingModel.hash01(seed, n) < 0.55)
	warehouse(out, f.shed)
	# 남쪽 야적장: 컨테이너 더미 (2~3단)
	var x := area.position.x + 10.0
	var k := 0
	while x + 100.0 < area.end.x - 70.0:
		_container(out, Rect2(Vector2(x, area.end.y - 76.0), Vector2(100, 28)), 0, CONTAINER_COLORS[(k + 2) % CONTAINER_COLORS.size()], true,
			BuildingModel.hash01(seed, k + 30) < 0.4)
		_container(out, Rect2(Vector2(x, area.end.y - 40.0), Vector2(100, 28)), 0, CONTAINER_COLORS[(k + 4) % CONTAINER_COLORS.size()], k % 2 == 0)
		x += 112.0
		k += 1
	# 지게차 둘
	_forklift(out, Vector2(f.shed.position.x + 20.0, f.shed.end.y + 40.0))
	_forklift(out, Vector2(cr.end.x - 40.0, cr.end.y + 30.0))
	# 경비 초소와 차단기 (남동쪽 출입구)
	var booth := box(out, Rect2(Vector2(area.end.x - 34.0, area.end.y - 70.0), Vector2(28, 24)), 0, 24, Color("c9c6b8"), &"punched")
	booth.deco = [&"door"]
	booth.roof_color = Color("5c6266")
	_gate_arm(out, Vector2(area.end.x - 14.0, area.end.y - 36.0), 46.0)
	# 투광등
	for at in [area.position + Vector2(4, 4), Vector2(area.end.x - 8.0, area.position.y + area.size.y * 0.48), Vector2(area.position.x + 4.0, area.end.y - 90.0)]:
		box(out, Rect2(at, Vector2(4, 4)), 0, 86, Color("2f3437"), &"none", &"lamp_pole")


## 부두 헬기장 바닥: 노란 테두리 원과 흰 H (H는 화면에서 똑바로 읽히게 월드 (1,-1)·(-1,-1) 방향으로 그린다)
static func _dock_helipad(ci: CanvasItem, c: Vector2) -> void:
	ci.draw_circle(c, HELIPAD_RADIUS, Color("3d4043"))
	ci.draw_arc(c, HELIPAD_RADIUS - 3.0, 0.0, TAU, 32, Color(0.95, 0.78, 0.2), 3.0)
	ci.draw_arc(c, HELIPAD_RADIUS * 0.66, 0.0, TAU, 28, Color(0.94, 0.94, 0.9, 0.85), 2.0)
	var right := Vector2(1, -1).normalized()
	var up := Vector2(-1, -1).normalized()
	var hx := HELIPAD_RADIUS * 0.2
	var hy := HELIPAD_RADIUS * 0.36
	for bar in [[Vector2(-hx, -hy), Vector2(-hx, hy)], [Vector2(hx, -hy), Vector2(hx, hy)], [Vector2(-hx, 0), Vector2(hx, 0)]]:
		var a: Vector2 = bar[0]
		var b: Vector2 = bar[1]
		ci.draw_line(c + right * a.x + up * a.y, c + right * b.x + up * b.y, Color.WHITE, 4.0)


static func _container(out: Array[BuildingModel.Piece], rr: Rect2, h0: float, color: Color, doors: bool, double := false) -> BuildingModel.Piece:
	var cargo := box(out, rr, h0, h0 + 28.0, color, &"metal")
	cargo.roof_color = color.darkened(0.15)
	if doors:
		cargo.deco = [&"container_doors"]
	if double:
		var up := BuildingModel._box(Rect2(rr.position + Vector2(rr.size.x * 0.08, 0), rr.size * Vector2(0.84, 1.0)), h0 + 28.0, h0 + 56.0,
			color.lightened(0.18).lerp(Color("3e657f"), 0.3), &"flat", color.darkened(0.1), &"metal", cargo.seed + 1)
		cargo.on_top.append(up)
	return cargo


static func _forklift(out: Array[BuildingModel.Piece], at: Vector2) -> void:
	var body := box(out, Rect2(at, Vector2(16, 22)), 0, 10, YELLOW)
	body.roof_color = Color("d8a23a")
	body.on_top.append(BuildingModel._box(Rect2(at + Vector2(2, 8), Vector2(12, 12)), 10, 22, Color("2c2f33"), &"flat", Color("2c2f33"), &"none", 1))
	box(out, Rect2(at + Vector2(3, -9), Vector2(10, 9)), 0, 2, Color("3a3a3a"))


## 갠트리 크레인: 바퀴 대차 위 다리 넷, 짧은 변의 X 버팀, 긴 변의 위 거더 둘, 거더를 잇는 트롤리와 운전실,
## 줄에 매달린 컨테이너. 바닥에 닿는 대차·다리만 막는다
static func crane(out: Array[BuildingModel.Piece], r: Rect2) -> void:
	for x in [r.position.x, r.end.x - 12.0]:
		for y in [r.position.y, r.end.y - 12.0]:
			var bogie := box(out, Rect2(x - 4, y - 4, 20, 20), 0, 8, STEEL)
			bogie.on_top.append(BuildingModel._box(Rect2(x, y, 12, 12), 8, 150, YELLOW, &"flat", YELLOW.lightened(0.1), &"none", 3))
		box(out, Rect2(x, r.position.y + 12.0, 12, r.size.y - 24.0), 8, 150, YELLOW, &"none", &"crane_brace")
	for y in [r.position.y, r.end.y - 14.0]:
		box(out, Rect2(r.position.x - 8.0, y, r.size.x + 16.0, 14), 150, 166, YELLOW)
	var c := r.get_center()
	var trolley := box(out, Rect2(c.x - 16.0, r.position.y + 2.0, 32, r.size.y - 4.0), 166, 174, YELLOW.darkened(0.08))
	trolley.on_top.append(BuildingModel._box(Rect2(c.x - 12.0, r.end.y - 34.0, 24, 22), 174, 190, Color("d9d6cc"), &"flat", Color("5c6266"), &"glass", 5))
	var hoist := box(out, Rect2(c - Vector2(32, 13), Vector2(64, 26)), 92, 166, STEEL, &"none", &"hoist")
	hoist.on_top.append(BuildingModel._box(Rect2(c - Vector2(30, 12), Vector2(60, 24)), 64, 90, CONTAINER_COLORS[0].lightened(0.1), &"flat",
		CONTAINER_COLORS[0], &"metal", 7))


static func warehouse(out: Array[BuildingModel.Piece], r: Rect2) -> void:
	var shed := box(out, r, 0, 60, Color("8b9292"), &"metal", &"gable")
	shed.rise = 30
	shed.eave = 6
	shed.roof_color = Color("496c86")
	shed.deco = [&"shutter", &"door"]


## 출입구 차단기: 기둥(막는다)과 서쪽으로 뻗은 빨강·흰 막대(공중)
static func _gate_arm(out: Array[BuildingModel.Piece], post: Vector2, length: float) -> void:
	box(out, Rect2(post, Vector2(10, 10)), 0, 24, Color("737a7a"))
	var n := int(length / 8.0)
	for k in n:
		box(out, Rect2(post + Vector2(-8.0 * (k + 1), 3), Vector2(8, 4)), 19, 23, Color("cb3c30") if k % 2 else Color("eae7d8"))


static func barrier(out: Array[BuildingModel.Piece], c: Vector2) -> void:
	box(out, Rect2(c - Vector2(70, 8), Vector2(16, 16)), 0, 32, Color("737a7a"))
	for k in 12:
		box(out, Rect2(c + Vector2(-60 + k * 10, -2), Vector2(10, 4)), 26, 32, Color("cb3c30") if k % 2 else Color("eae7d8"))


# ── 충돌·걷는 길·세워 둔 차 ───────────────────────────────

## 막는 바닥: 바닥에 선 덩어리만. 공중 덩어리(캐노피·거더·천막·전구 줄)와 팔각정 지붕 밑은 지나간다
static func collision_rects(r: Rect2, t: BuildingType, seed: int) -> Array[Rect2]:
	var pieces: Array[BuildingModel.Piece] = []
	build(pieces, r, t, seed)
	return BuildingModel.ground_obstacles(pieces)


static func _pavilion_posts(r: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for x in [r.position.x, r.end.x - 6.0]:
		for y in [r.position.y, r.end.y - 6.0]:
			out.append(Rect2(x, y, 6, 6))
	return out


## 보행자가 부지 안 공터를 오가는 길 (닫힌 꼭짓점 목록). 막는 덩어리와 겹치지 않게 골랐다
static func walk_loops(r: Rect2, t: BuildingType) -> Array[PackedVector2Array]:
	if StreetBuilding.owns(t.style):
		return StreetBuilding.walk_loops(r, t)
	var out: Array[PackedVector2Array] = []
	match t.style:
		&"landmark_tower":
			if BuildingSprite.merged_lot(r):
				return Namsan.walk_loops(r)
			var c := tower_center(r)
			out.append(_ring(Rect2(c - Vector2(80, 80), Vector2(160, 160))))
		&"terminal":
			var f := _terminal_frame(r)
			var hall: Rect2 = f.hall
			var area: Rect2 = f.area
			out.append(_ring(Rect2(area.position.x + 10.0, hall.end.y + 8.0, area.size.x - 20.0, 8.0)))
		&"market":
			var f := _market_frame(r)
			var area: Rect2 = f.area
			var c: Vector2 = f.c
			out.append(_ring(Rect2(c.x - 6.0, area.position.y + 8.0, 12.0, area.size.y - 28.0)))
			out.append(_ring(Rect2(area.position.x + 8.0, c.y - 6.0, area.size.x - 16.0, 12.0)))
		&"broadcast":
			var f := _broadcast_frame(r)
			var hall: Rect2 = f.hall
			var area: Rect2 = f.area
			out.append(_ring(Rect2(area.position.x + 20.0, hall.end.y + 22.0, hall.size.x - 10.0, area.end.y - hall.end.y - 62.0)))
		&"industrial_dock":
			var f := _dock_frame(r)
			var area: Rect2 = f.area
			var cr: Rect2 = f.crane
			out.append(_ring(Rect2(area.position.x + 10.0, cr.end.y + 14.0, cr.size.x - 10.0, 8.0)))
		&"sky_tower": return Lotte.tower_loops(r)
		&"lake_park": return Lotte.park_loops(r)
	return out


static func _ring(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## 세워 둔 차 [위치, 방향(rotation)] — 터미널 승강장의 고속버스. 앞이 본관(북쪽)을 본다
static func parking(r: Rect2, t: BuildingType) -> Array:
	if StreetBuilding.owns(t.style):
		return StreetBuilding.parking(r, t)
	var out := []
	if t.style == &"landmark_tower" and BuildingSprite.merged_lot(r):
		return Namsan.parking(r)
	if t.style == &"terminal":
		for bay: Rect2 in _terminal_frame(r).bays:
			out.append([bay.get_center() + Vector2(0, 6), 0.0])
	elif t.style == &"industrial_dock":
		var f := _dock_frame(r)
		out.append([f.pad, 0.0, DOCK_HELI])   # 4장 부두: 탈 수 있는 헬기
		out.append([f.spg, PI * 0.5, DOCK_SPG])
		out.append([f.jeep, 0.0, DOCK_JEEP])
	return out


# ── 바닥 (청크가 그린다) ───────────────────────────────────

static func draw_ground(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int) -> void:
	if StreetBuilding.owns(t.style):
		StreetBuilding.draw_ground(ci, r, t, seed)
		return
	match t.style:
		&"landmark_tower":
			if BuildingSprite.merged_lot(r):
				Namsan.draw_ground(ci, r, seed)
			else:
				_park_ground(ci, r, seed)
		&"terminal": _terminal_ground(ci, r)
		&"market": _market_ground(ci, r, seed)
		&"broadcast": _broadcast_ground(ci, r)
		&"industrial_dock": _dock_ground(ci, r, seed)
		&"sky_tower": Lotte.tower_ground(ci, r, seed)
		&"lake_park": Lotte.park_ground(ci, r, seed)
		&"namsan_summit": Namsan.summit_ground(ci, r, seed)
		_: BuildingModel._plinth(ci, r, seed)


static func _speckle(ci: CanvasItem, r: Rect2, seed: int, n: int, a: Color, b: Color, size := 4.0) -> void:
	for k in n:
		var at := r.position + r.size * Vector2(StreetBuilding._h(seed, k + 500), StreetBuilding._h(seed + 7919, k * 31 + 501))   # hash01은 x·y가 한 줄로 늘어선다
		ci.draw_rect(Rect2(at, Vector2(size, size * 0.6)), a if k % 2 == 0 else b)


static func _park_ground(ci: CanvasItem, r: Rect2, seed: int) -> void:
	var c := tower_center(r)
	var pc := pavilion_center(r)
	ci.draw_rect(r, Color("4a7336"))
	_speckle(ci, r, seed, 160, Color("3f6630"), Color("5a8443"), 5.0)
	# 바위 비탈 (숲 사이 낮은 바위)
	for k in 7:
		var at := r.position + Vector2(20, 20) + (r.size - Vector2(80, 80)) * Vector2(BuildingModel.hash01(seed, k + 200), BuildingModel.hash01(seed, k + 220))
		if at.distance_to(c) < 170.0 or at.distance_to(pc) < 70.0:
			continue
		BuildingModel.low_box(ci, Rect2(at, Vector2(26 + k % 3 * 8, 18)), 7.0, Color("8d8d86"))
		BuildingModel.low_box(ci, Rect2(at + Vector2(8, 6), Vector2(14, 10)), 11.0, Color("a19f96"))
	# 돌계단 길: 남쪽·동쪽 부지 끝에서 광장까지, 광장에서 팔각정까지
	var stone := Color("b9b2a2")
	var south := Rect2(c.x - 16.0, c.y, 32.0, r.end.y - c.y)
	var east := Rect2(c.x, c.y - 16.0, r.end.x - c.x, 32.0)
	var west := Rect2(pc.x, pc.y - 13.0, c.x - pc.x, 26.0)
	for path in [south, east, west]:
		ci.draw_rect(path, stone)
	var y := c.y + 110.0
	while y < r.end.y:
		ci.draw_line(Vector2(south.position.x, y), Vector2(south.end.x, y), Color("8f887a"), 2.0)
		y += 9.0
	var x := c.x + 110.0
	while x < r.end.x:
		ci.draw_line(Vector2(x, east.position.y), Vector2(x, east.end.y), Color("8f887a"), 2.0)
		x += 9.0
	# 길가 나무 난간
	for edge in [[Vector2(south.position.x - 3, c.y + 110), Vector2(south.position.x - 3, r.end.y)],
			[Vector2(south.end.x + 3, c.y + 110), Vector2(south.end.x + 3, r.end.y)],
			[Vector2(c.x + 110, east.position.y - 3), Vector2(r.end.x, east.position.y - 3)],
			[Vector2(c.x + 110, east.end.y + 3), Vector2(r.end.x, east.end.y + 3)]]:
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		ci.draw_line(a + IsoView.lift(7), b + IsoView.lift(7), Color("6b4a2e"), 2.0)
		var n := int(a.distance_to(b) / 18.0)
		for i in n + 1:
			var p := a.lerp(b, float(i) / maxf(n, 1))
			ci.draw_line(p, p + IsoView.lift(8), Color("5a3d25"), 2.0)
	# 광장: 팔각 돌 마당과 둥근 줄눈
	var oct := PackedVector2Array()
	for k in 8:
		var a := TAU * (k + 0.5) / 8.0
		oct.append(c + Vector2(cos(a), sin(a)) * 112.0)
	ci.draw_colored_polygon(oct, Color("c6bfae"))
	oct.append(oct[0])
	ci.draw_polyline(oct, Color("8f887a"), 3.0)
	for rad in [60.0, 86.0]:
		ci.draw_arc(c, rad, 0.0, TAU, 40, Color("aaa392"), 1.5)
	# 꽃밭
	for k in 24:
		var a := TAU * k / 24.0
		var at := c + Vector2(cos(a), sin(a)) * 104.0
		if absf(at.x - c.x) < 24.0 or absf(at.y - c.y) < 24.0:
			continue
		ci.draw_circle(at, 3.0, [Color("e9a6bf"), Color("f2d35b"), Color("e46a5a")][k % 3])
	# 팔각정 바닥 기단
	BuildingModel.low_box(ci, Rect2(pc - Vector2(32, 32), Vector2(64, 64)), 4.0, Color("b3a58c"))


static func _hazard(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r, Color("1d1d1f"))
	var vertical := r.size.y > r.size.x
	var t := 0.0
	var n := 0
	var length := r.size.y if vertical else r.size.x
	while t < length:
		var seg := minf(8.0, length - t)
		var piece := Rect2(r.position + Vector2(0, t), Vector2(r.size.x, seg)) if vertical else Rect2(r.position + Vector2(t, 0), Vector2(seg, r.size.y))
		if n % 2 == 0:
			ci.draw_rect(piece, Color("e3b023"))
		t += 8.0
		n += 1


static func _terminal_ground(ci: CanvasItem, r: Rect2) -> void:
	var f := _terminal_frame(r)
	var area: Rect2 = f.area
	var hall: Rect2 = f.hall
	ci.draw_rect(r, Color("3a3c40"))
	ci.draw_rect(r, Color("8f918c"), false, 3.0)
	# 본관 앞 보도와 점자 블록
	var walk := Rect2(r.position.x, hall.end.y, r.size.x, 30.0)
	ci.draw_rect(walk, Color("b8b3a6"))
	var x := walk.position.x
	while x < walk.end.x:
		ci.draw_line(Vector2(x, walk.position.y), Vector2(x, walk.end.y), Color("a29d90"), 1.0)
		x += 14.0
	ci.draw_line(Vector2(walk.position.x, walk.position.y + 20.0), Vector2(walk.end.x, walk.position.y + 20.0), Color("e0b52a"), 3.0)
	# 승강장: 칸 사이 안전지대(노랑·검정)와 번호, 정차선
	var bays: Array = f.bays
	for k in bays.size():
		var bay: Rect2 = bays[k]
		ci.draw_rect(bay.grow(-4.0), Color("44464b"))
		ci.draw_line(Vector2(bay.position.x + 8.0, bay.position.y + 8.0), Vector2(bay.end.x - 8.0, bay.position.y + 8.0), Color(1, 1, 1, 0.8), 3.0)
		ci.draw_string(ThemeDB.fallback_font, Vector2(bay.position.x, bay.end.y - 4.0), "%d" % (k + 1),
			HORIZONTAL_ALIGNMENT_CENTER, bay.size.x, 22, Color(1, 1, 1, 0.55))
		if k > 0:
			var prev: Rect2 = bays[k - 1]
			var gap := Rect2(prev.end.x + 3.0, bay.position.y + 6.0, bay.position.x - prev.end.x - 6.0, bay.size.y - 6.0)
			_hazard(ci, gap)
	_hazard(ci, Rect2(area.position.x - 6.0, bays[0].position.y + 6.0, bays[0].position.x - area.position.x + 2.0, 10.0))
	_hazard(ci, Rect2(bays[2].end.x + 4.0, bays[2].position.y + 6.0, area.end.x + 6.0 - bays[2].end.x - 4.0, 10.0))


static func _market_ground(ci: CanvasItem, r: Rect2, seed: int) -> void:
	var f := _market_frame(r)
	var c: Vector2 = f.c
	var lane: float = f.lane
	ci.draw_rect(r, Color("857a6c"))
	# 보도블록 줄눈
	var x := r.position.x
	while x < r.end.x:
		ci.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color("766c5f"), 1.0)
		x += 16.0
	var y := r.position.y
	while y < r.end.y:
		ci.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color("766c5f"), 1.0)
		y += 16.0
	# 골목 가운데 배수로와 물웅덩이
	ci.draw_line(Vector2(c.x, r.position.y), Vector2(c.x, r.end.y), Color("4c4740"), 3.0)
	ci.draw_line(Vector2(r.position.x, c.y), Vector2(r.end.x, c.y), Color("4c4740"), 3.0)
	for k in 6:
		var at := Vector2(c.x + (BuildingModel.hash01(seed, k) - 0.5) * lane * 0.4, r.position.y + r.size.y * BuildingModel.hash01(seed, k + 9))
		ci.draw_circle(at, 5.0 + k % 3 * 2.0, Color(0.32, 0.38, 0.46, 0.55))
	# 가게 앞 상자 더미 (낮아서 밟고 지나간다)
	for q: Rect2 in f.quads:
		for k in 3:
			var at := Vector2(q.end.x + 2.0, q.position.y + 20.0 + k * q.size.y / 3.0)
			BuildingModel.low_box(ci, Rect2(at, Vector2(8, 10)), 5.0, [Color("c79a4a"), Color("6b9a4a"), Color("b0453a")][k])
			at = Vector2(q.position.x + 20.0 + k * q.size.x / 3.0, q.end.y + 2.0)
			BuildingModel.low_box(ci, Rect2(at, Vector2(10, 8)), 5.0, [Color("d0a24b"), Color("4f7fae"), Color("b0453a")][k])


static func _broadcast_ground(ci: CanvasItem, r: Rect2) -> void:
	var f := _broadcast_frame(r)
	var hall: Rect2 = f.hall
	var area: Rect2 = f.area
	ci.draw_rect(r, Color("9c9b93"))
	var x := r.position.x
	while x < r.end.x:
		ci.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color("8d8c84"), 1.0)
		x += 24.0
	# 정문 앞 돌길과 화단
	var path := Rect2(hall.get_center().x - 26.0, hall.end.y, 52.0, r.end.y - hall.end.y)
	ci.draw_rect(path, Color("c3beb1"))
	for side in [-1.0, 1.0]:
		var bed := Rect2(Vector2(hall.get_center().x + side * 70.0 - 30.0, hall.end.y + 18.0), Vector2(60, 22))
		BuildingModel.low_box(ci, bed, 6.0, Color("4f7a3e"))
		for k in 5:
			ci.draw_circle(bed.position + Vector2(8 + k * 11, 10) + IsoView.lift(7), 2.5, [Color("e46a5a"), Color("f2d35b")][k % 2])
	# 주차 칸
	var y := area.end.y - 120.0
	for k in 4:
		var at := Vector2(area.end.x - 140.0 + k * 34.0, y)
		ci.draw_line(at, at + Vector2(0, 60), Color(1, 1, 1, 0.75), 2.0)
	# 가로수 밑 띠 화단
	ci.draw_rect(Rect2(area.position.x, area.end.y - 18.0, area.size.x, 14.0), Color("4a6a38"))


static func _dock_ground(ci: CanvasItem, r: Rect2, seed: int) -> void:
	var f := _dock_frame(r)
	var area: Rect2 = f.area
	var cr: Rect2 = f.crane
	ci.draw_rect(r, Color("6c6d68"))
	_speckle(ci, r, seed, 40, Color(0.2, 0.2, 0.2, 0.25), Color(0.85, 0.85, 0.8, 0.12), 10.0)
	# 크레인 레일 둘
	for x in [cr.position.x + 6.0, cr.end.x - 6.0]:
		for dx in [-3.0, 3.0]:
			ci.draw_line(Vector2(x + dx, area.position.y), Vector2(x + dx, cr.end.y + 20.0), Color("3a3b3c"), 2.0)
	# 컨테이너 칸 선과 통로 노란 선
	ci.draw_rect(cr.grow(-20.0), Color(0.95, 0.85, 0.3, 0.6), false, 2.0)
	ci.draw_line(Vector2(area.position.x, cr.end.y + 12.0), Vector2(area.end.x, cr.end.y + 12.0), Color("e0b52a"), 3.0)
	ci.draw_line(Vector2(area.position.x, cr.end.y + 22.0), Vector2(area.end.x, cr.end.y + 22.0), Color("e0b52a"), 3.0)
	_dock_helipad(ci, f.pad)
	# 둘레 안전띠와 계선주(볼라드), 폐타이어 방현재
	_hazard(ci, Rect2(r.position.x, r.position.y, r.size.x, 6.0))
	_hazard(ci, Rect2(r.position.x, r.position.y, 6.0, r.size.y))
	var x := r.position.x + 30.0
	while x < r.end.x - 20.0:
		BuildingModel.low_box(ci, Rect2(x, r.position.y + 8.0, 8, 8), 6.0, Color("9b2f25"))
		ci.draw_arc(Vector2(x + 30.0, r.position.y + 2.0), 5.0, 0.0, TAU, 12, Color("1b1b1c"), 3.0)
		x += 90.0
