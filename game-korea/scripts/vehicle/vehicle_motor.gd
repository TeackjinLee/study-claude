class_name VehicleMotor
extends RefCounted
## 차량 물리의 순수 계산부. 노드·씬 트리 없이 돌아가므로 헤드리스 테스트에서 그대로 쓴다.
##
## 모델: 속도를 차체 기준 전진 성분과 옆 성분으로 나눈다.
## 전진 성분은 엔진·브레이크가, 옆 성분은 grip이 0으로 끌어당긴다.
## 차체가 돌면 이전 프레임의 속도가 새 차체 기준으로는 옆 성분을 갖게 되고,
## grip이 그걸 다 못 잡는 만큼 미끄러진다 — 이게 드리프트다.

var stats: VehicleType
var heading := 0.0          ## rad, 0 = 화면 위쪽
var velocity := Vector2.ZERO
var steer := 0.0            ## 현재 조향 (-1..1). 입력을 따라 부드럽게 움직인다


## 노면 상태 (비 오면 DayNight가 낮춘다). 모든 차에 같이 먹는다
static var road_grip := 1.0


func _init(p_stats: VehicleType) -> void:
	stats = p_stats


func forward() -> Vector2:
	return Vector2.UP.rotated(heading)


func right() -> Vector2:
	return Vector2.RIGHT.rotated(heading)


func forward_speed() -> float:
	return velocity.dot(forward())


func lateral_speed() -> float:
	return velocity.dot(right())


## throttle: -1..1 (음수 = 브레이크, 멈춘 뒤엔 후진), steer_input: -1..1
func step(throttle: float, steer_input: float, handbrake: bool, delta: float) -> void:
	var fwd := forward_speed()
	var lat := lateral_speed()

	if handbrake:
		fwd = move_toward(fwd, 0.0, stats.handbrake_decel * delta)
	elif throttle > 0.0:
		if fwd < 0.0:
			fwd = move_toward(fwd, 0.0, stats.brake_force * delta)
		else:
			fwd = move_toward(fwd, stats.max_speed * throttle, stats.acceleration * delta)
	elif throttle < 0.0:
		if fwd > 0.0:
			fwd = move_toward(fwd, 0.0, stats.brake_force * -throttle * delta)
		else:
			fwd = move_toward(fwd, -stats.reverse_speed, stats.acceleration * 0.6 * delta)
	else:
		fwd = move_toward(fwd, 0.0, stats.coast_drag * delta)

	var grip := stats.grip * (stats.handbrake_grip if handbrake else 1.0) * road_grip
	lat = move_toward(lat, 0.0, grip * delta)

	# 회전 '전' 차체 기준으로 속도를 다시 조립한다. 차체가 돈 만큼 다음 프레임에 옆 성분이 생긴다.
	velocity = forward() * fwd + right() * lat

	steer = move_toward(steer, clampf(steer_input, -1.0, 1.0), stats.steer_response * delta)
	# 조향력은 전체 속도로 정한다. 옆으로 미끄러지는 중에도(전진 성분≈0) 차체는 돌아야 드리프트가 된다.
	var authority := clampf(velocity.length() / stats.turn_speed_ref, 0.0, 1.0)
	# 후진 중에만 조향을 뒤집는다. 스핀으로 차체가 진행 방향을 등져도 핸들 방향은 그대로다.
	var reversing := throttle < 0.0 and fwd < -1.0 and not handbrake
	var direction := -1.0 if reversing else 1.0
	var rate := stats.turn_rate * (stats.drift_turn_boost if handbrake else 1.0)
	heading = wrapf(heading + steer * rate * authority * direction * delta, -PI, PI)
