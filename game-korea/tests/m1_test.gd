extends Node
## M1 완료 기준 검증: 도보 이동, 탑승(0.3초 이내)·하차, 운전자 탈취, 보행자 24명이 인도를 걷고 차를 피한다.
## 실행: godot --headless --path . res://tests/m1_test.tscn

const MAX_ENTER_FRAMES := 18     ## 0.3초 @60fps

var _failures: Array[String] = []
var main: Node2D


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = 0   # 도로 NPC 차는 M2 테스트에서 따로 본다
	main.bus_count = 0
	add_child(main)
	await _frames(2)

	await _test_walk()
	await _test_arrow_turn()
	await _test_enter_exit()
	await _test_steal()
	await _test_pedestrians_on_sidewalk()
	await _test_dodge_and_fear()
	_test_determinism()

	if _failures.is_empty():
		print("m1_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _test_walk() -> void:
	var p: Player = main.player
	_expect(main.director.current_vehicle == null, "시작은 도보")
	var start := p.global_position
	Input.action_press("accelerate")
	await _frames(1)
	_expect(is_equal_approx(p.velocity.length(), Player.WALK_SPEED), "도보는 관성 없이 즉시 최고 속도 (%.0f)" % p.velocity.length())
	await _frames(29)
	Input.action_release("accelerate")
	await _frames(1)
	_expect(p.velocity == Vector2.ZERO, "키를 떼면 즉시 정지")
	var moved := start.y - p.global_position.y
	_expect(moved > 40.0, "0.5초 걸어서 인도를 따라 위로 40px 이상 (실제 %.0f)" % moved)
	main.reset()
	await _frames(1)


## 방향키 ←→는 제자리에서 돌기만, ↑는 바라보는 쪽으로 걷는다 (WASD는 화면 방향 그대로)
func _test_arrow_turn() -> void:
	var p: Player = main.player
	var start := p.global_position
	var face := p.facing
	Input.action_press("turn_right")
	await _frames(20)
	Input.action_release("turn_right")
	await _frames(1)
	_expect(p.global_position.distance_to(start) < 0.5, "→는 걷지 않는다 (움직인 %.1fpx)" % p.global_position.distance_to(start))
	var turned := angle_difference(face, p.facing)
	_expect(turned > 0.8, "→로 오른쪽으로 돈다 (%.2f rad)" % turned)
	var ahead := Vector2.UP.rotated(p.facing)
	Input.action_press("walk_forward")
	await _frames(20)
	Input.action_release("walk_forward")
	await _frames(1)
	var step := p.global_position - start
	_expect(step.length() > 15.0 and step.normalized().dot(ahead) > 0.9, "↑는 바라보는 쪽으로 걷는다 (%s)" % step)
	_expect(absf(angle_difference(p.facing, ahead.angle() + PI / 2.0)) < 0.01, "↑로 걸어도 방향은 그대로")
	main.reset()
	await _frames(1)


func _test_enter_exit() -> void:
	var d: Director = main.director
	var car: Vehicle = main.start_vehicle
	_expect(d.nearest_enterable() == car, "출발점에서 가장 가까운 탈 차는 출발 차")
	d.request_enter_exit()
	var frames := 0
	while d.current_vehicle == null and frames < 60:
		await _frames(1)
		frames += 1
	_expect(d.current_vehicle == car, "F로 출발 차에 탑승")
	_expect(frames <= MAX_ENTER_FRAMES, "탑승 전환 %d프레임 (0.3초=%d 이내)" % [frames, MAX_ENTER_FRAMES])
	_expect(not main.player.visible, "탑승 중 주인공은 숨겨진다")
	_expect(main.camera.target == car, "카메라가 차를 따라간다")

	Input.action_press("accelerate")
	await _frames(60)
	Input.action_release("accelerate")
	_expect(car.speed() > 200.0, "운전 가능 (속도 %.0f)" % car.speed())

	d.request_enter_exit()
	await _frames(1)
	_expect(d.current_vehicle == null and main.player.visible, "F로 하차")
	_expect(main.player.global_position.distance_to(car.global_position) < 60.0, "차 옆에 내린다")
	_expect(not main.player.blocked_at(main.player.global_position), "내린 자리가 벽·차와 겹치지 않는다")
	await _frames(120)
	_expect(car.speed() < 5.0, "빈 차는 스스로 선다 (속도 %.0f)" % car.speed())
	main.reset()
	await _frames(1)


func _test_steal() -> void:
	var d: Director = main.director
	var target: Vehicle = null
	for v: Vehicle in main.vehicles:
		if v.has_driver:
			target = v
			break
	var before: int = main.pedestrians.peds.size()
	var stolen := []
	d.vehicle_stolen.connect(func(v, driver): stolen.append(driver), CONNECT_ONE_SHOT)
	main.player.global_position = target.door_position(false) + Vector2(-20, 0).rotated(target.motor.heading)
	await _frames(1)
	d.request_enter_exit()
	await _frames(MAX_ENTER_FRAMES + 1)
	_expect(d.current_vehicle == target, "운전자 있는 차 탈취")
	_expect(not target.has_driver, "운전자는 차에서 빠진다")
	_expect(main.pedestrians.peds.size() == before + 1, "끌려 나온 운전자가 보행자로 생긴다")
	_expect(stolen.size() == 1 and (stolen[0] as Pedestrian).state == Pedestrian.State.FLEE, "끌려 나온 운전자는 도망친다")
	main.reset()
	await _frames(1)


func _test_pedestrians_on_sidewalk() -> void:
	var peds: Array[Pedestrian] = main.pedestrians.peds
	var initial := 0
	for p in peds:
		if p.npc != null:
			initial += 1
	_expect(initial >= PedestrianManager.COUNT, "보행자 %d명 이상 (실제 %d)" % [PedestrianManager.COUNT, initial])
	# LOD 때문에 멀리 있는 보행자는 멈춰 있으므로, 전부 활성화해 5초 걷게 한다
	for p in peds:
		p.set_active(true)
	main.pedestrians.set_physics_process(false)
	await _frames(300)
	main.pedestrians.set_physics_process(true)
	var walking := 0
	for p in peds:
		if p.state == Pedestrian.State.FLEE:
			continue
		if _in_building(p.global_position):
			_failures.append("보행자가 건물 안에 있음: %s" % p.global_position)
		if p.state == Pedestrian.State.WALK:
			walking += 1
		_expect(_on_sidewalk(p.global_position), "보행자가 인도 밖에 있음: %s" % p.global_position)
	_expect(walking >= 12, "5초 뒤 절반 이상 걷는 중 (실제 %d)" % walking)


func _test_dodge_and_fear() -> void:
	# 한 블록 인도에 모인 세 명 쪽으로 빠른 차를 몰아 본다
	var peds: Array[Pedestrian] = main.pedestrians.peds
	var loop := City.sidewalk_loop(Vector2i(2, 2))
	var group: Array[Pedestrian] = []
	for i in 3:
		var p := peds[i]
		p.global_position = loop[0] + Vector2(200 + i * 40, 0)
		p.resume_walking()
		group.append(p)
	var car: Vehicle = main.start_vehicle
	main.director.enter_immediately(car)
	# 인도 바로 위(같은 y)에서 오른쪽으로 500px/s로 달려오게 둔다
	car.place(group[0].global_position + Vector2(-420, 0), PI * 0.5)
	car.motor.velocity = Vector2.RIGHT * 500.0
	main.pedestrians.set_physics_process(true)
	var dodged := false
	for f in 30:
		await _frames(1)
		if group[0].is_scared():
			dodged = true
			break
	_expect(dodged, "다가오는 차를 보고 피하거나 도망친다")
	await _frames(30)
	var scared := 0
	for p in group:
		if p.is_scared():
			scared += 1
	_expect(scared >= 2, "빠른 차가 지나가면 주변까지 겁먹는다 (%d/3)" % scared)
	main.reset()
	await _frames(1)

	# 넘어진 사람은 KNOCK_TIME 뒤 일어나 도망쳤다가 다시 걷는다 (도로에 누운 채 교통을 막지 않게)
	var knocked: Pedestrian = peds[0]
	knocked.global_position = loop[0] + Vector2(200, 0)
	knocked.set_active(true)
	knocked.resume_walking()
	knocked.knock_down(Vector2.DOWN)
	knocked.panic(Vector2.UP)
	_expect(knocked.state == Pedestrian.State.KNOCKED, "넘어진 동안엔 겁먹어도 그대로 누워 있다")
	await _frames(int(Pedestrian.KNOCK_TIME * 60.0) + 10)
	_expect(knocked.state == Pedestrian.State.FLEE, "넘어진 사람은 일어나 도망친다 (%d)" % knocked.state)
	await _frames(int(Pedestrian.FLEE_TIME * 1.2 * 60.0) + 10)
	_expect(knocked.state == Pedestrian.State.WALK or knocked.state == Pedestrian.State.IDLE,
		"도망친 뒤 다시 걷는다 (%d)" % knocked.state)
	main.reset()
	await _frames(1)


func _test_determinism() -> void:
	var a := PedestrianManager.new()
	var b := PedestrianManager.new()
	add_child(a)
	add_child(b)
	var same := a.peds.size() == b.peds.size()
	for i in mini(a.peds.size(), b.peds.size()):
		same = same and a.peds[i].position == b.peds[i].position and a.peds[i].npc == b.peds[i].npc
	_expect(same, "같은 시드면 보행자 배치가 같다")
	a.queue_free()
	b.queue_free()


func _in_building(pos: Vector2) -> bool:
	for r: Rect2 in main.city.buildings:
		if r.has_point(pos):
			return true
	return false


func _on_sidewalk(pos: Vector2) -> bool:
	var block := City.nearest_block(pos)
	var r := City.block_rect(block.x, block.y)
	return r.grow(4.0).has_point(pos) and not r.grow(-City.SIDEWALK - 2.0).has_point(pos)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
