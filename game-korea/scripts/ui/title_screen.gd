class_name TitleScreen
extends Node
## 게임을 켜면 처음 나오는 타이틀 화면. 그림은 output/imagegen/title_screen/parts의 시안 파츠를 tools/prepare_title_assets.py로 다듬은
## assets/title/* — 배경, 경찰 헬기와 탐조등, 추격 차량 5대, 전경 인물 3인, 로고, 메뉴 스킨. 글자·간판 깜박임·경광등·빗줄기는 코드(TitleBackdrop).
## 새 게임 / 이어 하기(자동 저장) / 슬롯 선택(카드) / 도감(adult_codex) / 종료. ↑↓ Enter, 1·2·3은 그 슬롯으로 바로 시작, Esc는 팝업 닫기.
## 고르면 Main.entry에 시작 방식을 적고 본편 장면으로 넘어간다 (Main이 읽어 불러온다).
## 헤드리스 테스트나 `--chapter=N` 실행에서는 타이틀 없이 바로 본편이다 (기존 Main.load_on_start 조건은 그대로).

const MainScript := preload("res://scripts/main.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const CODEX_SCENE := "res://scenes/ui/adult_codex.tscn"
const ASSETS := "res://assets/title/"
const GREEN := Color("3bff8a")
const CYAN := Color("3abbd9")
const GOLD := Color("ffd23b")
const RED := Color("ff3b5c")
const PANEL_BG := Color(0.04, 0.09, 0.14, 0.90)
const VIEW := Vector2(1280, 720)

## 추격 차량 (뒤에서 앞으로): [그림, 바닥 가운데(화면), 폭 px, 경광등 왼쪽 색("" 이면 경광등 없음)]
const CARS := [
	["veh_police_front", Vector2(868, 500), 78.0, "blue"],
	["veh_swat", Vector2(965, 526), 196.0, "blue"],
	["veh_police_rear", Vector2(790, 534), 168.0, "red"],
	["veh_police_front", Vector2(828, 632), 292.0, "blue"],
	["veh_striker", Vector2(626, 640), 274.0, ""],
]
## 전경 인물 (뒤에서 앞으로): [그림, 왼쪽 위(화면), 폭 px]. 화면 오른쪽·아래로 잘려 나간다
const FIGURES := [["char_hero", Vector2(930, 4), 410.0], ["char_boss", Vector2(905, 346), 340.0], ["char_police", Vector2(1020, 388), 330.0]]
## 헬기: 기체 왼쪽 위(화면)와 폭, 빛기둥 배율 (램프 자리는 lights.json)
const HELI_AT := Vector2(668, 30)
const HELI_WIDTH := 128.0
const BEAM_SCALE := 0.72

var auto_skip := true                       ## false면 헤드리스·--chapter에서도 타이틀을 세운다 (테스트용)
var save_prefix := SaveGame.DEFAULT_PREFIX  ## 저장 칸 이름 앞부분 (테스트는 다른 이름을 쓴다)
var menu: Array[TitleMenuButton] = []
var cards: Array[SlotCard] = []
var saves := {}                             ## 슬롯 → SaveGame (없으면 null). 슬롯 1~3과 SaveGame.AUTO_SLOT
var started := &""                          ## 시작을 눌렀다 ("new" / "load") — 테스트가 읽는다

var _modal: CanvasLayer
var _modal_kind := &""
var _toast: Label
var _loading: Label
var _starting := false
var _last_focus := 0
var _car_info: Array = []
var _heli: Node2D
var _beam: Node2D
var _t := 0.0
var _no_change_scene := false               ## 테스트: 장면을 바꾸지 않는다


func _ready() -> void:
	# 웹 멀티 주소는 타이틀 UI·포커스를 만들기 전에 전용 클라이언트로 보낸다.
	if OS.has_feature("web") and WebRuntime.multiplayer_requested:
		get_tree().change_scene_to_file.call_deferred("res://scenes/session/client.tscn")
		return
	if auto_skip and (DisplayServer.get_name() == "headless" or MainScript.start_chapter_arg() > 0):
		get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)
		return
	if DisplayServer.get_name() != "headless":
		MainScript.limit_frame_rate()
		Settings.load_and_apply()
	_read_saves()
	_build_scene()
	_build_front()
	_build_ui()
	if menu.size() > 0:
		menu[0].grab_focus.call_deferred()


func _process(delta: float) -> void:
	_t += delta
	if _heli:
		# 헬기는 완만하게 떠다니고, 탐조등 빛기둥은 램프를 중심으로 좌우로 쓸고 간다
		var bob := Vector2(sin(_t * 0.45) * 30.0, sin(_t * 0.8 + 1.0) * 7.0)
		_heli.position = bob
		_beam.rotation = sin(_t * 0.6) * 0.14
		_beam.modulate.a = 0.85 + 0.15 * sin(_t * 3.1)


func _read_saves() -> void:
	saves.clear()
	for slot in [SaveGame.AUTO_SLOT, 1, 2, 3]:
		saves[slot] = SaveGame.read(SaveGame.slot_path(save_prefix, slot))


# ── 그림 ──────────────────────────────────────────────────

func _tex(name: String) -> Texture2D:
	return load(ASSETS + name) as Texture2D


## 그림을 폭 width로 놓는다. 위치는 왼쪽 위(top_left=true) 또는 아래 가운데
func _sprite(parent: Node, name: String, at: Vector2, width: float, top_left := false) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = _tex(name + ".png")
	sp.centered = false
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR     # 프로젝트 기본(nearest)이면 줄인 그림이 자글거린다
	var k := width / sp.texture.get_width()
	sp.scale = Vector2(k, k)
	sp.position = at if top_left else at - Vector2(width * 0.5, sp.texture.get_height() * k)
	parent.add_child(sp)
	return sp


func _build_scene() -> void:
	var lights: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSETS + "lights.json"))
	var stage := Node2D.new()
	add_child(stage)
	# 배경: 화면에 꽉 차게 (가운데 맞춤)
	var bg := Sprite2D.new()
	bg.texture = load(ASSETS + "bg_street.webp")
	bg.centered = false
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var k := maxf(VIEW.x / bg.texture.get_width(), VIEW.y / bg.texture.get_height())
	bg.scale = Vector2(k, k)
	bg.position = (VIEW - bg.texture.get_size() * k) * 0.5
	stage.add_child(bg)
	# 헬기와 탐조등 빛기둥 (빛이라 ADD 합성). 램프 자리를 중심으로 빛기둥을 흔든다
	_heli = Node2D.new()
	stage.add_child(_heli)
	var body := _sprite(_heli, "heli_body", HELI_AT, HELI_WIDTH, true)
	var body_k := HELI_WIDTH / body.texture.get_width()
	var lamp: Vector2 = HELI_AT + Vector2(lights.heli_lamp_body[0] * body.texture.get_width(), lights.heli_lamp_body[1] * body.texture.get_height()) * body_k
	_beam = Node2D.new()
	_beam.position = lamp
	_heli.add_child(_beam)
	_heli.move_child(_beam, 0)      # 기체 뒤에
	var beam := Sprite2D.new()
	beam.texture = _tex("heli_beam.png")
	beam.centered = false
	beam.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	beam.scale = Vector2(BEAM_SCALE, BEAM_SCALE)
	var bt := beam.texture.get_size()
	beam.position = -Vector2(lights.heli_lamp_beam[0] * bt.x, lights.heli_lamp_beam[1] * bt.y) * BEAM_SCALE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	beam.material = add
	_beam.add_child(beam)
	# 그림 위 효과 (왼쪽 어둡게·네온 깜박임·길바닥 불빛)
	var glow := TitleBackdrop.new(TitleBackdrop.Mode.GLOW)
	glow.cars = _car_info
	stage.add_child(glow)
	for spec in CARS:
		_add_car(stage, spec, lights)
	for spec in FIGURES:
		_sprite(stage, spec[0], spec[1], spec[2], true)


func _add_car(parent: Node, spec: Array, lights: Dictionary) -> void:
	var sp := _sprite(parent, spec[0], spec[1], spec[2])
	var size := sp.texture.get_size() * sp.scale
	var info := {"at": spec[1], "k": float(spec[2]) / 260.0, "siren": spec[3] != "", "left": spec[3], "lamps": []}
	if info.siren and lights.has(spec[0]):
		for lamp: Array in lights[spec[0]]:
			info.lamps.append(sp.position + Vector2(lamp[0] * size.x, lamp[1] * size.y))
	_car_info.append(info)


func _build_front() -> void:
	var front := CanvasLayer.new()
	front.layer = 1
	add_child(front)
	var rain := TitleBackdrop.new(TitleBackdrop.Mode.RAIN)
	rain.cars = _car_info
	front.add_child(rain)


# ── UI ────────────────────────────────────────────────────

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	# 「서울 거리」 로고와 슬로건 배너 (그림 한 장)
	var logo := TextureRect.new()
	logo.texture = _tex("logo.png")
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_SCALE
	logo.position = Vector2(46, 32)
	logo.size = Vector2(452, 452.0 * logo.texture.get_height() / logo.texture.get_width())
	root.add_child(logo)
	var panel := PanelContainer.new()
	panel.position = Vector2(64, 252)
	panel.size = Vector2(424, 392)
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var skin := StyleBoxTexture.new()
	skin.texture = _tex("ui_panel.png")
	skin.set_texture_margin_all(32)
	skin.set_content_margin_all(30)
	panel.add_theme_stylebox_override("panel", skin)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var auto: SaveGame = saves.get(SaveGame.AUTO_SLOT)
	_add_menu(box, "새 게임 시작", "", func(): _start(&"new"))
	var cont := _add_menu(box, "이어 하기", "(자동 저장 · %s)" % _chapter_label(auto) if auto else "(자동 저장 없음)",
		func(): _start(&"load", SaveGame.AUTO_SLOT))
	cont.disabled = auto == null
	if cont.disabled:
		cont.focus_mode = Control.FOCUS_NONE     # 키보드 ↑↓가 못 누르는 칸에 걸리지 않게
	_add_menu(box, "슬롯 선택", "(슬롯 1 · 2 · 3)", open_slots)
	_add_menu(box, "인물 · 차량 도감", "", open_codex)
	_add_menu(box, "게임 종료", "", func(): get_tree().quit())
	var hint := HintBar.new()
	hint.position = Vector2(0, 664)
	hint.size = Vector2(1280, 56)
	root.add_child(hint)
	_toast = Label.new()
	_toast.position = Vector2(0, 628)
	_toast.size = Vector2(1280, 30)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.add_theme_color_override("font_color", GOLD)
	_toast.modulate.a = 0.0
	root.add_child(_toast)
	_loading = Label.new()
	_loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading.add_theme_font_size_override("font_size", 40)
	_loading.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_loading.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_loading.text = "불러오는 중…"
	_loading.visible = false
	root.add_child(_loading)


static func _panel_style(border: Color, margin: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(margin)
	sb.shadow_color = Color(border, 0.28)
	sb.shadow_size = 14
	return sb


func _add_menu(parent: Container, main: String, sub: String, action: Callable) -> TitleMenuButton:
	var b := TitleMenuButton.new()
	b.main_text = main
	b.sub_text = sub
	b.custom_minimum_size = Vector2(364, 62)
	b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	b.pressed.connect(action)
	b.mouse_entered.connect(func():
		if not b.disabled and _modal == null:
			b.grab_focus())
	b.focus_entered.connect(func(): _last_focus = menu.find(b))
	parent.add_child(b)
	menu.append(b)
	return b


func _chapter_label(s: SaveGame) -> String:
	if s.finished:
		return "엔딩"
	var ch: ChapterType = MainScript.CHAPTERS[clampi(s.chapter - 1, 0, MainScript.CHAPTERS.size() - 1)]
	return "%d장 %s" % [s.chapter, ch.title]


# ── 팝업: 슬롯 카드 / 도감 ────────────────────────────────

func open_slots() -> void:
	if _modal:
		return
	_read_saves()
	_modal = CanvasLayer.new()
	_modal.layer = 10
	_modal_kind = &"slots"
	add_child(_modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.68)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(RED, 22))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	var title := Label.new()
	title.text = "서울 거리 — 어느 슬롯에서 이어 할까?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.45, 0.95, 0.9))
	v.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)
	cards.clear()
	for slot in [SaveGame.AUTO_SLOT, 1, 2, 3]:
		var card := SlotCard.new()
		card.slot = slot
		card.save = saves.get(slot)
		card.label_text = _chapter_label(card.save) if card.save else ""
		card.disabled = card.save == null
		if card.disabled:
			card.focus_mode = Control.FOCUS_NONE
		card.custom_minimum_size = Vector2(330, 116)
		card.pressed.connect(func(): _start(&"load", slot))
		card.mouse_entered.connect(func():
			if not card.disabled:
				card.grab_focus())
		grid.add_child(card)
		cards.append(card)
	var hint := Label.new()
	hint.text = "↑↓←→ 고르기    Enter 시작    1 · 2 · 3 슬롯 바로 시작    Esc 닫기"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	v.add_child(hint)
	var first := cards.filter(func(c: SlotCard): return not c.disabled)
	if first.is_empty():
		hint.text = "저장된 게임이 없습니다    Esc 닫기"
	else:
		(first[0] as SlotCard).grab_focus.call_deferred()


func open_codex() -> void:
	if _modal:
		return
	_modal = CanvasLayer.new()
	_modal.layer = 10
	_modal_kind = &"codex"
	add_child(_modal)
	var codex: Control = load(CODEX_SCENE).instantiate()
	codex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(codex)
	var hint := Label.new()
	hint.text = "Esc 닫기"
	hint.position = Vector2(1130, 14)
	hint.size = Vector2(130, 28)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", GOLD)
	_modal.add_child(hint)


func close_modal() -> void:
	if _modal == null:
		return
	_modal.queue_free()
	_modal = null
	_modal_kind = &""
	cards.clear()
	if _last_focus >= 0 and _last_focus < menu.size():
		menu[_last_focus].grab_focus.call_deferred()


func has_modal() -> bool:
	return _modal != null


# ── 시작 ──────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _starting:
		return
	if event.is_action_pressed("ui_cancel") and _modal:
		close_modal()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and _modal_kind != &"codex":
		var n: int = event.keycode - KEY_0
		if n >= 1 and n <= SaveGame.SLOTS:
			start_slot(n)
			get_viewport().set_input_as_handled()


## 1·2·3: 그 슬롯으로 바로 시작. 비었으면 알려 준다
func start_slot(slot: int) -> bool:
	if saves.get(slot) == null:
		_notice("슬롯 %d — 비어 있습니다" % slot)
		return false
	_start(&"load", slot)
	return true


func _notice(text: String) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


## 시작 방식을 Main에 적는다 (테스트가 장면을 바꾸지 않고 확인하려고 따로 뗐다)
func prepare_start(kind: StringName, slot := 0) -> void:
	started = kind
	MainScript.entry = String(kind)
	MainScript.entry_slot = slot


func _start(kind: StringName, slot := 0) -> void:
	if _starting:
		return
	_starting = true
	prepare_start(kind, slot)
	if _no_change_scene:
		return
	if _loading:
		_loading.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().canvas_transform = Transform2D.IDENTITY
	get_tree().change_scene_to_file(MAIN_SCENE)


# ── 부품 ──────────────────────────────────────────────────

## 메뉴 버튼: 평소 / 선택(황금·청록 테두리, ▶) / 못 누름
class TitleMenuButton extends Button:
	var main_text := ""
	var sub_text := ""

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		# 시안의 버튼 3상태 (assets/title/ui_btn_*): 평소 / 선택(청록→황금 테두리) / 못 누름. 9-슬라이스라 폭만 늘어난다
		var normal := _skin("ui_btn_normal.png", 22.0)
		var focus := _skin("ui_btn_focus.png", 24.0)
		var disabled := _skin("ui_btn_disabled.png", 22.0)
		add_theme_stylebox_override("normal", normal)
		add_theme_stylebox_override("hover", normal)
		add_theme_stylebox_override("pressed", focus)
		add_theme_stylebox_override("focus", focus)
		add_theme_stylebox_override("disabled", disabled)

	static func _skin(file: String, margin: float) -> StyleBoxTexture:
		var sb := StyleBoxTexture.new()
		sb.texture = load("res://assets/title/" + file)
		sb.set_texture_margin_all(margin)
		return sb

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var on := has_focus() and not disabled
		var col := Color(1.0, 0.9, 0.5) if on else (Color(0.4, 0.45, 0.5) if disabled else Color(0.88, 0.91, 0.96))
		var x := 26.0
		if on:
			draw_colored_polygon(PackedVector2Array([Vector2(14, size.y * 0.5 - 8), Vector2(14, size.y * 0.5 + 8), Vector2(26, size.y * 0.5)]), Color("ffd23b"))
			x = 36.0
		var ms := 26
		draw_string(font, Vector2(x, size.y * 0.5 + ms * 0.34), main_text, HORIZONTAL_ALIGNMENT_LEFT, -1, ms, col)
		if sub_text != "":
			var mw := font.get_string_size(main_text, HORIZONTAL_ALIGNMENT_LEFT, -1, ms).x
			draw_string(font, Vector2(x + mw + 8.0, size.y * 0.5 + ms * 0.34), sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				Color(col, 0.62))


## 슬롯 카드: 자동 저장 | 슬롯 1~3 — 장·돈·미션 진행. 비었으면 '비어 있음'
class SlotCard extends Button:
	var slot := 0
	var save: SaveGame
	var label_text := ""

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.06, 0.11, 0.17, 0.95)
		normal.border_color = Color(0.2, 0.4, 0.5)
		normal.set_border_width_all(2)
		normal.set_corner_radius_all(8)
		var focus := StyleBoxFlat.new()
		focus.bg_color = Color(0.09, 0.17, 0.24, 0.98)
		focus.border_color = Color("ffd23b")
		focus.set_border_width_all(3)
		focus.set_corner_radius_all(8)
		focus.shadow_color = Color(1.0, 0.82, 0.23, 0.35)
		focus.shadow_size = 8
		var disabled := normal.duplicate() as StyleBoxFlat
		disabled.bg_color = Color(0.05, 0.07, 0.1, 0.8)
		disabled.border_color = Color(0.14, 0.2, 0.25)
		add_theme_stylebox_override("normal", normal)
		add_theme_stylebox_override("hover", normal)
		add_theme_stylebox_override("pressed", focus)
		add_theme_stylebox_override("focus", focus)
		add_theme_stylebox_override("disabled", disabled)

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var name_text := "자동 저장" if slot == SaveGame.AUTO_SLOT else "슬롯 %d" % slot
		var gold := Color(1.0, 0.88, 0.45)
		if save == null:
			draw_string(font, Vector2(18, 32), "%s |" % name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(gold, 0.55))
			draw_string(font, Vector2(0, size.y * 0.66), "비어 있음", HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(1, 1, 1, 0.3))
			return
		draw_string(font, Vector2(18, 32), "%s | %s" % [name_text, label_text], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, gold)
		draw_string(font, Vector2(18, 66), "₩ %s" % Hud.won(save.money), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.95))
		draw_string(font, Vector2(18, 98), "미션 %d/%d" % [save.completed.size(), MissionSystem.MISSIONS.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
			Color(0.62, 0.78, 0.86))
		if save.saved_at != "":
			draw_string(font, Vector2(0, 98), save.saved_at.substr(0, 16).replace("T", " "), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 16.0, 14,
				Color(1, 1, 1, 0.4))


## 아래 조작 안내: 키 모양 + 설명
class HintBar extends Control:
	const ITEMS := [["↑↓", "선택"], ["Enter", "결정"], ["1·2·3", "슬롯 바로 시작"], ["Esc", "팝업 닫기"]]

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, 0.72))
		var font := ThemeDB.fallback_font
		var x := 70.0
		for it: Array in ITEMS:
			var kw := font.get_string_size(it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 22.0
			var key := StyleBoxFlat.new()
			key.bg_color = Color(0.13, 0.15, 0.2)
			key.border_color = Color(0.45, 0.5, 0.6)
			key.set_border_width_all(1)
			key.set_corner_radius_all(5)
			draw_style_box(key, Rect2(x, 12, kw, 30))
			draw_string(font, Vector2(x, 33), it[0], HORIZONTAL_ALIGNMENT_CENTER, kw, 16, Color(0.9, 0.93, 1.0))
			x += kw + 10.0
			var dw := font.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			draw_string(font, Vector2(x, 34), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.82, 0.86, 0.94))
			x += dw + 38.0
