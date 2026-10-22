class_name PlayerControl
extends RefCounted
## 플레이어마다 하나씩 가진 입력 출처. 기본은 로컬, 외부 모드는 키보드를 읽지 않는다.
## 이동에 필요한 입력만 보관한다. 현재 차·체력·실제 게임 결과는 기존 게임 시스템이 결정한다.

signal action_requested(action: StringName)

var _local := true
var _command := PlayerInputCommand.new()


func is_local() -> bool:
	return _local


## 반환값은 내부 버퍼다. 호출자는 보관하거나 수정하지 않고 현재 틱에서만 읽는다.
func read(screen_walk := true) -> PlayerInputCommand:
	if _local:
		LocalPlayerInput.sample(_command, screen_walk)
	return _command


## 외부 명령은 이미 월드 방향이어야 한다. 호출자의 이후 수정은 이 객체에 영향을 주지 않는다.
func submit(command: PlayerInputCommand) -> void:
	_local = false
	_command.copy_from(command)


## 연결 해제·입력 출처 변경 시 눌림이 남지 않도록 중립 입력으로 바꾼다.
func use_external() -> void:
	_local = false
	_command = PlayerInputCommand.new()


func use_local() -> void:
	_local = true
	_command = PlayerInputCommand.new()


## 한 번의 동작을 요청한다. 서버의 중복 방지·권한 검사는 네트워크 단계에서 추가한다.
func request_action(action: StringName) -> void:
	if action in [&"enter_exit", &"weapon_next", &"weapon_prev", &"fire"]:
		action_requested.emit(action)
