extends RefCounted
## 서버·예측·재실행이 같은 60Hz 이동식을 쓴다. 도시 모드는 공통 정적 충돌을 검사한다.
## 차량·피격처럼 동적 객체가 만드는 결과는 아직 동기화하지 않는다.
const STEP := 1.0 / 60.0
const MIN_POSITION := Vector2(80, 80)
const MAX_POSITION := Vector2(720, 720)
const MAX_STATES := 32
var _buffers: Dictionary = {}


static func step(actor: Player, direction: Vector2, sprint: bool, city_world := false) -> void:
	var velocity := direction.limit_length(1.0) * (Player.RUN_SPEED if sprint else Player.WALK_SPEED)
	actor.velocity = velocity
	if city_world:
		var zone := CityMap.level_zone(actor.global_position)
		if zone >= 0:
			actor.set_level(zone)
		var from := actor.global_transform
		var remaining := velocity * STEP
		# 좌표를 중간마다 확정하지 않고 정적 벽에 대한 이동 검사만 재실행한다.
		for slide in range(3):
			if remaining.is_zero_approx():
				break
			var hit := KinematicCollision2D.new()
			if not actor.test_move(from, remaining, hit):
				from.origin += remaining
				break
			from.origin += hit.get_travel()
			remaining = hit.get_remainder().slide(hit.get_normal())
		actor.global_position = from.origin
		zone = CityMap.level_zone(actor.global_position)
		if zone >= 0:
			actor.set_level(zone)
	else:
		actor.global_position = (actor.global_position + velocity * STEP).clamp(MIN_POSITION, MAX_POSITION)
	if velocity != Vector2.ZERO:
		actor.facing = Vector2.UP.angle_to(velocity)
		actor.walk_phase += STEP * velocity.length() / 9.0


func push(id: int, tick: int, state: Array) -> void:
	if not _buffers.has(id):
		_buffers[id] = []
	var buffer: Array = _buffers[id]
	buffer.append([tick, state[2], state[3], state[4], state[5], state[7] if state.size() > 7 else 0])
	if buffer.size() > MAX_STATES:
		buffer.pop_front()


func count(id: int) -> int:
	return _buffers[id].size() if _buffers.has(id) else 0


func present(id: int, actor: Player, tick: float) -> void:
	if not _buffers.has(id) or _buffers[id].is_empty():
		return
	var buffer: Array = _buffers[id]
	while buffer.size() > 2 and buffer[1][0] <= tick:
		buffer.pop_front()
	var a: Array = buffer[0]
	var b: Array = buffer[1] if buffer.size() > 1 else a
	var weight := clampf((tick - a[0]) / maxf(b[0] - a[0], 1.0), 0.0, 1.0)
	# 층 전환은 다른 높이 사이를 가로질러 보간하지 않는다.
	if a[5] != b[5]:
		actor.global_position = b[1]
		actor.velocity = b[2]
		actor.facing = b[3]
		actor.walk_phase = b[4]
		actor.set_level(b[5])
		return
	actor.set_level(a[5])
	# 새 상태가 끊기면 최신 위치에서 멈추고 추측으로 계속 달리지 않는다.
	actor.global_position = a[1].lerp(b[1], weight)
	actor.velocity = a[2].lerp(b[2], weight)
	actor.facing = lerp_angle(a[3], b[3], weight)
	actor.walk_phase = lerpf(a[4], b[4], weight)


func erase(id: int) -> void:
	_buffers.erase(id)


func clear() -> void:
	_buffers.clear()
