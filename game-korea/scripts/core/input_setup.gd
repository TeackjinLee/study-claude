extends Node
## 입력 액션을 코드로 등록한다 (project.godot을 손으로 편집하지 않기 위해).

const KEYS := {
	"accelerate": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN],
	"steer_left": [KEY_A, KEY_LEFT],
	"steer_right": [KEY_D, KEY_RIGHT],
	"handbrake": [KEY_SPACE],
	"enter_exit": [KEY_F],
	"sprint": [KEY_SHIFT],
	"reset": [KEY_R],
	"fire": [KEY_CTRL, KEY_J],
	"weapon_prev": [KEY_Q],
	"weapon_next": [KEY_E],
	"vehicle_1": [KEY_1],
	"vehicle_2": [KEY_2],
	"vehicle_3": [KEY_3],
	"side_job": [KEY_B],
	"view_toggle": [KEY_F9],   ## 2.5D ↔ 위에서 보기
}

## [action, axis, 방향]
const PAD_AXES := [
	["accelerate", JOY_AXIS_TRIGGER_RIGHT, 1.0],
	["brake", JOY_AXIS_TRIGGER_LEFT, 1.0],
	["steer_left", JOY_AXIS_LEFT_X, -1.0],
	["steer_right", JOY_AXIS_LEFT_X, 1.0],
	["accelerate", JOY_AXIS_LEFT_Y, -1.0],   # 도보 이동용 (주행 중엔 스틱 위 = 가속)
	["brake", JOY_AXIS_LEFT_Y, 1.0],
]
const PAD_BUTTONS := {
	"handbrake": JOY_BUTTON_A,
	"enter_exit": JOY_BUTTON_Y,
	"sprint": JOY_BUTTON_LEFT_SHOULDER,
	"reset": JOY_BUTTON_BACK,
	"fire": JOY_BUTTON_X,
	"weapon_prev": JOY_BUTTON_DPAD_LEFT,
	"weapon_next": JOY_BUTTON_DPAD_RIGHT,
	"side_job": JOY_BUTTON_DPAD_UP,
}


func _enter_tree() -> void:
	for action: String in KEYS:
		_ensure(action)
		for key: Key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for entry: Array in PAD_AXES:
		var ev := InputEventJoypadMotion.new()
		ev.axis = entry[1]
		ev.axis_value = entry[2]
		InputMap.action_add_event(entry[0], ev)
	for action: String in PAD_BUTTONS:
		var ev := InputEventJoypadButton.new()
		ev.button_index = PAD_BUTTONS[action]
		InputMap.action_add_event(action, ev)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("fire", click)


func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
