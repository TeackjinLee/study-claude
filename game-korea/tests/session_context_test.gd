extends Node
## 참가자 ID/연결 분리, 역할별 물리·입력, 재접속과 싱글 연결의 수명을 검증한다.

var _failures: Array[String] = []


func _ready() -> void:
	_test_registry()
	await _test_roles()
	await _test_bootstrap()
	await _test_offline_main()
	if _failures.is_empty():
		print("session_context_test: PASS")
		get_tree().quit(0)
	else:
		for message in _failures:
			printerr("FAIL: ", message)
		get_tree().quit(1)


func _test_registry() -> void:
	var registry := PlayerRegistry.new()
	_expect(registry.add(0) == null and registry.add(1, -1) == null, "0번 참가자·음수 연결 거부")
	var first := registry.add(10, 101)
	_expect(first != null and registry.for_peer(101) == first, "참가자 ID와 peer ID는 별개")
	_expect(registry.add(10, 102) == null and registry.add(20, 101) == null, "참가자·연결 중복 거부")
	registry.add(20, 102)
	registry.add(30, 103)
	registry.add(40, 104)
	_expect(registry.add(50, 105) == null, "다섯 번째 참가자 거부")
	_expect(not registry.bind_peer(10, 102) and registry.for_peer(101) == first, "연결 충돌은 기존 매핑을 바꾸지 않음")
	_expect(registry.bind_peer(10, 201) and registry.for_peer(101) == null and registry.for_peer(201) == first, "재접속 시 참가자 ID 유지·옛 연결 제거")
	var actor := Player.new()
	_expect(registry.bind_actor(10, actor) and not registry.bind_actor(20, actor), "한 캐릭터의 중복 등록 거부")
	actor.free()
	_expect(not first.has_actor(), "해제된 캐릭터 조회는 안전하게 실패")
	_expect(registry.remove(10) and registry.for_peer(201) == null, "제거 시 연결 매핑도 제거")
	_expect(registry.add(10) == null and registry.add(50, 105) != null, "제거한 ID는 재사용하지 않고 새 ID로 입장")
	_expect(registry.ids() == [20, 30, 40, 50], "참가자 목록은 안정된 ID 순서")


func _test_roles() -> void:
	var server := SessionActors.new()
	server.session = GameSessionContext.new(GameSessionContext.Role.SERVER)
	add_child(server)
	var a := server.spawn_player(10, 101, Vector2(100, 100))
	var b := server.spawn_player(20, 102, Vector2(400, 100))
	_expect(server.session.is_authority() and not server.session.has_presentation(), "서버는 계산 권한만 가짐")
	_expect(not server.session.set_local_player(10), "서버에 로컬 키보드 소유자를 지정할 수 없음")
	_expect(not a.control.is_local() and a.is_physics_processing() and not a.is_processing(), "서버 캐릭터는 외부 입력·물리만 실행")
	var command := PlayerInputCommand.new()
	command.move_world = Vector2.RIGHT
	_expect(server.session.submit_from_peer(101, command), "연결 소유자의 입력 전달")
	command.move_world = Vector2.DOWN
	server.session.submit_from_peer(102, command)
	_expect(not server.session.submit_from_peer(999, command), "알 수 없는 연결 입력 거부")
	Input.action_press("accelerate")
	await _frames(3)
	_expect(a.velocity.is_equal_approx(Vector2.RIGHT * Player.WALK_SPEED) and b.velocity.is_equal_approx(Vector2.DOWN * Player.WALK_SPEED), "서버의 두 플레이어는 독립 입력으로 이동")
	server.session.players.bind_peer(10, 0)
	await _frames(2)
	_expect(a.velocity == Vector2.ZERO and not server.session.submit_from_peer(101, command), "접속 해제 시 눌림 제거·옛 연결 차단")
	server.session.players.bind_peer(10, 201)
	_expect(server.session.submit_from_peer(201, command), "재접속한 연결로 입력 재개")
	var requests: Array = []
	a.control.action_requested.connect(func(action): requests.append(action))
	_expect(server.session.action_from_peer(201, &"enter_exit") and requests == [&"enter_exit"], "단발 동작도 연결 소유자에게 전달")
	_expect(not server.session.action_from_peer(101, &"enter_exit") and not server.session.action_from_peer(201, &"unknown"), "옛 연결·알 수 없는 동작 거부")
	var client := SessionActors.new()
	client.position = Vector2(50, 30)
	client.session = GameSessionContext.new(GameSessionContext.Role.CLIENT)
	add_child(client)
	var view := client.spawn_player(10, 101, Vector2(100, 700))
	client.session.set_local_player(10)
	_expect(not client.session.is_authority() and client.session.has_presentation(), "클라이언트는 표시 역할")
	_expect(view.control.is_local() and not view.is_physics_processing(), "로컬 클라이언트도 아직 위치를 임의 확정하지 않음")
	var before := view.global_position
	await _frames(3)
	_expect(view.global_position == before, "클라이언트는 키보드로 서버 이동을 중복 계산하지 않음")
	_expect(not client.session.submit_from_peer(101, command), "클라이언트는 서버 입력 적용 API를 사용할 수 없음")
	_expect(client.apply_player_state(10, Vector2(800, 700), Vector2.RIGHT, 1.0, 1), "클라이언트는 수신한 상태를 표시")
	await _frames(2)
	_expect(view.global_position == Vector2(800, 700) and view.level == 1, "수신한 위치·층 유지")
	_expect(not client.apply_player_state(10, Vector2(NAN, 0), Vector2.ZERO, 0, 0), "유효하지 않은 상태 거부")
	_expect(not server.apply_player_state(10, Vector2.ZERO, Vector2.ZERO, 0, 0), "서버는 클라이언트 표시 API를 실행하지 않음")
	_expect(client.remove_player(10) and client.session.local_player_id() == 0, "퇴장하면 로컬 선택도 해제")
	_expect(not client.remove_player(10), "중복 퇴장 안전 처리")
	Input.action_release("accelerate")
	var context := server.session
	server.queue_free()
	client.queue_free()
	await _frames(2)
	_expect(context.players.size() == 0, "세션 컨테이너 해제 시 등록부 정리")


func _test_bootstrap() -> void:
	for path in ["res://scenes/session/server.tscn", "res://scenes/session/client.tscn"]:
		var boot: Node = load(path).instantiate()
		boot.auto_connect = false
		add_child(boot)
		var context: GameSessionContext = boot.actors.session
		var expected: GameSessionContext.Role = GameSessionContext.Role.SERVER if "server" in path else GameSessionContext.Role.CLIENT
		_expect(context.role() == expected and context.players.size() == 0, "서버·클라이언트 진입 씬은 역할만 준비하고 싱글 세계를 만들지 않음")
		boot.queue_free()
		await _frames(2)


func _test_offline_main() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = 0
	main.bus_count = 0
	main.police_patrols = 0
	main.load_on_start = false
	add_child(main)
	var context: GameSessionContext = main.session
	var local := context.local_player()
	_expect(context.role() == GameSessionContext.Role.OFFLINE and context.is_authority() and context.has_presentation(), "싱글 기본 역할 유지")
	_expect(context.players.size() == 1 and local.player_id == 1 and local.actor == main.player, "기존 player가 등록부의 로컬 플레이어와 일치")
	_expect(local.director == main.director and local.weapons == main.weapons, "기존 조종권·무기 참조 연결")
	_expect(main.player.control.is_local(), "싱글 로컬 입력 유지")
	main.queue_free()
	await _frames(2)
	_expect(context.players.size() == 0 and context.local_player_id() == 0, "싱글 장면 종료 시 등록부 정리")


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
