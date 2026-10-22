class_name PauseMenu
extends CanvasLayer
## 일시정지 메뉴 (Esc · 패드 Start): 계속하기 / 지도 / 설정 / 타이틀로 / 게임 종료. 열려 있는 동안 게임은 멈춘다.
## 설정: 소리 크기(전체·효과음·음악·배경음), 언어(한국어·English), 전체 화면, 2.5D 화면 — 바꾸면 바로 적용하고 저장한다(Settings).
## 지도: 도시 전체(CityMap 블록·강·잠긴 구역)와 주인공·산 은신처·공중전화·미션 목표 (MapView).
## 세이브 메뉴가 열려 있으면 Esc는 그쪽이 받는다.

signal quit_to_title

var main: Node2D
var _root: Control
var _panel: PanelContainer
var _list: VBoxContainer
var _title: Label
var _page := &""


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.07, 0.08, 0.11, 0.96)
	box.border_color = Hud.GOLD
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(26)
	_panel.add_theme_stylebox_override("panel", box)
	center.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_panel.add_child(v)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Hud.GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	v.add_child(_list)


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	get_tree().paused = true
	_show_main()


func close() -> void:
	visible = false
	get_tree().paused = false
	Settings.save()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if main and main.save_menu and main.save_menu.visible:
		return
	get_viewport().set_input_as_handled()
	if not visible:
		open()
	elif _page != &"main":
		_show_main()
	else:
		close()


func _clear(title: String) -> void:
	for c in _list.get_children():
		c.queue_free()
	_title.text = Locale.t(title)


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = Locale.t(text)
	b.custom_minimum_size = Vector2(360, 46)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(action)
	_list.add_child(b)
	return b


func _show_main() -> void:
	_page = &"main"
	_clear("일시정지")
	var first := _button("계속하기", close)
	_button("지도", _show_map)
	_button("설정", _show_settings)
	_button("타이틀로", func():
		close()
		quit_to_title.emit())
	_button("게임 종료", func(): get_tree().quit())
	first.grab_focus.call_deferred()


func _show_map() -> void:
	_page = &"map"
	_clear("서울 지도")
	var map := MapView.new()
	map.main = main
	map.custom_minimum_size = Vector2(760, 560)
	_list.add_child(map)
	var back := _button("돌아가기", _show_main)
	back.grab_focus.call_deferred()


func _show_settings() -> void:
	_page = &"settings"
	_clear("설정")
	for row in [["전체 소리", "master"], ["효과음", "sfx"], ["음악 (라디오)", "music"], ["배경음", "ambience"]]:
		_slider(row[0], row[1])
	var lang := OptionButton.new()
	lang.add_item("한국어")
	lang.add_item("English")
	lang.selected = Settings.LANGS.find(String(Settings.get_value("lang")))
	lang.item_selected.connect(func(i: int):
		Settings.set_value("lang", Settings.LANGS[i])
		if main and main.has_method("_update_goal"):
			main._update_goal()
		_show_settings())
	_row("언어 / Language", lang)
	var full := CheckButton.new()
	full.button_pressed = bool(Settings.get_value("fullscreen"))
	full.toggled.connect(func(on: bool): Settings.set_value("fullscreen", on))
	_row("전체 화면", full)
	var iso := CheckButton.new()
	iso.button_pressed = bool(Settings.get_value("iso"))
	iso.toggled.connect(func(on: bool):
		Settings.set_value("iso", on)
		if main and main.has_method("set_iso"):
			main.set_iso(on))
	_row("2.5D 화면 (F9)", iso)
	var back := _button("돌아가기", _show_main)
	back.grab_focus.call_deferred()


func _slider(label: String, key: String) -> void:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(Settings.get_value(key))
	s.custom_minimum_size = Vector2(220, 24)
	s.value_changed.connect(func(x: float): Settings.set_value(key, x))
	_row(label, s)


func _row(label: String, control: Control) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := Label.new()
	l.text = Locale.t(label)
	l.custom_minimum_size = Vector2(200, 0)
	l.add_theme_font_size_override("font_size", 18)
	h.add_child(l)
	h.add_child(control)
	_list.add_child(h)
