extends Node
##  입력 분리 검증: 두 외부 플레이어, 로컬 키 격리, 월드 방향, 운전·탑승·조준 전달.

var _failures: Array[String] = []


func _ready() -> void:
	var a := Player.new()
	var b := Player.new()
	a.position = Vector2(100, 100)
	b.position = Vector2(400, 100)
	a.control.use_external()
	b.control.use_external()
	add_child(a)
	add_child(b)
	var ca := PlayerInputCommand.new()
	ca.move_world = Vector2.RIGHT
	ca.sprint = true
	a.control.submit(ca)
	ca.move_world = Vector2.LEFT  # 호출자가 바꾼 값이 섞이지 않는지도 본다
	var cb := PlayerInputCommand.new()
	cb.move_world = Vector2.DOWN
	b.control.submit(cb)
	Input.action_press("accelerate")
	Input.action_press("sprint")
	Input.action_press("fire")
	await _frames(3)
	_expect(a.velocity.is_equal_approx(Vector2.RIGHT * Player.RUN_SPEED), "Aは送った右向き走りのまま")
	_expect(b.velocity.is_equal_approx(Vector2.DOWN * Player.WALK_SPEED), "Bは独立した下向き歩き。ローカル走りキーは混ざらない")
	_expect(not b.control.read().fire, "ローカル発射キーが外部入力に混ざらない")
	b.control.use_external()
	await _frames(2)
	_expect(b.velocity == Vector2.ZERO, "外部入力を解除すると押しっぱなしが消える")
	var invalid := PlayerInputCommand.new()
	invalid.move_world = Vector2(INF, 0)
	invalid.throttle = NAN
	invalid.steer = 9.0
	invalid.aim_enabled = true
	invalid.aim_world = Vector2(NAN, 0)
	b.control.submit(invalid)
	_expect(b.control.read().move_world == Vector2.ZERO and b.control.read().throttle == 0.0, "유효하지 않은 수치는 중립 입력")
	_expect(b.control.read().steer == 1.0 and not b.control.read().aim_enabled, "입력 범위와 조준 좌표 검사")
	for action in ["accelerate", "sprint", "fire"]:
		Input.action_release(action)
	b.control.use_local()
	b.screen_walk = false
	Input.action_press("accelerate")
	await _frames(2)
	_expect(b.velocity.is_equal_approx(Vector2.UP * Player.WALK_SPEED), "로컬 입력 복귀와 월드 방향 보행 유지")
	b.screen_walk = true
	await _frames(2)
	_expect(b.velocity.normalized().is_equal_approx(IsoView.walk_dir(Vector2.UP)), "화면 입력은 로컬 수집에서만 변환")
	Input.action_release("accelerate")
	b.control.use_external()
	a.control.use_external()
	var car := Vehicle.new()
	car.stats = load("res://data/vehicles/car_avela.tres")
	car.position = Vector2(100, 400)
	add_child(car)
	a.position = car.door_position(false)
	var d := Director.new()
	d.player = a
	d.vehicles = [car]
	add_child(d)
	var key := InputEventAction.new()
	key.action = &"enter_exit"
	key.pressed = true
	d._unhandled_input(key)
	_expect(not d.is_entering(), "외부 플레이어는 로컬 F 이벤트를 무시")
	a.control.request_action(&"enter_exit")
	await _frames(18)
	_expect(d.current_vehicle == car, "외부 동작 요청으로 탑승")
	var drive := PlayerInputCommand.new()
	drive.throttle = 0.7
	drive.steer = -0.25
	drive.handbrake = true
	drive.aim_enabled = true
	drive.aim_world = Vector2(800, 500)
	a.control.submit(drive)
	Input.action_press("brake")
	await _frames(2)
	_expect(is_equal_approx(car.throttle_input, 0.7) and is_equal_approx(car.steer_input, -0.25) and car.handbrake_input, "차에도 같은 외부 입력 전달")
	var w := PlayerWeapons.new()
	w.player = a
	w.director = d
	add_child(w)
	w.set_physics_process(false)
	_expect(w.mouse_point(a.position) == drive.aim_world, "외부 조준은 마우스·카메라에 의존하지 않음")
	var click := InputEventMouseButton.new()
	click.pressed = true
	w._input(click)
	_expect(not w.mouse_aim, "외부 플레이어는 마우스 이벤트를 무시")
	a.arsenal.give(load("res://data/weapons/pistol.tres"), 10)
	var weapon_before := a.arsenal.index
	key.action = &"weapon_next"
	w._unhandled_input(key)
	_expect(a.arsenal.index == weapon_before, "로컬 무기 변경 이벤트가 외부 플레이어에게 전달되지 않음")
	a.control.request_action(&"weapon_next")
	_expect(a.arsenal.index != weapon_before and b.arsenal.weapons.size() == 1, "외부 무기 변경은 해당 플레이어에게만 적용")
	a.control.request_action(&"enter_exit")
	await _frames(2)
	_expect(d.current_vehicle == null and a.visible, "외부 동작 요청으로 하차")
	Input.action_release("brake")
	d.queue_free()
	w.queue_free()
	a.queue_free()
	b.queue_free()
	car.queue_free()
	await _frames(1)
	if _failures.is_empty():
		print("player_control_test: PASS")
		get_tree().quit(0)
	else:
		for message in _failures:
			printerr("FAIL: ", message)
		get_tree().quit(1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
