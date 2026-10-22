class_name CityMap
extends RefCounted
## 도시 전체 배치(구역·한강·다리)와 도로 연결. 노드 없는 정적 데이터 — City·LaneGraph·RoadNav가 함께 본다.
##
## 블록 (i, j)는 City.block_rect(i, j). 교차로 (i, j)는 세로 도로 i번과 가로 도로 j번이 만나는 곳.
## 도로 구간은 양옆 블록 중 하나라도 땅이면 있다. 양옆이 다 물이면 다리(BRIDGES)일 때만 있다.
## 구역은 장(Chapter)마다 열린다. 잠긴 구역 블록은 담으로 막히고, 잠긴 교차로로 들어가는 도로는 통제된다.
## 교차로는 붙은 땅 블록 중 하나라도 열린 구역이면 열린다. 강 한가운데 다리 교차로는 다리 양끝이 다 열려야 열린다.

const DISTRICTS: Array[DistrictType] = [
	preload("res://data/districts/gangnam.tres"),
	preload("res://data/districts/jongno.tres"),
	preload("res://data/districts/hongdae.tres"),
	preload("res://data/districts/riverside.tres"),
	preload("res://data/districts/yeouido.tres"),
	preload("res://data/districts/outskirts.tres"),
	preload("res://data/districts/industrial.tres"),
	preload("res://data/districts/jamsil.tres"),
	preload("res://data/districts/gwangjin.tres"),
]
## 블록 좌표 범위 (양끝 포함). 교차로 좌표는 MIN ~ MAX + 1
const MIN := Vector2i(-5, -11)
const MAX := Vector2i(8, 5)
## 잠실(동쪽 확장) 전의 동쪽 끝 블록. 건물 번호는 이 안을 먼저 센다 — 예전 도시의 건물 번호·겉모습이 그대로 남게
const LEGACY_MAX_X := 5
## 한강을 건너는 세로 도로 번호
const BRIDGES: Array[int] = [-3, 2, 5, 7]   ## 7 = 잠실대교 (잠실 ↔ 광진)
## 다리 위 도로 높이 (2.5D 화면 px). 다리는 강물 위로 이만큼 떠 있고, 양끝은 경사로로 땅에 닿는다.
## 그림에만 쓴다 — 다리 밑으로 지나는 길이 없어서(밑은 강물) 물리·충돌은 평면 그대로다
const DECK_HEIGHT := 46.0
## 경사로 길이 (월드 px). 짧은 다리는 길이의 40%까지 줄인다
const RAMP := 380.0
const STEPS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]   ## 북 동 남 서
## 고가차도: [축, 도로 번호, 첫 교차로, 끝 교차로]. 축 1이면 가로 도로 j번이 교차로 (첫~끝, j)를, 축 0이면 세로 도로 i번이
## 교차로 (i, 첫~끝)을 넘는다. 넘는 교차로 바로 앞뒤 구간은 경사로, 넘는 교차로 사이 구간은 상판이다(밑은 막혀 있다).
## 넘는 교차로에서는 고가 위(그 축)도 밑의 길(다른 축)도 직진만 한다 — 신호가 없고, 위아래가 서로 막지 않는다.
## 물리는 층(level)으로 나눈다: 고가 위(1)의 차·사람은 충돌 레이어를 Layers.DECK 쪽으로 옮겨 밑(0)과 부딪히지 않는다
const OVERPASSES: Array[Vector4i] = [Vector4i(1, 2, 1, 2)]   ## 강남 가로 2번 도로 — 교차로 (1,2)·(2,2)를 넘는다
## 고가 상판 높이 (2.5D 화면 px). 밑으로 차가 지나간다
const OVER_HEIGHT := 50.0
## 경사로가 이 높이를 넘은 곳부터 고가 층이다 — 그 아래 경사로 입구는 땅과 같은 층(옆으로 드나든다)
const OVER_SWITCH := 14.0
## 층이 달라도 바닥 높이 차가 이보다 작으면 서로 본다 (경사로 입구에서 앞차를 놓치지 않게)
const MEET_HEIGHT := 18.0
const LAST_CHAPTER := 4

## 열린 장. 게임(main)이 정한다 — 테스트마다 main이 새로 정하므로 이전 값이 남지 않는다
static var chapter := 1
static var _blocks := {}       ## Vector2i 블록 → DistrictType (물은 없음)
static var _open_cache := {}   ## 교차로 → 열림 (장이 바뀌면 비운다)
static var _road_cache := {}   ## Vector3i(교차로, 방향) → 도로 있음 (지도는 안 바뀐다)
static var _open_road_cache := {}
static var _spans := {}        ## 다리 세로 도로 번호 → Array[Vector2] (다리 위 구간 y 시작·끝, 교차로 포함)
static var _over_cells := {}   ## 고가가 넘는 교차로 → 고가 축 (지도는 안 바뀐다)


static func _ensure() -> void:
	if not _blocks.is_empty():
		return
	for d in DISTRICTS:
		for j in range(d.blocks.position.y, d.blocks.end.y):
			for i in range(d.blocks.position.x, d.blocks.end.x):
				_blocks[Vector2i(i, j)] = d


## 건물을 세는 블록 차례: 예전 지도(LEGACY_MAX_X까지)를 줄마다, 그다음 동쪽 확장을 줄마다
static func layout_order() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for east in [false, true]:
		for j in range(MIN.y, MAX.y + 1):
			for i in range(MIN.x, MAX.x + 1):
				if (i > LEGACY_MAX_X) == east:
					out.append(Vector2i(i, j))
	return out


static func set_chapter(n: int) -> void:
	chapter = clampi(n, 1, LAST_CHAPTER)
	_open_cache.clear()
	_open_road_cache.clear()


static func in_bounds(b: Vector2i) -> bool:
	return b.x >= MIN.x and b.y >= MIN.y and b.x <= MAX.x and b.y <= MAX.y


static func node_in_bounds(c: Vector2i) -> bool:
	return c.x >= MIN.x and c.y >= MIN.y and c.x <= MAX.x + 1 and c.y <= MAX.y + 1


## 블록이 속한 구역 (물이나 지도 밖이면 null)
static func district_of(b: Vector2i) -> DistrictType:
	_ensure()
	return _blocks.get(b)


static func is_land(b: Vector2i) -> bool:
	return district_of(b) != null


static func is_water(b: Vector2i) -> bool:
	return in_bounds(b) and not is_land(b)


static func is_open_block(b: Vector2i) -> bool:
	var d := district_of(b)
	return d != null and d.chapter <= chapter


## 월드 좌표가 속한 블록 (도로 위면 가장 가까운 블록)
static func block_at(pos: Vector2) -> Vector2i:
	var center := City.ROAD + City.BLOCK * 0.5
	return Vector2i(roundi((pos.x - center) / City.PITCH), roundi((pos.y - center) / City.PITCH))


## 월드 좌표가 있는 구역 (강 위면 null)
static func district_at(pos: Vector2) -> DistrictType:
	return district_of(block_at(pos))


## 교차로에 붙은 네 블록
static func node_blocks(c: Vector2i) -> Array[Vector2i]:
	return [c + Vector2i(-1, -1), c + Vector2i(0, -1), c + Vector2i(-1, 0), c]


## 교차로 c에서 d 방향 도로 구간의 양옆 블록
static func flanks(c: Vector2i, d: int) -> Array[Vector2i]:
	match d:
		0: return [c + Vector2i(-1, -1), c + Vector2i(0, -1)]
		1: return [c + Vector2i(0, -1), c]
		2: return [c + Vector2i(-1, 0), c]
		_: return [c + Vector2i(-1, -1), c + Vector2i(-1, 0)]


## 교차로 c에서 d 방향으로 도로 구간이 있는가 (잠김과 상관없이)
static func road(c: Vector2i, d: int) -> bool:
	var key := Vector3i(c.x, c.y, d)
	var hit: Variant = _road_cache.get(key)
	if hit != null:
		return hit
	var result := false
	if node_in_bounds(c) and node_in_bounds(c + STEPS[d]):
		for b in flanks(c, d):
			result = result or is_land(b)
		result = result or is_bridge(c, d)
	_road_cache[key] = result
	return result


## 양옆이 다 물인 다리 구간인가
static func is_bridge(c: Vector2i, d: int) -> bool:
	if d % 2 == 1 or not BRIDGES.has(c.x):
		return false
	for b in flanks(c, d):
		if not is_water(b):
			return false
	return true


static func node_exists(c: Vector2i) -> bool:
	for d in 4:
		if road(c, d):
			return true
	return false


## 교차로가 열려 있는가 (차·사람이 들어갈 수 있다)
static func is_open_node(c: Vector2i) -> bool:
	if _open_cache.has(c):
		return _open_cache[c]
	var result := false
	if node_exists(c):
		var land := false
		for b in node_blocks(c):
			var dist := district_of(b)
			if dist:
				land = true
				result = result or dist.chapter <= chapter
		if not land:
			result = _bridge_open(c)
	_open_cache[c] = result
	return result


## 강 한가운데 다리 교차로: 다리를 따라 남북 양끝의 땅 교차로가 다 열려 있어야 열린다
static func _bridge_open(c: Vector2i) -> bool:
	for d in [0, 2]:
		var n := c
		while true:
			if not road(n, d):
				return false
			n += STEPS[d]
			var land := false
			for b in node_blocks(n):
				land = land or is_land(b)
			if land:
				if not is_open_node(n):
					return false
				break
	return true


## 다리가 놓인 구간들: 세로 도로 k번에서 강 위를 지나는 y 구간 (이어진 다리 구간과 그 사이 강 한가운데 교차로를 합친다)
static func bridge_spans(k: int) -> Array[Vector2]:
	if _spans.has(k):
		return _spans[k]
	var out: Array[Vector2] = []
	for j in range(MIN.y, MAX.y + 1):
		if not is_bridge(Vector2i(k, j), 2):
			continue
		var y0 := j * City.PITCH + City.ROAD
		var y1 := y0 + City.BLOCK
		if not out.is_empty() and is_equal_approx(out[-1].y + City.ROAD, y0):
			out[-1].y = y1
		else:
			out.append(Vector2(y0, y1))
	_spans[k] = out
	return out


## 그 자리 땅 높이 (2.5D 화면 px): 다리 위면 DECK_HEIGHT, 경사로면 그 사이, 나머지는 0.
## 고가차도 위는 level이 1이면 상판 높이, 0이면 밑(넘는 교차로 밑은 0, 경사로 입구는 그 높이). -1(층을 모름)이면 넘는 교차로만 밑으로 본다
static func ground_height(pos: Vector2, level := -1) -> float:
	for k in BRIDGES:
		if absf(pos.x - City.road_center(k)) > City.ROAD * 0.5 + 8.0:
			continue
		for span in bridge_spans(k):
			if pos.y > span.x and pos.y < span.y:
				return deck_height_at(span, pos.y)
	var o := overpass_at(pos)
	if o < 0:
		return 0.0
	if level != 1 and _in_over_cell(OVERPASSES[o], pos):
		return 0.0
	return over_height(o, pos)


# ── 고가차도 ──────────────────────────────────────────────

## 고가 o의 (진행 방향 좌표, 가로지르는 좌표)
static func _over_axes(o: Vector4i, pos: Vector2) -> Vector2:
	return pos if o.x == 1 else Vector2(pos.y, pos.x)


## 고가 o의 (진행, 가로) 좌표 → 월드
static func over_point(o: Vector4i, along: float, across: float) -> Vector2:
	return Vector2(along, across) if o.x == 1 else Vector2(across, along)


## 고가 o가 시작·끝나는 진행 좌표 (경사로 입구 = 앞뒤 교차로 상자의 가장자리)
static func over_extent(o: Vector4i) -> Vector2:
	return Vector2((o.z - 1) * City.PITCH + City.ROAD, (o.w + 1) * City.PITCH)


## pos가 놓인 고가차도 번호 (도로 폭 안, 경사로 입구~출구). 없으면 -1
static func overpass_at(pos: Vector2) -> int:
	for i in OVERPASSES.size():
		var o := OVERPASSES[i]
		var p := _over_axes(o, pos)
		var ext := over_extent(o)
		if p.x > ext.x and p.x < ext.y and absf(p.y - City.road_center(o.y)) < City.ROAD * 0.5:
			return i
	return -1


static func _in_over_cell(o: Vector4i, pos: Vector2) -> bool:
	var along := _over_axes(o, pos).x
	var n := floori(along / City.PITCH)
	return n >= o.z and n <= o.w and along - n * City.PITCH < City.ROAD


## 고가 o의 상판 높이 (경사로는 부드럽게, 넘는 교차로·그 사이 상판은 OVER_HEIGHT)
static func over_height(o: int, pos: Vector2) -> float:
	var ov := OVERPASSES[o]
	var along := _over_axes(ov, pos).x
	var ext := over_extent(ov)
	var t := clampf(minf(along - ext.x, ext.y - along) / City.BLOCK, 0.0, 1.0)
	return OVER_HEIGHT * smoothstep(0.0, 1.0, t)


## 경사로가 OVER_SWITCH 높이에 닿는 곳까지 입구에서의 거리 (월드 px)
static func over_switch_distance() -> float:
	var lo := 0.0
	var hi := 1.0
	for i in 30:
		var mid := (lo + hi) * 0.5
		if OVER_HEIGHT * smoothstep(0.0, 1.0, mid) < OVER_SWITCH:
			lo = mid
		else:
			hi = mid
	return lo * City.BLOCK


## 그 자리가 정하는 층: 1 고가 위(경사로가 OVER_SWITCH보다 높은 곳·상판), 0 땅, -1 넘는 교차로 상자(위아래가 다 지나가므로 지금 층을 그대로 둔다)
static func level_zone(pos: Vector2) -> int:
	var o := overpass_at(pos)
	if o < 0:
		return 0
	if _in_over_cell(OVERPASSES[o], pos):
		return -1
	return 1 if over_height(o, pos) >= OVER_SWITCH else 0


## 고가가 넘는 교차로면 고가 축(0 세로·1 가로 — 진행 방향 d의 d % 2와 같다), 아니면 -1
static func over_axis(c: Vector2i) -> int:
	if _over_cells.is_empty():
		_over_cells[RoadNav.INVALID] = -1
		for o in OVERPASSES:
			for n in range(o.z, o.w + 1):
				_over_cells[Vector2i(n, o.y) if o.x == 1 else Vector2i(o.y, n)] = o.x
	return _over_cells.get(c, -1)


## 교차로 c에서 d 방향 도로 구간이 고가(경사로·상판)인가
static func over_strip(c: Vector2i, d: int) -> bool:
	# 구간을 북·서쪽 끝 교차로 a에서 동(1)·남(2) 방향으로 본다
	var a := c + STEPS[d] if d == 0 or d == 3 else c
	var axis := 1 if d % 2 == 1 else 0
	for o in OVERPASSES:
		var road_k := a.y if axis == 1 else a.x
		var n := a.x if axis == 1 else a.y
		if o.x == axis and road_k == o.y and n >= o.z - 1 and n <= o.w:
			return true
	return false


## 층이 다른 둘이 서로 닿는가 (같은 층이거나, 경사로 입구처럼 바닥 높이가 거의 같다)
static func meet(pa: Vector2, la: int, pb: Vector2, lb: int) -> bool:
	return la == lb or absf(ground_height(pa, la) - ground_height(pb, lb)) < MEET_HEIGHT


## 다리 구간 span 안의 y에서 다리 높이 (양끝 경사로는 부드럽게)
static func deck_height_at(span: Vector2, y: float) -> float:
	var ramp := minf(RAMP, (span.y - span.x) * 0.4)
	var t := clampf(minf(y - span.x, span.y - y) / ramp, 0.0, 1.0)
	return DECK_HEIGHT * smoothstep(0.0, 1.0, t)


## 열린 도로 구간인가 (양끝 교차로가 다 열려 있다)
static func open_road(c: Vector2i, d: int) -> bool:
	var key := Vector3i(c.x, c.y, d)
	var hit: Variant = _open_road_cache.get(key)
	if hit != null:
		return hit
	var result := road(c, d) and is_open_node(c) and is_open_node(c + STEPS[d])
	_open_road_cache[key] = result
	return result


## 장 n에 새로 열리는 구역들
static func districts_of_chapter(n: int) -> Array[DistrictType]:
	var result: Array[DistrictType] = []
	for d in DISTRICTS:
		if d.chapter == n:
			result.append(d)
	return result


static func district(id: StringName) -> DistrictType:
	for d in DISTRICTS:
		if d.id == id:
			return d
	return null


## 지도 전체 (도로 포함) 월드 사각형
static func world_rect() -> Rect2:
	var a := Vector2(MIN.x * City.PITCH, MIN.y * City.PITCH)
	var b := Vector2((MAX.x + 1) * City.PITCH + City.ROAD, (MAX.y + 1) * City.PITCH + City.ROAD)
	return Rect2(a, b - a)
