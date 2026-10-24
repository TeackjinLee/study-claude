extends Node
## 메뉴·설정·현지화 검증 (M7).
##  1. 번역표(data/i18n/ui.csv): 줄마다 영어가 있고, 형식 글자(%s·%d…)의 차례가 한국어와 같다.
##     영어로 바꾸면 Locale.t가 영어를, 표에 없는 글자는 한국어 그대로. 화면에 늘 뜨는 글자(조작 안내·구역·차·무기 이름)는 표에 있다.
##  2. 설정(Settings): 소리 크기가 버스에 들어가고, 언어가 Locale·Dialogue에 들어가며, 저장했다 다시 읽으면 같다.
##  3. 일시정지 메뉴: Esc로 열면 게임이 멈추고 다시 Esc로 닫힌다. 지도·설정 화면이 열리고, 지도가 그려진다(미션이 있으면 목표까지 노란 길, 수배 중이면 카센터 강조).
## 실행: godot --headless --fixed-fps 60 --path . res://tests/ui_test.tscn

var _failures: Array[String] = []


func _ready() -> void:
	_test_table()
	_test_settings()
	_test_minimap_route()
	await _test_pause()
	Locale.lang = "ko"
	Dialogue.lang = "ko"
	if _failures.is_empty():
		print("ui_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _test_table() -> void:
	Locale.reload()
	var f := FileAccess.open(Locale.PATH, FileAccess.READ)
	f.get_csv_line()
	var re := RegEx.create_from_string("%[0-9.]*[sdif]")
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2 or row[0] == "" or row[0].begins_with("#"):
			continue
		_expect(row[1] != "", "영어가 없다: %s" % row[0])
		var a := re.search_all(row[0]).map(func(m): return m.get_string().right(1))
		var b := re.search_all(row[1]).map(func(m): return m.get_string().right(1))
		_expect(a == b, "형식 글자 차례가 다르다: %s → %s (%s / %s)" % [row[0], row[1], a, b])
	Locale.lang = "en"
	_expect(Locale.t("일시정지") == "Paused", "영어로 바꾸면 영어 (%s)" % Locale.t("일시정지"))
	_expect(Locale.t("표에 없는 글자") == "표에 없는 글자", "표에 없으면 한국어 그대로")
	for s in [Hud.HINT_FOOT, Hud.HINT_DRIVE, Hud.HINT_FLY]:
		_expect(Locale.has(s), "조작 안내가 번역표에 있다: %s" % s)
	for d in CityMap.DISTRICTS:
		_expect(Locale.has(d.display_name), "구역 이름이 번역표에 있다: %s" % d.display_name)
	for w in ["pistol", "smg", "shotgun", "rifle", "rocket", "bat", "fist"]:
		var t: WeaponType = load("res://data/weapons/%s.tres" % w)
		_expect(Locale.has(t.display_name), "무기 이름이 번역표에 있다: %s" % t.display_name)
	for ch in Radio.CHANNELS:
		_expect(Locale.has(ch.display_name), "라디오 채널 이름이 번역표에 있다: %s" % ch.display_name)
	Locale.lang = "ko"
	_expect(Locale.t("일시정지") == "일시정지", "한국어면 그대로")


func _test_settings() -> void:
	Settings.path = "user://ui_test_settings.cfg"
	Settings.load_and_apply()
	Settings.set_value("music", 0.25)
	_expect(absf(AudioSetup.volume(AudioSetup.MUSIC) - 0.25) < 0.01, "음악 크기가 버스에 들어간다 (%.2f)" % AudioSetup.volume(AudioSetup.MUSIC))
	Settings.set_value("sfx", 0.0)
	_expect(AudioSetup.volume(AudioSetup.SFX) == 0.0, "0이면 끈다")
	Settings.set_value("lang", "en")
	_expect(Locale.lang == "en" and Dialogue.lang == "en", "언어가 글자·대사에 들어간다")
	Settings.save()
	Settings.values = Settings.DEFAULTS.duplicate()
	Settings.load_and_apply()
	_expect(Settings.get_value("lang") == "en" and absf(float(Settings.get_value("music")) - 0.25) < 0.01, "저장했다 다시 읽으면 같다")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.values = Settings.DEFAULTS.duplicate()
	Settings.apply()
	Settings.path = Settings.PATH


func _test_pause() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = 0
	main.bus_count = 0
	main.police_patrols = 0
	add_child(main)
	await _frames(5)
	var menu: PauseMenu = main.pause_menu
	_expect(menu != null and not menu.is_open(), "일시정지 메뉴가 있고 닫혀 있다")
	var esc := InputEventAction.new()
	esc.action = "pause"
	esc.pressed = true
	Input.parse_input_event(esc)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(menu.is_open() and get_tree().paused, "Esc로 열면 게임이 멈춘다")
	main.missions.start(main.missions.by_id(&"gangnam_06"))
	menu._show_map()
	await get_tree().process_frame
	await get_tree().process_frame
	var map: MapView = null
	for c in menu._list.get_children():
		if c is MapView:
			map = c
	_expect(map != null, "지도 화면")
	if map:
		_expect(map._route.size() > 1 and map._route[map._route.size() - 1] == main.missions.objective_position(),
			"지도에 목표까지 노란 길 (%d점)" % map._route.size())
		_expect(not map.spray_alert(), "수배가 없으면 카센터를 강조하지 않는다")
		main.police.wanted.raise_to(2)
		_expect(map.spray_alert(), "수배 중에는 지도에서 카센터를 강조한다")
		main.police.wanted.raise_to(WantedSystem.LOCK_LEVEL)
		_expect(not map.spray_alert(), "★5부터는 도색으로 못 떼니 카센터를 강조하지 않는다")
		main.police.wanted.clear()
	menu._show_settings()
	await get_tree().process_frame
	_expect(menu._list.get_child_count() >= 7, "설정 화면 (%d)" % menu._list.get_child_count())
	menu._show_main()
	menu.close()
	_expect(not get_tree().paused, "닫으면 다시 간다")
	main.queue_free()
	await _frames(2)


## 미니맵 GPS 길: 도로(교차로 가운데)를 따라 목표까지 이어지고, 꺾는 길은 곧은 거리보다 길다
func _test_minimap_route() -> void:
	var from := LaneGraph.center(Vector2i(1, 1)) + Vector2(60, 0)
	var goal := LaneGraph.center(Vector2i(3, 3)) + Vector2(0, 50)
	var r := Minimap.route(from, Vector2.ZERO, goal)
	_expect(r.size() >= 4 and r[0] == from and r[r.size() - 1] == goal, "GPS 길이 출발점에서 목표까지 이어진다 (%s)" % r)
	var length := 0.0
	var on_road := true
	for k in r.size() - 1:
		length += r[k].distance_to(r[k + 1])
		# 사이 구간은 도로를 따라 가로·세로로만 간다
		if k > 0 and k < r.size() - 2:
			var d := r[k + 1] - r[k]
			on_road = on_road and (absf(d.x) < 1.0 or absf(d.y) < 1.0)
	_expect(on_road, "GPS 길은 도로를 따라 가로·세로로 간다")
	_expect(length >= from.distance_to(goal), "GPS 길은 곧은 거리보다 짧지 않다")
	var near := Minimap.route(from, Vector2.ZERO, from + Vector2(80, 0))
	_expect(near.size() == 2, "가까운 목표는 곧게 잇는다")
	_expect(Minimap.distance_text(1000.0) == "60m" and Minimap.distance_text(30000.0) == "1.8km",
		"거리 표시 (%s · %s)" % [Minimap.distance_text(1000.0), Minimap.distance_text(30000.0)])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
