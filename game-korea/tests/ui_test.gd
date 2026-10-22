extends Node
## 메뉴·설정·현지화 검증 (M7).
##  1. 번역표(data/i18n/ui.csv): 줄마다 영어가 있고, 형식 글자(%s·%d…)의 차례가 한국어와 같다.
##     영어로 바꾸면 Locale.t가 영어를, 표에 없는 글자는 한국어 그대로. 화면에 늘 뜨는 글자(조작 안내·구역·차·무기 이름)는 표에 있다.
##  2. 설정(Settings): 소리 크기가 버스에 들어가고, 언어가 Locale·Dialogue에 들어가며, 저장했다 다시 읽으면 같다.
##  3. 일시정지 메뉴: Esc로 열면 게임이 멈추고 다시 Esc로 닫힌다. 지도·설정 화면이 열리고, 지도가 그려진다.
## 실행: godot --headless --fixed-fps 60 --path . res://tests/ui_test.tscn

var _failures: Array[String] = []


func _ready() -> void:
	_test_table()
	_test_settings()
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
	menu._show_map()
	await get_tree().process_frame
	var map: MapView = null
	for c in menu._list.get_children():
		if c is MapView:
			map = c
	_expect(map != null, "지도 화면")
	menu._show_settings()
	await get_tree().process_frame
	_expect(menu._list.get_child_count() >= 7, "설정 화면 (%d)" % menu._list.get_child_count())
	menu._show_main()
	menu.close()
	_expect(not get_tree().paused, "닫으면 다시 간다")
	main.queue_free()
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
