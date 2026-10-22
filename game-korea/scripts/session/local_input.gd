class_name LocalPlayerInput
extends RefCounted
## 전역 입력을 읽는 어댑터. 시뮬레이션은 여기서 만든 월드 입력을 사용한다.

static func sample(into: PlayerInputCommand, screen_walk: bool) -> void:
	into.throttle = Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
	into.steer = Input.get_axis("steer_left", "steer_right")
	var move := Vector2(into.steer, -into.throttle).limit_length(1.0)
	into.move_world = IsoView.walk_dir(move) if IsoView.enabled and screen_walk else move
	into.sprint = Input.is_action_pressed("sprint")
	into.handbrake = Input.is_action_pressed("handbrake")
	into.fire = Input.is_action_pressed("fire")
	into.turret = Input.get_axis("weapon_prev", "weapon_next")
