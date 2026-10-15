extends Node
## 타이틀 화면 검증 (docs: output/imagegen/title_screen).
##  1. 헤드리스에서도 TitleScreen(auto_skip=false)이 세워진다: 메뉴 5개, 저장이 없으면 '이어 하기'가 못 누름, 첫 버튼에 포커스.
##  2. 저장 칸이 있으면 이어 하기가 켜지고, 슬롯 카드 4장(자동·1~3)이 요약을 가진다 (빈 칸은 못 누름).
##  3. 1·2·3: 저장이 있는 슬롯이면 Main.entry="load"와 슬롯 번호가 적히고, 빈 슬롯이면 시작하지 않는다.
##  4. 새 게임·이어 하기를 누르면 Main.entry가 "new"·"load"(자동 저장 칸)가 된다.
##  5. Main이 entry를 읽는다: "load"면 그 슬롯의 돈이 돌아오고, "new"면 저장이 있어도 새로 시작하며, 읽은 뒤 entry는 비워진다.
##  6. 팝업: 슬롯 카드·도감을 열고 Esc로 닫는다. 도감이 열려 있는 동안 1·2·3은 먹지 않는다.
##  7. 키보드 ↑↓: 메뉴 포커스 이웃이 위·아래 버튼이다.
## 실행: godot --headless --fixed-fps 60 --path . res://tests/title_test.tscn

const MainScript := preload("res://scripts/main.gd")
const PREFIX := "user://title_test_"

var _failures: Array[String] = []


func _ready() -> void:
	_remove_saves()
	await _test_no_saves()
	_write_saves()
	await _test_with_saves()
	await _test_start_slots()
	await _test_menu_buttons()
	await _test_main_reads_entry()
	await _test_popups()
	_remove_saves()
	MainScript.entry = ""
	if _failures.is_empty():
		print("title_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _title() -> TitleScreen:
	var t := TitleScreen.new()
	t.auto_skip = false
	t.save_prefix = PREFIX
	t._no_change_scene = true
	add_child(t)
	return t


func _free(n: Node) -> void:
	n.queue_free()
	await _frames(2)


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


func _action(name: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


func _remove_saves() -> void:
	for slot in [SaveGame.AUTO_SLOT, 1, 2, 3]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.slot_path(PREFIX, slot)))


func _write_saves() -> void:
	for row in [[SaveGame.AUTO_SLOT, 500000, 1], [1, 1850000, 2]]:
		var s := SaveGame.new()
		s.money = row[1]
		s.chapter = row[2]
		s.completed.append("m1")
		s.saved_at = "2026-10-15T19:30:00"
		_expect(s.write(SaveGame.slot_path(PREFIX, row[0])), "저장 파일을 쓴다 (%d)" % row[0])


func _test_no_saves() -> void:
	var t := _title()
	await _frames(3)
	_expect(t.menu.size() == 5, "메뉴 버튼 5개 (%d)" % t.menu.size())
	_expect(t.menu[1].disabled, "저장이 없으면 '이어 하기'를 누를 수 없다")
	_expect(not t.menu[0].disabled and not t.menu[2].disabled, "새 게임·슬롯 선택은 늘 누를 수 있다")
	_expect(t.menu[0].has_focus(), "첫 버튼(새 게임 시작)에 포커스")
	_expect(t.start_slot(2) == false and t.started == &"", "빈 슬롯 번호를 눌러도 시작하지 않는다")
	await _free(t)


func _test_with_saves() -> void:
	var t := _title()
	await _frames(3)
	_expect(not t.menu[1].disabled, "자동 저장이 있으면 '이어 하기'가 켜진다")
	t.open_slots()
	await _frames(2)
	_expect(t.cards.size() == 4, "슬롯 카드 4장 (자동·1·2·3): %d" % t.cards.size())
	if t.cards.size() == 4:
		_expect(not t.cards[0].disabled and t.cards[0].save.money == 500000, "자동 저장 카드에 요약")
		_expect(not t.cards[1].disabled and t.cards[1].save.chapter == 2, "슬롯 1 카드에 2장")
		_expect(t.cards[2].disabled and t.cards[3].disabled, "빈 슬롯 2·3 카드는 누를 수 없다")
	t.close_modal()
	await _free(t)


func _test_start_slots() -> void:
	var t := _title()
	await _frames(2)
	_expect(t.start_slot(1), "슬롯 1(저장 있음)은 바로 시작")
	_expect(t.started == &"load" and MainScript.entry == "load" and MainScript.entry_slot == 1, "1 → entry=load, slot 1 (%s, %d)" % [MainScript.entry, MainScript.entry_slot])
	MainScript.entry = ""
	await _free(t)
	# 키 입력으로도 같다 (_unhandled_input)
	t = _title()
	await _frames(2)
	t._unhandled_input(_key(KEY_1))
	_expect(MainScript.entry == "load" and MainScript.entry_slot == 1, "숫자 키 1 → 슬롯 1")
	MainScript.entry = ""
	await _free(t)
	t = _title()
	await _frames(2)
	t._unhandled_input(_key(KEY_3))
	_expect(t.started == &"", "숫자 키 3(빈 슬롯)은 시작하지 않는다")
	await _free(t)


func _test_menu_buttons() -> void:
	var t := _title()
	await _frames(3)
	t.menu[0].pressed.emit()
	_expect(MainScript.entry == "new", "새 게임 시작 → entry=new (%s)" % MainScript.entry)
	MainScript.entry = ""
	await _free(t)
	t = _title()
	await _frames(3)
	t.menu[1].pressed.emit()
	_expect(MainScript.entry == "load" and MainScript.entry_slot == SaveGame.AUTO_SLOT, "이어 하기 → 자동 저장 칸")
	MainScript.entry = ""
	await _free(t)
	# 키보드 ↑↓: 포커스 이웃
	t = _title()
	await _frames(3)
	_expect(t.menu[0].find_valid_focus_neighbor(SIDE_BOTTOM) == t.menu[1], "새 게임에서 ↓ → 이어 하기")
	_expect(t.menu[2].find_valid_focus_neighbor(SIDE_TOP) == t.menu[1], "슬롯 선택에서 ↑ → 이어 하기")
	await _free(t)


func _test_main_reads_entry() -> void:
	# 슬롯 1에 돈이 든 저장을 만든다
	var a := _main()
	a.wallet.earn(123456)
	var saved: int = a.wallet.money
	_expect(a.save_game(1), "저장이 된다")
	await _free(a)
	MainScript.entry = "load"
	MainScript.entry_slot = 1
	var b := _main()
	await _frames(2)
	_expect(b.wallet.money == saved, "entry=load → 슬롯 1의 돈이 돌아온다 (%d / %d)" % [b.wallet.money, saved])
	_expect(MainScript.entry == "", "Main이 읽은 뒤 entry는 비워진다")
	_expect(not b.save_menu.is_open(), "타이틀에서 골랐으면 불러오기 메뉴가 뜨지 않는다")
	await _free(b)
	MainScript.entry = "new"
	var c := _main()
	await _frames(2)
	_expect(c.wallet.money != saved and not c.save_menu.is_open(), "entry=new → 저장이 있어도 새로 시작 (%d)" % c.wallet.money)
	_expect(MainScript.entry == "", "entry=new도 읽은 뒤 비워진다")
	await _free(c)
	# 타이틀을 거치지 않은 직접 실행(entry 비어 있음)은 예전 그대로
	var d := _main()
	await _frames(2)
	_expect(d.wallet.money != saved, "entry 없이 만든 Main은 저장을 불러오지 않는다 (테스트 실행 그대로)")
	await _free(d)


func _main() -> Node2D:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.save_prefix = PREFIX
	main.traffic_count = 0
	main.bus_count = 0
	main.police_patrols = 0
	add_child(main)
	return main


func _test_popups() -> void:
	var t := _title()
	await _frames(3)
	t.open_slots()
	_expect(t.has_modal(), "슬롯 카드 팝업이 열린다")
	t._unhandled_input(_action("ui_cancel"))
	await _frames(2)
	_expect(not t.has_modal(), "Esc로 슬롯 카드 팝업이 닫힌다")
	t.open_codex()
	await _frames(3)
	_expect(t.has_modal(), "도감 팝업이 열린다")
	t._unhandled_input(_key(KEY_1))
	_expect(t.started == &"", "도감이 열려 있으면 1·2·3이 시작하지 않는다")
	t._unhandled_input(_action("ui_cancel"))
	await _frames(2)
	_expect(not t.has_modal(), "Esc로 도감이 닫힌다")
	await _frames(2)
	_expect(t.menu.any(func(b: TitleScreen.TitleMenuButton): return b.has_focus()), "팝업을 닫으면 포커스가 메뉴로 돌아온다")
	await _free(t)
