class_name GangMember
extends Pedestrian
## 갱 조직원. 평소엔 시민처럼 인도를 걷지만, 싸울 때는 겁먹지 않고 주인공에게 다가가 총을 쏜다.
## 싸울지·쏠지는 GangManager가 정하고, 여기서는 fighting이면 goal 쪽으로 움직이기만 한다.

const KEEP_DISTANCE := 140.0     ## 이만큼 떨어져 서서 쏜다

var gang: GangType
var resident := false            ## 구역을 도는 조직원 (아니면 미션이 세운 사람 — 끝나면 화면 밖에서 치운다)
var guard := false               ## 미션 표적·경호: 자리를 지키고, 주인공이 다가오면 늘 싸운다
var home := Vector2.ZERO         ## guard가 지키는 자리
var fighting := false            ## GangManager가 매 프레임 넣는다
var goal := Vector2.ZERO
var aggro := 0.0                 ## 맞아서 화가 난 남은 시간
var reload := 0.0


func _physics_process(delta: float) -> void:
	reload -= delta
	aggro = maxf(aggro - delta, 0.0)
	# 싸우는 조직원은 겁먹지 않는다 — 화나기 전에 도망치던 참이면 돌아선다.
	# (아래 싸움 분기는 상태 시간을 줄이지 않아, 그대로 두면 FLEE로 영영 남아 쏘지 못했다)
	if (fighting or guard) and state in [State.FLEE, State.IDLE]:
		_set_state(State.WALK, 0.0)
	var busy := state == State.DODGE or state == State.KNOCKED or state == State.DEAD
	if busy or not (fighting or guard):
		super._physics_process(delta)
		return
	var vel := Vector2.ZERO
	if fighting:
		var to := goal - global_position
		if to.length() > keep_distance():
			vel = to.normalized() * npc.run_speed
		facing = Vector2.UP.angle_to(to)
	elif global_position.distance_to(home) > 8.0:
		vel = (home - global_position).normalized() * walk_speed
		facing = Vector2.UP.angle_to(vel)
	velocity = vel
	if vel != Vector2.ZERO:
		walk_phase += delta * vel.length() / 9.0
	move_and_slide()
	queue_redraw()


## 이만큼 떨어져 서서 공격한다 (주먹이면 바짝 붙는다)
func keep_distance() -> float:
	if npc.weapon and npc.weapon.melee:
		return npc.weapon.max_range * 0.5
	return KEEP_DISTANCE


## 싸우는 조직원·경호원은 겁먹지 않는다
func panic(away: Vector2, forced := false) -> bool:
	if state == State.DEAD:
		return false
	if fighting or guard:
		if state != State.KNOCKED or state_time <= 0.0:
			_set_state(State.WALK, 0.0)
		return false
	return super.panic(away, forced)


func resume_walking() -> void:
	if guard:
		_set_state(State.WALK, 0.0)
	else:
		super.resume_walking()


func _draw() -> void:
	super._draw()
	if state == State.KNOCKED or state == State.DEAD or gang == null:
		return
	if IsoView.enabled:
		# 2.5D: 가슴에 갱 상징색 띠
		draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, IsoView.ground(global_position)).scaled_local(Vector2(npc.body_scale, npc.body_scale)))
		draw_rect(Rect2(-4.5, -17, 9, 2.2), gang.accent)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	# 어깨에 갱 상징색 띠 — 시민과 구별된다
	draw_set_transform(Vector2.ZERO, facing, Vector2.ONE)
	draw_rect(Rect2(-6, 1.5, 12, 1.8), gang.accent)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
