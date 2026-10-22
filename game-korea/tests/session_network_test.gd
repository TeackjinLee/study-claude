extends Node
## 격리된 MultiplayerAPI 셋을 실제 WebSocket으로 연결하여 권한·이동·입력 만료·퇴장을 검증한다.
var _failures: Array[String] = []
var _scopes: Array[Node] = []

func _ready() -> void:
	var server := _boot("Server", GameSessionContext.Role.SERVER)
	var a := _boot("First", GameSessionContext.Role.CLIENT)
	await _wait(func(): return a.snapshots > 0)
	var b := _boot("Second", GameSessionContext.Role.CLIENT)
	await _wait(func(): return a.actors.session.players.size() == 2 and b.actors.session.players.size() == 2)
	_expect(server.actors.session.players.size() == 2, "서버와 두 클라이언트 입장")
	if b.actors.session.players.size() != 2:
		_finish()
		return
	var id: int = a.actors.session.local_player_id()
	var other_id: int = b.actors.session.local_player_id()
	_expect(id > 0 and other_id > 0 and id != other_id, "서버가 서로 다른 로컬 참가자 ID 배정")
	# 자동 키보드 전송을 멈추고 실제 RPC로 첫 번째 연결의 입력만 보낸다.
	a.set_physics_process(false)
	b.set_physics_process(false)
	var source: Player = server.actors.session.players.find(id).actor
	var still: Player = server.actors.session.players.find(other_id).actor
	var before := source.position
	var other_before := still.position
	for i in range(1, 12):
		a.receive_input.rpc_id(1, 100 + i, Vector2.RIGHT, true)
		await get_tree().create_timer(0.04).timeout
	_expect(source.position.x > before.x + 50 and source.velocity.length() <= Player.RUN_SPEED + 0.01, "서버가 자신의 입력으로만 달리기·속도 제한")
	_expect(still.position.distance_to(other_before) < 1, "다른 참가자는 움직이지 않음")
	await get_tree().create_timer(0.65).timeout
	_expect(source.velocity == Vector2.ZERO, "입력 만료 시 서버 자동 정지")
	var peer: int = server.actors.session.players.find(id).peer_id
	_expect(not server.accept_input(peer, 1, Vector2.LEFT, false, Time.get_ticks_msec()), "과거 순번 거부")
	_expect(not server.accept_input(999, 999, Vector2.RIGHT, true, Time.get_ticks_msec()), "알 수 없는 연결 거부")
	_expect(not server.accept_input(peer, 1000, Vector2(NAN, 0), true, Time.get_ticks_msec()), "NaN 이동 거부")
	_expect(a.actors.session.players.find(id).actor.position.distance_to(source.position) < 0.1 and b.actors.session.players.find(id).actor.position.distance_to(source.position) < 0.1, "두 클라이언트가 서버 확정 좌표로 수렴")
	a._peer.close()
	await _wait(func(): return server.actors.session.players.size() == 1 and b.actors.session.players.size() == 1)
	_expect(server.actors.session.players.size() == 1 and b.actors.session.players.find(id) == null, "연결 해제 시 서버·상대 브라우저에서 제거")
	var c := _boot("Late", GameSessionContext.Role.CLIENT)
	await _wait(func(): return c.actors.session.players.size() == 2)
	_expect(c.actors.session.players.find(other_id) != null and c.actors.session.local_player_id() > other_id, "늦은 입장 전체 상태와 새 ID 배정")
	var d := _boot("Fourth", GameSessionContext.Role.CLIENT)
	await _wait(func(): return d.actors.session.players.size() == 3)
	var e := _boot("Fifth", GameSessionContext.Role.CLIENT)
	await _wait(func(): return e.actors.session.players.size() == 4)
	var excess := _boot("Excess", GameSessionContext.Role.CLIENT)
	await get_tree().create_timer(0.8).timeout
	_expect(server.actors.session.players.size() == 4 and excess.actors.session.players.size() == 0, "정원 4명·초과 연결 거부")
	server._peer.close()
	await get_tree().create_timer(0.5).timeout
	_expect(b.actors.session.players.size() == 0 and not b.is_physics_processing(), "서버 종료 시 클라이언트 정리·입력 정지")
	_finish()

func _boot(scope_name: String, role: GameSessionContext.Role) -> Node:
	var scope := Node.new()
	scope.name = scope_name
	add_child(scope)
	_scopes.append(scope)
	get_tree().set_multiplayer(SceneMultiplayer.new(), scope.get_path())
	var boot: Node = load("res://scripts/session/session_bootstrap.gd").new()
	boot.name = "NetworkSession"
	boot.role = role
	boot.server_port = 19089
	boot.server_url = "ws://127.0.0.1:19089"
	scope.add_child(boot)
	return boot

func _wait(predicate: Callable) -> void:
	var end := Time.get_ticks_msec() + 4000
	while not predicate.call() and Time.get_ticks_msec() < end:
		await get_tree().process_frame

func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)

func _finish() -> void:
	for scope in _scopes:
		scope.queue_free()
	await get_tree().process_frame
	for message in _failures:
		printerr("FAIL: ", message)
	print("session_network_test: ", "PASS" if _failures.is_empty() else "FAIL")
	get_tree().quit(0 if _failures.is_empty() else 1)
