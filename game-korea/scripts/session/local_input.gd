class_name LocalPlayerInput
extends RefCounted
## 전역 입력을 읽는 어댑터. 시뮬레이션은 여기서 만든 월드 입력을 사용한다.

static func sample(into: PlayerInputCommand, screen_walk: bool) -> void:
	var push := Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
	var side := Input.get_axis("steer_left", "steer_right")
	into.turn = Input.get_axis("turn_left", "turn_right")
	into.forward = Input.get_action_strength("walk_forward") - Input.get_action_strength("walk_back")
	# 차는 방향키도 WASD처럼 몬다
	into.throttle = clampf(push + into.forward, -1.0, 1.0)
	into.steer = clampf(side + into.turn, -1.0, 1.0)
	var move := Vector2(side, -push).limit_length(1.0)
	into.move_world = IsoView.walk_dir(move) if IsoView.enabled and screen_walk else move
	into.sprint = Input.is_action_pressed("sprint")
	into.handbrake = Input.is_action_pressed("handbrake")
	into.fire = Input.is_action_pressed("fire")
	into.turret = Input.get_axis("weapon_prev", "weapon_next")
