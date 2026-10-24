class_name TrafficAI
extends RefCounted
## NPC 운전자. 차선 경로를 따라가며(pure pursuit) 가속·브레이크·조향 입력만 만든다 —
## 차의 물리는 플레이어 차와 똑같은 VehicleMotor가 처리한다.
##
## 속도 목표는 여러 제한 중 가장 낮은 값이다:
## 순항 속도 / 회전 속도 / 정지선(예약 못 받았을 때) / 앞 장애물 / 버스 정류장.

const DECEL := 420.0              ## 계획에 쓰는 편안한 감속 px/s² (실제 브레이크는 더 세다)
const MIN_GAP := 26.0             ## 앞차와 멈춰 설 간격
const PASS_GAP := 110.0           ## 추월할 장애물 뒤에서는 이만큼 떨어져 선다
const MIN_PASS_ROOM := 90.0       ## 이보다 가까우면 옆으로 못 빠지므로 먼저 후진한다
const BACKUP_SPEED := 70.0
const SAMPLE_STEP := 16.0
const RIGHT_TURN_SPEED := 170.0
const LEFT_TURN_SPEED := 210.0
const PASS_WAIT := 2.0            ## 막힌 채 이만큼 서 있으면 추월을 시도한다
const OFFSET_BLEND := 80.0        ## 경로점의 옆 오프셋은 실제 위치에서 시작해 이 거리에 걸쳐 목표 차로로 옮겨 간다
const GRANT_TIMEOUT := 3.0        ## 예약을 받고도 이만큼 못 움직이면 예약을 내놓는다
const DWELL_TIME := 3.0
const RELOCALIZE_DISTANCE := 70.0
const MERGE_BEFORE_STOP := 140.0  ## 추월 중 못 돌아왔으면 정지선 이만큼 앞에서 기다린다 (돌아올 공간)
const MERGE_SPEED := 150.0        ## 안쪽 차로로 돌아가는 동안의 속도
const MERGE_BEHIND := 200.0       ## 돌아갈 때 내 뒤로 비어 있어야 하는 거리

var vehicle: Vehicle
var system: TrafficSystem
var id := 0
var route: Array[LanePiece] = []
var s := 0.0
var cruise := 300.0

var has_grant := false
var grant_cell := Vector2i.ZERO
var pending_cell := RoadNav.INVALID   ## 예약을 기다리는 교차로 (없으면 INVALID)
var grant_idle := 0.0

var lateral := 0.0                 ## 현재 구간 차선에서 실제로 오른쪽으로 벗어난 거리
var pass_target := 0.0             ## 가려는 차로의 옆 오프셋 (0 = 안쪽 차로, PASS_OFFSET = 바깥 차로)
var pass_piece: LanePiece = null
var pass_until := 0.0
var blocked_time := 0.0
var backing := false
var backing_from := 0.0
var _pass_now := false
var stuck_time := 0.0
var halt := false
var honking := false

var bus_corners: Array[Vector2i] = []
var bus_next := 0
var dwell_left := 0.0
var dwelled_piece: LanePiece = null

var red_runs := 0          ## 예약 없이 교차로에 들어간 횟수 (0이어야 한다)
var distance := 0.0        ## 지금까지 달린 거리 (테스트용)
var age := 0.0             ## 생긴 뒤 지난 시간 (테스트용)
var persistent := false    ## 멀어져도 치우지 않는다 (미션 차량 등)


func _init(p_vehicle: Vehicle, p_system: TrafficSystem, p_id: int, piece: LanePiece, p_s: float) -> void:
	vehicle = p_vehicle
	system = p_system
	id = p_id
	cruise = minf(vehicle.stats.max_speed * 0.45, 320.0)
	route = [piece]
	s = p_s
	_extend()


func debug_string() -> String:
	var p := route[0]
	return "%s %s %s s=%.0f/%.0f spd=%.0f grant=%s pend=%s pass=%.0f/%.0f back=%s stuck=%.1f halt=%s" % [
		vehicle.stats.id, "SEG" if p.kind == LanePiece.Kind.SEGMENT else "TURN%d" % p.turn,
		p.to_cell, s, p.length, vehicle.motor.forward_speed(), has_grant, pending_cell,
		lateral, pass_target, backing, stuck_time, halt]


func is_bus() -> bool:
	return not bus_corners.is_empty()


func is_dwelling() -> bool:
	return dwell_left > 0.0


func half_length() -> float:
	return vehicle.stats.size.y * 0.5


func drive(delta: float) -> void:
	_localize()
	var piece := route[0]
	var speed := vehicle.motor.forward_speed()
	distance += maxf(speed, 0.0) * delta
	age += delta
	var target := cruise if piece.kind == LanePiece.Kind.SEGMENT else _turn_speed(piece)

	if piece.kind == LanePiece.Kind.SEGMENT:
		target = minf(target, _intersection_limit(piece, speed, delta))
		if is_bus():
			target = minf(target, _bus_stop_limit(piece, speed, delta))

	honking = false
	var obstacle := system.scan_ahead(self)
	if not obstacle.is_empty():
		# 둘 다 같은 감속으로 선다고 보면 v² ≤ 2·D·여유 + 앞차속도². 여유가 음수면 앞차보다 느리게 → 간격이 다시 벌어진다
		var room: float = obstacle.gap - (PASS_GAP if obstacle.passable else MIN_GAP)
		var lead := maxf(obstacle.speed, 0.0)
		target = minf(target, sqrt(maxf(2.0 * DECEL * room + lead * lead, 0.0)))
	_update_pass(piece, obstacle, speed, delta)
	if piece.kind == LanePiece.Kind.SEGMENT:
		if pass_target > 0.0:
			# 아직 끼어들 자리가 없으면 교차로 앞 바깥 차로에서 기다린다 (옆 차가 먼저 가게).
			# 단, 비켜 가던 장애물 옆에서는 서지 않는다.
			var wait_at := clampf(maxf(pass_until, piece.length - half_length() - MERGE_BEFORE_STOP),
				0.0, piece.length - half_length() - 60.0)
			var to_merge := wait_at - s
			target = minf(target, sqrt(2.0 * DECEL * maxf(to_merge, 0.0)))
		elif absf(lateral) > 12.0:
			# 돌아가는 중: 옆으로 가려면 앞으로 움직여야 하므로 세우지 않고 천천히
			target = minf(target, MERGE_SPEED)
	if halt:
		target = 0.0
		backing = false

	stuck_time = stuck_time + delta if absf(speed) < 5.0 else 0.0
	if backing:
		_apply_backup(speed)
	else:
		_apply(target, speed)


func _turn_speed(piece: LanePiece) -> float:
	if piece.turn == 1:
		return minf(cruise, RIGHT_TURN_SPEED)
	if piece.turn == -1:
		return minf(cruise, LEFT_TURN_SPEED)
	return cruise


## 교차로 앞: 회전 속도까지 미리 줄이고, 예약을 못 받으면 정지선에 선다.
func _intersection_limit(piece: LanePiece, speed: float, delta: float) -> float:
	var next := route[1]
	var to_box := piece.length - s - half_length()
	var limit := sqrt(pow(_turn_speed(next), 2) + 2.0 * DECEL * maxf(to_box, 0.0))
	if has_grant:
		grant_idle = grant_idle + delta if absf(speed) < 5.0 else 0.0
		if grant_idle > GRANT_TIMEOUT:
			_release()
		return limit
	var to_stop := piece.length - s - half_length() - 4.0
	if to_stop > speed * speed / (2.0 * DECEL) + 40.0:
		return limit
	pending_cell = piece.to_cell
	var ctl := system.controller
	# 신호가 막혔으면 들어갈 자리를 볼 것 없이 못 간다 — 자리 확인(차 목록을 모두 돈다)을 건너뛴다.
	# try_reserve는 그래도 불러 기다림 줄에서 뺀다 (예전과 같다)
	if not ctl.may_enter(piece.to_cell, next.dir_in):
		ctl.try_reserve(piece.to_cell, next.dir_in, next.dir_out, id)
	elif system.exit_has_room(route[2], self) \
			and ctl.try_reserve(piece.to_cell, next.dir_in, next.dir_out, id):
		has_grant = true
		grant_cell = piece.to_cell
		grant_idle = 0.0
		pending_cell = RoadNav.INVALID
		return limit
	return minf(limit, sqrt(2.0 * DECEL * maxf(to_stop, 0.0)))


## 버스: 정류장 구간 한가운데에서 3초 선다
func _bus_stop_limit(piece: LanePiece, speed: float, delta: float) -> float:
	if not system.is_bus_stop(piece) or dwelled_piece == piece:
		return INF
	if dwell_left > 0.0:
		dwell_left -= delta
		if dwell_left <= 0.0:
			dwelled_piece = piece
		return 0.0
	var to_stop := piece.length * 0.5 - s
	if to_stop < 6.0 and absf(speed) < 15.0:
		dwell_left = DWELL_TIME
		return 0.0
	return sqrt(2.0 * DECEL * maxf(to_stop, 0.0))


## 서 있는 장애물(빈 차·플레이어 차·고장 차·정차한 버스)에 막히면 바깥 차로로 비켜 간다
func _update_pass(piece: LanePiece, obstacle: Dictionary, speed: float, delta: float) -> void:
	if backing:
		# 공간이 생겼거나, 뒤가 막혔거나, 너무 많이 물러났으면 그만
		var room: bool = obstacle.is_empty() or obstacle.gap >= PASS_GAP
		var behind_clear := system.lane_clear(self, 0.0, s - half_length() * 2.0 - 40.0, s - half_length())
		if room or not behind_clear or backing_from - s > 120.0:
			backing = false
			_pass_now = true   # 물러난 뒤엔 다시 기다리지 않고 바로 추월한다
		return
	var blocked := not obstacle.is_empty() and absf(speed) < 15.0
	blocked_time = blocked_time + delta if blocked else 0.0
	var want_pass := _pass_now or (blocked and blocked_time > PASS_WAIT)
	_pass_now = false
	if pass_target == 0.0 and want_pass and not obstacle.is_empty():
		var too_close: bool = obstacle.gap < MIN_PASS_ROOM
		if obstacle.passable and piece.kind == LanePiece.Kind.SEGMENT and too_close:
			if system.lane_clear(self, 0.0, s - half_length() * 2.0 - 60.0, s - half_length()):
				backing = true
				backing_from = s
				return
		# 너무 붙어 있는데 뒤도 막혔으면 옆으로 빠지다 긁는다 — 기다린다
		if obstacle.passable and piece.kind == LanePiece.Kind.SEGMENT and not too_close:
			var until: float = s + obstacle.gap + half_length() * 2.0 + obstacle.length + 30.0
			if until < piece.length - half_length() - 100.0 \
					and system.lane_clear(self, LaneGraph.PASS_OFFSET, s - 70.0, until + 40.0):
				pass_target = LaneGraph.PASS_OFFSET
				pass_piece = piece
				pass_until = until
		honking = pass_target == 0.0
	if pass_target > 0.0 and (piece != pass_piece or s > pass_until):
		# 끼어들 자리: 내 차 길이 + 앞뒤 여유. 뒤는 넉넉히 본다 — 뒤차가 나보다 빠를 수 있다.
		var behind := half_length() + MERGE_BEHIND
		if piece != pass_piece or system.lane_clear(self, 0.0, s - behind, s + half_length() + 40.0):
			pass_target = 0.0
	elif pass_target > 0.0 and system.lane_clear(self, 0.0, s - half_length() - 20.0, s + half_length() + 200.0):
		# 비켜 가던 장애물이 떠났다 — 안쪽 차로가 앞까지 비었으면 바로 돌아간다
		pass_target = 0.0


## 경로점. dist는 내 중심에서 앞으로의 거리.
## 현재 구간에서는 옆 오프셋을 실제 위치(lateral)에서 목표 차로(pass_target)로 OFFSET_BLEND에 걸쳐 옮긴다 —
## 가까운 점은 차가 실제로 있는 곳, 먼 점은 가려는 차로. 장애물 감지와 조향이 같은 점을 쓴다.
func route_point(dist: float) -> Vector2:
	var d := s + dist
	for piece in route:
		if d <= piece.length:
			var p := piece.point_at(d)
			if piece == route[0] and (pass_target > 0.0 or absf(lateral) > 1.0):
				var off := lerpf(lateral, pass_target, clampf(dist / OFFSET_BLEND, 0.0, 1.0))
				p += LaneGraph.right_of(piece.tangent_at(d)) * off
			return p
		d -= piece.length
	return route[route.size() - 1].point_at(INF)


func _apply(target: float, speed: float) -> void:
	var look := clampf(absf(speed) * 0.45, 40.0, 140.0)
	var local := vehicle.to_local(route_point(look))
	vehicle.steer_input = clampf(Vector2.UP.angle_to(local) * 2.2, -1.0, 1.0)
	vehicle.handbrake_input = false
	if target < 1.0 and speed < 8.0:
		vehicle.throttle_input = 0.0
	elif speed > target + 15.0:
		vehicle.throttle_input = -clampf((speed - target) / 150.0, 0.2, 1.0) if speed > 5.0 else 0.0
	else:
		vehicle.throttle_input = clampf(target / vehicle.stats.max_speed, 0.0, 1.0)


func _apply_backup(speed: float) -> void:
	vehicle.steer_input = 0.0
	vehicle.handbrake_input = false
	vehicle.throttle_input = 0.0 if speed < -BACKUP_SPEED else -1.0


func _localize() -> void:
	var pos := vehicle.global_position
	var proj := route[0].project(pos)
	for i in 3:
		if proj.x < route[0].length - 1.0:
			break
		_advance()
		proj = route[0].project(pos)
	s = proj.x
	lateral = (pos - route[0].point_at(s)).dot(LaneGraph.right_of(route[0].tangent_at(s)))
	if proj.y > RELOCALIZE_DISTANCE:
		relocalize()


func _advance() -> void:
	var done: LanePiece = route.pop_front()
	if done.kind == LanePiece.Kind.SEGMENT:
		# 교차로 진입
		if pending_cell == done.to_cell:
			system.controller.release(pending_cell, id)
			pending_cell = RoadNav.INVALID
		if not has_grant:
			red_runs += 1
		pass_target = 0.0
	elif has_grant:
		_release()
	_extend()


## 사고 등으로 경로를 벗어나면 가까운 차선에 다시 합류한다
func relocalize() -> void:
	_release()
	pass_target = 0.0
	var seg := system.graph.nearest_segment(vehicle.global_position, vehicle.motor.forward())
	route = [seg]
	s = seg.project(vehicle.global_position).x
	_extend()


func _release() -> void:
	if has_grant:
		system.controller.release(grant_cell, id)
	if pending_cell != RoadNav.INVALID:
		system.controller.release(pending_cell, id)
	has_grant = false
	grant_idle = 0.0
	pending_cell = RoadNav.INVALID


func release_all() -> void:
	_release()


func _extend() -> void:
	while route.size() < 3:
		var last: LanePiece = route[route.size() - 1]
		if last.kind == LanePiece.Kind.SEGMENT:
			route.append(system.graph.turn(last.to_cell, last.dir_in, _choose_exit(last)))
		else:
			route.append(system.graph.segment(last.to_cell, last.dir_out))


func _choose_exit(seg: LanePiece) -> int:
	var options := system.graph.exits(seg.to_cell, seg.dir_in)
	if options.is_empty():
		# 통제된 길로 들어와 열린 출구가 없다 (장을 되돌렸을 때 등) — 닫힌 길이라도 고른다. 바리케이드에 막히면 옮겨진다
		for out in 4:
			if out != (seg.dir_in + 2) % 4 and CityMap.road(seg.to_cell, out) and LaneGraph.allowed(seg.to_cell, seg.dir_in, out):
				options.append(out)
	if is_bus():
		if seg.to_cell == bus_corners[bus_next]:
			bus_next = (bus_next + 1) % bus_corners.size()
			return LaneGraph.dir_index(bus_corners[bus_next] - seg.to_cell)
		return seg.dir_in
	# 직진 2 : 우회전 1 : 좌회전 1
	var weights: Array[float] = []
	var total := 0.0
	for out in options:
		var w := 2.0 if out == seg.dir_in else 1.0
		weights.append(w)
		total += w
	var roll := system.rng.randf() * total
	for k in options.size():
		roll -= weights[k]
		if roll <= 0.0:
			return options[k]
	return options[options.size() - 1]
