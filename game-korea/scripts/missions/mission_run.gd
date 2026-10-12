class_name MissionRun
extends RefCounted
## 진행 중인 미션 하나의 상태. 노드 없는 순수 계산 —
## 세상에서 모은 사실(facts)만 보고 단계를 넘기거나 실패를 정한다. 스폰·그리기는 MissionSystem이 한다.
##
## facts 키:
##   pos: Vector2            주인공(차에 탔으면 차) 위치
##   speed: float            그 속도
##   in_vehicle: bool        미션 차에 타고 있다
##   vehicle_lost: bool      미션 차가 불타거나 부서졌다
##   vehicle_health: float   미션 차 체력 비율 (0~1)
##   targets_left: int       이번 단계에서 남은 표적 (KILL·DESTROY)
##   wanted: int             수배 별

signal step_started(index: int)
signal finished(passed: bool, reason: String)

enum State { RUNNING, PASSED, FAILED }

const DELIVER_SPEED := 120.0   ## 이보다 느려야 '세웠다'로 본다

var mission: MissionType
var step := 0
var elapsed := 0.0
var state := State.RUNNING
var fail_reason := ""


func _init(m: MissionType) -> void:
	mission = m


func current() -> MissionStep:
	return mission.steps[step] if step < mission.steps.size() else null


func running() -> bool:
	return state == State.RUNNING


## 남은 시간 (제한 없으면 INF)
func time_left() -> float:
	return maxf(mission.time_limit - elapsed, 0.0) if mission.time_limit > 0.0 else INF


func update(delta: float, facts: Dictionary) -> void:
	if not running():
		return
	elapsed += delta
	var reason := fail_check(facts)
	if reason != "":
		fail(reason)
		return
	if step_done(current(), facts):
		advance()


func advance() -> void:
	step += 1
	if step >= mission.steps.size():
		state = State.PASSED
		finished.emit(true, "")
	else:
		step_started.emit(step)


func fail(reason: String) -> void:
	if not running():
		return
	state = State.FAILED
	fail_reason = reason
	finished.emit(false, reason)


func fail_check(f: Dictionary) -> String:
	if mission.time_limit > 0.0 and elapsed >= mission.time_limit:
		return "시간 초과"
	if needs_vehicle() and f.get("vehicle_lost", false):
		return "차가 부서졌다"
	var s := current()
	if s.kind == MissionStep.Kind.DELIVER and s.min_health > 0.0 and f.get("vehicle_health", 1.0) < s.min_health:
		return "차가 너무 망가졌다"
	return ""


## 지금 단계나 남은 단계에 미션 차가 필요한지 (ENTER 단계 전에는 차가 없으니 아니다)
func needs_vehicle() -> bool:
	var s := current()
	if s.kind == MissionStep.Kind.ENTER:
		return false
	for k in range(step, mission.steps.size()):
		var t := mission.steps[k]
		if t.kind == MissionStep.Kind.DELIVER or (t.kind == MissionStep.Kind.GOTO and t.need_vehicle):
			return true
	return false


static func step_done(s: MissionStep, f: Dictionary) -> bool:
	var pos: Vector2 = f.get("pos", Vector2.INF)
	var inside: bool = f.get("in_vehicle", false)
	match s.kind:
		MissionStep.Kind.GOTO:
			return pos.distance_to(s.points[0]) < s.radius and (inside or not s.need_vehicle)
		MissionStep.Kind.ENTER:
			return inside
		MissionStep.Kind.DELIVER:
			return inside and pos.distance_to(s.points[0]) < s.radius and f.get("speed", 0.0) < DELIVER_SPEED
		MissionStep.Kind.KILL, MissionStep.Kind.DESTROY:
			return f.get("targets_left", 1) <= 0
		MissionStep.Kind.LOSE_WANTED:
			return f.get("wanted", 1) == 0
	return false
