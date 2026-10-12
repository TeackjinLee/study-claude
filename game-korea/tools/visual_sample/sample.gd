extends Node
## 실행: godot --path . res://tools/visual_sample.tscn
## 자동 캡처: godot --path . res://tools/visual_sample.tscn -- --capture
## M6 게임을 그대로 포함하는 M7 시각 샘플. 별도 저장 접두사로 실제 진행 상황과 분리한다.

const STREET = preload("res://tools/visual_sample/street.gd")
const ATMOSPHERE = preload("res://tools/visual_sample/atmosphere.gd")
const VEHICLE_LIGHT = preload("res://tools/visual_sample/vehicle_light.gd")
const PROFILE = preload("res://data/visual/gangnam_night.tres")
const MAIN = preload("res://scenes/main.tscn")
const OUT := "res://.screenshots/"

var game: Node2D
var street: Node2D
var atmosphere: Control
var vehicle_lights: Node2D
var panels: Control
var mode_label: Label
var art_enabled := true
var follow := false
var intersection := Vector2.ZERO


func _ready() -> void:
	get_window().title = "서울 거리 프로젝트 — 강남 비주얼 샘플"
	game = MAIN.instantiate()
	game.load_on_start = false
	game.save_prefix = "user://visual_sample_save_"
	add_child(game)
	intersection = LaneGraph.center(Vector2i(3, 3))
	game.camera.set_physics_process(false)
	game.camera.global_position = intersection + Vector2(0, 80)
	game.camera.zoom = Vector2(0.9, 0.9)
	game.start_vehicle.apply_stats(load("res://data/vehicles/car_taxi.tres"))
	game.start_vehicle.place(intersection + Vector2(72, 170), 0)
	game.player.global_position = intersection + Vector2(112, 170)
	_add_parked("res://data/vehicles/car_avela_r.tres", Vector2(-270, 72), PI * 0.5)
	_add_parked("res://data/vehicles/police_patrol.tres", Vector2(-72, -190), PI)
	_add_parked("res://data/vehicles/trk_porta.tres", Vector2(345, -72), -PI * 0.5)
	# 샘플 구역 인도에 기존 시민을 재배치한다. 행동 로직은 원래 보행자 로직을 사용한다.
	for k in mini(12, game.pedestrians.peds.size()):
		var cell := Vector2i(2 + k % 2, 2 + (k / 2) % 2)
		var loop := City.sidewalk_loop(cell)
		var p: Pedestrian = game.pedestrians.peds[k]
		var corner := 0
		for n in 4:
			if loop[n].distance_squared_to(intersection) < loop[corner].distance_squared_to(intersection):
				corner = n
		p.loop = loop
		p.global_position = loop[corner].lerp(loop[(corner + 1) % 4], 0.05 + (k / 4) * 0.1)
		p.resume_walking()
	street = STREET.new()
	street.city = game.city
	street.profile = PROFILE
	game.add_child(street)
	vehicle_lights = VEHICLE_LIGHT.new()
	vehicle_lights.game = game
	vehicle_lights.glow = street.glow
	game.add_child(vehicle_lights)
	var screen := CanvasLayer.new()
	screen.layer = 1
	add_child(screen)
	atmosphere = ATMOSPHERE.new()
	atmosphere.drops = PROFILE.rain_drops
	screen.add_child(atmosphere)
	panels = Control.new()
	panels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panels.draw.connect(_draw_panels)
	screen.add_child(panels)
	game.hud.layer = 2
	game.save_menu.layer = 4
	mode_label = Label.new()
	mode_label.add_theme_font_size_override("font_size", 14)
	mode_label.add_theme_color_override("font_color", Color("bdc4c8"))
	mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(mode_label)
	get_viewport().size_changed.connect(_layout)
	_layout()
	game.hud.notify("강남대로 — F로 차에 타고 거리를 둘러보세요")
	if "--capture" in OS.get_cmdline_user_args():
		await _capture()


func _add_parked(path: String, offset: Vector2, heading: float) -> void:
	var car := Vehicle.new()
	car.stats = load(path)
	game.add_child(car)
	car.place(intersection + offset, heading)
	game.vehicles.append(car)


func _process(_delta: float) -> void:
	if is_instance_valid(game) and not follow:
		game.camera.global_position = intersection + Vector2(0, 80)
		game.camera.zoom = Vector2(0.9, 0.9)


func _draw_panels() -> void:
	var size := get_viewport().get_visible_rect().size
	for r in [Rect2(20, 20, 275, 154), Rect2(size.x - 295, 20, 275, 155),
		Rect2(20, size.y - 260, 196, 226), Rect2(238, size.y - 58, size.x - 258, 38)]:
		panels.draw_style_box(_panel_style(), r)
	panels.draw_line(Vector2(20, 20), Vector2(95, 20), PROFILE.cyan, 2)
	panels.draw_line(Vector2(size.x - 95, 20), Vector2(size.x - 20, 20), PROFILE.warm, 2)


func _panel_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.025, 0.045, 0.067, 0.86)
	box.border_color = Color(0.37, 0.48, 0.54, 0.4)
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	return box


func _place(control: Control, pos: Vector2, extent := Vector2.ZERO) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	control.position = pos
	if extent != Vector2.ZERO:
		control.size = extent


func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	var hud: Hud = game.hud
	_place(hud._info, Vector2(36, 32))
	hud._info.add_theme_font_size_override("font_size", 18)
	_place(hud._weapon, Vector2(36, 91), Vector2(240, 25))
	hud._weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hud._weapon.add_theme_font_size_override("font_size", 17)
	_place(hud._bars, Vector2(36, 128))
	_place(hud._money, Vector2(size.x - 280, 32), Vector2(242, 32))
	hud._money.add_theme_font_size_override("font_size", 25)
	_place(hud._stars, Vector2(size.x - 225, 76))
	_place(hud._respect, Vector2(size.x - 280, 119), Vector2(242, 35))
	hud._respect.add_theme_font_size_override("font_size", 14)
	_place(hud._minimap, Vector2(32, size.y - 248), Vector2(172, 172))
	hud._hint.hide()
	hud._goal.hide()
	_place(hud._prompt, Vector2(240, size.y - 102), Vector2(size.x - 475, 30))
	hud._prompt.add_theme_font_size_override("font_size", 16)
	_place(hud._notice, Vector2(size.x - 510, size.y - 140), Vector2(478, 30))
	hud._notice.add_theme_font_size_override("font_size", 16)
	_place(hud._mission_title, Vector2(310, 25), Vector2(size.x - 620, 32))
	_place(hud._objective, Vector2(310, 60), Vector2(size.x - 620, 32))
	hud._objective.add_theme_font_size_override("font_size", 16)
	mode_label.position = Vector2(252, size.y - 50)
	_update_mode()
	panels.queue_redraw()


func _update_mode() -> void:
	mode_label.text = "%s  ·  B 비교  V 비  C 카메라  P 추격  ·  WASD 이동  F 탑승  Shift 달리기" % ("야간 샘플" if art_enabled else "기본 렌더")


func _set_art(enabled: bool) -> void:
	art_enabled = enabled
	street.visible = enabled
	vehicle_lights.visible = enabled
	atmosphere.visible = enabled
	_update_mode()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_B:
			_set_art(not art_enabled)
		KEY_V:
			atmosphere.rain_enabled = not atmosphere.rain_enabled
		KEY_C:
			follow = not follow
			game.camera.set_physics_process(follow)
			if follow:
				game.camera.target = game.director.controlled_target()
				game.camera.snap()
			else:
				game.camera.global_position = intersection + Vector2(0, 80)
				game.camera.zoom = Vector2(0.9, 0.9)
		KEY_P:
			game.police.last_known = game.director.controlled_target().global_position
			game.police.wanted.report(WantedSystem.Crime.HIT_OFFICER)
		_:
			return
	get_viewport().set_input_as_handled()


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for k in 45:
		await get_tree().physics_frame
	# 비교 화면은 같은 위치·같은 순간을 사용한다. 게임을 멈춰도 화면은 계속 그린다.
	game.process_mode = Node.PROCESS_MODE_DISABLED
	await _press_key(KEY_B)
	await _save("m7_gangnam_before")
	await _press_key(KEY_B)
	await _press_key(KEY_V)
	await _save("m7_gangnam_night")
	await _press_key(KEY_V)
	await _save("m7_gangnam_rain")
	get_window().size = Vector2i(1920, 1080)
	for k in 3:
		await get_tree().process_frame
	await _save("m7_gangnam_large")
	get_window().size = Vector2i(1280, 720)
	for k in 3:
		await get_tree().process_frame
	game.process_mode = Node.PROCESS_MODE_INHERIT
	game.director.enter_immediately(game.start_vehicle)
	await _press_key(KEY_C)
	Input.action_press("accelerate")
	for k in 70:
		await get_tree().physics_frame
	Input.action_release("accelerate")
	await _save("m7_gangnam_drive")
	# 추격 캡처는 장식 적용 구역으로 돌아와 실제 경찰이 시야에 들어올 때까지 기다린다.
	game.start_vehicle.place(intersection + Vector2(58, 165), 0)
	game.camera.snap()
	await _press_key(KEY_P)
	if game.police.wanted.level < 2:
		push_error("추격 키 입력 확인 실패")
		get_tree().quit(1)
		return
	for k in 600:
		await get_tree().physics_frame
		if k > 120 and game.police.seen:
			break
	await _save("m7_gangnam_chase")
	get_tree().quit()


func _press_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame

	print("샘플 입력: ", OS.get_keycode_string(code), " · 아트=", art_enabled,
		" · 비=", atmosphere.rain_enabled, " · 추적 카메라=", follow, " · 수배=", game.police.wanted.level)


func _save(file: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + file + ".png"))
	if error != OK:
		push_error("샘플 화면 저장 실패: " + file)
		get_tree().quit(1)
	print("샘플 저장: ", file, " · ", get_viewport().get_texture().get_size())
