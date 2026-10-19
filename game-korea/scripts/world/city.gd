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
const CHUNK := 1                 ## 청크 하나의 블록 수 (가로·세로). 1이면 화면에 걸친 블록만 그린다 — 크면 화면 밖 블록까지 매 프레임 그린다
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
## 2.5D 기능 건물 겉모습 (SpecialBuilding). 충돌·위에서 보기는 그대로 두고 2.5D 모양만 바꾼다 (looks).
## 경찰서·병원·본부·카센터는 정해 둔 부지, 갱 아지트는 공중전화 묶음 옆 건물(GangType.base_look),
## 사우나·편의점은 자동 배치 부지에 흩뿌린다(BuildingType.replaces·scatter).
const LOOK_POLICE := preload("res://data/buildings/special/police.tres")
const LOOK_HOSPITAL := preload("res://data/buildings/special/hospital.tres")
const LOOK_CAR_CENTER := preload("res://data/buildings/special/car_center.tres")
const SCATTER_LOOKS: Array[BuildingType] = [
	preload("res://data/buildings/special/sauna.tres"),
	preload("res://data/buildings/special/convenience.tres"),
]
## 각 구역에서 기존 기능 건물을 제외한 부지 하나에 랜드마크를 고정 배치한다.
const LANDMARK_PLACEMENTS := [

	["landmark_tower", &"jongno", Vector2i(2,-6)],
	["market", &"jongno", Vector2i(0,-8)],
	["terminal", &"gangnam", Vector2i(0,1)],
	["broadcast", &"yeouido", Vector2i(-3,-2)],
	["industrial_dock", &"industrial", Vector2i(-4,0)],
	["church", &"jongno", Vector2i(4,-6)],
	["motel", &"gangnam", Vector2i(4,2)],
	["gas_station", &"industrial", Vector2i(-2,2)],
	["nightlife", &"hongdae", Vector2i(-2,-7)],
	["parking_tower", &"gangnam", Vector2i(3,1)],
	["school", &"jongno", Vector2i(3,-8)],
	["subway", &"hongdae", Vector2i(-4,-6)],
	["fire_station", &"industrial", Vector2i(-2,4)],
	["finance_tower", &"yeouido", Vector2i(-2,-2)],
	["print_alley", &"jongno", Vector2i(1,-7)],
]
var landmark_indices := {}
## 블록 → 그 블록 랜드마크 부지 안 공터를 오가는 보행자 길들 (PedestrianManager가 인도 대신 쓰기도 한다)
static var lot_loops := {}

const GANGS: Array[GangType] = [
	preload("res://data/gangs/gangnam.tres"),
	preload("res://data/gangs/oldtown.tres"),
	preload("res://data/gangs/smuggler.tres"),
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
var looks := {}                          ## 건물 번호 → 2.5D 기능 건물 겉모습 (경찰서·병원·아지트·정비소·사우나·편의점)
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
var _bridge_layer: Node2D
var _owners := {}                        ## 건물 번호 → 블록 (청크 그리기용)
var _views := {}                         ## 건물 번호 → Array[BuildingView] (2.5D 입체 건물, 덩어리마다 조각들)
var _tops := {}                          ## 건물 번호 → 2.5D 꼭대기 높이
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
	var layer := 0                 ## 0 아스팔트 · 1 인도·강 · 2 차선·난간·공원·마당 (청크 경계를 넘어도 이 순서로 겹친다)

	func _draw() -> void:
		city.draw_chunk(self, area, layer)


## 2.5D 다리: 강물 위로 띄운 상판·교각·난간 (위에서 보기에서는 청크가 평면으로 그린다)
class BridgeLayer extends Node2D:
	var city: City

	func _draw() -> void:
		if IsoView.enabled:
			city.draw_bridges(self)


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
	_bridge_layer = BridgeLayer.new()
	_bridge_layer.city = self
	add_child(_bridge_layer)
	OverpassView.build(self)
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

	_assign_looks()
	_assign_landmarks()


## 2.5D 기능 건물 겉모습을 정한다 (RNG 없이 건물 번호로만 — 늘 같은 도시)
func _assign_looks() -> void:
	looks.clear()
	for idx in buildings.size():
		var r := buildings[idx]
		if stations.has(r):
			looks[idx] = LOOK_POLICE
		elif hospitals.has(r):
			looks[idx] = LOOK_HOSPITAL
		elif r == spray:
			looks[idx] = LOOK_CAR_CENTER
		elif r == hq:
			looks[idx] = GANGS[0].base_look
	# 갱 아지트: 공중전화 묶음마다 가장 가까운 보통 건물
	for gang in GANGS:
		if gang.base_look == null:
			continue
		for k in range(0, gang.phones.size(), 3):
			var best := -1
			var best_d := INF
			for idx in buildings.size():
				var d := _rect_distance(buildings[idx], gang.phones[k])
				if d < best_d:
					best_d = d
					best = idx
			if best >= 0 and not looks.has(best) and kinds[best] != null and buildings[best] != hideout:
				looks[best] = gang.base_look
	# 사우나·편의점: 원래 종류가 replaces에 있고 부지 크기가 맞는 건물 중 일부
	for idx in buildings.size():
		var kind := kinds[idx]
		var r := buildings[idx]
		if looks.has(idx) or kind == null or r == hideout or r == warehouse:
			continue
		for k in SCATTER_LOOKS.size():
			var look := SCATTER_LOOKS[k]
			if kind.id in look.replaces and _footprint(r) in look.footprints \
					and BuildingModel.hash01(idx, 600 + k * 17) < look.scatter:
				looks[idx] = look
				break


func _assign_landmarks() -> void:
	landmark_indices.clear()
	lot_loops.clear()
	for spec in LANDMARK_PLACEMENTS:
		var best := -1
		var score := INF
		for idx in buildings.size():
			var r := buildings[idx]
			if looks.has(idx) or kinds[idx] == null or r == hideout or r == warehouse:
				continue
			var dist := CityMap.district_of(_owners[idx])
			if dist == null or dist.id != spec[1]:
				continue
			var d := Vector2(_owners[idx]).distance_squared_to(Vector2(spec[2])) * 1000000.0 - r.get_area()
			if _footprint(r) != 0:
				d += 1000000000.0
			if d < score:
				score = d
				best = idx
		if best >= 0:
			looks[best] = load("res://data/buildings/landmarks/%s.tres" % spec[0])
			landmark_indices[spec[0]] = best
			var loops := LandmarkBuilding.walk_loops(buildings[best], looks[best])
			if not loops.is_empty():
				lot_loops[_owners[best]] = (lot_loops.get(_owners[best], []) as Array) + Array(loops)   # 한 블록에 둘이면 합친다


## 랜드마크 공터에 세워 둘 차 [위치, 방향] (열린 구역만). 차종은 Main이 정한다
func landmark_parking() -> Array:
	var out := []
	for key in landmark_indices:
		var idx: int = landmark_indices[key]
		if CityMap.is_open_block(_owners[idx]):
			out.append_array(LandmarkBuilding.parking(buildings[idx], looks[idx]))
	var site := work_site()
	if not site.is_empty():
		out.append_array(site.spots)
	return out


## 4장 외곽 공단 도로 공사 현장: 세로 도로 WORK_ROAD의 동쪽(북행) 바깥 차선을 라바콘으로 막고 굴삭기·불도저를 세운다.
## 안쪽 차선은 열려 있어 차가 비켜 지나간다 (교통 AI는 서 있는 차를 추월한다). 그 구역이 닫혀 있으면 빈 사전
const WORK_ROAD := Vector2i(-4, 2)          ## (세로 도로 번호, 구간)
const WORK_EXCAVATOR := "res://data/vehicles/heavy_excavator.tres"
const WORK_DOZER := "res://data/vehicles/heavy_dozer.tres"


static func work_site() -> Dictionary:
	var block := Vector2i(WORK_ROAD.x, WORK_ROAD.y)
	if not CityMap.is_open_block(block):
		return {}
	var at := func(t: float) -> Vector2: return curb_vertical(WORK_ROAD.x, WORK_ROAD.y, t)
	var lane_x: float = at.call(0.5).x - 32.0               # 막은 차선의 안쪽 경계 (라바콘 줄)
	var cones: Array[Vector2] = []
	var t := 0.16
	while t <= 0.86:
		cones.append(Vector2(lane_x, at.call(t).y))
		t += 0.07
	for k in 3:                                              # 남쪽(차가 오는 쪽) 끝은 비스듬히 차선을 좁힌다
		cones.append(Vector2(lane_x + 14.0 * (k + 1), at.call(0.86).y + 30.0 * (k + 1)))
	var road_edge := road_center(WORK_ROAD.x) + ROAD * 0.5
	return {
		"spots": [[at.call(0.34), 0.0, WORK_EXCAVATOR], [at.call(0.66), 0.0, WORK_DOZER]],
		"cones": cones,
		"sign": Vector2(lane_x + 8.0, at.call(0.86).y + 130.0),
		"pile": Vector2(road_edge + SIDEWALK * 0.5 + 8.0, at.call(0.48).y),
	}


static func _rect_distance(r: Rect2, p: Vector2) -> float:
	return (p - p.clamp(r.position, r.end)).length()


## 부지 크기 → 0 블록 통째 · 1 블록 절반 · 2 블록 1/4
static func _footprint(r: Rect2) -> int:
	var full := BLOCK - SIDEWALK * 2.0 - 1.0
	if r.size.x >= full and r.size.y >= full:
		return 0
	return 1 if r.size.x >= full or r.size.y >= full else 2


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
	body.collision_layer = Layers.WORLD
	add_child(body)
	var w := world_rect()
	var rects: Array[Rect2] = []
	for idx in buildings.size():
		# 사람과 차량이 공유하는 물리 장애물. 부지 전체 대신 실제 벽/기둥만 막는다.
		rects.append_array(BuildingModel.ground_obstacles(_pieces(idx)))
		var ground_kind := _ground_kind(idx)
		if ground_kind and ground_kind.style in [&"house", &"hanok"]:
			rects.append_array(BuildingModel.yard_walls(buildings[idx]))
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
	for layer in 3:
		var j := CityMap.MIN.y
		while j <= CityMap.MAX.y + 1:
			var i := CityMap.MIN.x
			while i <= CityMap.MAX.x + 1:
				var chunk := Chunk.new()
				chunk.city = self
				chunk.area = Rect2i(i, j, CHUNK, CHUNK)
				chunk.layer = layer
				add_child(chunk)
				_chunks.append(chunk)
				i += CHUNK
			j += CHUNK


func _draw() -> void:
	draw_rect(world_rect(), WATER)


## 청크 하나: 그 안의 블록·교차로와, 그 안 교차로에서 동·남으로 뻗은 도로 구간.
## layer마다 따로 그린다 — 모든 청크의 아스팔트 위에 인도, 그 위에 차선을 얹어야 블록 경계에서 연석이 덮이지 않는다
func draw_chunk(ci: CanvasItem, area: Rect2i, layer := -1) -> void:
	var font := ThemeDB.fallback_font
	if layer <= 0:
		_draw_chunk_asphalt(ci, area)
	if layer < 0 or layer == 1:
		_draw_chunk_blocks(ci, area)
	if layer < 0 or layer == 2:
		_draw_chunk_roads(ci, area, font)


func _draw_chunk_asphalt(ci: CanvasItem, area: Rect2i) -> void:
	for j in range(area.position.y, area.end.y):
		for i in range(area.position.x, area.end.x):
			var c := Vector2i(i, j)
			if CityMap.node_exists(c) and not _on_deck(c):
				RoadDetail.asphalt(ci, node_rect(c))
			for d in [1, 2]:
				if CityMap.road(c, d) and not (IsoView.enabled and CityMap.is_bridge(c, d)):
					RoadDetail.asphalt(ci, segment_rect(c, d))


func _draw_chunk_blocks(ci: CanvasItem, area: Rect2i) -> void:
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
			RoadDetail.pavement(ci, r)
			ci.draw_rect(r, CURB, false, 3.0)
			if dist.plazas.has(b):
				_draw_plaza(ci, r.grow(-SIDEWALK), b == PLAZA)


func _draw_chunk_roads(ci: CanvasItem, area: Rect2i, font: Font) -> void:
	for j in range(area.position.y, area.end.y):
		for i in range(area.position.x, area.end.x):
			var c := Vector2i(i, j)
			for d in [2, 1]:
				if not CityMap.road(c, d) or (IsoView.enabled and CityMap.is_bridge(c, d)) or CityMap.over_strip(c, d):
					continue   # 다리·고가 구간의 차선은 상판이 그린다
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
			# 고가차도가 넘는 교차로 밑 그늘
			if IsoView.enabled and CityMap.over_axis(c) >= 0:
				ci.draw_rect(node_rect(c), OverpassView.UNDER)
			# 교차로 둘레 중 강 쪽 (도로가 끊긴 쪽) 난간
			if CityMap.node_exists(c) and not _on_deck(c):
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
		# 2.5D: 바닥(마당·화단·담장)만 그리고, 벽과 지붕은 BuildingView가 세워 그린다
		for idx in buildings.size():
			if area.has_point(_owners[idx]):
				BuildingModel.draw_ground(ci, buildings[idx], _ground_kind(idx), idx)
		return
	for idx in buildings.size():
		if area.has_point(_owners[idx]):
			_draw_building(ci, buildings[idx], idx, font)


# ── 2.5D 입체 건물 ────────────────────────────────────────

func _make_views() -> void:
	for idx in buildings.size():
		var list: Array[BuildingView] = []
		var top := 0.0
		for p in _pieces(idx):
			for v in BuildingView.make(self, self, idx, p):
				v.visible = IsoView.enabled
				list.append(v)
			top = maxf(top, p.top())
		_views[idx] = list
		_tops[idx] = top
		if not _by_block.has(_owners[idx]):
			_by_block[_owners[idx]] = []
		_by_block[_owners[idx]].append(idx)


## 건물 하나의 2.5D 덩어리들. 특수 건물은 부지 꽉 찬 상자에 위에서 본 지붕 그림
func _pieces(idx: int) -> Array[BuildingModel.Piece]:
	var r := buildings[idx]
	var kind := kinds[idx]
	var h := building_height(idx)
	if looks.has(idx):
		return BuildingModel.build(r, looks[idx], idx, h)
	if kind == null or r == hq or r == hideout:
		var windows := &"glass" if kind and kind.style == &"office" else (&"officetel" if kind else &"punched")
		return BuildingModel.special(r, h, kind.wall_color if kind else _special_wall(r), windows, idx)
	return BuildingModel.build(r, kind, idx, h)


## 2.5D에서 건물이 화면에 차지하는 높이 (지붕·굴뚝 포함) — 주인공을 가리는지 볼 때 쓴다
func building_top(idx: int) -> float:
	return _tops.get(idx, building_height(idx))


## 2.5D 건물 높이 (화면 px). 같은 종류라도 번호에 따라 한 층씩 들쭉날쭉하다
func building_height(idx: int) -> float:
	var r := buildings[idx]
	var kind := kinds[idx]
	var floors := 0
	if looks.has(idx):
		floors = looks[idx].floors
	elif kind:
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


## 바닥 그림 종류 (특수 건물은 부지를 꽉 채우므로 없음)
func _ground_kind(idx: int) -> BuildingType:
	if looks.has(idx):
		return looks[idx]
	var r := buildings[idx]
	return null if r == hq or r == hideout else kinds[idx]


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
	_bridge_layer.queue_redraw()


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
		if looks.has(idx) and LandmarkBuilding.owns(looks[idx].style):
			_fade_pieces(idx, p, head, delta)
			continue
		var r := buildings[idx]
		var goal := 1.0
		if not r.has_point(p) and p.x < r.end.x and p.y < r.end.y \
				and Geometry2D.is_point_in_polygon(head, BuildingView.silhouette(r, building_top(idx))):
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


## 랜드마크는 부지 안 공터를 걸어 다닌다: 부지 전체가 아니라 주인공을 가리는 덩어리(탑·캐노피·크레인…)만 흐린다
func _fade_pieces(idx: int, p: Vector2, head: Vector2, delta: float) -> void:
	var faded := false
	for v: BuildingView in _views[idx]:
		var r := v.rect
		var goal := 1.0
		if p.x < r.end.x and p.y < r.end.y and Geometry2D.is_point_in_polygon(head, BuildingView.silhouette(r, v.height)):
			goal = FADE_ALPHA
		v.modulate.a = move_toward(v.modulate.a, goal, delta * 3.0)
		faded = faded or v.modulate.a < 1.0
	if faded:
		_fade[idx] = FADE_ALPHA
	else:
		_fade.erase(idx)


## 잠긴 구역의 건물은 어둡게
func _shade_locked_views() -> void:
	for idx: int in _views:
		var locked := locked_blocks.has(_owners[idx])
		for v: BuildingView in _views[idx]:
			v.self_modulate = Color(0.38, 0.38, 0.45) if locked else Color.WHITE
			if v.glow:
				v.glow.visible = not locked   # 잠긴 구역은 불도 꺼져 있다


## 2.5D에서 다리 상판이 덮는 강 한가운데 교차로 (BridgeLayer가 띄워 그린다)
static func _on_deck(c: Vector2i) -> bool:
	if not IsoView.enabled or not CityMap.BRIDGES.has(c.x):
		return false
	for b in CityMap.node_blocks(c):
		if CityMap.is_land(b):
			return false
	return true


const DECK_SLAB := 7.0          ## 다리 상판 두께 (화면 px)
const DECK_RAIL := 6.0          ## 난간 높이
const PIER_GAP := 300.0         ## 교각 사이 (월드 px)
const CONCRETE := Color(0.5, 0.51, 0.55)
const DECK_STEP := 24.0         ## 상판을 나눠 그리는 간격 (경사로가 매끈하게)


## 2.5D 다리: 물 위 그림자 → 교각 → 상판 옆면 → 상판 → 차선 → 난간 순으로 그린다
func draw_bridges(ci: CanvasItem) -> void:
	var hw := ROAD * 0.5
	for k in CityMap.BRIDGES:
		var cx := road_center(k)
		for span in CityMap.bridge_spans(k):
			var ys: Array[float] = []
			var y := span.x
			while y < span.y:
				ys.append(y)
				y += DECK_STEP
			ys.append(span.y)
			var hs: Array[float] = []
			for v in ys:
				hs.append(CityMap.deck_height_at(span, v))
			var at := func(x: float, i: int, dh := 0.0) -> Vector2:
				return Vector2(x, ys[i]) + IsoView.lift(maxf(hs[i] + dh, 0.0))
			# 물 위 그림자 (상판이 떠 있는 만큼 오른쪽 아래로 드러난다)
			ci.draw_rect(Rect2(cx - hw, span.x, ROAD, span.y - span.x), Color(0, 0, 0, 0.32))
			# 교각: 물에서 상판 밑까지 기둥 둘과 가로보
			var ramp := minf(CityMap.RAMP, (span.y - span.x) * 0.4)
			var n := maxi(1, int((span.y - span.x - ramp) / PIER_GAP))
			for p in n:
				var py := lerpf(span.x + ramp * 0.5, span.y - ramp * 0.5, (p + 0.5) / n)
				var top := CityMap.deck_height_at(span, py) - DECK_SLAB
				if top < 6.0:
					continue
				# 물에 닿는 받침 (물결 테)
				for sx in [-1.0, 1.0]:
					var foot := Vector2(cx + sx * (hw - 20.0), py)
					ci.draw_circle(foot + Vector2(4, 4), 26.0, Color(WATER_LIGHT, 0.35))
					_pillar(ci, Rect2(foot - Vector2(16, 16), Vector2(32, 32)), 0.0, top)
				_pillar(ci, Rect2(cx - hw + 2.0, py - 12.0, ROAD - 4.0, 24.0), top - 8.0, top)
			# 상판 옆면 (오른쪽 아래를 보는 동쪽 면)
			for i in ys.size() - 1:
				ci.draw_primitive(PackedVector2Array([at.call(cx + hw, i), at.call(cx + hw, i + 1),
					at.call(cx + hw, i + 1, -DECK_SLAB), at.call(cx + hw, i, -DECK_SLAB)]),
					PackedColorArray([CONCRETE.darkened(0.3)]), PackedVector2Array())
			# 상판 (아스팔트)
			for i in ys.size() - 1:
				ci.draw_primitive(PackedVector2Array([at.call(cx - hw, i), at.call(cx + hw, i),
					at.call(cx + hw, i + 1), at.call(cx - hw, i + 1)]),
					PackedColorArray([ASPHALT]), PackedVector2Array())
			# 차선: 가운데 노랑 겹선, 흰 점선
			for off in [-3.0, 3.0]:
				var line := PackedVector2Array()
				for i in ys.size():
					line.append(at.call(cx + off, i))
				ci.draw_polyline(line, LANE_YELLOW, 2.0)
			for i in ys.size() - 1:
				if i % 2 == 0:
					for lane in [-ROAD * 0.25, ROAD * 0.25]:
						ci.draw_line(at.call(cx + lane, i), at.call(cx + lane, i + 1), LANE_WHITE, 2.0)
			# 난간: 서쪽은 안쪽 면, 동쪽은 바깥 면이 보인다. 윗선은 밝게
			for x in [cx - hw + 3.0, cx + hw - 1.0]:
				for i in ys.size() - 1:
					ci.draw_primitive(PackedVector2Array([at.call(x, i), at.call(x, i + 1),
						at.call(x, i + 1, DECK_RAIL), at.call(x, i, DECK_RAIL)]),
						PackedColorArray([RAIL.darkened(0.35)]), PackedVector2Array())
				var rail := PackedVector2Array()
				for i in ys.size():
					rail.append(at.call(x, i, DECK_RAIL))
				ci.draw_polyline(rail, RAIL, 2.0)


## 교각 상자 (바닥 사각형 r을 높이 h0~h1로 세운다). 보이는 남·동쪽 면만 그린다
static func _pillar(ci: CanvasItem, r: Rect2, h0: float, h1: float) -> void:
	var s := Vector2(r.position.x, r.end.y)
	var e := Vector2(r.end.x, r.position.y)
	ci.draw_colored_polygon(IsoView.wall(s, r.end, h0, h1), CONCRETE.darkened(IsoView.face_shade(Vector2.DOWN)))
	ci.draw_colored_polygon(IsoView.wall(e, r.end, h0, h1), CONCRETE.darkened(IsoView.face_shade(Vector2.RIGHT)))
	ci.draw_rect(Rect2(r.position + IsoView.lift(h1), r.size), CONCRETE)


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

	# 양쪽 배수구는 차선 밖, 맨홀은 차로 안의 평면 장식.
	for edge in [-1.0, 1.0]:
		for along in [a+90, b-90]:
			RoadDetail.drain(ci, p.call(along, edge*(ROAD*.5-7)), vertical)
	RoadDetail.manhole(ci, p.call(a+BLOCK*.43, ROAD*.28))

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
			RoadDetail.worn_paint(ci, Rect2(r0, r1 - r0).abs())
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
	if looks.has(idx) and LandmarkBuilding.owns(looks[idx].style):
		var t: BuildingType = looks[idx]
		ci.draw_rect(r,Color("535657"))
		for part in LandmarkBuilding.collision_rects(r,t,idx):
			ci.draw_rect(part,Color("929990"))
			ci.draw_rect(part,Color("434b50"),false,2)
		ci.draw_string(font,r.get_center(),t.display_name,HORIZONTAL_ALIGNMENT_CENTER,-1,16,Color.WHITE)
		return
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

