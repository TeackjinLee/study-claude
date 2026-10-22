class_name PlayerRegistry
extends RefCounted
## 한 방의 참가자 등록부. 식별자·연결·노드 중복을 검사하고 조회만 담당한다.
## player_id와 peer_id를 같은 번호라고 가정하지 않는다. 관심 영역 이탈은 참가자 제거가 아니다.

signal player_added(player_id: int)
signal player_removed(player_id: int)
signal peer_changed(player_id: int, peer_id: int)

const CAPACITY := 4
var _players: Dictionary[int, GamePlayerSession] = {}
var _peers: Dictionary[int, int] = {}
var _retired: Dictionary[int, bool] = {}


func size() -> int:
	return _players.size()


func ids() -> Array[int]:
	var result: Array[int] = _players.keys()
	result.sort()
	return result


func find(player_id: int) -> GamePlayerSession:
	return _players.get(player_id)


func for_peer(peer_id: int) -> GamePlayerSession:
	return find(_peers.get(peer_id, 0)) if peer_id > 0 else null


func add(player_id: int, peer_id := 0) -> GamePlayerSession:
	if player_id <= 0 or peer_id < 0 or _players.has(player_id) or _retired.has(player_id) \
			or size() >= CAPACITY or (peer_id > 0 and _peers.has(peer_id)):
		return null
	var entry := GamePlayerSession.new(player_id)
	entry.peer_id = peer_id
	_players[player_id] = entry
	if peer_id > 0:
		_peers[peer_id] = player_id
	player_added.emit(player_id)
	return entry


## 재접속은 레코드를 지우지 않고 이 메서드로 연결을 교체한다.
func bind_peer(player_id: int, peer_id: int) -> bool:
	var entry := find(player_id)
	if entry == null or peer_id < 0 or (peer_id > 0 and _peers.has(peer_id) and _peers[peer_id] != player_id):
		return false
	if entry.peer_id == peer_id:
		return true
	if entry.peer_id > 0:
		_peers.erase(entry.peer_id)
	entry.peer_id = peer_id
	if peer_id > 0:
		_peers[peer_id] = player_id
	peer_changed.emit(player_id, peer_id)
	return true


func bind_actor(player_id: int, actor: Player) -> bool:
	var entry := find(player_id)
	if entry == null or not is_instance_valid(actor) or actor.is_queued_for_deletion():
		return false
	if entry.has_actor() and entry.actor != actor:
		return false
	for other: GamePlayerSession in _players.values():
		if other.player_id != player_id and other.has_actor() and other.actor == actor:
			return false
	entry.actor = actor
	return true


## 노드 정지·퇴장 처리는 세션 소유자가 먼저 한다. ID는 같은 방에서 재사용하지 않는다.
func remove(player_id: int) -> bool:
	var entry := find(player_id)
	if entry == null:
		return false
	if entry.peer_id > 0:
		_peers.erase(entry.peer_id)
	_players.erase(player_id)
	_retired[player_id] = true
	player_removed.emit(player_id)
	return true
