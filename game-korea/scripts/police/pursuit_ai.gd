class_name PursuitAI
extends RefCounted
## 추격 운전자 (경찰차). 목표가 직접 보이면 곧장 달려들고, 안 보이면 도로 격자로 길을 찾는다.
## TrafficAI처럼 가속·브레이크·조향 입력만 만든다 — 물리는 플레이어 차와 같은 VehicleMotor.
## 신호·차선은 무시한다(사이렌). 앞을 막은 차는 옆으로 비켜 가고, 벽에 걸리면 후진해서 빠져나온다.

const LANE_BIAS := 44.0          ## 도로 가운데에서 진행 방향 오른쪽으로 이만큼 붙어 달린다
const CORNER_SPEED := 240.0      ## 교차로에서 꺾을 때의 속도
const PLAN_BRAKE := 0.8          ## 감속 계획에 쓰는 브레이크 비율 (차종 brake_force × 이 값)
const WAYPOINT_REACH := 70.0     ## 교차로 중심에 이만큼 다가가면 다음 교차로를 본다
const LOOK_MIN := 90.0           ## 차로를 따라 이만큼(속도에 비례, 최대 LOOK_MAX) 앞을 노린다
const LOOK_MAX := 260.0
const STOP_DISTANCE := 70.0      ## stop_at_target일 때 목표 앞 이 거리에서 선다
const AVOID_MARGIN := 14.0
const STUCK_TIME := 0.9
const REVERSE_TIME := 0.8
const LOS_INTERVAL := 0.1

var vehicle: Vehicle
var vehicles: Array[Vehicle]     ## 피해야 할 차들 (도시 전체 목록을 공유)
var target := Vector2.ZERO       ## 쫓아갈 곳 (디스패처가 매 프레임 넣는다)
var target_velocity := Vector2.ZERO
var target_vehicle: Vehicle = null   ## ram이면 이 차는 피하지 않는다
var ram := false                 ## 목표에 감속 없이 들이받는다 (★2부터)
var stop_at_target := false      ## 목표 앞에서 선다 (도보 주인공 앞에 경찰을 내려 줄 때)
var top_speed := 0.0
var plan_decel := 0.0
var direct := false              ## 목표가 직접 보이는 중
var waypoint := RoadNav.INVALID
var stuck_count := 0             ## 후진해서 빠져나온 횟수 (디스패처가 너무 많으면 옮긴다)

var _stuck := 0.0
var _reverse_left := 0.0
var _reverse_steer := 0.0
var _los_timer := 0.0


func _init(p_vehicle: Vehicle, p_vehicles: Array[Vehicle]) -> void:
	vehicle = p_vehicle
	vehicles = p_vehicles
	top_speed = vehicle.stats.max_speed * 0.95
	plan_decel = vehicle.stats.brake_force * PLAN_BRAKE


func drive(delta: float) -> void:
	var pos := vehicle.global_position
	var speed := vehicle.motor.forward_speed()
	if _reverse_left > 0.0:
		_reverse_left -= delta
		vehicle.throttle_input = -1.0
		vehicle.steer_input = _reverse_steer
		vehicle.handbrake_input = false
		return

	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = LOS_INTERVAL
		direct = RoadNav.clear_path(vehicle.get_world_2d().direct_space_state, pos, target,
			vehicle.stats.size.x * 0.5 + 2.0)

	var aim: Vector2
	var limit := top_speed
	var dist := pos.distance_to(target)
	if direct:
		waypoint = RoadNav.INVALID
		# 목표가 움직이면 조금 앞을 노린다
		aim = target + target_velocity * clampf(dist / maxf(absf(speed), 250.0), 0.0, 0.6)
		if stop_at_target:
			limit = minf(limit, sqrt(2.0 * plan_decel * maxf(dist - STOP_DISTANCE, 0.0)))
		elif not ram:
			limit = minf(limit, target_velocity.length() + sqrt(2.0 * plan_decel * maxf(dist - 90.0, 0.0)))
	else:
		aim = _route_aim(pos)
		limit = minf(limit, _corner_limit(pos))

	aim = _avoid(aim, speed)
	var local := vehicle.to_local(aim)
	var angle := Vector2.UP.angle_to(local)
	vehicle.steer_input = clampf(angle * 2.5, -1.0, 1.0)
	# 크게 꺾어야 하면 속도를 줄인다. 빠를 땐 핸드브레이크로 돌린다
	limit = minf(limit, lerpf(top_speed, 200.0, clampf(absf(angle) / 1.3, 0.0, 1.0)))
	vehicle.handbrake_input = absf(angle) > 1.0 and speed > 300.0

	if limit < 5.0 and absf(speed) < 15.0:
		vehicle.throttle_input = 0.0
	elif speed > limit + 20.0:
		vehicle.throttle_input = -clampf((speed - limit) / 150.0, 0.3, 1.0)
	else:
		vehicle.throttle_input = 1.0 if speed < limit else 0.0
	_check_stuck(speed, delta)


func is_stopped() -> bool:
	return vehicle.speed() < 30.0


## 다음 교차로로 가는 차로(도로 가운데에서 오른쪽으로 LANE_BIAS) 위, 속도에 비례한 거리 앞을 노린다.
## 먼 교차로를 바로 노리면 차로를 벗어났을 때 거의 꺾지 않아 벽을 긁는다.
func _route_aim(pos: Vector2) -> Vector2:
	var forward := vehicle.motor.forward()
	if waypoint == RoadNav.INVALID or pos.distance_to(LaneGraph.center(waypoint)) < WAYPOINT_REACH:
		waypoint = RoadNav.next_cell(pos, forward if vehicle.speed() > 60.0 else Vector2.ZERO, target)
	var wp := LaneGraph.center(waypoint)
	var to := wp - pos
	var axis := Vector2(signf(to.x), 0.0) if absf(to.x) > absf(to.y) else Vector2(0.0, signf(to.y))
	var lane_end := wp + LaneGraph.right_of(axis) * LANE_BIAS
	var along := (pos - lane_end).dot(axis)          # 교차로까지 남은 거리 (음수)
	var look := clampf(absf(vehicle.motor.forward_speed()) * 0.45, LOOK_MIN, LOOK_MAX)
	return lane_end + axis * minf(along + look, 0.0)


## 다음 교차로에서 꺾어야 하면 미리 회전 속도까지 줄인다
func _corner_limit(pos: Vector2) -> float:
	if waypoint == RoadNav.INVALID:
		return INF
	var wp := LaneGraph.center(waypoint)
	var into := (wp - pos).normalized()
	var after := RoadNav.next_cell(wp + into, into, target)
	var out := (LaneGraph.center(after) - wp).normalized()
	if into.dot(out) > 0.7:
		return INF
	return sqrt(CORNER_SPEED * CORNER_SPEED + 2.0 * plan_decel * maxf(pos.distance_to(wp) - 50.0, 0.0))


## 앞을 막은 차가 있으면 그 옆으로 노리는 점을 옮긴다
func _avoid(aim: Vector2, speed: float) -> Vector2:
	var look := 70.0 + absf(speed) * 0.6
	var half_w := vehicle.stats.size.x * 0.5
	var nearest := INF
	var shift := 0.0
	for v in vehicles:
		if v == vehicle or (ram and v == target_vehicle):
			continue
		if v.global_position.distance_to(vehicle.global_position) > look + 80.0:
			continue
		var local := vehicle.to_local(v.global_position)
		var ahead := -local.y - vehicle.stats.size.y * 0.5 - v.stats.size.y * 0.5
		var need := half_w + v.stats.size.x * 0.5 + AVOID_MARGIN
		if ahead < -20.0 or ahead > look or absf(local.x) > need:
			continue
		if ahead < nearest:
			nearest = ahead
			# 장애물 반대쪽으로. 정면이면 오른쪽으로.
			var side := -signf(local.x) if absf(local.x) > 2.0 else 1.0
			shift = local.x + side * need
	if nearest == INF:
		return aim
	var a := vehicle.to_local(aim)
	var d := clampf(nearest + vehicle.stats.size.y, 40.0, maxf(-a.y, 40.0))
	return vehicle.to_global(Vector2(shift, -d))


func _check_stuck(speed: float, delta: float) -> void:
	if vehicle.throttle_input > 0.5 and absf(speed) < 25.0:
		_stuck += delta
	else:
		_stuck = maxf(_stuck - delta, 0.0)
	if _stuck > STUCK_TIME:
		_stuck = 0.0
		_reverse_left = REVERSE_TIME
		_reverse_steer = -vehicle.steer_input if absf(vehicle.steer_input) > 0.2 else 1.0
		stuck_count += 1
		waypoint = RoadNav.INVALID
