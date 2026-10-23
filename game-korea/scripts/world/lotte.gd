class_name Lotte
## 잠실 롯데 (사용자 요청으로 실제 이름 — docs/09 가칭 목록). 두 블록씩 합친 세로로 긴 부지에 선다 (CityMap.MERGES).
## 롯데월드타워: 둥근 모서리 사각 탑신을 비스듬히 돌려(ANGLE) 위로 갈수록 붓끝처럼 좁히고 꼭대기는 두 쪽으로 갈라진다.
##   북쪽에 비스듬한 롯데월드몰, 그 사이 둥근 에비뉴엘, 타워 둘레 돌린 기단, 남쪽 월드파크 광장(분수·잔디·나무).
## 롯데월드: 북쪽 끝 호텔 탑, 유리 볼트 지붕을 얹은 실내 놀이 궁(어드벤처), 남쪽 석촌호수(비스듬한 타원)와
##   다리로 잇는 매직아일랜드(성·자이로드롭·회전목마), 호수 둘레 산책길.
## 덩어리는 돌린 다각형(BuildingModel._prism)이 많다 — 축에 나란한 상자만 쓰지 않는다. 모든 자리는 부지에서 계산한다 (RNG 없이).

const GLASS := Color("b8c6cf")
const TINT := Color("7f98a8")     ## 은빛 유리 (위로 갈수록 밝다)
const TOP := 1150.0               ## 탑신 꼭대기 (화면 px) — 남산 타워·금융타워의 두 배쯤, 도시에서 가장 높다
const STEPS := 30                 ## 탑신 토막 수 (촘촘해야 곡선처럼 보인다)
const ANGLE := 0.36               ## 타워·기단을 돌린 각 (라디안)
const MALL_ANGLE := -0.2          ## 몰·에비뉴엘을 돌린 각
const PARK_ANGLE := -0.12         ## 롯데월드 호텔·놀이 궁
const LAKE_ANGLE := -0.25         ## 석촌호수
const WATER := Color("3d7896")
const WALK := Color("c39a7c")
const PAVE := Color("bdb7ab")
const PAVE_LINE := Color("a9a397")


## 부지 안 비율 자리 → 월드
static func _at(r: Rect2, u: float, v: float) -> Vector2:
	return r.position + r.size * Vector2(u, v)


## 부지 크기에 맞춘 배율 (도시의 합친 부지 520 × 1288 기준 — 도감의 블록 하나 부지에서는 줄어든다)
static func _s(r: Rect2) -> float:
	return minf(r.size.x / 520.0, r.size.y / 1288.0)


## 돌린 사각형 (반폭 half)
static func _rot_rect(c: Vector2, half: Vector2, angle: float) -> PackedVector2Array:
	return BuildingModel.rounded_square(c, half, 0.0, angle, 1)


# ── 롯데월드타워 ─────────────────────────────────────────

static func tower_frame(r: Rect2) -> Dictionary:
	var s := _s(r)
	var t := _at(r, 0.5, 0.64)
	return {
		"tower": t,
		"half": 84.0 * s,
		"podium": 112.0 * s,
		"mall": _at(r, 0.47, 0.235),
		"mall_half": Vector2(190, 165) * s,
		"avenuel": _at(r, 0.5, 0.447),
		"avenuel_r": Vector2(165, 46) * s,
		"loop": BuildingModel.rounded_square(t, Vector2.ONE * 140.0 * s, 0.0, ANGLE, 1),
		"plaza": Rect2(_at(r, 0.0, 0.78), r.size * Vector2(1.0, 0.22)),
		"fountain": _at(r, 0.5, 0.885),
	}


static func build_tower(out: Array[BuildingModel.Piece], r: Rect2, seed: int) -> void:
	var f := tower_frame(r)
	var t: Vector2 = f.tower
	var half: float = f.half
	# 기단: 타워와 같이 돌린 둥근 사각 (로비·전망대 매표소)
	var podium := BuildingModel._prism(BuildingModel.rounded_square(t, Vector2.ONE * f.podium, 26.0, ANGLE, 2), 0, 22, Color("cdc8bc"),
		&"flat", Color("8f9a8a"), &"glass", seed)
	podium.glass_tint = Color("40596a")
	podium.floor_height = 22
	podium.deco = [&"entrance"]
	out.append(podium)
	# 탑신: 아래는 곧게, 위로 갈수록 빨리 좁아지는 붓끝 모양 (토막을 차례로 얹는다)
	var under := podium
	var h := 22.0
	var step := (TOP - 70.0 - 22.0) / STEPS
	for k in STEPS:
		var u := float(k) / (STEPS - 1)
		var w := half * lerpf(1.0, 0.5, pow(u, 1.35))
		var seg := BuildingModel._prism(BuildingModel.rounded_square(t, Vector2.ONE * w, w * 0.34, ANGLE, 2), h, h + step,
			GLASS.lerp(Color("e3eaee"), u), &"flat", GLASS.darkened(0.2), &"glass", seed + k)
		seg.glass_tint = TINT.lerp(Color("c3d3dc"), u)
		seg.floor_height = 18
		under.on_top.append(seg)
		under = seg
		h += step
	# 전망대: 어두운 유리 띠
	var top_w := half * 0.5
	var deck := BuildingModel._prism(BuildingModel.rounded_square(t, Vector2.ONE * top_w, top_w * 0.34, ANGLE, 2), h, h + 22, Color("5d6f7b"),
		&"flat", Color("8a9aa4"), &"glass", seed + 40)
	deck.glass_tint = Color("2c3c48")
	deck.floor_height = 22
	under.on_top.append(deck)
	h += 22.0
	# 꼭대기 왕관: 가운데가 갈라진 두 쪽이 좁아지며 솟는다 (서쪽이 더 높다), 끝에 항공 장애등
	var ex := Vector2.from_angle(ANGLE)
	for side in [-1, 1]:
		var piece := deck
		var hh := h
		var tall := 120.0 if side < 0 else 92.0
		for k in 4:
			var taper := lerpf(1.0, 0.4, k / 3.0)
			var hw := Vector2(top_w * 0.44 * taper, top_w * taper)
			var c: Vector2 = t + ex * side * (top_w * 0.06 + hw.x)
			var cap := BuildingModel._prism(BuildingModel.rounded_square(c, hw, hw.x * 0.3, ANGLE, 1), hh, hh + tall / 4.0,
				Color("e4ebef"), &"flat", Color("b4c2ca"), &"glass", seed + 50 + k)
			cap.glass_tint = Color("b9cbd6").lerp(Color("dde7ec"), k / 3.0)
			cap.floor_height = 10
			piece.on_top.append(cap)
			piece = cap
			hh += tall / 4.0
		if side < 0:
			var tip := BuildingModel.bounds(piece.poly).get_center()
			piece.on_top.append(BuildingModel._box(Rect2(tip - Vector2(2, 2), Vector2(4, 4)), hh, hh + 26, Color("d8dde0"), &"antenna", Color("ff3b2a"), &"none", seed))
	# 롯데월드몰: 몰 본관(옥상 정원)과 그 위 한 층 물러난 유리 층
	var mall := BuildingModel._prism(_rot_rect(f.mall, f.mall_half, MALL_ANGLE), 0, 58, Color("d9d4c9"), &"flat", Color("7f9474"), &"glass", seed + 60)
	mall.glass_tint = Color("4b6878")
	mall.floor_height = 14.5
	mall.deco = [&"entrance", &"top_sign"]
	mall.text = "롯데월드몰"
	out.append(mall)
	var upper := BuildingModel._prism(_rot_rect(f.mall + Vector2(-20, -24) * _s(r), f.mall_half * Vector2(0.62, 0.55), MALL_ANGLE), 58, 76,
		Color("e5e2da"), &"flat", Color("b8c0b4"), &"glass", seed + 61)
	upper.glass_tint = Color("6d8ea0")
	mall.on_top.append(upper)
	# 에비뉴엘: 몰과 타워 사이 둥근 크림색 돌 건물
	var ave := BuildingModel._prism(BuildingModel.ngon(f.avenuel, f.avenuel_r, 18, MALL_ANGLE), 0, 46, Color("e6dccb"), &"flat", Color("c9bda6"), &"punched", seed + 62)
	ave.floor_height = 15.3
	out.append(ave)
	# 광장: 화단 나무·깃대·가로등·볼라드 (산책 고리를 비운다)
	var loop: PackedVector2Array = f.loop
	var plaza: Rect2 = f.plaza
	var k := 0
	for uv in [Vector2(0.08, 0.80), Vector2(0.92, 0.80), Vector2(0.06, 0.96), Vector2(0.94, 0.97), Vector2(0.3, 0.98), Vector2(0.7, 0.985),
			Vector2(0.92, 0.6), Vector2(0.9, 0.7), Vector2(0.08, 0.66)]:
		var at := _at(r, uv.x, uv.y)
		if Namsan._distance(_closed(loop), at) > 26.0 and r.grow(-10.0).has_point(at):
			StreetBuilding._tree(out, at, seed + k, 1.25, k % 3 == 1)
		k += 1
	for k2 in 3:
		var flag := BuildingModel._box(Rect2(_at(r, 0.36 + k2 * 0.06, 0.995) - Vector2(1.5, 8), Vector2(3, 3)), 0, 70,
			Color("d8d8d8"), &"flag", [Color("c8372c"), Color.WHITE, Color("2f5f8c")][k2])
		flag.blocks_ground = false
		out.append(flag)
	for c in loop:
		StreetBuilding._lamp(out, c + (c - (f.tower as Vector2)).normalized() * 18.0, 44.0)
	var fc: Vector2 = f.fountain
	out.append(BuildingModel._prism(BuildingModel.ngon(fc, Vector2(9, 9), 10), 0, 14, Color("b9c2c6"), &"flat", Color("8fb8cc"), &"none", seed))


static func tower_ground(ci: CanvasItem, r: Rect2, seed: int) -> void:
	var f := tower_frame(r)
	var t: Vector2 = f.tower
	ci.draw_rect(r, PAVE)
	_angled_tiles(ci, r, 34.0, ANGLE, PAVE_LINE)
	# 타워 둘레 돌린 돌 마당과 물 띠
	var yard := BuildingModel.rounded_square(t, Vector2.ONE * (f.podium + 34.0), 40.0, ANGLE, 3)
	ci.draw_colored_polygon(yard, Color("cdc8bd"))
	ci.draw_polyline(_closed(yard), Color("8f8a80"), 2.0)
	ci.draw_polyline(_closed(BuildingModel.rounded_square(t, Vector2.ONE * (f.podium + 20.0), 34.0, ANGLE, 3)), Color(0.35, 0.55, 0.7, 0.8), 5.0)
	# 남쪽 월드파크: 잔디 둘과 둥근 분수
	var plaza: Rect2 = f.plaza
	for side in [-1.0, 1.0]:
		var lawn := BuildingModel.ngon(plaza.get_center() + Vector2(side * plaza.size.x * 0.26, 0), Vector2(plaza.size.x * 0.18, plaza.size.y * 0.3), 20, side * 0.3)
		ci.draw_colored_polygon(lawn, Color("5f8a46"))
		ci.draw_polyline(_closed(lawn), Color("4e7439"), 1.5)
	var fc: Vector2 = f.fountain
	ci.draw_colored_polygon(BuildingModel.ngon(fc, Vector2(46, 46), 24), Color("9c968a"))
	ci.draw_colored_polygon(BuildingModel.ngon(fc, Vector2(40, 40), 24), WATER.lightened(0.15))
	for k in 6:
		var a := TAU * k / 6.0
		ci.draw_line(fc + Vector2.from_angle(a) * 14.0, fc + Vector2.from_angle(a) * 34.0, Color(0.85, 0.93, 0.97, 0.5), 1.5)
	# 몰 앞 보도 띠
	ci.draw_colored_polygon(_rot_rect(f.mall, (f.mall_half as Vector2) + Vector2(14, 14), MALL_ANGLE), Color("d7d2c6"))


static func tower_loops(r: Rect2) -> Array[PackedVector2Array]:
	return [tower_frame(r).loop]


# ── 롯데월드 ─────────────────────────────────────────────

static func park_frame(r: Rect2) -> Dictionary:
	var s := _s(r)
	var lake_c := _at(r, 0.5, 0.7)
	var lake_r := Vector2(200, 288) * s
	var island := lake_c + Vector2(10, -24) * s
	return {
		"hotel": _at(r, 0.5, 0.075),
		"hotel_half": Vector2(150, 34) * s,
		"hall": _at(r, 0.48, 0.28),
		"hall_half": Vector2(225, 150) * s,
		"lake_c": lake_c,
		"lake_r": lake_r,
		"lake": _lake(lake_c, lake_r),
		"island": island,
		"island_r": Vector2(104, 84) * s,
		"bridge": Rect2(Vector2(island.x - 14.0 * s, lake_c.y - lake_r.y - 20.0 * s), Vector2(28.0 * s, lake_r.y - 60.0 * s)),
		"loop": BuildingModel.ngon(lake_c, lake_r + Vector2(22, 22) * s, 28, LAKE_ANGLE),
	}


## 석촌호수 물가 (조금 일렁이는 타원)
static func _lake(c: Vector2, rad: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := 36
	for k in n:
		var a := TAU * k / n
		var wob := 1.0 + 0.035 * sin(a * 3.0 + 0.6) + 0.02 * sin(a * 5.0)
		out.append(c + (Vector2(cos(a), sin(a)) * rad * wob).rotated(LAKE_ANGLE))
	return out


static func build_park(out: Array[BuildingModel.Piece], r: Rect2, seed: int) -> void:
	var f := park_frame(r)
	var s := _s(r)
	# 호텔 탑 (북쪽 끝)
	var hotel := BuildingModel._prism(_rot_rect(f.hotel, f.hotel_half, PARK_ANGLE), 0, 250, Color("d8d2c4"), &"flat", Color("9a958a"), &"punched", seed)
	hotel.text = "롯데호텔"
	hotel.deco = [&"top_sign", &"entrance"]
	out.append(hotel)
	hotel.on_top.append(BuildingModel._prism(_rot_rect(f.hotel, (f.hotel_half as Vector2) * Vector2(0.4, 0.6), PARK_ANGLE), 250, 266,
		Color("c9c2b2"), &"flat", Color("8a857a"), &"none", seed + 1))
	# 실내 놀이 궁: 크림색 벽 위에 유리 볼트 지붕 (단면 원을 층마다 좁혀 쌓는다)
	var hall_half: Vector2 = f.hall_half
	var hall := BuildingModel._prism(_rot_rect(f.hall, hall_half, PARK_ANGLE), 0, 52, Color("e2d6bd"), &"flat", Color("b9ad93"), &"punched", seed + 2)
	hall.text = "롯데월드"
	hall.deco = [&"top_sign", &"entrance"]
	hall.floor_height = 17.3
	out.append(hall)
	var under := hall
	var n := 6
	var rise := 70.0 * s
	for k in n:
		var a0 := PI * 0.5 * k / n
		var a1 := PI * 0.5 * (k + 1) / n
		var hw := Vector2(hall_half.x - 12.0, (hall_half.y - 10.0) * cos(a0))
		var vault := BuildingModel._prism(_rot_rect(f.hall, hw, PARK_ANGLE), 52 + rise * sin(a0), 52 + rise * sin(a1),
			Color("9fc6dc").lerp(Color("d6ebf4"), float(k) / n), &"flat", Color("b8dcec"), &"glass", seed + 10 + k)
		vault.glass_tint = Color("6aa3c0").lerp(Color("a9d3e6"), float(k) / n)
		vault.floor_height = maxf(4.0, rise * (sin(a1) - sin(a0)))
		under.on_top.append(vault)
		under = vault
	# 볼트 양끝 둥근 돔 (동쪽)
	var dome_c: Vector2 = (f.hall as Vector2) + Vector2.from_angle(PARK_ANGLE) * (hall_half.x - 52.0 * s)
	var dome_under := hall
	for k in 4:
		var a0 := PI * 0.5 * k / 4.0
		var a1 := PI * 0.5 * (k + 1) / 4.0
		var dr := 50.0 * s * cos(a0)
		var dome := BuildingModel._prism(BuildingModel.ngon(dome_c, Vector2(dr, dr), 16), 52 + rise * 1.35 * sin(a0), 52 + rise * 1.35 * sin(a1),
			Color("b5dbe9"), &"flat", Color("d8eef6"), &"glass", seed + 20 + k)
		dome.glass_tint = Color("7fb6cf")
		dome.floor_height = 8.0
		dome_under.on_top.append(dome)
		dome_under = dome
	# 호수: 다리·섬을 빼고 막는다 (보이지 않는 덩어리 — 물은 바닥 그림)
	for q in lake_blocks(f):
		StreetBuilding._add(out, q, 0, 4, Color(0, 0, 0, 0), &"none", &"sd_void")
	# 매직아일랜드 성: 흰 성벽(돌린 다각형), 분홍 탑들과 파란 고깔, 가운데 높은 탑
	var ic: Vector2 = f.island
	var castle_c := ic + Vector2(-8, -6) * s
	var wall := BuildingModel._prism(BuildingModel.ngon(castle_c, Vector2(38, 30) * s, 10, LAKE_ANGLE), 0, 30, Color("f1ece4"), &"flat", Color("d8d0c4"), &"punched", seed + 30)
	wall.deco = [&"entrance"]
	out.append(wall)
	var keep := BuildingModel._prism(BuildingModel.ngon(castle_c + Vector2(0, -4) * s, Vector2(16, 14) * s, 8, LAKE_ANGLE), 30, 84, Color("f6d7de"),
		&"spire", Color("3f6fb8"), &"punched", seed + 31)
	keep.rise = 48.0
	keep.accent = Color("f2c230")
	wall.on_top.append(keep)
	for k in 5:
		var a := TAU * (k + 0.25) / 5.0
		var at := castle_c + (Vector2(cos(a) * 42.0, sin(a) * 33.0) * s).rotated(LAKE_ANGLE)
		var tw := BuildingModel._prism(BuildingModel.ngon(at, Vector2(8, 8) * s, 8), 0, 52 + (k % 2) * 12, Color("f0c3cf"), &"spire", Color("4d7fc4"), &"punched", seed + 32 + k)
		tw.rise = 26.0 + (k % 2) * 8.0
		tw.accent = Color("f2c230")
		out.append(tw)
	# 자이로드롭: 섬 동쪽 높은 철탑과 의자 고리
	var drop_at := ic + Vector2(70, 26) * s
	var drop := BuildingModel._prism(BuildingModel.ngon(drop_at, Vector2(6, 6), 8), 0, 236, Color("d4392e"), &"flat", Color("f2c230"), &"none", seed + 40)
	out.append(drop)
	var seats := LandmarkBuilding.box(out, Rect2(drop_at - Vector2(14, 14), Vector2(28, 28)), 140, 152, Color("f2c230"), &"none", &"observation_ring")
	seats.roof_color = Color("e8a72a")
	# 회전목마: 섬 서쪽 둥근 천막
	var go_at := ic + Vector2(-66, 34) * s
	var carousel := BuildingModel._prism(BuildingModel.ngon(go_at, Vector2(17, 17) * s, 12), 0, 12, Color("f4e3c1"), &"spire", Color("d9473c"), &"none", seed + 41)
	carousel.rise = 16.0
	carousel.accent = Color("f2c230")
	out.append(carousel)
	# 섬 둘레 나무 (다리 길·탈것 자리 비움)
	var ir: Vector2 = f.island_r
	for a in 10:
		var ang := TAU * (a + 0.5) / 10.0
		var at := ic + (Vector2(cos(ang), sin(ang)) * ir * 0.86).rotated(LAKE_ANGLE)
		if absf(at.x - ic.x) < 24.0 * s and at.y < ic.y:
			continue
		if at.distance_to(drop_at) < 26.0 * s or at.distance_to(go_at) < 30.0 * s:
			continue
		StreetBuilding._tree(out, at, seed + 50 + a, 0.85, a % 3 == 0)
	# 호수 둘레: 산책길 바깥 나무, 산책길 가 가로등 (산책 고리를 비운다)
	var lc: Vector2 = f.lake_c
	var lr: Vector2 = f.lake_r
	for k in 28:
		var a := TAU * (k + 0.5) / 28.0
		var dir := Vector2(cos(a), sin(a))
		var lamp := lc + (dir * (lr + Vector2(36, 36) * s)).rotated(LAKE_ANGLE)
		if k % 3 == 0 and r.grow(-6.0).has_point(lamp) and not _in_hall(f, lamp):
			StreetBuilding._lamp(out, lamp, 40.0)
		var tree := lc + (dir * (lr + Vector2(56, 56) * s)).rotated(LAKE_ANGLE)
		if k % 2 == 1 and r.grow(-10.0).has_point(tree) and not _in_hall(f, tree):
			StreetBuilding._tree(out, tree, seed + 70 + k, 1.15, k % 5 == 1)


static func _in_hall(f: Dictionary, p: Vector2) -> bool:
	var q := (p - (f.hall as Vector2)).rotated(-PARK_ANGLE).abs()
	var hh: Vector2 = f.hall_half
	return q.x < hh.x + 16.0 and q.y < hh.y + 16.0


## 호수 물을 막는 가로 띠들 (섬과 다리는 비운다)
static func lake_blocks(f: Dictionary) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var island := BuildingModel.ngon(f.island, f.island_r, 24, LAKE_ANGLE)
	var bridge: Rect2 = f.bridge
	for q in BuildingModel.poly_rects(f.lake, 16.0):
		var holes: Array[Vector2] = []
		var y := q.get_center().y
		var y0 := q.position.y
		var y1 := q.end.y
		var top := BuildingModel._span(island, y0)
		var bot := BuildingModel._span(island, y1)
		var mid := BuildingModel._span(island, y)
		var hx0 := minf(minf(top.x, bot.x), mid.x)
		var hx1 := maxf(maxf(top.y, bot.y), mid.y)
		if hx1 > hx0:
			holes.append(Vector2(hx0, hx1))
		if y1 > bridge.position.y and y0 < bridge.end.y:
			holes.append(Vector2(bridge.position.x, bridge.end.x))
		holes.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var x := q.position.x
		for hole in holes:
			if hole.x > x:
				out.append(Rect2(x, y0, minf(hole.x, q.end.x) - x, y1 - y0))
			x = maxf(x, hole.y)
		if x < q.end.x:
			out.append(Rect2(x, y0, q.end.x - x, y1 - y0))
	return out.filter(func(q: Rect2) -> bool: return q.size.x > 1.0)


static func park_ground(ci: CanvasItem, r: Rect2, seed: int) -> void:
	var f := park_frame(r)
	var s := _s(r)
	ci.draw_rect(r, Color("5a8445"))
	LandmarkBuilding._speckle(ci, r, seed, 90, Color("4f763c"), Color("6a9450"), 5.0)
	# 호텔·궁 앞 돌 마당 (비스듬히)
	ci.draw_colored_polygon(_rot_rect(f.hall, (f.hall_half as Vector2) + Vector2(26, 30) * s, PARK_ANGLE), Color("d4cdbf"))
	ci.draw_colored_polygon(_rot_rect(f.hotel, (f.hotel_half as Vector2) + Vector2(18, 18) * s, PARK_ANGLE), Color("cfc8ba"))
	# 산책길 (벽돌색 보도)
	var lc: Vector2 = f.lake_c
	var lr: Vector2 = f.lake_r
	var walk := BuildingModel.ngon(lc, lr + Vector2(40, 40) * s, 36, LAKE_ANGLE)
	ci.draw_colored_polygon(walk, WALK)
	ci.draw_polyline(_closed(walk), Color("a8805e"), 2.0)
	# 물: 호안 돌 띠, 짙은 가운데, 물결
	var lake: PackedVector2Array = f.lake
	ci.draw_colored_polygon(BuildingModel.scaled(lake, lc, 1.03), Color("8d8a82"))
	ci.draw_colored_polygon(lake, WATER)
	ci.draw_colored_polygon(BuildingModel.scaled(lake, lc, 0.82), WATER.darkened(0.12))
	for k in 30:
		var at := lc + (Vector2(StreetBuilding._h(seed, k + 300) - 0.5, StreetBuilding._h(seed + 4099, k * 17 + 301) - 0.5) * lr * 1.4).rotated(LAKE_ANGLE)
		if Geometry2D.is_point_in_polygon(at, lake):
			ci.draw_line(at, at + Vector2(14.0 + k % 4 * 4.0, 0), Color(0.75, 0.88, 0.95, 0.35), 1.5)
	# 섬과 다리
	var ic: Vector2 = f.island
	var ir: Vector2 = f.island_r
	ci.draw_colored_polygon(BuildingModel.ngon(ic, ir + Vector2(5, 5), 24, LAKE_ANGLE), Color("8d8a82"))
	ci.draw_colored_polygon(BuildingModel.ngon(ic, ir, 24, LAKE_ANGLE), Color("6a9a50"))
	ci.draw_colored_polygon(BuildingModel.ngon(ic + Vector2(-8, -6) * s, ir * 0.6, 20, LAKE_ANGLE), Color("d9cdb4"))
	var bridge: Rect2 = f.bridge
	ci.draw_rect(bridge, Color("a8805e"))
	var y := bridge.position.y
	while y < bridge.end.y:
		ci.draw_line(Vector2(bridge.position.x, y), Vector2(bridge.end.x, y), Color("8a6748"), 1.0)
		y += 6.0
	for side in [bridge.position.x - 1.0, bridge.end.x + 1.0]:
		ci.draw_line(Vector2(side, bridge.position.y) + IsoView.lift(6), Vector2(side, bridge.end.y) + IsoView.lift(6), Color("f1ece4"), 2.0)
	# 꽃밭 (궁 앞)
	var hall_front: Vector2 = (f.hall as Vector2) + Vector2.from_angle(PARK_ANGLE + PI * 0.5) * ((f.hall_half as Vector2).y + 18.0 * s)
	var along := Vector2.from_angle(PARK_ANGLE)
	for k in 18:
		var at := hall_front + along * (k - 8.5) * 22.0 * s
		ci.draw_circle(at, 3.0, [Color("e9a6bf"), Color("f2d35b"), Color("e46a5a")][k % 3])


static func park_loops(r: Rect2) -> Array[PackedVector2Array]:
	return [park_frame(r).loop]


# ── 바닥 무늬 ──────────────────────────────────────────────

## 돌린 줄눈 (angle만큼 돌린 격자를 r 안에서 자른다)
static func _angled_tiles(ci: CanvasItem, r: Rect2, step: float, angle: float, color: Color) -> void:
	var c := r.get_center()
	var reach := r.size.length() * 0.5
	var ex := Vector2.from_angle(angle)
	var ey := Vector2.from_angle(angle + PI * 0.5)
	var box := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var lines := PackedVector2Array()
	for axis in [ex, ey]:
		var other: Vector2 = ey if axis == ex else ex
		var d := -reach
		while d <= reach:
			var a: Vector2 = c + other * d - axis * reach
			var b: Vector2 = c + other * d + axis * reach
			var cut := Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), box)
			for seg in cut:
				if seg.size() >= 2:
					lines.append(seg[0])
					lines.append(seg[seg.size() - 1])
			d += step
	if not lines.is_empty():
		ci.draw_multiline(lines, color, 1.0)


static func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	out.append(poly[0])
	return out
