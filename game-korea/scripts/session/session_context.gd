class_name GameSessionContext
extends RefCounted
## 역할은 생성 때 정하고 씬 수명 동안 바꾸지 않는다. headless 여부와 게임 권한은 별개다.
## 네트워크 연결·인증·입력 만료는 이후 전송 계층에서 처리한다.

enum Role { OFFLINE, SERVER, CLIENT }

var players := PlayerRegistry.new()
var _role: Role
var _local_player_id := 0


func _init(role: Role = Role.OFFLINE) -> void:
	_role = role
	players.peer_changed.connect(_on_peer_changed)
	players.player_removed.connect(_on_player_removed)


func role() -> Role:
	return _role


func is_authority() -> bool:
	return _role in [Role.OFFLINE, Role.SERVER]


func has_presentation() -> bool:
	return _role in [Role.OFFLINE, Role.CLIENT]


func local_player_id() -> int:
	return _local_player_id


func local_player() -> GamePlayerSession:
	return players.find(_local_player_id)


## 서버에는 로컬 키보드 소유자가 없다. 0은 로컬 선택을 해제한다.
func set_local_player(player_id: int) -> bool:
	if (_role == Role.SERVER and player_id != 0) or (player_id != 0 and players.find(player_id) == null):
		return false
	var previous := local_player()
	if previous != null and previous.has_actor():
		previous.actor.control.use_external()
	_local_player_id = player_id
	var current := local_player()
	if current != null and current.has_actor():
		current.actor.control.use_local()
	return true


func bind_actor(player_id: int, actor: Player) -> bool:
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		return false
	if not players.bind_actor(player_id, actor):
		return false
	if player_id == _local_player_id and has_presentation():
		actor.control.use_local()
	else:
		actor.control.use_external()
	# 클라이언트 위치는 스냅숏으로만 갱신한다. 예측은 다음 단계에서 추가한다.
	actor.set_physics_process(is_authority())
	actor.set_process(has_presentation())
	return true


## 호출한 peer로 소유자를 찾는다. 메시지에 적힌 player_id를 신뢰하지 않는다.
func submit_from_peer(peer_id: int, command: PlayerInputCommand) -> bool:
	if _role != Role.SERVER or command == null:
		return false
	var entry := players.for_peer(peer_id)
	if entry == null or not entry.has_actor():
		return false
	entry.actor.control.submit(command)
	return true


func action_from_peer(peer_id: int, action: StringName) -> bool:
	if _role != Role.SERVER or action not in [&"enter_exit", &"weapon_next", &"weapon_prev", &"fire"]:
		return false
	var entry := players.for_peer(peer_id)
	if entry == null or not entry.has_actor():
		return false
	entry.actor.control.request_action(action)
	return true


## 인증 처리가 아니다. 연결 교체 시 남아 있는 눌림을 지운다.
func _on_peer_changed(player_id: int, _peer_id: int) -> void:
	var entry := players.find(player_id)
	if entry != null and entry.has_actor():
		entry.actor.control.use_external()
		if player_id == _local_player_id and has_presentation():
			entry.actor.control.use_local()


func _on_player_removed(player_id: int) -> void:
	if player_id == _local_player_id:
		_local_player_id = 0
