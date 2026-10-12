extends Node
## 실제 게임 씬을 띄워 입력 → 주행 → 드리프트 자국 → 건물 충돌 → 차종 변경까지 확인한다.
## 실행: godot --headless --path . res://tests/smoke_test.tscn

var _failures: Array[String] = []


func _ready() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = 0   # 도로 NPC 차는 M2 테스트에서 따로 본다
	main.bus_count = 0
	add_child(main)
	await _frames(2)
	var v: Vehicle = main.start_vehicle
	main.director.enter_immediately(v)

	# 1. 직진 2초 — 위쪽으로 달려야 한다
	var start := v.global_position
	Input.action_press("accelerate")
	await _frames(120)
	_expect(start.y - v.global_position.y > 600.0, "직진 2초에 600px 이상 전진 (실제 %.0f)" % (start.y - v.global_position.y))
	_expect(v.speed() > 500.0, "2초 뒤 속도 500 이상 (실제 %.0f)" % v.speed())

	# 2. 핸드브레이크 + 조향 — 스키드 마크가 생겨야 한다
	Input.action_press("steer_right")
	Input.action_press("handbrake")
	await _frames(40)
	Input.action_release("handbrake")
	Input.action_release("steer_right")
	Input.action_release("accelerate")
	_expect(main.skid_marks.segment_count() > 10, "드리프트 스키드 마크 생성 (실제 %d)" % main.skid_marks.segment_count())

	# 3. 건물 정면으로 3초 돌진 — 뚫고 들어가면 안 된다
	var b: Rect2 = main.city.buildings[0]
	v.place(Vector2(b.get_center().x, b.end.y + 150.0), 0.0)
	Input.action_press("accelerate")
	await _frames(180)
	Input.action_release("accelerate")
	_expect(not b.has_point(v.global_position), "건물 관통 (차 위치 %s, 건물 %s)" % [v.global_position, b])
	_expect(v.global_position.y > b.end.y, "차가 건물 아래쪽 면 밖에 있어야 함")

	# 4. 차종 변경
	main.switch_vehicle(2)
	_expect(v.stats.id == &"TRK_PORTA", "3번 키 → 포르타로 변경")

	if _failures.is_empty():
		print("smoke_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
