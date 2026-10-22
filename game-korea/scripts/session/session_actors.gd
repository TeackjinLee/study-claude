class_name SessionActors
extends Node2D
## 서버/클라이언트 진입점에서 사용할 참가자 노드 컨테이너. 도시·AI·통신은 아직 만들지 않는다.
## 서버는 외부 입력으로 물리를 실행하고 클라이언트는 확정 상태를 받아 표시한다.

var session := GameSessionContext.new(GameSessionContext.Role.SERVER)
var _owned: Dictionary[int, Player] = {}


func spawn_player(player_id: int, peer_id := 0, at := Vector2.ZERO) -> Player:
	if not is_inside_tree() or not at.is_finite():
		return null
	var entry := session.players.add(player_id, peer_id)
	if entry == null:
		return null
	var actor := Player.new()
	actor.name = "Player_%d" % player_id
	# _ready 전부터 외부 입력으로 두어 로컬 키를 읽지 않게 한다.
	actor.control.use_external()
	add_child(actor)
	actor.global_position = at
	if not session.bind_actor(player_id, actor):
		session.players.remove(player_id)
		actor.queue_free()
		return null
	_owned[player_id] = actor
	return actor


func remove_player(player_id: int) -> bool:
	if not _owned.has(player_id):
		return false
	var actor: Player = _owned[player_id]
	if is_instance_valid(actor):
		actor.control.use_external()
		actor.input_enabled = false
		actor.set_physics_process(false)
		actor.queue_free()
	_owned.erase(player_id)
	return session.players.remove(player_id)


## 수신 처리에서 호출할 클라이언트 표시 API. 신뢰할 서버 연결 판별은 다음 단계다.
func apply_player_state(player_id: int, at: Vector2, velocity: Vector2, facing: float, level: int) -> bool:
	if session.role() != GameSessionContext.Role.CLIENT or not at.is_finite() \
			or not velocity.is_finite() or not is_finite(facing) or level not in [0, 1]:
		return false
	var entry := session.players.find(player_id)
	if entry == null or not entry.has_actor():
		return false
	entry.actor.global_position = at
	entry.actor.velocity = velocity
	entry.actor.facing = facing
	entry.actor.set_level(level)
	return true


func _exit_tree() -> void:
	# 외부에 보관된 context에도 해제된 참가자를 남기지 않는다.
	for player_id in _owned.keys():
		session.players.remove(player_id)
	_owned.clear()
