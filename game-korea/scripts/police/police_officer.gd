class_name PoliceOfficer
extends Pedestrian
## 도보 경찰. 보행자처럼 차를 피하고 차에 받히면 넘어지지만, 겁먹어 도망치지는 않는다.
## 할 일(duty)은 PoliceDispatcher가 정하고, 여기서는 그 목표로 걷거나 뛴다.

enum Duty { CHASE, RETURN, GUARD, LEAVE }

const ARRIVE := 14.0

var duty := Duty.CHASE
var car: Vehicle = null          ## 타고 온 경찰차 (빼앗기면 null)
var post := Vector2.ZERO         ## 지키는 자리 (도로 봉쇄). 차가 없으면 여기로 돌아간다
var goal := Vector2.ZERO         ## 디스패처가 매 프레임 넣는다 (CHASE: 주인공, RETURN: 차 문)
var reload := 0.0                ## 다음 발포까지 남은 시간 (★2부터 쏜다, PoliceDispatcher가 정한다)
var _waypoint := RoadNav.INVALID
var _los := true
var _los_timer := 0.0


func _physics_process(delta: float) -> void:
	reload -= delta
	if state == State.DODGE or state == State.KNOCKED or state == State.DEAD:
		super._physics_process(delta)
		return
	var vel := Vector2.ZERO
	match duty:
		Duty.CHASE, Duty.RETURN:
			vel = _toward(goal, delta) * npc.run_speed
		Duty.LEAVE:
			vel = _toward(goal, delta) * walk_speed
		Duty.GUARD:
			pass
	velocity = vel
	if vel != Vector2.ZERO:
		facing = Vector2.UP.angle_to(vel)
		walk_phase += delta * vel.length() / 9.0
	move_and_slide()
	queue_redraw()


func arrived() -> bool:
	return global_position.distance_to(goal) < ARRIVE


## 목표가 보이면 곧장, 건물에 가리면 도로를 따라 돈다. 이동 방향(단위 벡터)을 돌려준다.
func _toward(to: Vector2, delta: float) -> Vector2:
	var pos := global_position
	if pos.distance_to(to) < 2.0:
		return Vector2.ZERO
	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = 0.15
		_los = RoadNav.clear_path(get_world_2d().direct_space_state, pos, to, RADIUS)
	if _los:
		_waypoint = RoadNav.INVALID
		return (to - pos).normalized()
	if _waypoint == RoadNav.INVALID or pos.distance_to(LaneGraph.center(_waypoint)) < 20.0:
		_waypoint = RoadNav.next_cell(pos, Vector2.ZERO, to)
	return (LaneGraph.center(_waypoint) - pos).normalized()


## 경찰은 겁먹지 않는다: 넘어졌다 일어나도, 옆에서 누가 비명을 질러도 하던 일을 계속한다
func panic(_away: Vector2, _forced := false) -> bool:
	if state == State.DEAD:
		return false
	if state != State.KNOCKED or state_time <= 0.0:
		_set_state(State.WALK, 0.0)
	return false


func resume_walking() -> void:
	_set_state(State.WALK, 0.0)


func _draw() -> void:
	super._draw()
	if state != State.KNOCKED and state != State.DEAD:
		if IsoView.enabled:
			# 2.5D: 모자·헬멧은 NpcType 모습(hat)대로 PersonDrawer가 그린다
			return
		# 모자 챙
		draw_set_transform(Vector2.ZERO, facing, Vector2.ONE)
		draw_rect(Rect2(-3, -5.5, 6, 2), Color(0.05, 0.06, 0.14))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
