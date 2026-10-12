class_name City
extends Node2D
## 가상 서울 (M6): 구역 7개, 한강, 다리 3개. 격자 블록·도로·인도·건물(충돌)을 전부 코드로 그린다.
## 구역·강·다리 배치는 CityMap, 구역별 건물 비중은 data/districts/*.tres.
## 건물 배치는 블록 좌표만으로 결정된다(RNG 없음) — 실행할 때마다 같은 도시.
## 그리기는 블록 묶음(청크)마다 따로 해서 화면 밖은 그리지 않는다.
## 잠긴 구역은 담으로 막고, 잠긴 교차로로 들어가는 도로에는 통제 바리케이드를 세운다 (refresh_locks).

const BLOCK := 576.0
const ROAD := 192.0
const SIDEWALK := 28.0
const PITCH := BLOCK + ROAD
const ALLEY := 18.0
const WALL := 64.0
const CHUNK := 3                 ## 청크 하나의 블록 수 (가로·세로)
## 교차로 가장자리에서 정지선까지 (횡단보도 바로 뒤)
const STOP_LINE := 50.0
## 건물 없는 주차장 블록 — 드리프트 연습장
const PLAZA := Vector2i(1, 1)
## 강남 경찰서 블록 — 강남에서 체포되면 이 앞 인도에서 다시 시작한다
const POLICE_STATION := Vector2i(4, 2)
## 강남 병원 블록
const HOSPITAL := Vector2i(1, 4)
## 강남 조직 본부 블록 (출발점 바로 옆). 정문 옆 인도에 공중전화가 있다
const GANG_HQ := Vector2i(3, 3)
## 은신처 — 이 블록 오른쪽 건물(오피스텔). 문 앞에서 저장한다
const HIDEOUT := Vector2i(2, 3)
## 창고 블록 — 배달 미션의 목적지
const WAREHOUSE := Vector2i(5, 5)
## 카센터 — 이 블록 위쪽 건물. 왼쪽 도로 갓길의 정비 칸에 차를 세우면 도색(수배 −2)·수리
const SPRAY_SHOP := Vector2i(1, 3)
const DISTRICT := "강남대로"
## 자동 배치 건물 종류 (docs/04). 본부·은신처·창고·카센터·경찰서·병원은 정해 둔 블록에 있다.
## 순서를 바꾸면 도시 모양이 바뀐다 — 새 종은 뒤에 붙인다.
const BUILDING_TYPES: Array[BuildingType] = [
	preload("res://data/buildings/commercial.tres"),
	preload("res://data/buildings/mixed.tres"),
	preload("res://data/buildings/office.tres"),
	preload("res://data/buildings/officetel.tres"),
	preload("res://data/buildings/apt.tres"),
	preload("res://data/buildings/villa.tres"),
	preload("res://data/buildings/gosiwon.tres"),
	preload("res://data/buildings/warehouse.tres"),
	preload("res://data/buildings/house.tres"),
	preload("res://data/buildings/rowhouse.tres"),
	preload("res://data/buildings/oneroom.tres"),
	preload("res://data/buildings/factory.tres"),
	preload("res://data/buildings/hanok.tres"),
	preload("res://data/buildings/jjokbang.tres"),
	preload("res://data/buildings/campsite.tres"),
	preload("res://data/buildings/park.tres"),
]

const ASPHALT := Color(0.16, 0.17, 0.22)
const WATER := Color(0.07, 0.13, 0.24)
const WATER_LIGHT := Color(0.16, 0.27, 0.42, 0.6)
const SIDEWALK_COLOR := Color(0.33, 0.34, 0.40)
const CURB := Color(0.48, 0.49, 0.55)
const LANE_WHITE := Color(0.85, 0.85, 0.85, 0.75)
const LANE_YELLOW := Color(0.95, 0.75, 0.15, 0.85)
const RAIL := Color(0.62, 0.64, 0.7)
const LOCK_SHADE := Color(0.02, 0.02, 0.05, 0.62)
const BARRIER := Color(0.95, 0.55, 0.1)
const NEON := [
	Color(1.0, 0.23, 0.36), Color(0.23, 0.65, 1.0), Color(0.23, 1.0, 0.54),
	Color(1.0, 0.82, 0.23), Color(1.0, 0.36, 0.88),
]

var buildings: Array[Rect2] = []         ## 충돌하는 건물 (공원 제외)
var kinds: Array[BuildingType] = []      ## buildings와 같은 순서. 특수 건물(경찰서·병원·카센터)은 null
var parks: Array[Rect2] = []             ## 공원 부지 (지나갈 수 있다)
var park_kinds: Array[BuildingType] = []
var station := Rect2()                   ## 강남 경찰서
var hospital := Rect2()                  ## 강남 병원
var stations: Array[Rect2] = []          ## 모든 경찰서
var hospitals: Array[Rect2] = []         ## 모든 병원
var hq := Rect2()
var hideout := Rect2()
var warehouse := Rect2()
var spray := Rect2()
var locked_blocks: Array[Vector2i] = []
var barriers: Array[Rect2] = []          ## 통제 바리케이드 (잠긴 도로 입구)
var water: Array[Rect2] = []             ## 강물 사각형 (미니맵용)
var _lock_body: StaticBody2D
var _lock_layer: Node2D
var _owners := {}                        ## 건물 번호 → 블록 (청크 그리기용)
var _views := {}                         ## 건물 번호 → Array[BuildingView] (2.5D 입체 건물)
var _fade := {}                          ## 건물 번호 → 지금 불투명도 (흐려진 건물만. 주인공이 뒤에 있으면 흐려진다)
var _by_block := {}                      ## 블록 → 그 블록의 건물 번호들
var _chunks: Array[Chunk] = []

## 2.5D 특수 건물 층수
const STATION_FLOORS := 4
const HOSPITAL_FLOORS := 6
const SPRAY_FLOORS := 2
const FADE_ALPHA := 0.28                 ## 주인공을 가린 건물의 불투명도


## 블록 묶음 하나를 그리는 노드. 화면 밖 청크는 Godot가 그리지 않는다
class Chunk extends Node2D:
	var city: City
	var area: Rect2i

	func _draw() -> void:
		city.draw_chunk(self, area)


## 잠긴 구역 그늘과 바리케이드
class LockLayer extends Node2D:
	var city: City

	func _draw() -> void:
		city.draw_locks(self)


func _ready() -> void:
	z_index = -10
	_build_layout()
	_build_collision()
	_make_chunks()
	_make_views()
	_lock_layer = LockLayer.new()
	_lock_layer.city = self
	add_child(_lock_layer)
	refresh_locks()
	queue_redraw()


static func world_rect() -> Rect2:
	return CityMap.world_rect()


static func block_rect(i: int, j: int) -> Rect2:
	return Rect2(ROAD + i * PITCH, ROAD + j * PITCH, BLOCK, BLOCK)


static func road_center(k: int) -> float:
	return k * PITCH + ROAD * 0.5


## 블록 둘레 인도 한가운데를 도는 4꼭짓점 (시계 방향)
static func sidewalk_loop(block: Vector2i) -> PackedVector2Array:
	var r := block_rect(block.x, block.y).grow(-SIDEWALK * 0.5)
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## pos에서 가장 가까운 땅 블록 (강 위면 가까운 강변 블록)
static func nearest_block(pos: Vector2) -> Vector2i:
	var b := CityMap.block_at(pos)
	if CityMap.is_land(b):
		return b
	var best := Vector2i(clampi(b.x, CityMap.MIN.x, CityMap.MAX.x), clampi(b.y, CityMap.MIN.y, CityMap.MAX.y))
	var best_d := INF
	for dj in range(-2, 3):
		for di in range(-2, 3):
			var c := b + Vector2i(di, dj)
			if CityMap.is_land(c):
				var d := block_rect(c.x, c.y).get_center().distance_to(pos)
				if d < best_d:
					best_d = d
					best = c
	return best


## 세로 도로 k번의 오른쪽 갓길(상행)에 seg번째 구간, t(0~1) 위치. 위쪽을 향해 주차.
static func curb_vertical(k: int, seg: int, t: float) -> Vector2:
	return Vector2(road_center(k) + ROAD * 0.5 - 22.0, ROAD + seg * PITCH + BLOCK * t)


## 가로 도로 k번의 아래쪽 갓길(동행)에 seg번째 구간, t 위치. 오른쪽을 향해 주차.
static func curb_horizontal(k: int, seg: int, t: float) -> Vector2:
	return Vector2(ROAD + seg * PITCH + BLOCK * t, road_center(k) + ROAD * 0.5 - 22.0)


## 블록 정문 앞 인도 (블록 아래쪽 인도 가운데)
static func front_door(b: Vector2i) -> Vector2:
	var r := block_rect(b.x, b.y)
	return Vector2(r.get_center().x, r.end.y - SIDEWALK * 0.5)


## 강남 경찰서 정문 앞 인도
static func police_station_position() -> Vector2:
	return front_door(POLICE_STATION)


## 강남 병원 정문 앞 인도
static func hospital_position() -> Vector2:
	return front_door(HOSPITAL)


## pos에서 가장 가까운 열린 구역의 경찰서 정문 앞
static func nearest_police_station(pos: Vector2) -> Vector2:
	return _nearest_door(pos, true)


## pos에서 가장 가까운 열린 구역의 병원 정문 앞
static func nearest_hospital(pos: Vector2) -> Vector2:
	return _nearest_door(pos, false)


static func _nearest_door(pos: Vector2, police: bool) -> Vector2:
	var best := police_station_position() if police else hospital_position()
	var best_d := INF
	for d in CityMap.DISTRICTS:
		if d.chapter > CityMap.chapter:
			continue
		for b: Vector2i in (d.police_stations if police else d.hospitals):
			var door := front_door(b)
			if door.distance_to(pos) < best_d:
				best_d = door.distance_to(pos)
				best = door
	return best


## 강남 조직 본부 정문 앞 (블록 왼쪽 인도). 공중전화가 그 아래에 줄지어 있다
static func hq_door() -> Vector2:
	var b := block_rect(GANG_HQ.x, GANG_HQ.y)
	return Vector2(b.position.x + SIDEWALK * 0.5, b.position.y + BLOCK * 0.65)


## 본부 차고 앞 (블록 아래 가로 도로의 동행 차로) — 빼 온 차를 세우는 곳
static func hq_garage() -> Vector2:
	var b := block_rect(GANG_HQ.x, GANG_HQ.y)
	return Vector2(b.get_center().x, b.end.y + ROAD * 0.5 + 32.0)


## 은신처 문 앞 (블록 오른쪽 인도, 출발점 길 건너)
static func hideout_door() -> Vector2:
	var b := block_rect(HIDEOUT.x, HIDEOUT.y)
	return Vector2(b.end.x - SIDEWALK * 0.5, b.get_center().y)


## 카센터 정비 칸 (세로 도로 1번 오른쪽 갓길, 카센터 건물 옆)
static func spray_bay() -> Vector2:
	return curb_vertical(1, SPRAY_SHOP.y, 0.4)


## 창고 짐 내리는 곳 (블록 위 가로 도로의 동행 차로)
static func warehouse_dock() -> Vector2:
	var b := block_rect(WAREHOUSE.x, WAREHOUSE.y)
	return Vector2(b.get_center().x, b.position.y - ROAD * 0.5 + 48.0)


## 출발점: 세로 도로 3번 오른쪽 갓길의 첫 차 바로 옆 인도
static func start_position() -> Vector2:
	return curb_vertical(3, 3, 0.5) + Vector2(36.0, 0.0)


# ── 배치 ──────────────────────────────────────────────────

func _build_layout() -> void:
	buildings.clear()
	kinds.clear()
	parks.clear()
	park_kinds.clear()
	stations.clear()
	hospitals.clear()
	for j in range(CityMap.MIN.y, CityMap.MAX.y + 1):
		for i in range(CityMap.MIN.x, CityMap.MAX.x + 1):
			var cell := Vector2i(i, j)
			var dist := CityMap.district_of(cell)
			if dist == null or dist.plazas.has(cell):
				continue
			var inner := block_rect(i, j).grow(-SIDEWALK)
			var half := (inner.size - Vector2(ALLEY, ALLEY)) * 0.5
			if dist.police_stations.has(cell):
				stations.append(inner)
				if cell == POLICE_STATION:
					station = inner
				_add(inner, null, cell)
				continue
			if dist.hospitals.has(cell):
				hospitals.append(inner)
				if cell == HOSPITAL:
					hospital = inner
				_add(inner, null, cell)
				continue
			if cell == GANG_HQ:
				hq = inner
				_add(inner, _type(&"OFFICE"), cell)
				continue
			if cell == WAREHOUSE:
				warehouse = inner
				_add(inner, _type(&"WAREHOUSE"), cell)
				continue
			var rects: Array[Rect2] = []
			var footprint := 0
			match posmod(i * 7 + j * 13, 4):
				0:
					rects = [inner]
				1:
					footprint = 1
					rects = [Rect2(inner.position, Vector2(half.x, inner.size.y)),
						Rect2(inner.position + Vector2(half.x + ALLEY, 0), Vector2(half.x, inner.size.y))]
				2:
					footprint = 1
					rects = [Rect2(inner.position, Vector2(inner.size.x, half.y)),
						Rect2(inner.position + Vector2(0, half.y + ALLEY), Vector2(inner.size.x, half.y))]
				_:
					footprint = 2
					for oy in [0.0, half.y + ALLEY]:
						for ox in [0.0, half.x + ALLEY]:
							rects.append(Rect2(inner.position + Vector2(ox, oy), half))
			for n in rects.size():
				var r := rects[n]
				if cell == HIDEOUT and n == rects.size() - 1:
					hideout = r
					_add(r, _type(&"OFFICETEL"), cell)
				elif cell == SPRAY_SHOP and n == 0:
					spray = r
					_add(r, null, cell)
				else:
					_add(r, _pick_kind(dist, footprint, i * 131 + j * 37 + n * 11), cell)


func _add(r: Rect2, kind: BuildingType, cell: Vector2i) -> void:
	if kind and not kind.solid:
		parks.append(r)
		park_kinds.append(kind)
		return
	_owners[buildings.size()] = cell
	buildings.append(r)
	kinds.append(kind)


func _type(id: StringName) -> BuildingType:
	for t in BUILDING_TYPES:
		if t.id == id:
			return t
	return null


## 구역 비중으로 부지에 맞는 건물 종류를 고른다 (RNG 없이 seed로만 — 늘 같은 도시)
func _pick_kind(dist: DistrictType, footprint: int, seed: int) -> BuildingType:
	var total := 0.0
	for t in BUILDING_TYPES:
		if footprint in t.footprints:
			total += _weight(dist, t)
	var roll := float(posmod(seed * 2654435761, 1000)) / 1000.0 * total
	for t in BUILDING_TYPES:
		var w := _weight(dist, t)
		if footprint in t.footprints and w > 0.0:
			roll -= w
			if roll < 0.0:
				return t
	return BUILDING_TYPES[0]


static func _weight(dist: DistrictType, t: BuildingType) -> float:
	if dist.building_weights.is_empty():
		return t.weight
	return float(dist.building_weights.get(t.id, 0.0))


# ── 충돌 ──────────────────────────────────────────────────

func _build_collision() -> void:
	var body := StaticBody2D.new()
	add_child(body)
	var w := world_rect()
	var rects := buildings.duplicate()
	rects.append(Rect2(w.position.x - WALL, w.position.y - WALL, w.size.x + WALL * 2, WALL))
	rects.append(Rect2(w.position.x - WALL, w.end.y, w.size.x + WALL * 2, WALL))
	rects.append(Rect2(w.position.x - WALL, w.position.y, WALL, w.size.y))
	rects.append(Rect2(w.end.x, w.position.y, WALL, w.size.y))
	water = water_rects()
	rects.append_array(water)
	for r: Rect2 in rects:
		_add_box(body, r)


static func _add_box(body: StaticBody2D, r: Rect2) -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = r.size
	shape.shape = rect
	shape.position = r.get_center()
	body.add_child(shape)


## 강물 (물 블록 + 도로가 없는 물 위 구간·교차로). 차도 사람도 못 들어간다
static func water_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for j in range(CityMap.MIN.y, CityMap.MAX.y + 1):
		for i in range(CityMap.MIN.x, CityMap.MAX.x + 1):
			if CityMap.is_water(Vector2i(i, j)):
				result.append(block_rect(i, j))
	for j in range(CityMap.MIN.y, CityMap.MAX.y + 2):
		for i in range(CityMap.MIN.x, CityMap.MAX.x + 2):
			var c := Vector2i(i, j)
			if not CityMap.node_exists(c):
				result.append(node_rect(c))
			for d in [1, 2]:
				if CityMap.node_in_bounds(c + CityMap.STEPS[d]) and not CityMap.road(c, d):
					result.append(segment_rect(c, d))
	return result


## 교차로 상자
static func node_rect(c: Vector2i) -> Rect2:
	return Rect2(c.x * PITCH, c.y * PITCH, ROAD, ROAD)


## 교차로 c에서 d 방향 도로 구간의 사각형 (교차로 상자 제외)
static func segment_rect(c: Vector2i, d: int) -> Rect2:
	var a := node_rect(c)
	match d:
		1: return Rect2(a.end.x, a.position.y, BLOCK, ROAD)
		2: return Rect2(a.position.x, a.end.y, ROAD, BLOCK)
		0: return Rect2(a.position.x, a.position.y - BLOCK, ROAD, BLOCK)
		_: return Rect2(a.position.x - BLOCK, a.position.y, BLOCK, ROAD)


# ── 잠긴 구역 ─────────────────────────────────────────────

## 장이 바뀌면 부른다: 잠긴 블록에 담, 잠긴 교차로·도로에 충돌체와 바리케이드
func refresh_locks() -> void:
	locked_blocks.clear()
	barriers.clear()
	if _lock_body:
		_lock_body.queue_free()
	_lock_body = StaticBody2D.new()
	add_child(_lock_body)
	for j in range(CityMap.MIN.y, CityMap.MAX.y + 1):
		for i in range(CityMap.MIN.x, CityMap.MAX.x + 1):
			var b := Vector2i(i, j)
			if CityMap.is_land(b) and not CityMap.is_open_block(b):
				locked_blocks.append(b)
				_add_box(_lock_body, block_rect(i, j))
	for j in range(CityMap.MIN.y, CityMap.MAX.y + 2):
		for i in range(CityMap.MIN.x, CityMap.MAX.x + 2):
			var c := Vector2i(i, j)
			if not CityMap.node_exists(c) or CityMap.is_open_node(c):
				continue
			_add_box(_lock_body, node_rect(c))
			for d in 4:
				if not CityMap.road(c, d):
					continue
				_add_box(_lock_body, segment_rect(c, d))
				# 열린 교차로 바로 앞에 바리케이드를 그린다
				if CityMap.is_open_node(c + CityMap.STEPS[d]):
					var dir := Vector2(CityMap.STEPS[(d + 2) % 4])
					var start := node_rect(c + CityMap.STEPS[d]).get_center() + dir * (ROAD * 0.5)
					var across := Vector2(-dir.y, dir.x) * ROAD * 0.5
					var a := start + across + dir * 4.0
					var b := start - across + dir * 22.0
					barriers.append(Rect2(a, b - a).abs())
	if _lock_layer:
		_lock_layer.queue_redraw()
	_shade_locked_views()


func draw_locks(ci: CanvasItem) -> void:
	var font := ThemeDB.fallback_font
	for b in locked_blocks:
		var r := block_rect(b.x, b.y)
		ci.draw_rect(r, LOCK_SHADE)
		ci.draw_rect(r.grow(-4), Color(BARRIER, 0.55), false, 4.0)
	for r in barriers:
		ci.draw_rect(r, Color(0.1, 0.1, 0.1))
		var long := r.size.x > r.size.y
		var n := int((r.size.x if long else r.size.y) / 24.0)
		for k in n:
			if k % 2 == 0:
				var off := Vector2(k * 24.0, 0) if long else Vector2(0, k * 24.0)
				var size := Vector2(24, r.size.y) if long else Vector2(r.size.x, 24)
				ci.draw_rect(Rect2(r.position + off, size), BARRIER)
		ci.draw_rect(r, Color(1, 1, 1, 0.8), false, 2.0)
	# 구역마다 잠긴 이유를 한 번 적는다
	for d in CityMap.DISTRICTS:
		if d.chapter <= CityMap.chapter:
			continue
		var center := (block_rect(d.blocks.position.x, d.blocks.position.y).position
			+ block_rect(d.blocks.end.x - 1, d.blocks.end.y - 1).end) * 0.5
		ci.draw_string(font, center + Vector2(-300, -10), d.display_name, HORIZONTAL_ALIGNMENT_CENTER, 600, 54,
			Color(1, 1, 1, 0.35))
		ci.draw_string(font, center + Vector2(-300, 40), "통제 구역 — %d장에서 열린다" % d.chapter,
			HORIZONTAL_ALIGNMENT_CENTER, 600, 30, Color(BARRIER, 0.6))


# ── 그리기 ────────────────────────────────────────────────

func _make_chunks() -> void:
	var j := CityMap.MIN.y
	while j <= CityMap.MAX.y + 1:
		var i := CityMap.MIN.x
		while i <= CityMap.MAX.x + 1:
			var chunk := Chunk.new()
			chunk.city = self
			chunk.area = Rect2i(i, j, CHUNK, CHUNK)
			add_child(chunk)
			_chunks.append(chunk)
			i += CHUNK
		j += CHUNK


func _draw() -> void:
	draw_rect(world_rect(), WATER)


## 청크 하나: 그 안의 블록·교차로와, 그 안 교차로에서 동·남으로 뻗은 도로 구간
func draw_chunk(ci: CanvasItem, area: Rect2i) -> void:
	var font := ThemeDB.fallback_font
	for j in range(area.position.y, area.end.y):
		for i in range(area.position.x, area.end.x):
			var c := Vector2i(i, j)
			if CityMap.node_exists(c):
				ci.draw_rect(node_rect(c), ASPHALT)
			for d in [1, 2]:
				if CityMap.road(c, d):
					ci.draw_rect(segment_rect(c, d), ASPHALT)
	for j in range(area.position.y, area.end.y):
		for i in range(area.position.x, area.end.x):
			var b := Vector2i(i, j)
			if CityMap.is_water(b):
				_draw_water(ci, block_rect(i, j), b)
				continue
			var dist := CityMap.district_of(b)
			if dist == null:
				continue
			var r := block_rect(i, j)
			ci.draw_rect(r, dist.sidewalk)
			ci.draw_rect(r, CURB, false, 3.0)
			if dist.plazas.has(b):
				_draw_plaza(ci, r.grow(-SIDEWALK), b == PLAZA)
	for j in range(area.position.y, area.end.y):
		for i in range(area.position.x, area.end.x):
			var c := Vector2i(i, j)
			for d in [2, 1]:
				if not CityMap.road(c, d):
					continue
				var fl := CityMap.flanks(c, d)
				var water_sides: Array[float] = []
				if CityMap.is_water(fl[0]):
					water_sides.append(-1.0)
				if CityMap.is_water(fl[1]):
					water_sides.append(1.0)
				if d == 2:
					_draw_road_segment(ci, i, j, true, water_sides)
				else:
					_draw_road_segment(ci, j, i, false, water_sides)
			# 교차로 둘레 중 강 쪽 (도로가 끊긴 쪽) 난간
			if CityMap.node_exists(c):
				var box := node_rect(c)
				for d in 4:
					if CityMap.road(c, d):
						continue
					var corners := [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]
					var a: Vector2 = corners[d]
					var b: Vector2 = corners[(d + 1) % 4]
					var inward := Vector2(-CityMap.STEPS[d]) * 3.0
					ci.draw_line(a + inward, b + inward, RAIL, 6.0)
	for idx in parks.size():
		if area.has_point(CityMap.block_at(parks[idx].get_center())):
			BuildingDrawer.draw(ci, parks[idx], park_kinds[idx], idx, font)
	if IsoView.enabled:
		return   # 2.5D에서는 BuildingView가 벽과 지붕을 세워 그린다
	for idx in buildings.size():
		if area.has_point(_owners[idx]):
			_draw_building(ci, buildings[idx], idx, font)


# ── 2.5D 입체 건물 ────────────────────────────────────────

func _make_views() -> void:
	for idx in buildings.size():
		var r := buildings[idx]
		var kind := kinds[idx]
		var parts := BuildingView.split(r)
		var list: Array[BuildingView] = []
		for k in parts.size():
			var v := BuildingView.new()
			v.city = self
			v.idx = idx
			v.rect = r
			v.part = parts[k]
			v.roof = k == parts.size() - 1
			v.kind = kind
			v.height = building_height(idx)
			v.wall = kind.wall_color if kind else _special_wall(r)
			v.style = kind.style if kind else &"special"
			v.visible = IsoView.enabled
			add_child(v)
			list.append(v)
		_views[idx] = list
		if not _by_block.has(_owners[idx]):
			_by_block[_owners[idx]] = []
		_by_block[_owners[idx]].append(idx)


## 2.5D 건물 높이 (화면 px). 같은 종류라도 번호에 따라 한 층씩 들쭉날쭉하다
func building_height(idx: int) -> float:
	var r := buildings[idx]
	var kind := kinds[idx]
	var floors := 0
	if kind:
		floors = kind.floors
		if floors >= 3:
			floors += posmod(idx, 3) - 1
	elif stations.has(r):
		floors = STATION_FLOORS
	elif hospitals.has(r):
		floors = HOSPITAL_FLOORS
	else:
		floors = SPRAY_FLOORS
	return maxf(floors, 1) * IsoView.FLOOR_HEIGHT


func _special_wall(r: Rect2) -> Color:
	if stations.has(r):
		return Color(0.7, 0.72, 0.78)
	if hospitals.has(r):
		return Color(0.86, 0.86, 0.86)
	return Color(0.4, 0.4, 0.44)


## 2.5D ↔ 위에서 보기 전환 (IsoView.enabled를 바꾼 뒤 부른다)
func set_iso(on: bool) -> void:
	for idx: int in _views:
		for v: BuildingView in _views[idx]:
			v.visible = on
	for c in _chunks:
		c.queue_redraw()


func _process(delta: float) -> void:
	if not IsoView.enabled:
		return
	var cam := ChaseCamera.current_cam()
	if cam == null or cam.target == null or not is_instance_valid(cam.target):
		return
	var p := cam.target.global_position
	var head := p + IsoView.lift(14.0)
	# 주인공 둘레 블록의 건물과, 아직 흐린 건물만 본다
	var here := CityMap.block_at(p)
	var check := {}
	for idx: int in _fade:
		check[idx] = true
	for j in range(here.y - 1, here.y + 3):
		for i in range(here.x - 1, here.x + 3):
			for idx: int in _by_block.get(Vector2i(i, j), []):
				check[idx] = true
	for idx: int in check:
		var r := buildings[idx]
		var goal := 1.0
		if not r.has_point(p) and p.x < r.end.x and p.y < r.end.y \
				and Geometry2D.is_point_in_polygon(head, BuildingView.silhouette(r, building_height(idx))):
			goal = FADE_ALPHA
		var now: float = _fade.get(idx, 1.0)
		if is_equal_approx(now, goal):
			continue
		now = move_toward(now, goal, delta * 3.0)
		if is_equal_approx(now, 1.0):
			_fade.erase(idx)
		else:
			_fade[idx] = now
		for v: BuildingView in _views[idx]:
			v.modulate.a = now


## 잠긴 구역의 건물은 어둡게
func _shade_locked_views() -> void:
	for idx: int in _views:
		var locked := locked_blocks.has(_owners[idx])
		for v: BuildingView in _views[idx]:
			v.self_modulate = Color(0.38, 0.38, 0.45) if locked else Color.WHITE


func _draw_water(ci: CanvasItem, r: Rect2, b: Vector2i) -> void:
	for k in 5:
		var y := r.position.y + 60 + k * 110 + posmod(b.x * 37 + k * 13, 40)
		var x := r.position.x + 40 + posmod(b.y * 53 + k * 71, 200)
		ci.draw_line(Vector2(x, y), Vector2(x + 90, y), WATER_LIGHT, 3.0)
		ci.draw_line(Vector2(x + 140, y + 40), Vector2(x + 200, y + 40), WATER_LIGHT, 2.0)


## vertical=true면 k번째 세로 도로의 seg번째 구간
## water_sides: 강에 닿은 쪽 (-1 = 왼쪽·위, 1 = 오른쪽·아래)에 난간을 친다. 양쪽 다 강이면 다리.
func _draw_road_segment(ci: CanvasItem, k: int, seg: int, vertical: bool, water_sides: Array[float]) -> void:
	var bridge := water_sides.size() == 2
	var c := road_center(k)
	var a := ROAD + seg * PITCH
	var b := a + BLOCK
	var p := func(along: float, across: float) -> Vector2:
		return Vector2(c + across, along) if vertical else Vector2(along, c + across)

	for side in water_sides:
		ci.draw_line(p.call(a - 4, side * (ROAD * 0.5 + 4)), p.call(b + 4, side * (ROAD * 0.5 + 4)), Color(0, 0, 0, 0.35), 6.0)
		ci.draw_line(p.call(a - 4, side * (ROAD * 0.5 - 3)), p.call(b + 4, side * (ROAD * 0.5 - 3)), RAIL, 6.0)
	if bridge:
		# 다리 교각
		for t in [0.25, 0.75]:
			var at: float = lerpf(a, b, t)
			for side in [-1.0, 1.0]:
				var q: Vector2 = p.call(at, side * (ROAD * 0.5 + 16))
				ci.draw_rect(Rect2(q - Vector2(10, 10), Vector2(20, 20)), Color(0.3, 0.32, 0.36))
	ci.draw_line(p.call(a + 48, -3.0), p.call(b - 48, -3.0), LANE_YELLOW, 2.0)
	ci.draw_line(p.call(a + 48, 3.0), p.call(b - 48, 3.0), LANE_YELLOW, 2.0)
	var y := a + 60.0
	while y < b - 72.0:
		for lane in [-ROAD * 0.25, ROAD * 0.25]:
			ci.draw_line(p.call(y, lane), p.call(y + 24, lane), LANE_WHITE, 2.0)
		y += 56.0
	# 정지선 (우측통행). 세로 도로: 위쪽 끝엔 북행이 +x 절반으로, 아래쪽 끝엔 남행이 -x 절반으로 들어온다.
	# 가로 도로: 왼쪽 끝엔 서행이 -y 절반으로, 오른쪽 끝엔 동행이 +y 절반으로 들어온다.
	var side := 1.0 if vertical else -1.0
	var stop := Color(0.9, 0.9, 0.9, 0.8)
	if bridge:
		return
	ci.draw_line(p.call(a + STOP_LINE, 0.0), p.call(a + STOP_LINE, side * (ROAD * 0.5 - 4.0)), stop, 4.0)
	ci.draw_line(p.call(b - STOP_LINE, 0.0), p.call(b - STOP_LINE, -side * (ROAD * 0.5 - 4.0)), stop, 4.0)
	# 교차로 앞 횡단보도
	for start in [a + 4.0, b - 40.0]:
		var x := -ROAD * 0.5 + 12.0
		while x < ROAD * 0.5 - 12.0:
			var r0: Vector2 = p.call(start, x)
			var r1: Vector2 = p.call(start + 36.0, x + 10.0)
			ci.draw_rect(Rect2(r0, r1 - r0).abs(), Color(0.9, 0.9, 0.9, 0.55))
			x += 20.0


func _draw_plaza(ci: CanvasItem, r: Rect2, practice: bool) -> void:
	ci.draw_rect(r, Color(0.19, 0.20, 0.25))
	var x := r.position.x + 40
	while x < r.end.x - 40:
		ci.draw_line(Vector2(x, r.position.y + 20), Vector2(x, r.position.y + 90), LANE_WHITE, 2.0)
		ci.draw_line(Vector2(x, r.end.y - 90), Vector2(x, r.end.y - 20), LANE_WHITE, 2.0)
		x += 44
	if practice:
		ci.draw_string(ThemeDB.fallback_font, r.get_center() + Vector2(-120, 10), "드리프트 연습장",
			HORIZONTAL_ALIGNMENT_CENTER, 240, 28, Color(1, 1, 1, 0.25))


func _draw_building(ci: CanvasItem, r: Rect2, idx: int, font: Font) -> void:
	if stations.has(r):
		_draw_station(ci, r, font)
	elif hospitals.has(r):
		_draw_hospital(ci, r, font)
	elif r == hq:
		_draw_hq(ci, r, font)
	elif r == hideout:
		_draw_hideout(ci, r, font)
	elif r == warehouse:
		_draw_warehouse(ci, r, font)
	elif r == spray:
		_draw_spray_shop(ci, r, font)
	else:
		BuildingDrawer.draw(ci, r, kinds[idx], idx, font)


## 경찰서: 흰 지붕에 파란 테두리, 옥상 헬기장, 정문 위 간판
func _draw_station(ci: CanvasItem, r: Rect2, font: Font) -> void:
	var navy := Color(0.12, 0.2, 0.45)
	if BuildingDrawer.shadows:
		ci.draw_rect(Rect2(r.position + Vector2(10, 12), r.size), Color(0, 0, 0, 0.4))
	ci.draw_rect(r, Color(0.78, 0.8, 0.84))
	ci.draw_rect(r.grow(-10), navy, false, 6.0)
	ci.draw_rect(r, navy.darkened(0.4), false, 3.0)
	var c := r.get_center() + Vector2(0, -30)
	ci.draw_arc(c, 70, 0, TAU, 40, Color(0.95, 0.8, 0.15), 5.0)
	ci.draw_string(font, c + Vector2(-40, 24), "H", HORIZONTAL_ALIGNMENT_CENTER, 80, 72, Color(0.95, 0.8, 0.15))
	_draw_front_sign(ci, r, font, "경 찰 서", navy, Color(0.4, 0.6, 1.0), Color.WHITE)


## 병원: 흰 지붕에 빨간 십자, 정문 위 간판
func _draw_hospital(ci: CanvasItem, r: Rect2, font: Font) -> void:
	var red := Color(0.85, 0.12, 0.15)
	if BuildingDrawer.shadows:
		ci.draw_rect(Rect2(r.position + Vector2(10, 12), r.size), Color(0, 0, 0, 0.4))
	ci.draw_rect(r, Color(0.9, 0.9, 0.9))
	ci.draw_rect(r.grow(-10), Color(0.7, 0.72, 0.75), false, 4.0)
	ci.draw_rect(r, Color(0.45, 0.46, 0.5), false, 3.0)
	var c := r.get_center() + Vector2(0, -30)
	ci.draw_rect(Rect2(c - Vector2(22, 70), Vector2(44, 140)), red)
	ci.draw_rect(Rect2(c - Vector2(70, 22), Vector2(140, 44)), red)
	_draw_front_sign(ci, r, font, "병 원", Color.WHITE, red, red)


## 정문 위 간판 하나 (아래쪽 면 가운데)
static func _draw_front_sign(ci: CanvasItem, r: Rect2, font: Font, text: String, bg: Color, edge: Color, ink: Color, width := 180.0) -> void:
	var sign := Rect2(r.get_center().x - width * 0.5, r.end.y - 40, width, 30)
	ci.draw_rect(sign.grow(5), Color(edge, 0.2))
	ci.draw_rect(sign, bg)
	ci.draw_rect(sign, edge, false, 2.0)
	ci.draw_string(font, Vector2(sign.position.x, sign.end.y - 7), text,
		HORIZONTAL_ALIGNMENT_CENTER, sign.size.x, 22, ink)


## 강남 조직 본부: 위장 회사 '금강개발'. 검은 유리 지붕에 금색 테
func _draw_hq(ci: CanvasItem, r: Rect2, font: Font) -> void:
	var gold := Color(0.95, 0.75, 0.25)
	if BuildingDrawer.shadows:
		ci.draw_rect(Rect2(r.position + Vector2(10, 12), r.size), Color(0, 0, 0, 0.45))
	ci.draw_rect(r, Color(0.08, 0.08, 0.1))
	var y := r.position.y + 24
	while y < r.end.y - 60:
		ci.draw_line(Vector2(r.position.x + 18, y), Vector2(r.end.x - 18, y), Color(0.16, 0.18, 0.24), 6.0)
		y += 26
	ci.draw_rect(r.grow(-8), gold, false, 3.0)
	ci.draw_rect(r, Color(0.02, 0.02, 0.03), false, 3.0)
	# 왼쪽 정문 (공중전화가 있는 인도 쪽)
	var door := Vector2(r.position.x, hq_door().y)
	ci.draw_rect(Rect2(door - Vector2(0, 26), Vector2(14, 52)), gold.darkened(0.3))
	ci.draw_string(font, r.get_center() + Vector2(-140, -10), "금강", HORIZONTAL_ALIGNMENT_CENTER, 280, 64, Color(gold, 0.35))
	_draw_front_sign(ci, r, font, "금강개발(주)", Color(0.05, 0.05, 0.06), gold, gold)


## 은신처: 평범한 오피스텔. 오른쪽 문에 초록 등
func _draw_hideout(ci: CanvasItem, r: Rect2, font: Font) -> void:
	var roof := Color(0.3, 0.34, 0.36)
	if BuildingDrawer.shadows:
		ci.draw_rect(Rect2(r.position + Vector2(10, 12), r.size), Color(0, 0, 0, 0.4))
	ci.draw_rect(r, roof)
	for row in 6:
		for col in 3:
			var cell := Rect2(r.position + Vector2(18 + col * (r.size.x - 36) / 3.0, 24 + row * (r.size.y - 90) / 6.0),
				Vector2((r.size.x - 36) / 3.0 - 10, 18))
			ci.draw_rect(cell, roof.lightened(0.08))
	ci.draw_rect(r, roof.darkened(0.45), false, 3.0)
	var door := Vector2(r.end.x, hideout_door().y)
	ci.draw_rect(Rect2(door - Vector2(10, 18), Vector2(10, 36)), Color(0.3, 1.0, 0.5, 0.8))
	_draw_front_sign(ci, r, font, "오피스텔", Color(0.12, 0.2, 0.16), Color(0.4, 1.0, 0.6), Color(0.85, 1.0, 0.9), 150.0)


## 창고: 골함석 지붕과 위쪽 셔터 문
func _draw_warehouse(ci: CanvasItem, r: Rect2, font: Font) -> void:
	var roof := Color(0.42, 0.45, 0.4)
	if BuildingDrawer.shadows:
		ci.draw_rect(Rect2(r.position + Vector2(10, 12), r.size), Color(0, 0, 0, 0.4))
	ci.draw_rect(r, roof)
	var x := r.position.x + 12
	while x < r.end.x - 8:
		ci.draw_line(Vector2(x, r.position.y + 6), Vector2(x, r.end.y - 6), roof.darkened(0.2), 3.0)
		x += 16
	ci.draw_rect(r, roof.darkened(0.5), false, 3.0)
	for k in 3:
		var dx := r.position.x + r.size.x * (0.25 + 0.25 * k)
		ci.draw_rect(Rect2(dx - 40, r.position.y, 80, 14), Color(0.85, 0.65, 0.15))
	_draw_front_sign(ci, r, font, "물류 창고", Color(0.25, 0.25, 0.22), Color(0.95, 0.7, 0.2), Color(1.0, 0.9, 0.6), 150.0)


## 카센터: 왼쪽 벽에 정비 칸 셔터, 지붕에 스프레이 얼룩
func _draw_spray_shop(ci: CanvasItem, r: Rect2, font: Font) -> void:
	var roof := Color(0.3, 0.3, 0.33)
	if BuildingDrawer.shadows:
		ci.draw_rect(Rect2(r.position + Vector2(10, 12), r.size), Color(0, 0, 0, 0.4))
	ci.draw_rect(r, roof)
	var colors := [Color(0.9, 0.2, 0.25), Color(0.2, 0.6, 0.95), Color(0.95, 0.8, 0.2), Color(0.3, 0.85, 0.4)]
	for k in colors.size():
		ci.draw_circle(r.get_center() + Vector2(-90 + k * 60, -20 + (k % 2) * 30), 22.0, Color(colors[k], 0.45))
	ci.draw_rect(r, roof.darkened(0.5), false, 3.0)
	var door_y := spray_bay().y
	ci.draw_rect(Rect2(r.position.x, door_y - 40, 12, 80), Color(0.85, 0.65, 0.15))
	for yy in range(int(door_y) - 36, int(door_y) + 40, 8):
		ci.draw_line(Vector2(r.position.x + 1, yy), Vector2(r.position.x + 11, yy), Color(0.5, 0.38, 0.1), 1.0)
	_draw_front_sign(ci, r, font, "카센터 · 도색", Color(0.12, 0.12, 0.15), Color(0.3, 0.8, 1.0), Color(0.8, 0.95, 1.0), 170.0)
