class_name SaveMenu
extends CanvasLayer
## 세이브 슬롯 메뉴. 은신처에서는 "어느 슬롯에 저장할까", 게임을 켤 때는 "새 게임 / 자동 저장 / 어느 슬롯에서 이어 할까".
## 은신처를 살지 묻는 예·아니오 창(CONFIRM)도 같은 틀을 쓴다 — 예는 slot 1, 아니오는 slot 0.
## 열려 있는 동안 게임은 멈춘다. 고르면 chosen(slot), 닫으면 canceled. 새 게임은 slot 0, 자동 저장은 SaveGame.AUTO_SLOT.
## 조작: 위·아래 + Enter(Space), 숫자 1~3 바로 고르기, Esc 닫기(저장 메뉴만) — 패드는 십자키·A·B.

signal chosen(slot: int)
signal canceled

enum Mode { SAVE, LOAD, CONFIRM }

var mode := Mode.SAVE
var _panel: PanelContainer
var _title: Label
var _list: VBoxContainer
var _hint: Label
var _buttons: Array[Button] = []
var _slots: Array[int] = []        ## 버튼마다 슬롯 번호 (0 = 새 게임)


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.09, 0.12, 0.96)
	box.border_color = Color(0.4, 1.0, 0.6)
	box.set_border_width_all(2)
	box.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", box)
	center.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	v.add_child(_list)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_hint)


## lines[k]는 슬롯 k+1의 요약 ("" 이면 비어 있음)
func open_save(lines: Array[String]) -> void:
	mode = Mode.SAVE
	_title.text = "은신처 — 어디에 저장할까?"
	_hint.text = "↑↓ 고르기   Enter 저장   1·2·3 바로 고르기   Esc 닫기"
	_fill(lines, false)


## auto는 자동 저장 칸 요약 ("" 이면 줄을 넣지 않는다)
func open_load(lines: Array[String], auto := "") -> void:
	mode = Mode.LOAD
	_title.text = "서울 거리 프로젝트 — 이어 하기"
	_hint.text = "↑↓ 고르기   Enter 시작   1·2·3 바로 고르기"
	_fill(lines, true, auto)


## 예·아니오 (예 = slot 1). Esc는 아니오
func open_confirm(question: String, yes: String, no: String) -> void:
	mode = Mode.CONFIRM
	_title.text = question
	_hint.text = "↑↓ 고르기   Enter 결정   Esc 그만두기"
	_clear()
	_add_button(yes, 1, false)
	_add_button(no, 0, false)
	_show(0)


func is_open() -> bool:
	return visible


## 버튼을 누른 것과 같다 (테스트에서도 쓴다). 불러오기에서 빈 슬롯은 고를 수 없다.
func choose(slot: int) -> bool:
	var k := _slots.find(slot)
	if k < 0 or _buttons[k].disabled:
		return false
	_close()
	chosen.emit(slot)
	return true


func cancel() -> void:
	if not visible:
		return
	_close()
	canceled.emit()


func _clear() -> void:
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	_slots.clear()


func _fill(lines: Array[String], with_new_game: bool, auto := "") -> void:
	_clear()
	if with_new_game:
		_add_button("새 게임", 0, false)
	if auto != "":
		_add_button("자동 저장   %s" % auto, SaveGame.AUTO_SLOT, false)
	for k in lines.size():
		var empty := lines[k] == ""
		var text := "슬롯 %d   %s" % [k + 1, "비어 있음" if empty else lines[k]]
		if mode == Mode.SAVE and not empty:
			text += "   (덮어쓰기)"
		_add_button(text, k + 1, mode == Mode.LOAD and empty)
	# 저장은 가장 최근 슬롯 대신 첫 슬롯, 불러오기는 첫 번째로 이어 할 칸(자동 저장 포함)에 포커스
	var focus := 0
	if mode == Mode.LOAD:
		for k in _buttons.size():
			if _slots[k] > 0 and not _buttons[k].disabled:
				focus = k
				break
	_show(focus)


func _show(focus: int) -> void:
	visible = true
	get_tree().paused = true
	_buttons[focus].grab_focus.call_deferred()


func _add_button(text: String, slot: int, disabled: bool) -> void:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(560, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(func(): choose(slot))
	_list.add_child(b)
	_buttons.append(b)
	_slots.append(slot)


func _close() -> void:
	visible = false
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if mode == Mode.SAVE:
			cancel()
		elif mode == Mode.CONFIRM:
			choose(0)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var n: int = event.keycode - KEY_0
		if mode != Mode.CONFIRM and n >= 1 and n <= SaveGame.SLOTS:
			choose(n)
			get_viewport().set_input_as_handled()
