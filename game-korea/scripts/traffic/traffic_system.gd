class_name TrafficSystem
extends Node2D
## 교통 전체: 차선 그래프·신호·NPC 차량 생성과 보충, 장애물 감지, 신호등·정류장 그리기.

signal vehicle_spawned(vehicle: Vehicle)
signal vehicle_teleported(ai: TrafficAI)   ## 갇힌 차를 옮기기 직전 (테스트·디버그용)

const TRAFFIC_TYPES: Array[VehicleType] = [
	preload("res://data/vehicles/car_avela.tres"),
	preload("res://data/vehicles/car_avela_r.tres"),
	preload("res://data/vehicles/trk_porta.tres"),
	preload("res://data/vehicles/car_sonato.tres"),
	preload("res://data/vehicles/car_sorea.tres"),
	preload("res://data/vehicles/car_rumi.tres"),
	preload("res://data/vehicles/car_taxi.tres"),
	preload("res://data/vehicles/etc_bike.tres"),
	preload("res://data/vehicles/sp_ambulance.tres"),
	preload("res://data/vehicles/car_striker.tres"),
	preload("res://data/vehicles/car_zenith_g8.tres"),
	preload("res://data/vehicles/trk_bongo.tres"),
	preload("res://data/vehicles/trk_titan.tres"),
	preload("res://data/vehicles/trk_tanker.tres"),
	preload("res://data/vehicles/trk_garbage.tres"),
	preload("res://data/vehicles/trk_mixer.tres"),
	preload("res://data/vehicles/bus_village.tres"),
	preload("res://data/vehicles/bus_express.tres"),
	preload("res://data/vehicles/sp_tow.tres"),
	preload("res://data/vehicles/etc_bicycle.tres"),
	preload("res://data/vehicles/etc_camper.tres"),
	preload("res://data/vehicles/etc_truck.tres"),
]
## 차종마다 나오는 비중. VehicleType.districts가 있으면 그 구역 도로에서만 나온다
const TRAFFIC_WEIGHTS: Array[float] = [4.0, 1.0, 2.0, 3.0, 2.0, 2.0, 3.0, 2.0, 0.5,
	1.0, 0.8, 2.0, 1.5, 0.8, 0.5, 1.5, 1.5, 1.0, 0.4, 1.5, 1.0, 1.5]
## 이보다 긴 차는 일반 교통에 넣지 않는다 — 교차로에서 돌 때 뒤꽁무니가 바깥으로 휘어
## 맞은편 정지선에 선 차를 친다 (시내버스는 노선이 우회전만 해서 괜찮다). 주차·미션 차로 쓴다
const MAX_TRAFFIC_LENGTH := 80.0
const BUS_TYPE: VehicleType = preload("res://data/vehicles/bus_city.tres")
## 시내버스 노선: 이 교차로들을 시계 방향으로 돈다
const BUS_CORNERS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(4, 1), Vector2i(4, 4), Vector2i(1, 4)]
const SEED := 4242
const RESPAWN_INTERVAL := 1.0
const SPAWN_MIN_CAMERA_DISTANCE := 900.0   ## 화면 밖에서만 보충한다
## 도시가 넓어서 차는 카메라 둘레에만 둔다: 이 반경 안에서 생기고, DESPAWN_RADIUS보다 멀어지면 치운다
const STREAM_RADIUS := 2600.0
const DESPAWN_RADIUS := 3300.0
const SPAWN_CLEARANCE := 110.0
const STUCK_RESPAWN_TIME := 25.0
const LIGHT_REDRAW_INTERVAL := 0.2
const LIGHT_DRAW_REACH := 1300.0            ## 카메라에서 이만큼(줌 1 기준) 안의 신호등·정류장만 그린다

var traffic_count := 20
var seed := SEED
var bus_count := 2
var vehicles: Array[Vehicle] = []          ## 도시의 모든 차 (주차·플레이어 차 포함, main과 공유)
var pedestrians: PedestrianManager
var player: Player

var graph := LaneGraph.new()
var controller: TrafficController
var rng := RandomNumberGenerator.new()
var ais: Array[TrafficAI] = []
var teleports := 0
var _drawn_spot := Vector2i.ZERO          ## 신호등을 그린 때 카메라가 있던 블록 (블록을 넘으면 다시 그린다)
var _bus_stops := {}                       ## LanePiece → true
var _next_id := 1
var _respawn_timer := 0.0
var _light_timer := 0.0


func _ready() -> void:
	z_index = -4
	rng.seed = seed
	controller = TrafficController.new(graph)
	_build_bus_stops()
	for i in bus_count:
		_spawn_bus(i * 2)
	for i in traffic_count:
		spawn_random(null, false)


func _physics_process(delta: float) -> void:
	controller.advance(delta)
	_light_timer -= delta
	var cam := ChaseCamera.current_cam()
	var spot := CityMap.block_at(cam.global_position) if cam else Vector2i.ZERO
	if _light_timer <= 0.0 or spot != _drawn_spot:
		_light_timer = LIGHT_REDRAW_INTERVAL
		_drawn_spot = spot
		queue_redraw()
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = RESPAWN_INTERVAL
		_maintain()


# ── 생성 · 보충 ──────────────────────────────────────────

func spawn_at(type: VehicleType, piece: LanePiece, s: float) -> Vehicle:
	var v := Vehicle.new()
	v.stats = type
	v.has_driver = true
	add_child(v)
	v.place(piece.point_at(s), Vector2.UP.angle_to(piece.tangent_at(s)))
	v.ai = TrafficAI.new(v, self, _next_id, piece, s)
	_next_id += 1
	vehicles.append(v)
	ais.append(v.ai)
	vehicle_spawned.emit(v)
	return v


## type이 null이면 일반 차종 중에서 고른다. 카메라 둘레(STREAM_RADIUS 안)의 열린 구간에 세운다
func spawn_random(type: VehicleType, far_from_camera: bool) -> Vehicle:
	var pieces := nearby_segments(SPAWN_MIN_CAMERA_DISTANCE if far_from_camera else 0.0, STREAM_RADIUS)
	if pieces.is_empty():
		return null
	for attempt in 30:
		var piece: LanePiece = pieces[rng.randi() % pieces.size()]
		var s := rng.randf_range(60.0, piece.length - 120.0)
		var pos := piece.point_at(s)
		if far_from_camera and _camera_distance(pos) < SPAWN_MIN_CAMERA_DISTANCE:
			continue
		if not is_clear(pos):
			continue
		return spawn_at(type if type else _pick_type(pos), piece, s)
	return null


## center(없으면 카메라, 그것도 없으면 주인공)에서 가운데가 [near, far] 거리인 열린 구간들
func nearby_segments(near: float, far: float, at: Variant = null) -> Array[LanePiece]:
	var center: Vector2 = at if at != null else focus()
	var result: Array[LanePiece] = []
	for piece in graph.all_segments:
		var d := piece.point_at(piece.length * 0.5).distance_to(center)
		if d >= near and d <= far and LaneGraph.is_open(piece):
			result.append(piece)
	return result


## 교통을 모아 둘 중심: 카메라, 없으면 주인공
func focus() -> Vector2:
	var camera := ChaseCamera.current_cam() if is_inside_tree() else null
	if camera:
		return camera.global_position
	return player.global_position if player else Vector2.ZERO


## 원래 AI 없이 달리던 차(추격을 마친 경찰차 등)에 운전자를 붙여 가장 가까운 차선에 합류시킨다
func adopt(v: Vehicle) -> void:
	var piece := graph.nearest_segment(v.global_position, v.motor.forward())
	var s := clampf(piece.project(v.global_position).x, 0.0, piece.length - 1.0)
	v.ai = TrafficAI.new(v, self, _next_id, piece, s)
	_next_id += 1
	ais.append(v.ai)


func _spawn_bus(corner_index: int) -> Vehicle:
	var from := BUS_CORNERS[corner_index]
	var to := BUS_CORNERS[(corner_index + 1) % BUS_CORNERS.size()]
	var piece := graph.segment(from, LaneGraph.dir_index(to - from))
	if not is_clear(piece.point_at(80.0)):
		return null
	var v := spawn_at(BUS_TYPE, piece, 80.0)
	v.ai.bus_corners = BUS_CORNERS
	v.ai.bus_next = (corner_index + 1) % BUS_CORNERS.size()
	v.ai.route = [piece]
	v.ai._extend()
	return v


func _pick_type(pos: Vector2) -> VehicleType:
	var dist := CityMap.district_of(City.nearest_block(pos))
	var total := 0.0
	for k in TRAFFIC_TYPES.size():
		total += _weight(k, dist)
	var roll := rng.randf() * total
	for k in TRAFFIC_TYPES.size():
		roll -= _weight(k, dist)
		if roll <= 0.0 and _weight(k, dist) > 0.0:
			return TRAFFIC_TYPES[k]
	return TRAFFIC_TYPES[0]


func _weight(k: int, dist: DistrictType) -> float:
	var t := TRAFFIC_TYPES[k]
	if t.size.y > MAX_TRAFFIC_LENGTH:
		return 0.0
	if not t.districts.is_empty() and (dist == null or not t.districts.has(dist.id)):
		return 0.0
	return TRAFFIC_WEIGHTS[k]


## 빼앗긴 차를 보충하고, 화면 밖에서 오래 갇힌 차는 다른 곳으로 옮긴다. 경찰 순찰차는 경찰이 따로 센다.
func _maintain() -> void:
	var cars := 0
	var buses := 0
	for ai in ais:
		if ai.is_bus():
			buses += 1
		elif ai.vehicle.stats.category != &"police":
			cars += 1
	if cars < traffic_count:
		spawn_random(null, true)
	if buses < bus_count:
		var v := _spawn_bus(buses * 2)
		if v and _camera_distance(v.global_position) < SPAWN_MIN_CAMERA_DISTANCE:
			remove_ai(v)
			vehicles.erase(v)
			v.queue_free()
	for ai in ais:
		if ai.stuck_time > STUCK_RESPAWN_TIME and not ai.is_bus() \
				and _camera_distance(ai.vehicle.global_position) > SPAWN_MIN_CAMERA_DISTANCE:
			_teleport(ai)
			break
	# 멀어진 일반 차는 치운다 (다음 정비 때 카메라 둘레에 새로 생긴다)
	for ai in ais:
		if not ai.is_bus() and not ai.persistent and ai.vehicle.stats.category != &"police" \
				and _camera_distance(ai.vehicle.global_position) > DESPAWN_RADIUS:
			despawn(ai.vehicle)
			break


## 장이 바뀌어 통제 구역이 달라졌다: 닫힌 길 위의 NPC 차는 치운다 (경찰·버스·미션 차는 남긴다)
func on_map_changed() -> void:
	for ai: TrafficAI in ais.duplicate():
		var piece := ai.route[0]
		var closed := not CityMap.is_open_node(piece.from_cell) or not CityMap.is_open_node(piece.to_cell)
		if closed and not ai.persistent and not ai.is_bus() and ai.vehicle.stats.category != &"police":
			despawn(ai.vehicle)


## NPC 차를 없앤다
func despawn(v: Vehicle) -> void:
	remove_ai(v)
	vehicles.erase(v)
	v.queue_free()


func _teleport(ai: TrafficAI) -> void:
	var pieces := nearby_segments(SPAWN_MIN_CAMERA_DISTANCE, STREAM_RADIUS)
	if pieces.is_empty():
		return
	for attempt in 30:
		var piece: LanePiece = pieces[rng.randi() % pieces.size()]
		var s := rng.randf_range(60.0, piece.length - 120.0)
		var pos := piece.point_at(s)
		if _camera_distance(pos) < SPAWN_MIN_CAMERA_DISTANCE or not is_clear(pos):
			continue
		vehicle_teleported.emit(ai)
		ai.release_all()
		ai.vehicle.place(pos, Vector2.UP.angle_to(piece.tangent_at(s)))
		ai.route = [piece]
		ai.s = s
		ai.stuck_time = 0.0
		ai._extend()
		teleports += 1
		return


## 플레이어가 빼앗은 차 등: AI를 떼어 낸다 (차는 그대로 남는다)
func remove_ai(v: Vehicle) -> void:
	if v.ai == null:
		return
	v.ai.release_all()
	ais.erase(v.ai)
	v.ai = null


func is_clear(pos: Vector2, clearance := SPAWN_CLEARANCE) -> bool:
	for v in vehicles:
		if not v.apart(pos, maxi(CityMap.level_zone(pos), 0)) and v.global_position.distance_to(pos) < clearance:
			return false
	if player and player.global_position.distance_to(pos) < clearance:
		return false
	return true


func _camera_distance(pos: Vector2) -> float:
	var camera := ChaseCamera.current_cam()
	return pos.distance_to(camera.global_position) if camera else INF


# ── 감지 ──────────────────────────────────────────────────

## 내 경로 앞의 가장 가까운 장애물. {gap, speed, passable, length} 또는 {}.
func scan_ahead(ai: TrafficAI) -> Dictionary:
	var me := ai.vehicle
	var speed := absf(me.motor.forward_speed())
	var scan := speed * speed / (2.0 * TrafficAI.DECEL) + 110.0
	var half_w := me.stats.size.x * 0.5
	var reach := scan + ai.half_length() + 60.0
	var forward := me.motor.forward()

	var candidates: Array = []   # [검사점 배열, 반폭, 속도 벡터, 노드]
	for v in vehicles:
		# 떠 있는 헬기·고가 위아래 차는 길을 막지 않는다
		if v == me or v.global_position.distance_to(me.global_position) > reach + v.stats.size.y \
				or v.apart(me.global_position, me.level):
			continue
		var f := v.motor.forward() * v.stats.size.y * 0.45
		candidates.append([[v.global_position + f, v.global_position, v.global_position - f],
			v.stats.size.x * 0.5, v.motor.velocity, v])
	if pedestrians:
		for p in pedestrians.peds:
			if p.active and not p.is_dead() and p.global_position.distance_to(me.global_position) < reach \
					and CityMap.meet(p.global_position, p.level, me.global_position, me.level):
				candidates.append([[p.global_position], Pedestrian.RADIUS + 4.0, p.velocity, p])
	if player and player.visible and player.global_position.distance_to(me.global_position) < reach \
			and CityMap.meet(player.global_position, player.level, me.global_position, me.level):
		candidates.append([[player.global_position], Player.RADIUS + 4.0, player.velocity, player])
	if candidates.is_empty():
		return {}

	# 검사점(경로 위 점)을 먼저 모두 뽑고, 검사점들을 감싼 상자에서 먼 후보는 뺀다.
	# 상자 밖 점은 어느 검사점과도 문턱 안에 들 수 없으므로 결과는 그대로이고, 거리 계산이 크게 준다
	var samples := PackedVector2Array()
	var d := 0.0
	while d <= scan:
		samples.append(ai.route_point(ai.half_length() + d))
		d += TrafficAI.SAMPLE_STEP
	var box := Rect2(samples[0], Vector2.ZERO)
	for q in samples:
		box = box.expand(q)
	var near: Array = []
	for c: Array in candidates:
		var area := box.grow(half_w + c[1] + 5.0)
		for q: Vector2 in c[0]:
			if area.has_point(q):
				near.append(c)
				break
	if near.is_empty():
		return {}
	for k in samples.size():
		var sample := samples[k]
		for c: Array in near:
			var threshold: float = half_w + c[1] + 4.0
			for q: Vector2 in c[0]:
				if q.distance_to(sample) < threshold:
					return _obstacle(k * TrafficAI.SAMPLE_STEP, c, forward)
	return {}


func _obstacle(gap: float, c: Array, forward: Vector2) -> Dictionary:
	var node: Node2D = c[3]
	var vel: Vector2 = c[2]
	var passable := false
	var length := 16.0
	if node is Vehicle:
		var v := node as Vehicle
		length = v.stats.size.y
		passable = vel.length() < 20.0 and (v.ai == null or v.ai.is_dwelling() or v.ai.stuck_time > 6.0)
	return {"gap": gap, "speed": vel.dot(forward), "passable": passable, "length": length}


## 현재 구간에서 offset 차로의 [from, to] 구간이 비었는지
func lane_clear(ai: TrafficAI, offset: float, from: float, to: float) -> bool:
	var piece := ai.route[0]
	var half_w := ai.vehicle.stats.size.x * 0.5
	var s := maxf(from, 0.0)
	while s <= minf(to, piece.length):
		var p := piece.point_at(s) + LaneGraph.right_of(piece.tangent_at(s)) * offset
		for v in vehicles:
			if v == ai.vehicle or v.apart(ai.vehicle.global_position, ai.vehicle.level):
				continue
			var f := v.motor.forward() * v.stats.size.y * 0.45
			for q in [v.global_position + f, v.global_position, v.global_position - f]:
				if (q as Vector2).distance_to(p) < half_w + v.stats.size.x * 0.5 + 6.0:
					return false
		s += TrafficAI.SAMPLE_STEP
	return true


## 교차로를 지나 들어갈 구간 입구에 내 차가 들어갈 자리가 있는지 (교차로 꼬리물기 방지)
func exit_has_room(seg: LanePiece, ai: TrafficAI) -> bool:
	var need := ai.vehicle.stats.size.y + 30.0
	for other in ais:
		if other != ai and other.route[0].kind == LanePiece.Kind.TURN and other.route[1] == seg:
			need += other.vehicle.stats.size.y + 20.0
	var dir := LaneGraph.DIRS[seg.dir_in]
	var right := LaneGraph.right_of(dir)
	var start := seg.points[0]
	for v in vehicles:
		if v == ai.vehicle or v.apart(ai.vehicle.global_position, ai.vehicle.level):
			continue
		var rel := v.global_position - start
		var along := rel.dot(dir) - v.stats.size.y * 0.5
		if absf(rel.dot(right)) < 30.0 and along > -40.0 and along < need:
			return false
	return true


# ── 버스 정류장 ────────────────────────────────────────────

func is_bus_stop(piece: LanePiece) -> bool:
	return _bus_stops.has(piece)


## 노선 위 구간을 하나 걸러 하나씩 정류장으로
func _build_bus_stops() -> void:
	for k in BUS_CORNERS.size():
		var from := BUS_CORNERS[k]
		var to := BUS_CORNERS[(k + 1) % BUS_CORNERS.size()]
		var d := LaneGraph.dir_index(to - from)
		var cell := from
		var n := 0
		while cell != to:
			if n % 2 == 0:
				_bus_stops[graph.segment(cell, d)] = true
			cell += LaneGraph.STEPS[d]
			n += 1


# ── 그리기 ────────────────────────────────────────────────

func _draw() -> void:
	# 카메라 둘레만 그린다 — 도시 전체 신호등·정류장을 그리면 한 번에 20ms가 넘는다
	var cam := ChaseCamera.current_cam()
	var near := Rect2(-1e9, -1e9, 2e9, 2e9)
	if cam:
		var reach := LIGHT_DRAW_REACH / maxf(cam.zoom.x, 0.2)
		near = Rect2(cam.global_position - Vector2(reach, reach), Vector2(reach, reach) * 2.0)
	var font := ThemeDB.fallback_font
	for piece: LanePiece in _bus_stops:
		var mid := piece.point_at(piece.length * 0.5)
		if not near.has_point(mid):
			continue
		var right := LaneGraph.right_of(LaneGraph.DIRS[piece.dir_in])
		var pole := mid + right * (City.ROAD * 0.5 - LaneGraph.LANE_OFFSET + 12.0)
		draw_rect(Rect2(pole - Vector2(15, 9), Vector2(30, 18)), Color(0.1, 0.35, 0.8))
		draw_rect(Rect2(pole - Vector2(15, 9), Vector2(30, 18)), Color(0.75, 0.85, 1.0), false, 1.5)
		draw_string(font, pole + Vector2(-15, 5), "정류장", HORIZONTAL_ALIGNMENT_CENTER, 30, 9, Color.WHITE)
	for cell: Vector2i in controller.signal_offsets:
		var c := LaneGraph.center(cell)
		if not near.has_point(c):
			continue
		for d in 4:
			if not CityMap.road(cell, (d + 2) % 4):
				continue
			var dir := LaneGraph.DIRS[d]
			var pos := c - dir * (LaneGraph.HALF + 10.0) + LaneGraph.right_of(dir) * (LaneGraph.HALF + 10.0)
			var color := Color(0.25, 0.95, 0.4)
			match controller.light(cell, d):
				TrafficController.Light.YELLOW:
					color = Color(1.0, 0.8, 0.15)
				TrafficController.Light.RED:
					color = Color(1.0, 0.2, 0.2)
			draw_circle(pos, 12.0, Color(color, 0.18))
			draw_circle(pos, 7.0, Color(0.06, 0.06, 0.07))
			draw_circle(pos, 5.0, color)
