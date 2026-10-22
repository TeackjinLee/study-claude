class_name Paramedic
extends Pedestrian
## 구급대원. 구급차에서 내려 기절한 사람에게 달려가고, 둘이 들것을 들고 구급차 뒤로 옮긴다 (EmsDispatcher).
## 일하는 동안은 총소리에 겁먹지 않는다 (직접 맞으면 넘어진다). 들것을 드는 동안은 EmsDispatcher가 자리를 정한다.
## 기절시키면 바로 수배 ★4다 (PoliceDispatcher).

var goal := Vector2.INF           ## 달려갈 곳 (INF면 제자리)
var on_duty := true               ## 구급차 일 중 — 끝나면(구급차를 잃으면) 평범한 사람처럼 걷는다
var steered := false              ## 들것을 드는 중 — 자리는 EmsDispatcher가 옮긴다


func _physics_process(delta: float) -> void:
	if not on_duty or state == State.DEAD or state == State.DODGE:
		super._physics_process(delta)
		return
	_track_level()
	speech_time -= delta
	if state == State.KNOCKED:
		# 넘어졌다가 일어나면 하던 일로 돌아간다 (겁먹고 달아나지 않는다)
		state_time -= delta
		velocity = Vector2.ZERO
		if state_time <= 0.0:
			_set_state(State.WALK, 0.0)
		return
	if state != State.WALK:
		_set_state(State.WALK, 0.0)
	if steered:
		return
	var vel := Vector2.ZERO
	if goal != Vector2.INF and global_position.distance_to(goal) > 3.0:
		vel = (goal - global_position).normalized() * minf(npc.run_speed, global_position.distance_to(goal) * 8.0)
	velocity = vel
	if vel != Vector2.ZERO:
		facing = Vector2.UP.angle_to(vel)
		walk_phase += delta * vel.length() / 9.0
	move_and_slide()


## 일하는 구급대원은 겁먹지 않는다 (직접 맞았을 때만 피한다)
func panic(away: Vector2, forced := false) -> bool:
	if on_duty and not forced:
		return false
	return super.panic(away, forced)


## 일을 그만두고 평범한 사람처럼 걷는다
func off_duty() -> void:
	on_duty = false
	steered = false
	goal = Vector2.INF
	if not is_dead() and state != State.KNOCKED:
		resume_walking()
