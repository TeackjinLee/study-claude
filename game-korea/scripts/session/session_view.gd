extends Node2D
## 공통 도시 또는 연습장의 클라이언트 화면. 카메라·시간대·이름표는 로컬에서만 만든다.
var boot: Node
var _status: Label
var _positions: Label
var _labels: Dictionary[int, Label] = {}
var _layer: CanvasLayer
var _old_canvas: Transform2D
var _ui_clock := 0.0
var _title: Label
var _help: Label
var _camera: ChaseCamera
var _sky: DayNight

func _ready() -> void:
	process_priority = 1100   # 추적 카메라가 화면 변환을 적용한 뒤 이름표를 맞춘다
	_old_canvas = get_viewport().canvas_transform
	get_viewport().size_changed.connect(_resize)
	_resize()
	z_index = 0
	_layer = CanvasLayer.new()
	add_child(_layer)
	_title = _label(Vector2(30, 24), 28)
	_status = _label(Vector2(32, 70), 20)
	_positions = _label(Vector2(32, 112), 18)
	_help = _label(Vector2(30, 632), 19)
	configure_world()

## welcome에서 서버가 확정한 월드를 받은 뒤에도 다시 호출할 수 있다.
func configure_world() -> void:
	_title.text = "서울 거리 프로젝트 · 도시 멀티플레이" if boot.city_world else "서울 거리 프로젝트 · 이동 동기화 연습장"
	_help.text = "WASD / 방향키 이동 · Shift 달리기\n내 입력 예측 · 상대 보간 · 차량·NPC·전투·저장은 아직 연결하지 않았습니다"
	if boot.city_world and boot.city != null and _camera == null:
		_camera = ChaseCamera.new()
		add_child(_camera)
		_camera.make_current()
		_sky = DayNight.new()
		_sky.paused_clock = true
		add_child(_sky)
		# 이번 단계는 고정된 야간 도시다. 매 프레임 날씨·조명을 다시 계산하지 않는다.
		_sky.set_process(false)
	_resize()
	queue_redraw()


func _label_position(actor: Player) -> Vector2:
	var at := actor.global_position + IsoView.lift(IsoView.ground(actor.global_position, actor.level))
	return get_viewport().canvas_transform * at + Vector2(-18, -55)

func _label(at: Vector2, size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.90, 0.94, 0.98))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	_layer.add_child(label)
	return label

func _resize() -> void:
	if boot.city_world:
		return
	get_viewport().canvas_transform = IsoView.canvas(get_viewport().get_visible_rect().size, Vector2(400, 400), 1.25)

func _draw() -> void:
	if boot.city_world:
		return
	draw_rect(Rect2(40, 40, 720, 720), Color(0.16, 0.23, 0.28))
	draw_rect(Rect2(80, 80, 640, 640), Color(0.28, 0.34, 0.37))
	for value in range(80, 721, 80):
		draw_line(Vector2(value, 80), Vector2(value, 720), Color(0.36, 0.43, 0.46), 1)
		draw_line(Vector2(80, value), Vector2(720, value), Color(0.36, 0.43, 0.46), 1)
	draw_rect(Rect2(80, 80, 640, 640), Color(0.39, 0.85, 0.76), false, 3)

func _process(delta: float) -> void:
	if _camera != null:
		var entry: GamePlayerSession = boot.actors.session.local_player()
		var target: Player = entry.actor if entry != null and entry.has_actor() else null
		if _camera.target != target:
			_camera.target = target
			if target != null:
				_camera.snap()
	# 이름표 위치는 보간된 캐릭터와 함께 움직이고, 글자 갱신만 10Hz로 제한한다.
	for id: int in _labels:
		var entry: GamePlayerSession = boot.actors.session.players.find(id)
		if entry != null and entry.has_actor():
			_labels[id].position = _label_position(entry.actor)
	_ui_clock += delta
	if _ui_clock < 0.1:
		return
	_ui_clock = 0.0
	_status.text = boot.status
	var ids: Array[int] = boot.actors.session.players.ids()
	var lines := "표시 좌표 · 내 입력 예측 / 상대 보간\n"
	for id in ids:
		var actor: Player = boot.actors.session.players.find(id).actor
		var own: bool = id == boot.actors.session.local_player_id()
		if not _labels.has(id):
			_labels[id] = _label(Vector2.ZERO, 18)
		_labels[id].text = "P%d%s" % [id, " · 나" if own else ""]
		_labels[id].modulate = Color(0.42, 1, 0.83) if own else Color(1, 0.78, 0.42)
		_labels[id].position = _label_position(actor)
		lines += "P%d  (%0.1f, %0.1f)\n" % [id, actor.position.x, actor.position.y]
	for id: int in _labels.keys():
		if id not in ids:
			_labels[id].queue_free()
			_labels.erase(id)
	_positions.text = lines

func _exit_tree() -> void:
	get_viewport().canvas_transform = _old_canvas
