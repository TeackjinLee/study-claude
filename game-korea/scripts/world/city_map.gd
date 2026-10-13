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
]
## 블록 좌표 범위 (양끝 포함). 교차로 좌표는 MIN ~ MAX + 1
const MIN := Vector2i(-5, -11)
const MAX := Vector2i(5, 5)
## 한강을 건너는 세로 도로 번호
const BRIDGES: Array[int] = [-3, 2, 5]
## 다리 위 도로 높이 (2.5D 화면 px). 다리는 강물 위로 이만큼 떠 있고, 양끝은 경사로로 땅에 닿는다.
## 그림에만 쓴다 — 다리 밑으로 지나는 길이 없어서(밑은 강물) 물리·충돌은 평면 그대로다
const DECK_HEIGHT := 46.0
## 경사로 길이 (월드 px). 짧은 다리는 길이의 40%까지 줄인다
const RAMP := 380.0
const STEPS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]   ## 북 동 남 서
const LAST_CHAPTER := 4

## 열린 장. 게임(main)이 정한다 — 테스트마다 main이 새로 정하므로 이전 값이 남지 않는다
static var chapter := 1
static var _blocks := {}       ## Vector2i 블록 → DistrictType (물은 없음)
static var _open_cache := {}   ## 교차로 → 열림 (장이 바뀌면 비운다)
static var _road_cache := {}   ## Vector3i(교차로, 방향) → 도로 있음 (지도는 안 바뀐다)
static var _open_road_cache := {}
static var _spans := {}        ## 다리 세로 도로 번호 → Array[Vector2] (다리 위 구간 y 시작·끝, 교차로 포함)


static func _ensure() -> void:
	if not _blocks.is_empty():
		return
	for d in DISTRICTS:
		for j in range(d.blocks.position.y, d.blocks.end.y):
			for i in range(d.blocks.position.x, d.blocks.end.x):
				_blocks[Vector2i(i, j)] = d


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


## 그 자리 땅 높이 (2.5D 화면 px): 다리 위면 DECK_HEIGHT, 경사로면 그 사이, 나머지는 0
static func ground_height(pos: Vector2) -> float:
	for k in BRIDGES:
		if absf(pos.x - City.road_center(k)) > City.ROAD * 0.5 + 8.0:
			continue
		for span in bridge_spans(k):
			if pos.y > span.x and pos.y < span.y:
				return deck_height_at(span, pos.y)
	return 0.0


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
