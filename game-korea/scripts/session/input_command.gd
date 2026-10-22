class_name PlayerInputCommand
extends RefCounted
## 한 물리 틱의 지속 입력. 이동·조준은 카메라와 독립적인 월드 좌표다.
## 한 번 누르는 동작(탑승·무기 변경 등)은 PlayerControl.request_action으로 전달한다.

var move_world := Vector2.ZERO
var sprint := false
var throttle := 0.0
var steer := 0.0
var handbrake := false
var fire := false
var turret := 0.0
var aim_enabled := false
var aim_world := Vector2.ZERO


## 입력 출처의 객체를 보관하지 않고 값을 복사한다. 네트워크 권한 검사는 향후 서버에서 따로 한다.
func copy_from(other: PlayerInputCommand) -> void:
	move_world = other.move_world.limit_length(1.0) if other.move_world.is_finite() else Vector2.ZERO
	sprint = other.sprint
	throttle = clampf(other.throttle, -1.0, 1.0) if is_finite(other.throttle) else 0.0
	steer = clampf(other.steer, -1.0, 1.0) if is_finite(other.steer) else 0.0
	handbrake = other.handbrake
	fire = other.fire
	turret = clampf(other.turret, -1.0, 1.0) if is_finite(other.turret) else 0.0
	aim_enabled = other.aim_enabled and other.aim_world.is_finite()
	aim_world = other.aim_world if aim_enabled else Vector2.ZERO
