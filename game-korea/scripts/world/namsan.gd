class_name Namsan
## 남산: 타워 공원과 양옆 숲 블록을 합친 산 (CityMap.MERGES — 가로 3블록, Terrain.MOUNDS가 부지를 솟게 한다).
## 꼭대기 평지에 N서울타워(둥근 탑신·전망대 셋·송신탑, 밤에 탑신 조명)·팔각정·봉수대·사랑의 자물쇠 난간과 케이블카 승강장,
## 남동쪽 입구에서 꼭대기까지 굽이진 남산 순환로(차가 오른다 — 꼭대기에 순환 마을버스가 서 있다, 길가 가로등),
## 서쪽 기슭 승강장에서 꼭대기 승강장까지 케이블카(Namsan.Cable — 두 칸이 엇갈려 오르내린다, 그림만),
## 서·북·동에서 오르는 흙 등산로, 나머지는 숲과 바위. 모든 자리는 부지 사각형에서 계산한다 (RNG 없이 — 늘 같은 산).

const FOREST := preload("res://data/buildings/forest.tres")
## 꼭대기 평지: 산 부지 안의 작은 부지 (Terrain.MOUNDS의 평지 반폭과 같다 — 평평해서 통째 그림을 붙인다, lot_300x168)
const SUMMIT := preload("res://data/buildings/landmarks/namsan_summit.tres")
const SUMMIT_HALF := Vector2(150, 84)
const VILLAGE_BUS := "res://data/vehicles/bus_village.tres"
## 지붕 이름: 벽 없이 여기서 그린다 (BuildingView._walls는 BARE를 건너뛴다)
const ROOFS: Array[StringName] = [&"lock_fence", &"tower_glow", &"cable_pylon"]
const BARE: Array[StringName] = [&"lock_fence", &"tower_glow", &"cable_pylon"]
## 불빛 조각에서 빛나는 것
const GLOWS: Array[StringName] = [&"tower_glow"]
const FLOOR := Color("2f4228")
const FLOOR_DARK := Color("27391f")
const FLOOR_LIGHT := Color("3b5230")
const STONE := Color("c9c2b2")
const STONE_LINE := Color("aaa395")
const ASPHALT := Color("3b3d42")
const TRAIL := Color("8a7253")
const ROAD_W := 40.0          ## 순환로 폭 (월드 px)
const LOCK_COLORS := [Color("e8413a"), Color("f2c230"), Color("3f8fd8"), Color("ef7fb1"), Color("6cc070"), Color("f08a2c"), Color("b06ad8")]


# ── 자리 ──────────────────────────────────────────────────

## 꼭대기 평지 가운데(c)에서 본 자리들. 평지는 Terrain.MOUNDS의 반폭(±150, ±84)
static func frame(r: Rect2) -> Dictionary:
	var c := r.get_center()
	var beacons: Array[Vector2] = []
	for k in 5:
		beacons.append(c + Vector2(-70.0 + k * 12.0, 70.0))
	return {
		"c": c,
		"tower": c + Vector2(0, -20),
		"ring": Rect2(c + Vector2(-82, -78), Vector2(164, 130)),          # 꼭대기 산책 고리 (보행자)
		"top_station": Rect2(c + Vector2(-148, -80), Vector2(44, 32)),
		"base_station": Rect2(Vector2(r.position.x + 36.0, c.y - 64.0), Vector2(64, 40)),
		"pavilion": c + Vector2(-124, 38),
		"beacons": beacons,
		"bus": c + Vector2(112, -34),
	}


## 남산 순환로: 남동쪽 인도에서 들어와 남쪽 비탈을 두 번 꺾어 꼭대기 평지 동쪽까지 (월드 점, 12px 간격)
static func road(r: Rect2) -> PackedVector2Array:
	var ctrl := PackedVector2Array()
	for uv in [Vector2(0.93, 1.06), Vector2(0.93, 1.0), Vector2(0.88, 0.80), Vector2(0.78, 0.66), Vector2(0.68, 0.76),
			Vector2(0.60, 0.62), Vector2(0.565, 0.53)]:
		ctrl.append(r.position + r.size * uv)
	return _smooth(ctrl, 12.0)


## 흙 등산로 셋 (서쪽 케이블카 승강장 옆 · 북쪽 · 동쪽에서 꼭대기로)
static func trails(r: Rect2) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for line in [
			[Vector2(0.055, 0.62), Vector2(0.16, 0.66), Vector2(0.25, 0.42), Vector2(0.34, 0.62), Vector2(0.40, 0.44), Vector2(0.45, 0.50)],
			[Vector2(0.40, -0.02), Vector2(0.36, 0.14), Vector2(0.44, 0.22), Vector2(0.41, 0.33), Vector2(0.46, 0.38)],
			[Vector2(1.01, 0.30), Vector2(0.86, 0.26), Vector2(0.76, 0.40), Vector2(0.66, 0.30), Vector2(0.575, 0.36)]]:
		var ctrl := PackedVector2Array()
		for uv: Vector2 in line:
			ctrl.append(r.position + r.size * uv)
		out.append(_smooth(ctrl, 10.0))
	return out


## 꺾은선을 캣멀롬 곡선으로 다듬어 step 간격 점으로
static func _smooth(ctrl: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in ctrl.size() - 1:
		var p0 := ctrl[maxi(k - 1, 0)]
		var p1 := ctrl[k]
		var p2 := ctrl[k + 1]
		var p3 := ctrl[mini(k + 2, ctrl.size() - 1)]
		var n := maxi(2, ceili(p1.distance_to(p2) / step))
		for i in n:
			var t := float(i) / n
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(ctrl[ctrl.size() - 1])
	return out


static func _distance(line: PackedVector2Array, p: Vector2) -> float:
	var d := INF
	for k in line.size() - 1:
		d = minf(d, p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, line[k], line[k + 1])))
	return sqrt(d)


## 꼭대기 평지 둘레 (부드러운 둥근 사각형, 바닥 그림·나무 비우기)
static func _plaza(c: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := 64
	for k in n:
		var a := TAU * k / n
		var d := Vector2(cos(a), sin(a))
		# 초타원(지수 4): 가로 160 · 세로 92
		var s := pow(pow(absf(d.x) / 160.0, 4.0) + pow(absf(d.y) / 92.0, 4.0), -0.25)
		out.append(c + d * s)
	return out


# ── 덩어리 ────────────────────────────────────────────────

## 꼭대기 평지 부지 (산 부지 가운데)
static func summit_rect(r: Rect2) -> Rect2:
	return Rect2(r.get_center() - SUMMIT_HALF, SUMMIT_HALF * 2.0)


static func build(out: Array[BuildingModel.Piece], r: Rect2, seed: int) -> void:
	var f := frame(r)
	var c: Vector2 = f.c
	# 꼭대기 건물들은 따로 짓는다 (통째 그림 NAMSAN_SUMMIT_lot_300x168이 있으면 붙는다)
	var summit := BuildingModel.build(summit_rect(r), SUMMIT, seed, 0.0)
	for p in summit:
		if p.roof == &"tower_glow":
			p.sprite = null   # 탑신 밤 조명은 그림이 있어도 코드로 (불빛 조각만 그린다)
	out.append_array(summit)
	# 기슭 케이블카 승강장
	_station(out, f.base_station, seed)
	# 케이블 철탑 둘 (볼록한 산을 넘게 줄을 받친다)
	for at in pylons(r):
		LandmarkBuilding.box(out, Rect2(at - Vector2(7, 7), Vector2(14, 14)), 0, PYLON_H, Color("7f878d"), &"none", &"cable_pylon")
	# 순환로 가로등 (길 바깥쪽, 150px마다)
	var rd := road(r)
	var walked := 0.0
	var next := 70.0
	for k in range(1, rd.size()):
		walked += rd[k].distance_to(rd[k - 1])
		if walked >= next and not _in_plaza(c, rd[k], 1.0):
			var along := (rd[k] - rd[k - 1]).normalized()
			StreetBuilding._lamp(out, rd[k] + Vector2(along.y, -along.x) * (ROAD_W * 0.5 + 8.0), 40.0)
			next += 150.0
	_forest(out, r, f, seed)


## 꼭대기 평지 sr의 건물: N서울타워·팔각정·봉수대·꼭대기 승강장·자물쇠 난간·가로등·벤치 (자리는 frame — 가운데 기준)
static func build_summit(out: Array[BuildingModel.Piece], sr: Rect2, seed: int) -> void:
	var f := frame(sr)
	var c: Vector2 = f.c
	_tower(out, f.tower, seed)
	# 팔각정 (기둥만 막는다)
	var pc: Vector2 = f.pavilion
	var pav := LandmarkBuilding.box(out, Rect2(pc - Vector2(22, 22), Vector2(44, 44)), 0, 24, Color("8b2b22"), &"none", &"pavilion")
	pav.roof_color = Color("4b5157")
	pav.accent = Color("3f7a5a")
	pav.rise = 15.0
	pav.eave = 10.0
	# 봉수대 다섯: 둥근 돌 굴뚝
	for at: Vector2 in f.beacons:
		var b := BuildingModel._prism(BuildingModel.ngon(at, Vector2(6, 6), 8, 0.2), 0, 18, Color("a19b8d"), &"flat", Color("3d3a36"), &"none", seed)
		out.append(b)
	_station(out, f.top_station, seed)
	# 사랑의 자물쇠 난간: 평지 남쪽 끝과 타워 뒤
	_fence(out, c + Vector2(-20, 82), c + Vector2(140, 82))
	_fence(out, c + Vector2(-60, -96), c + Vector2(70, -96))
	# 평지 가로등과 벤치
	for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		StreetBuilding._lamp(out, c + Vector2(0, -12) + d * Vector2(106, 76), 40.0)
	for x in [-40.0, 40.0]:
		LandmarkBuilding.box(out, Rect2(c + Vector2(x - 11, 60), Vector2(22, 7)), 0, 6, LandmarkBuilding.WOOD)


## 케이블카 승강장 하나와 옥상 바퀴집 (줄이 감기는 곳 — 줄 끝 높이 = 승강장 + WHEEL_H)
static func _station(out: Array[BuildingModel.Piece], rect: Rect2, seed: int) -> void:
	var st := LandmarkBuilding.box(out, rect, 0, STATION_H, Color("e1ddd2"), &"punched")
	st.deco = [&"entrance", &"name"]
	st.text = "남산 케이블카"
	st.roof_color = Color("7d8a91")
	st.accent = Color("c8372c")
	st.on_top.append(BuildingModel._box(Rect2(rect.get_center() - Vector2(12, 10), Vector2(24, 20)), STATION_H, STATION_H + WHEEL_H,
		Color("c8372c"), &"flat", Color("8e2a22"), &"none", seed))


## N서울타워: 둥근 로비 위 가는 탑신, 전망대 셋, 흰 뚜껑, 빨강·흰 송신탑. 탑신에 밤 조명(불빛 조각만 그린다)
static func _tower(out: Array[BuildingModel.Piece], t: Vector2, seed: int) -> void:
	var lobby := BuildingModel._prism(BuildingModel.ngon(t, Vector2(44, 44), 16, 0.1), 0, 26, Color("d8d4c6"), &"flat", Color("b9b3a2"), &"glass", seed)
	lobby.glass_tint = Color("3c5868")
	lobby.floor_height = 13
	lobby.deco = [&"entrance"]
	out.append(lobby)
	var ring := BuildingModel._prism(BuildingModel.ngon(t, Vector2(34, 34), 16, 0.1), 26, 34, Color("ece8dc"), &"flat", Color("cfc9b8"), &"none", seed + 1)
	lobby.on_top.append(ring)
	var shaft := BuildingModel._prism(BuildingModel.ngon(t, Vector2(12, 12), 12, 0.0), 34, 230, Color("eeece4"), &"flat", Color("d9d5c8"), &"none", seed + 2)
	ring.on_top.append(shaft)
	# 탑신 밤 조명: 얹지 않고 따로 세운다 (통째 그림이 붙어도 이것만 코드로 그리게)
	var lights := BuildingModel._box(Rect2(t - Vector2(12, 12), Vector2(24, 24)), 34, 230, Color.WHITE, &"tower_glow", Color.WHITE, &"none", seed)
	lights.blocks_ground = false
	out.append(lights)
	var under := shaft
	var decks := [[36.0, 230.0, 244.0, Color("cfcac0"), true], [42.0, 244.0, 260.0, Color("e4e0d4"), true], [34.0, 260.0, 272.0, Color("d6d1c4"), true],
		[18.0, 272.0, 288.0, Color("f0eee8"), false]]
	for k in decks.size():
		var d: Array = decks[k]
		var deck := BuildingModel._prism(BuildingModel.ngon(t, Vector2(d[0], d[0]), 16, 0.1), d[1], d[2], d[3], &"flat", (d[3] as Color).darkened(0.12),
			&"glass" if d[4] else &"none", seed + 3 + k)
		deck.glass_tint = Color("2c4a5c")
		deck.floor_height = d[2] - d[1]
		under.on_top.append(deck)
		under = deck
	under.on_top.append(BuildingModel._box(Rect2(t - Vector2(6, 6), Vector2(12, 12)), 288, 410, Color("c33a2c"), &"antenna", Color("ff3b2a"), &"none", seed))


## 사랑의 자물쇠 난간 a → b (짧은 토막 — 긴 덩어리는 그리는 순서가 꼬인다)
static func _fence(out: Array[BuildingModel.Piece], a: Vector2, b: Vector2) -> void:
	var n := maxi(1, ceili(a.distance_to(b) / 32.0))
	for k in n:
		var rect := Rect2(a.lerp(b, float(k) / n), Vector2.ZERO).expand(a.lerp(b, float(k + 1) / n)).grow(2.0)
		var p := LandmarkBuilding.box(out, rect, 0, 10, Color("6d7277"), &"none", &"lock_fence")
		p.seed = k * 7 + int(a.x)


static func _in_plaza(c: Vector2, p: Vector2, grow: float) -> bool:
	var d := (p - c).abs()
	return pow(d.x / (160.0 * grow), 4.0) + pow(d.y / (92.0 * grow), 4.0) < 1.0


## 숲: 길·등산로·평지·승강장을 비우고 부지 전체에 나무, 사이사이 바위. 벚나무가 조금 섞인다
static func _forest(out: Array[BuildingModel.Piece], r: Rect2, f: Dictionary, seed: int) -> void:
	var c: Vector2 = f.c
	var rd := road(r)
	var paths := trails(r)
	var stations: Array[Rect2] = [(f.top_station as Rect2).grow(22.0), (f.base_station as Rect2).grow(26.0)]
	var cable_a := (f.base_station as Rect2).get_center()
	var cable_b := (f.top_station as Rect2).get_center()
	var step := 44.0
	var k := 0
	var y := r.position.y + 14.0
	while y < r.end.y - 8.0:
		var x := r.position.x + 12.0 + fmod(y * 0.37, step * 0.5)
		while x < r.end.x - 8.0:
			var at := Vector2(x, y) + (Vector2(BuildingModel.hash01(seed, k * 3), StreetBuilding._h(seed, k * 3 + 1)) - Vector2(0.5, 0.5)) * step * 0.7
			at = at.clamp(r.position + Vector2(10, 10), r.end - Vector2(10, 10))
			k += 1
			x += step
			if _in_plaza(c, at, 1.12) or _distance(rd, at) < ROAD_W * 0.5 + 16.0:
				continue
			# 기슭은 듬성듬성 (풀밭·바위가 보여 산자락이 읽히게)
			var edge := minf(minf(at.x - r.position.x, r.end.x - at.x), minf(at.y - r.position.y, r.end.y - at.y))
			if edge < 60.0 and StreetBuilding._h(seed + 29, k) < 0.55:
				continue
			var near_path := false
			for line in paths:
				if _distance(line, at) < 18.0:
					near_path = true
					break
			for st in stations:
				near_path = near_path or st.has_point(at)
			# 케이블 밑은 낮은 나무만 (줄과 칸이 잘 보이게)
			var under_cable := Geometry2D.get_closest_point_to_segment(at, cable_a, cable_b).distance_to(at) < 22.0
			if near_path:
				continue
			var s := (0.8 if under_cable else 1.15) + BuildingModel.hash01(seed, k * 3 + 2) * 0.6
			var tree := BuildingModel._tree(at, seed + k, s)
			var roll := StreetBuilding._h(seed + 11, k)
			tree.roof_color = Color("e6a3c4") if roll < 0.035 else FOREST.roof_colors[posmod(seed + k, FOREST.roof_colors.size())]
			out.append(tree)
		y += step * 0.86
	for n in 9:
		var at := r.position + r.size * Vector2(0.06 + StreetBuilding._h(seed, n + 900) * 0.88, 0.1 + StreetBuilding._h(seed + 5, n + 950) * 0.8)
		if _in_plaza(c, at, 1.15) or _distance(rd, at) < 40.0:
			continue
		out.append(BuildingModel._box(Rect2(at - Vector2(10, 7), Vector2(20, 14)), 0.0, 8.0, Color("7c776c"), &"flat", Color("948e82"), &"none", seed + n))


# ── 바닥 (청크가 그린다 — 셰이더가 산 높이만큼 올린다. 큰 도형은 꼭짓점을 촘촘히) ──

static func draw_ground(ci: CanvasItem, r: Rect2, seed: int) -> void:
	var f := frame(r)
	var c: Vector2 = f.c
	Terrain.rect(ci, r, FLOOR)
	# 기슭 풀밭 띠 (나무가 듬성한 곳)
	var grass := Color("4d6a36")
	for band in [Rect2(r.position, Vector2(r.size.x, 50)), Rect2(r.position.x, r.end.y - 56, r.size.x, 56),
			Rect2(r.position, Vector2(50, r.size.y)), Rect2(r.end.x - 50, r.position.y, 50, r.size.y)]:
		Terrain.rect(ci, band, grass)
	for k in 260:
		var at := r.position + r.size * Vector2(StreetBuilding._h(seed, k + 40), StreetBuilding._h(seed + 3, k * 7 + 41))
		ci.draw_rect(Rect2(at, Vector2(9, 5)), FLOOR_DARK if k % 2 == 0 else FLOOR_LIGHT)
	# 등산로: 흙길과 나무 계단 턱
	for line in trails(r):
		ci.draw_polyline(line, TRAIL.darkened(0.25), 11.0)
		ci.draw_polyline(line, TRAIL, 8.0)
		for k in range(2, line.size() - 1, 3):
			var along := (line[k + 1] - line[k - 1]).normalized()
			var side := Vector2(-along.y, along.x) * 4.5
			ci.draw_line(line[k] - side, line[k] + side, Color("5e4a35"), 1.5)
	# 순환로: 아스팔트, 가장자리 흰 선, 가운데 노란 겹선
	var rd := road(r)
	ci.draw_polyline(rd, Color("5d5a52"), ROAD_W + 8.0)   # 길 어깨 (자갈)
	ci.draw_polyline(rd, ASPHALT, ROAD_W)
	for side in [-1.0, 1.0]:
		ci.draw_polyline(_offset(rd, side * (ROAD_W * 0.5 - 3.0)), Color(0.85, 0.85, 0.82, 0.8), 1.5)
	for side in [-1.0, 1.0]:
		ci.draw_polyline(_offset(rd, side * 1.6), Color(0.95, 0.75, 0.15, 0.85), 1.2)
	# 꼭대기 평지: 돌 포장, 줄눈, 테두리
	var plaza := _plaza(c)
	ci.draw_colored_polygon(plaza, STONE)
	var y := c.y - 84.0
	while y < c.y + 88.0:
		var span := _row(c, y)
		if span.y > span.x:
			var pts := PackedVector2Array()
			var x := span.x
			while x < span.y:
				pts.append(Vector2(x, y))
				x += 24.0
			pts.append(Vector2(span.y, y))
			ci.draw_polyline(pts, STONE_LINE, 1.0)
		y += 16.0
	var rim := plaza.duplicate()
	rim.append(plaza[0])
	ci.draw_polyline(rim, Color("8f897c"), 3.0)
	# 꼭대기 부지 바닥 (통째 그림이 있으면 그림, 없으면 summit_ground)
	BuildingModel.draw_ground(ci, summit_rect(r), SUMMIT, seed)
	# 기슭 승강장 앞 마당
	var base: Rect2 = f.base_station
	Terrain.rect(ci, base.grow(16.0), Color("b9b2a3"))


## 꼭대기 평지 바닥 (코드 그림): 타워 둘레 둥근 마당, 팔각정·봉수대 흙 마당, 버스 정류장
static func summit_ground(ci: CanvasItem, sr: Rect2, _seed: int) -> void:
	var f := frame(sr)
	ci.draw_rect(sr, STONE)
	var y := sr.position.y + 16.0
	while y < sr.end.y:
		ci.draw_line(Vector2(sr.position.x, y), Vector2(sr.end.x, y), STONE_LINE, 1.0)
		y += 16.0
	var t: Vector2 = f.tower
	ci.draw_colored_polygon(BuildingModel.ngon(t, Vector2(58, 58), 24), Color("dcd6c8"))
	ci.draw_polyline(_closed(BuildingModel.ngon(t, Vector2(58, 58), 24)), Color("a49d8f"), 2.0)
	ci.draw_colored_polygon(BuildingModel.ngon(f.pavilion, Vector2(30, 30), 8, PI / 8.0), Color("b9a98a"))
	var beacons: Array[Vector2] = f.beacons
	ci.draw_rect(Rect2(beacons[0] - Vector2(12, 12), Vector2(beacons[4].x - beacons[0].x + 24.0, 24)), Color("b4a587"))
	# 버스 정류장 (순환로 끝): 노란 줄
	var bus: Vector2 = f.bus
	ci.draw_rect(Rect2(bus - Vector2(18, 56), Vector2(36, 112)), Color("8f8b82"))
	ci.draw_rect(Rect2(bus - Vector2(18, 56), Vector2(36, 112)), Color(0.95, 0.75, 0.15, 0.9), false, 2.0)


## 꼭대기 평지를 가로줄 y로 자른 x 구간 (초타원 안)
static func _row(c: Vector2, y: float) -> Vector2:
	var dy := absf(y - c.y) / 92.0
	if dy >= 1.0:
		return Vector2(1, 0)
	var w := 160.0 * pow(1.0 - pow(dy, 4.0), 0.25) - 4.0
	return Vector2(c.x - w, c.x + w)


static func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	out.append(poly[0])
	return out


## 꺾은선을 옆으로 d만큼 민 선
static func _offset(line: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in line.size():
		var along := (line[mini(k + 1, line.size() - 1)] - line[maxi(k - 1, 0)]).normalized()
		out.append(line[k] + Vector2(-along.y, along.x) * d)
	return out


## 보행자 길: 꼭대기 산책 고리
static func walk_loops(r: Rect2) -> Array[PackedVector2Array]:
	var ring: Rect2 = frame(r).ring
	return [LandmarkBuilding._ring(ring)]


## 꼭대기 정류장에 선 순환 마을버스 (앞이 북쪽)
static func parking(r: Rect2) -> Array:
	return [[frame(r).bus, 0.0, VILLAGE_BUS]]


# ── 지붕·불빛 (BuildingView 안에서) ─────────────────────────

static func roof(v: BuildingView, p: BuildingModel.Piece) -> void:
	match p.roof:
		&"lock_fence": _lock_fence(v, p)
		&"tower_glow": pass   # 낮에는 탑신 그대로 (밤 조명만)
		&"cable_pylon": _pylon(v, p)


## 케이블 철탑: 네 다리가 위로 좁아지는 회색 철골, X 버팀, 꼭대기 가로 팔과 줄 바퀴
static func _pylon(v: BuildingView, p: BuildingModel.Piece) -> void:
	var r := p.rect
	var c := r.get_center()
	var legs := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var steel := p.wall
	var prev: Array = []
	var n := 6
	for k in n + 1:
		var f := float(k) / n
		var ring: Array = []
		for q: Vector2 in legs:
			ring.append(c + (q - c) * lerpf(1.0, 0.35, f) + IsoView.lift(lerpf(p.h0, p.h1, f)))
		if k > 0:
			for i in [0, 1, 3, 2]:
				v.draw_line(prev[i], ring[i], steel.darkened(0.25 if i != 2 else 0.0), 1.8 if i == 2 else 1.3)
			for pair in [[3, 2], [2, 1]]:
				v.draw_line(prev[pair[0]], ring[pair[1]], steel.darkened(0.1), 0.9)
				v.draw_line(prev[pair[1]], ring[pair[0]], steel.darkened(0.1), 0.9)
		prev = ring
	var top := c + IsoView.lift(p.h1)
	var arm := Vector2(0, 1) * 10.0   # 두 줄 사이 (CABLE_SIDE 쪽)
	v.draw_line(top - arm * 0.6, top + CABLE_SIDE + arm * 0.6, steel.darkened(0.3), 3.0)
	for at in [top, top + CABLE_SIDE]:
		v.draw_circle(at, 2.6, Color("2b2e31"))
		v.draw_circle(at, 1.2, Color("c9cdd0"))


## 난간: 짧은 기둥, 위·가운데 쇠줄, 줄마다 알록달록 자물쇠 점
static func _lock_fence(v: BuildingView, p: BuildingModel.Piece) -> void:
	var r := p.rect
	var along_x := r.size.x >= r.size.y
	var a := Vector2(r.position.x, r.get_center().y) if along_x else Vector2(r.get_center().x, r.position.y)
	var b := Vector2(r.end.x, r.get_center().y) if along_x else Vector2(r.get_center().x, r.end.y)
	var lift := func(w: Vector2, h: float) -> Vector2: return w + IsoView.lift(p.h0 + h)
	for f in [0.0, 1.0]:
		v.draw_line(lift.call(a.lerp(b, f), 0.0), lift.call(a.lerp(b, f), 10.0), p.wall.darkened(0.2), 1.6)
	v.draw_line(lift.call(a, 10.0), lift.call(b, 10.0), p.wall.lightened(0.2), 1.4)
	v.draw_line(lift.call(a, 5.5), lift.call(b, 5.5), p.wall, 1.0)
	var n := int(a.distance_to(b) / 2.2)
	for k in n:
		var f := (k + 0.5) / n
		var h := 9.0 if k % 2 == 0 else 4.5
		var col: Color = LOCK_COLORS[posmod(p.seed * 13 + k * 7 + k * k, LOCK_COLORS.size())]
		v.draw_rect(Rect2(lift.call(a.lerp(b, f), h) - Vector2(0.9, 0), Vector2(1.8, 2.2)), col)


## 밤 조명: 탑신 앞면에 아래는 파랑, 위로 갈수록 보라·분홍으로 번지는 빛 띠와 전망대 둘레 빛
static func glow(v: BuildingView, p: BuildingModel.Piece) -> void:
	if p.roof != &"tower_glow":
		return
	var c := p.rect.get_center()
	var n := 12
	for k in n:
		var f0 := float(k) / n
		var f1 := float(k + 1) / n
		var col := Color("3d7bff").lerp(Color("ff5fb8"), f0)
		var a := c + IsoView.lift(lerpf(p.h0, p.h1, f0))
		var b := c + IsoView.lift(lerpf(p.h0, p.h1, f1))
		var w := Vector2(13, 0)
		var uv := Vector2(2.0, 2.0)
		v.draw_primitive(PackedVector2Array([a - w + Vector2(0, 4), a + w + Vector2(0, 4), b + w + Vector2(0, 4), b - w + Vector2(0, 4)]),
			PackedColorArray([Color(col, 0.55)]), PackedVector2Array([uv, uv, uv, uv]))
		v.draw_primitive(PackedVector2Array([a - w * 2.4, a + w * 2.4, b + w * 2.4, b - w * 2.4]),
			PackedColorArray([Color(col, 0.1)]), PackedVector2Array([uv, uv, uv, uv]))


# ── 케이블카 (도시에 붙는 노드) ────────────────────────────

const CABLE_SAG := 18.0       ## 줄이 가운데에서 처지는 높이 (화면 px)
const STATION_H := 34.0       ## 승강장 높이
const WHEEL_H := 22.0         ## 승강장 옥상 바퀴집 (줄이 여기서 나간다)
const PYLON_H := 86.0         ## 케이블 철탑 높이 (땅에서 줄까지)
const PYLON_AT := [0.3, 0.64] ## 철탑 자리 (기슭 승강장 → 꼭대기 승강장 사이 비율)
const CABLE_HANG := 22.0      ## 줄에서 칸 지붕까지
const CABLE_PERIOD := 70.0    ## 한 칸이 오르고 내려오는 시간 (초) — 양끝에서 잠깐 선다
const CABLE_SEGMENTS := 10
const CABLE_SIDE := Vector2(0, 14)   ## 두 줄 사이 (월드 px) — 두 칸이 줄 하나씩 타고 가운데에서 엇갈린다

## 남산 부지 r에 케이블카(줄 토막과 두 칸)를 붙인다 (City._make_views)
static func attach(parent: Node, r: Rect2) -> void:
	var f := frame(r)
	var base: Rect2 = f.base_station
	var top: Rect2 = f.top_station
	var ends := anchors(r)
	for k in CABLE_SEGMENTS:
		var seg := CableRope.new()
		seg.ends = ends
		seg.f0 = float(k) / CABLE_SEGMENTS
		seg.f1 = float(k + 1) / CABLE_SEGMENTS
		parent.add_child(seg)
	for k in 2:
		var cab := Cabin.new()
		cab.ends = ends
		cab.phase = 0.2
		cab.down = k == 1
		cab.color = [Color("d23b30"), Color("f0b62a")][k]
		parent.add_child(cab)


## 케이블 철탑 자리 (월드)
static func pylons(r: Rect2) -> Array[Vector2]:
	var ends := anchors(r)
	return [ends[1][0], ends[2][0]]


## 줄이 걸리는 곳 [월드 자리, 높이를 잴 사각형, 그 위 높이]: 기슭 승강장 바퀴집 → 철탑 둘 → 꼭대기 승강장 바퀴집
static func anchors(r: Rect2) -> Array:
	var f := frame(r)
	var base: Rect2 = f.base_station
	var top: Rect2 = f.top_station
	var a := base.get_center()
	var b := top.get_center()
	var out := [[a, base, STATION_H + WHEEL_H - 4.0]]
	for t: float in PYLON_AT:
		var at := a.lerp(b, t)
		out.append([at, Rect2(at - Vector2(7, 7), Vector2(14, 14)), PYLON_H])
	out.append([b, top, STATION_H + WHEEL_H - 4.0])
	return out


## 줄 위 f(0 기슭 ~ 1 꼭대기, 바닥 거리 비율)의 (월드 자리, 높이). 걸린 곳 사이마다 조금 처진다
static func cable_at(ends: Array, f: float) -> Array:
	var total := 0.0
	for k in ends.size() - 1:
		total += (ends[k][0] as Vector2).distance_to(ends[k + 1][0])
	var want := clampf(f, 0.0, 1.0) * total
	for k in ends.size() - 1:
		var p: Vector2 = ends[k][0]
		var q: Vector2 = ends[k + 1][0]
		var span := p.distance_to(q)
		if want <= span or k == ends.size() - 2:
			var t := clampf(want / span, 0.0, 1.0)
			var hp: float = Terrain.max_height(ends[k][1]) + ends[k][2]
			var hq: float = Terrain.max_height(ends[k + 1][1]) + ends[k + 1][2]
			return [p.lerp(q, t), lerpf(hp, hq, t) - CABLE_SAG * span / total * 4.0 * t * (1.0 - t)]
		want -= span
	return [ends[0][0], 0.0]


## 줄 한 토막 (토막마다 깊이 정렬 — 앞 나무가 줄을 가린다)
class CableRope extends Node2D:
	var ends: Array
	var f0 := 0.0
	var f1 := 1.0
	var _iso := true

	func _ready() -> void:
		z_as_relative = false
		var mid: Array = Namsan.cable_at(ends, (f0 + f1) * 0.5)
		z_index = IsoView.z_of(mid[0]) + 2

	func _process(_delta: float) -> void:
		if _iso != IsoView.enabled:
			_iso = IsoView.enabled
			visible = _iso
			queue_redraw()

	func _draw() -> void:
		if not IsoView.enabled:
			return
		var pts := PackedVector2Array()
		var pts2 := PackedVector2Array()
		for k in 7:
			var at: Array = Namsan.cable_at(ends, lerpf(f0, f1, k / 6.0))
			pts.append(at[0] + IsoView.lift(at[1]))
			pts2.append(at[0] + Namsan.CABLE_SIDE + IsoView.lift(at[1]))
		draw_polyline(pts, Color("23262a"), 2.0)
		draw_polyline(pts2, Color("23262a"), 2.0)
		draw_polyline(pts, Color(0.75, 0.78, 0.8, 0.35), 0.8)
		draw_polyline(pts2, Color(0.75, 0.78, 0.8, 0.35), 0.8)


## 케이블카 한 칸: 시간에 따라 줄을 따라 오르내리고(다른 칸과 반 박자 엇갈린다), 밤에는 창이 밝다
class Cabin extends Node2D:
	var ends: Array
	var phase := 0.0
	var down := false          ## 다른 줄: 꼭대기에서 출발한다
	var color := Color.RED
	var _t := 0.0
	var _h := 0.0
	var _glow: Node2D

	func _ready() -> void:
		z_as_relative = false
		_glow = Node2D.new()
		_glow.material = BuildingView.light_material()
		_glow.draw.connect(_draw_glow)
		add_child(_glow)
		_t = phase * Namsan.CABLE_PERIOD

	func _process(delta: float) -> void:
		visible = IsoView.enabled
		if not visible:
			return
		_t += delta
		var s := fposmod(_t / Namsan.CABLE_PERIOD, 1.0)
		var tri := 1.0 - absf(s * 2.0 - 1.0)   # 0 → 1 → 0
		var f := smoothstep(0.08, 0.92, tri)
		if down:
			f = 1.0 - f
		var at: Array = Namsan.cable_at(ends, f)
		position = at[0] + (Namsan.CABLE_SIDE if down else Vector2.ZERO)
		_h = at[1]
		z_index = IsoView.z_of(position) + 3
		queue_redraw()
		_glow.queue_redraw()

	func _draw() -> void:
		var top := IsoView.lift(_h)
		draw_line(top, top + Vector2(0, Namsan.CABLE_HANG - 4.0), Color("2c2f33"), 1.5)
		draw_circle(top, 2.2, Color("4a4f55"))
		draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, _h))
		var body := Rect2(-9, Namsan.CABLE_HANG - 4.0, 18, 15)
		draw_rect(body, color)
		draw_rect(Rect2(body.position + Vector2(0, -2), Vector2(18, 3)), color.lightened(0.3))
		draw_rect(Rect2(body.position + Vector2(2, 3), Vector2(14, 6)), Color("26323b"))
		draw_rect(Rect2(body.position + Vector2(0, 13), Vector2(18, 2)), color.darkened(0.35))
		draw_set_transform_matrix(Transform2D.IDENTITY)

	func _draw_glow() -> void:
		_glow.draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, _h))
		var win := Rect2(-7, Namsan.CABLE_HANG + 3.0, 14, 6)
		var uv := Vector2(2.0, 2.05)
		_glow.draw_primitive(PackedVector2Array([win.position, Vector2(win.end.x, win.position.y), win.end, Vector2(win.position.x, win.end.y)]),
			PackedColorArray([Color(1.0, 0.86, 0.55)]), PackedVector2Array([uv, uv, uv, uv]))
		_glow.draw_set_transform_matrix(Transform2D.IDENTITY)
