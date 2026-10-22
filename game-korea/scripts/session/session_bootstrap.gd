extends Node
## 로컬 전용 WebSocket 도시·연습장 세션. 내 입력 예측·상대 보간을 쓰되 서버가 이동·참가자 ID를 확정한다.

@export var role: GameSessionContext.Role = GameSessionContext.Role.SERVER
@export var auto_connect := true
@export var city_world := false
@export var world_chapter := 1
@export var server_port := 9080
@export var server_url := "ws://127.0.0.1:9080"
const Motion = preload("res://scripts/session/session_motion.gd")
const INPUT_INTERVAL := 1.0 / 30.0
const STATE_INTERVAL := 1.0 / 15.0
const INPUT_LEASE_MS := 500
var city: City
var actors: SessionActors
var status := "연결 준비"
var snapshots := 0
var _peer: WebSocketMultiplayerPeer
var _next_id := 1
var _sequence := 0
var _last_snapshot := -1
var _input_clock := 0.0
var _state_clock := 0.0
var _last_received: Dictionary[int, int] = {}
var _last_sequence: Dictionary[int, int] = {}
var _tick := 0
var _connected_at := 0
var _ready_for_input := false
var _focused := true
var _view: Node
var _motion := Motion.new()
var _pending: Array = []
var _outgoing: Array = []
var _queues: Dictionary = {}
var _applied: Dictionary = {}
var _predicted := Vector2.ZERO
var _correction := Vector2.ZERO
var _snapshot_at := 0
var _render_tick := -1.0


func _ready() -> void:
	actors = SessionActors.new()
	actors.session = GameSessionContext.new(role)
	add_child(actors)
	set_physics_process(false)
	if not auto_connect:
		return
	city_world = _arg("world", "city" if city_world else "arena") == "city"
	if role == GameSessionContext.Role.SERVER and city_world:
		world_chapter = clampi(int(_arg("chapter", str(world_chapter))), 1, CityMap.LAST_CHAPTER)
		_create_city()
	if multiplayer is SceneMultiplayer:
		# 참가자 사이의 직접 통신은 쓰지 않는다. 입퇴장 정보도 서버 스냅숏으로 받는다.
		(multiplayer as SceneMultiplayer).server_relay = false
	# 두 진입 씬은 동일 RPC 경로(/root/NetworkSession)를 사용한다.
	multiplayer.peer_connected.connect(_joined)
	multiplayer.peer_disconnected.connect(_left)
	multiplayer.connection_failed.connect(_failed)
	multiplayer.server_disconnected.connect(_failed)
	_peer = WebSocketMultiplayerPeer.new()
	var error: Error
	if role == GameSessionContext.Role.SERVER:
		Engine.max_fps = 60
		error = _peer.create_server(int(_arg("port", str(server_port))), "127.0.0.1")
		status = "서버 대기 · 최대 4명"
	else:
		error = _peer.create_client(_server_url())
		status = "서버 연결 중"
		_view = load("res://scripts/session/session_view.gd").new()
		_view.boot = self
		add_child(_view)
		Engine.max_fps = 30 if OS.has_feature("web") else 60
	if error != OK:
		status = "연결 시작 실패: %s" % error_string(error)
		printerr(status)
		if role == GameSessionContext.Role.SERVER:
			get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = _peer
	_connected_at = Time.get_ticks_msec()
	process_physics_priority = -10
	set_physics_process(true)
	print("SESSION_START role=%s port=%s" % [GameSessionContext.Role.keys()[role], _arg("port", str(server_port))])


## 서버 권한으로 정한 장을 양쪽에 적용한다. 싱글 Main의 AI·저장·로컬 플레이어는 생성하지 않는다.
func _create_city() -> void:
	if city != null:
		return
	CityMap.set_chapter(world_chapter)
	RoadNav.clear_cache()
	city = City.new()
	city.name = "SharedCity"
	city.presentation_enabled = role == GameSessionContext.Role.CLIENT
	add_child(city)
	print("SESSION_WORLD city chapter=%d buildings=%d presentation=%s" % [world_chapter, city.buildings.size(), city.presentation_enabled])


func _server_url() -> String:
	if OS.has_feature("web"):
		return JavaScriptBridge.eval("(location.protocol === 'https:' ? 'wss://' : 'ws://') + location.hostname + ':9080'")
	return _arg("server-url", server_url)


func _arg(key: String, fallback: String) -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with("--%s=" % key):
			return value.get_slice("=", 1)
	return fallback


func _joined(peer_id: int) -> void:
	if role != GameSessionContext.Role.SERVER:
		return
	if actors.session.players.size() >= PlayerRegistry.CAPACITY:
		_peer.disconnect_peer(peer_id)
		return
	var id := _next_id
	_next_id += 1
	var slot := 0
	# 퇴장 뒤 빈 시작 지점을 재사용하되 참가자 ID는 재사용하지 않는다.
	while _slot_used(slot):
		slot += 1
	var at := City.start_position() + Vector2(0, slot * 24) if city_world else Vector2(280 + slot * 80, 400)
	var actor := actors.spawn_player(id, peer_id, at)
	if actor == null:
		_peer.disconnect_peer(peer_id)
		return
	actor.set_meta("spawn_slot", slot)
	# 동일 고정 틱 계산을 서버와 예측 양쪽에서 사용한다.
	actor.set_physics_process(false)
	_queues[peer_id] = []
	_applied[peer_id] = -1
	_last_received[peer_id] = Time.get_ticks_msec()
	_last_sequence[peer_id] = -1
	_welcome.rpc_id(peer_id, id, city_world, world_chapter)
	_broadcast()
	print("SESSION_JOIN player=%d peer=%d count=%d" % [id, peer_id, actors.session.players.size()])


func _slot_used(slot: int) -> bool:
	for id in actors.session.players.ids():
		if actors.session.players.find(id).actor.get_meta("spawn_slot", -1) == slot:
			return true
	return false


func _left(peer_id: int) -> void:
	if role != GameSessionContext.Role.SERVER:
		return
	var entry := actors.session.players.for_peer(peer_id)
	if entry != null:
		print("SESSION_LEAVE player=%d" % entry.player_id)
		actors.remove_player(entry.player_id)
	_last_received.erase(peer_id)
	_last_sequence.erase(peer_id)
	_queues.erase(peer_id)
	_applied.erase(peer_id)
	_broadcast()


@rpc("authority", "call_remote", "reliable")
func _welcome(player_id: int, use_city: bool, chapter: int) -> void:
	if role == GameSessionContext.Role.CLIENT:
		city_world = use_city
		world_chapter = clampi(chapter, 1, CityMap.LAST_CHAPTER)
		if city_world:
			_create_city()
		_view.configure_world()
		# 첫 전체 상태를 받은 뒤에만 로컬 입력을 활성화한다.
		set_meta("assigned_player", player_id)


@rpc("any_peer", "call_remote", "reliable")
func receive_input(sequence: int, direction: Vector2, sprint: bool) -> void:
	if role != GameSessionContext.Role.SERVER:
		return
	var sender := multiplayer.get_remote_sender_id()
	accept_input(sender, sequence, direction, sprint, Time.get_ticks_msec())


## 수신자 신원은 RPC가 제공한 연결 ID만 사용한다. 좌표·속도·다른 플레이어 ID는 받지 않는다.
func accept_input(sender: int, sequence: int, direction: Vector2, sprint: bool, now: int) -> bool:
	if role != GameSessionContext.Role.SERVER or not _last_sequence.has(sender) \
			or sequence <= _last_sequence[sender] or not direction.is_finite():
		return false
	# 한 연결의 과도한 입력을 버린다. 새 입력이 없으면 0.5초 뒤 정지한다.
	if _last_sequence[sender] >= 0 and now - _last_received[sender] < 12:
		return false
	var command := PlayerInputCommand.new()
	command.move_world = direction.limit_length(1.0)
	command.sprint = sprint
	if not actors.session.submit_from_peer(sender, command):
		return false
	_last_received[sender] = now
	_last_sequence[sender] = sequence
	return true


## 클라이언트는 물리 틱별 입력을 묶어 보낸다. 시간·이동량은 서버가 고정한다.
@rpc("any_peer", "call_remote", "reliable")
func receive_frames(frames: Array) -> void:
	accept_frames(multiplayer.get_remote_sender_id(), frames, Time.get_ticks_msec())


func accept_frames(sender: int, frames: Array, now: int) -> bool:
	if role != GameSessionContext.Role.SERVER or not _queues.has(sender) \
			or frames.is_empty() or frames.size() > 8 or _queues[sender].size() + frames.size() > 120:
		return false
	var previous: int = _last_sequence[sender]
	# 부분 적용 전에 묶음 전체를 검사한다.
	for frame in frames:
		if not frame is Array or frame.size() != 3 or not frame[0] is int \
				or not frame[1] is Vector2 or not frame[2] is bool:
			return false
		if frame[0] != previous + 1 or not frame[1].is_finite():
			return false
		previous = frame[0]
	for frame: Array in frames:
		_queues[sender].append([frame[0], frame[1].limit_length(1.0), frame[2]])
	_last_sequence[sender] = previous
	_last_received[sender] = now
	return true


func _physics_process(delta: float) -> void:
	if _peer == null:
		return
	if role == GameSessionContext.Role.SERVER:
		_tick += 1
		for id in actors.session.players.ids():
			var entry := actors.session.players.find(id)
			var peer_id := entry.peer_id
			var command := PlayerInputCommand.new()
			if Time.get_ticks_msec() - _last_received.get(peer_id, 0) > INPUT_LEASE_MS:
				_queues[peer_id].clear()
				entry.actor.control.use_external()
			elif not _queues[peer_id].is_empty():
				var frame: Array = _queues[peer_id].pop_front()
				command.move_world = frame[1]
				command.sprint = frame[2]
				_applied[peer_id] = frame[0]
			else:
				# 이전 단일 입력 API도 같은 서버 속도 제한을 사용한다.
				command = entry.actor.control.read(false)
			Motion.step(entry.actor, command.move_world, command.sprint, city_world)
		_state_clock += delta
		if _state_clock >= STATE_INTERVAL:
			_state_clock = fmod(_state_clock, STATE_INTERVAL)
			_broadcast()
	else:
		if not _ready_for_input:
			if Time.get_ticks_msec() - _connected_at > 10000:
				_failed()
			return
		_predict_input()
		_input_clock += delta
		if _input_clock >= INPUT_INTERVAL:
			_input_clock = fmod(_input_clock, INPUT_INTERVAL)
			_send_input()
		if Time.get_ticks_msec() - _connected_at > 3000:
			_failed()


func _predict_input() -> void:
	# 지연이 길어져도 입력 기록과 재실행 비용을 무한히 늘리지 않는다.
	if _pending.size() >= 120 or _outgoing.size() >= 8:
		return
	var command := PlayerInputCommand.new()
	var visible := true
	if OS.has_feature("web"):
		visible = not JavaScriptBridge.eval("document.hidden")
	if _focused and visible:
		LocalPlayerInput.sample(command, true)
	var actor: Player = actors.session.local_player().actor
	actor.global_position = _predicted
	Motion.step(actor, command.move_world, command.sprint, city_world)
	_predicted = actor.global_position
	var frame: Array = [_sequence, command.move_world, command.sprint]
	_sequence += 1
	_pending.append(frame)
	_outgoing.append(frame)


func _send_input() -> void:
	if _outgoing.is_empty() or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var socket := _peer.get_peer(1)
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN \
			or socket.get_current_outbound_buffered_amount() > 8192:
		return
	receive_frames.rpc_id(1, _outgoing.duplicate())
	_outgoing.clear()


func _process(delta: float) -> void:
	if role != GameSessionContext.Role.CLIENT or not _ready_for_input:
		return
	# 수신 시각의 지터로 표시 시간이 뒤로 가지 않도록 단조롭게 진행한다.
	var latest := float(_last_snapshot) + (Time.get_ticks_msec() - _snapshot_at) * 0.06 - 6.0
	_render_tick = maxf(_render_tick, minf(_render_tick + delta * 60.0, latest))
	for id in actors.session.players.ids():
		var actor: Player = actors.session.players.find(id).actor
		if id == actors.session.local_player_id():
			_correction *= exp(-delta * 18.0)
			if _correction.length_squared() < 0.25:
				_correction = Vector2.ZERO
			actor.global_position = _predicted + _correction
		else:
			_motion.present(id, actor, _render_tick)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_focused = false
		for action in ["accelerate", "brake", "steer_left", "steer_right", "sprint"]:
			Input.action_release(action)
		if _ready_for_input:
			_send_input()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_focused = true


func _broadcast() -> void:
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var states: Array = []
	for id in actors.session.players.ids():
		var entry := actors.session.players.find(id)
		var actor := entry.actor
		states.append([id, entry.peer_id, actor.global_position, actor.velocity, actor.facing, actor.walk_phase, _applied.get(entry.peer_id, -1), actor.level])
	for peer_id in multiplayer.get_peers():
		if actors.session.players.for_peer(peer_id) == null:
			continue
		var socket := _peer.get_peer(peer_id)
		if socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN \
				and socket.get_current_outbound_buffered_amount() < 16384:
			_state.rpc_id(peer_id, _tick, states)


@rpc("authority", "call_remote", "reliable")
func _state(tick: int, states: Array) -> void:
	if role != GameSessionContext.Role.CLIENT or tick <= _last_snapshot or states.size() > PlayerRegistry.CAPACITY:
		return
	_last_snapshot = tick
	_snapshot_at = Time.get_ticks_msec()
	if _render_tick < 0.0:
		_render_tick = tick - 6.0
	var assigned: int = get_meta("assigned_player", 0)
	var present: Array[int] = []
	for state: Array in states:
		if state.size() != 8:
			return
		var id: int = state[0]
		present.append(id)
		if actors.session.players.find(id) == null:
			actors.spawn_player(id, state[1], state[2])
		var actor: Player = actors.session.players.find(id).actor
		if id == assigned:
			var old_position := actor.global_position
			var old_level := actor.level
			actors.apply_player_state(id, state[2], state[3], state[4], state[7])
			actor.walk_phase = state[5]
			while not _pending.is_empty() and _pending[0][0] <= state[6]:
				_pending.pop_front()
			for frame: Array in _pending:
				Motion.step(actor, frame[1], frame[2], city_world)
			_predicted = actor.global_position
			# 미확인 예측 입력이 없으면 서버 위치를 불필요하게 뒤늦게 따라가지 않는다.
			_correction = old_position - _predicted if _ready_for_input and not _pending.is_empty() else Vector2.ZERO
			# 텔레포트·긴 단절은 과거 위치를 끌고 오지 않는다.
			if _correction.length() > 80.0 or old_level != actor.level:
				_correction = Vector2.ZERO
		else:
			_motion.push(id, tick, state)
			if _motion.count(id) == 1:
				actors.apply_player_state(id, state[2], state[3], state[4], state[7])
				actor.walk_phase = state[5]
	for id in actors.session.players.ids():
		if id not in present:
			actors.remove_player(id)
			_motion.erase(id)
	if assigned > 0 and not _ready_for_input and actors.session.players.find(assigned) != null:
		actors.session.set_local_player(assigned)
		_ready_for_input = true
		print("SESSION_READY local=%d players=%s" % [assigned, present])
	snapshots += 1
	_connected_at = Time.get_ticks_msec()
	status = "연결됨 · 나 P%d · %d/4명 · 서버 상태 %d" % [assigned, present.size(), tick]


func _failed() -> void:
	_ready_for_input = false
	_pending.clear()
	_outgoing.clear()
	_motion.clear()
	_correction = Vector2.ZERO
	set_physics_process(false)
	status = "연결 종료 또는 방이 가득 찼습니다 · 새로고침하여 재접속"
	for id in actors.session.players.ids():
		actors.remove_player(id)
	if _peer != null:
		_peer.close()
	print("SESSION_DISCONNECTED")


func _exit_tree() -> void:
	if _peer != null:
		_peer.close()
		multiplayer.multiplayer_peer = null
