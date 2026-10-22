class_name GamePlayerSession
extends RefCounted
## 방 안의 플레이어 한 명. player_id는 연결이 바뀌어도 유지하고 peer_id는 현재 연결만 나타낸다.
## 노드의 소유권은 씬에 있다. 레코드는 노드를 생성하거나 해제하지 않는다.

var player_id: int
var peer_id := 0
var actor: Player
var director: Director
var weapons: PlayerWeapons


func _init(id: int) -> void:
	player_id = id


func has_actor() -> bool:
	return is_instance_valid(actor) and not actor.is_queued_for_deletion()
