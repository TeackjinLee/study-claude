class_name ChaseCamera
extends Node2D
## 조종 대상(차·사람)을 따라가는 카메라. 진행 방향을 앞서 보여 주고, 빠를수록 줌아웃한다.
## 대상은 follow_velocity()와 zoom_ratio()를 가진 Node2D면 된다.
## Camera2D는 사선(2.5D) 변환을 못 하므로, 화면 변환(canvas_transform)을 직접 정한다 (IsoView).
## 다른 시스템은 화면 가운데를 ChaseCamera.current_cam()으로 묻는다.

const BASE_ZOOM := 1.1
const FAST_ZOOM := 0.62
const LOOK_AHEAD := 0.35      ## 속도 × 이 값(초)만큼 앞을 본다
const FOLLOW_SHARPNESS := 6.0
const ZOOM_SHARPNESS := 2.5
const VIEW_LIFT := 0.8        ## 떠 있는 헬기를 따라갈 때 화면을 높이의 이만큼 올려 헬기가 가운데 오게 한다

static var current: ChaseCamera

var target: Node2D
var zoom := Vector2(BASE_ZOOM, BASE_ZOOM)
var _view_lift := 0.0         ## 화면을 올린 높이 (2.5D 화면 px). global_position(화면 가운데 땅)은 그대로다


func _ready() -> void:
	process_priority = 1000      # 모든 이동이 끝난 뒤 화면을 맞춘다
	if target:
		global_position = target.global_position


func _exit_tree() -> void:
	if current == self:
		current = null


func make_current() -> void:
	current = self


## 지금 화면을 맡은 카메라 (없으면 null). 다른 시스템은 global_position을 화면 가운데로 쓴다
static func current_cam() -> ChaseCamera:
	if is_instance_valid(current) and current.is_inside_tree():
		return current
	return null


func snap() -> void:
	global_position = target.global_position
	zoom = Vector2(BASE_ZOOM, BASE_ZOOM)
	_view_lift = 0.0
	_apply()


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var vel: Vector2 = target.call("follow_velocity")
	var goal := target.global_position + vel * LOOK_AHEAD
	global_position = global_position.lerp(goal, 1.0 - exp(-FOLLOW_SHARPNESS * delta))
	var ratio: float = target.call("zoom_ratio")
	var z := lerpf(BASE_ZOOM, FAST_ZOOM, ratio)
	zoom = zoom.lerp(Vector2(z, z), 1.0 - exp(-ZOOM_SHARPNESS * delta))
	var altitude: Variant = target.get("altitude")
	_view_lift = lerpf(_view_lift, (altitude if altitude != null else 0.0) * VIEW_LIFT, 1.0 - exp(-FOLLOW_SHARPNESS * delta))


func _process(_delta: float) -> void:
	_apply()


func _apply() -> void:
	if current != self or not is_inside_tree():
		return
	var size := get_viewport().get_visible_rect().size
	# 웹에서는 보이는 도시 범위를 줄여 그리기 호출을 낮춘다 (추적·물리 위치는 그대로).
	var draw_zoom := zoom * (1.35 if OS.has_feature("web") else 1.0)
	if IsoView.enabled:
		get_viewport().canvas_transform = IsoView.canvas(size, global_position + IsoView.lift(_view_lift), draw_zoom.x)
	else:
		var t := Transform2D(0.0, draw_zoom, 0.0, Vector2.ZERO)
		t.origin = size * 0.5 - global_position * draw_zoom
		get_viewport().canvas_transform = t
