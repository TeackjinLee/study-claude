extends Node
## M4 차량 내구도·폭발 검증.
##  1. 피해 계산: 약한 충돌은 흠집 없음, 전속력 벽 충돌 한 번에는 안 터진다, 폭발 피해는 거리에 따라 준다.
##  2. 실제로 건물에 들이받으면 체력이 깎이지만 터지지 않는다. 들이받은 앞쪽이 찌그러진다(그림).
##  2-1. 체력이 20% 아래면 불이 난다 — 아직 탈 수 있지만 체력이 타들어가 결국 터진다.
##  3. 총에 맞아 체력이 0이 되면 불이 붙고(탈 수 없다), 잠시 뒤 터져 잔해가 된다.
##  4. 운전자가 탄 차에 불이 붙으면 운전자가 뛰어내려 도망치고, 교통은 새 차로 채워진다.
##  5. 연쇄 폭발: 줄지어 선 차 하나가 터지면 옆 차들이 차례로 터진다. 멀리 있는 차와 사람은 무사, 가까운 사람은 죽는다.
##  6. 불붙은 차에서 안 내리면 차와 함께 죽어 병원에서 시작한다. 바로 내려 달아나면 산다.
##  7. 불붙은 경찰차: 경찰이 내려 쫓아오고, 그 차는 더 이상 경찰차가 아니다.
##  8. 잔해는 시간이 지나 화면 밖이면 치운다.
## 실행: godot --headless --fixed-fps 60 --path . res://tests/vehicle_damage_test.tscn

const SEDAN: VehicleType = preload("res://data/vehicles/car_avela.tres")
const TRUCK: VehicleType = preload("res://data/vehicles/trk_porta.tres")
const PISTOL: WeaponType = preload("res://data/weapons/pistol.tres")

var _failures: Array[String] = []


func _ready() -> void:
	_test_model()
	await _test_wall_crash()
	await _test_fire_at_low_health()
	await _test_shoot_car()
	await _test_npc_bails_out()
	await _test_chain()
	await _test_burning_with_player()
	await _test_police_car_fire()
	await _test_wreck_cleanup()
	if _failures.is_empty():
		print("vehicle_damage_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _make_main(cars := 0, patrols := 0) -> Node2D:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = cars
	main.bus_count = 0
	main.police_patrols = patrols
	add_child(main)
	return main


func _free(main: Node2D) -> void:
	for a in ["accelerate", "brake", "steer_left", "steer_right", "fire", "sprint"]:
		Input.action_release(a)
	main.queue_free()
	await _frames(2)


func _test_model() -> void:
	_expect(DamageModel.crash_damage(200.0) == 0.0, "약한 충돌은 흠집도 없다")
	var full := DamageModel.crash_damage(SEDAN.max_speed)
	_expect(full > SEDAN.durability * 0.15 and full < SEDAN.durability * 0.5,
		"세단 전속력 정면 충돌 피해 %.0f (체력 %.0f의 15~50%%)" % [full, SEDAN.durability])
	_expect(DamageModel.explosion_falloff(0.0) == 1.0 and DamageModel.explosion_falloff(DamageModel.EXPLOSION_RADIUS) == 0.0, "폭발 피해는 중심 100% → 반경 끝 0%")
	_expect(DamageModel.EXPLOSION_VEHICLE_DAMAGE * DamageModel.explosion_falloff(90.0) >= SEDAN.durability,
		"90px 옆 세단은 폭발에 휘말려 터진다")
	_expect(DamageModel.EXPLOSION_VEHICLE_DAMAGE * DamageModel.explosion_falloff(90.0) < 300.0, "버스는 버틴다")


func _test_wall_crash() -> void:
	var main := _make_main()
	await _frames(2)
	var v: Vehicle = main.start_vehicle
	main.director.enter_immediately(v)
	# 세로 도로 1번을 북쪽으로 달려 도시 바깥 벽에 정면으로 들이받는다
	v.place(Vector2(City.road_center(1) + 40.0, 1000.0), 0.0)
	Input.action_press("accelerate")
	await _frames(150)
	Input.action_release("accelerate")
	await _frames(10)
	print("  벽 충돌 뒤 체력 %.0f / %.0f" % [v.health, v.stats.durability])
	_expect(v.health < v.stats.durability - 20.0, "건물에 들이받으면 체력이 깎인다 (%.0f)" % v.health)
	_expect(v.burning < 0.0 and not v.wrecked, "한 번 들이받아서는 불이 붙지 않는다")
	_expect(not v.dents.is_empty() and (v.dents[0][0] as Vector2).y < 0.0,
		"정면으로 들이받으면 앞이 찌그러진다 (%d곳)" % v.dents.size())
	await _free(main)


func _test_fire_at_low_health() -> void:
	var main := _make_main()
	await _frames(2)
	var car: Vehicle = main.start_vehicle
	car.take_damage(car.max_health() * 0.75, false)
	_expect(not car.on_fire, "체력 25%에서는 불이 안 난다")
	car.take_damage(car.max_health() * 0.1, false)
	_expect(car.on_fire and car.burning < 0.0 and car.usable(), "체력 20% 아래면 불이 나지만 아직 탈 수 있다")
	await _frames(int((DamageModel.FIRE_TIME + 0.5) * 60))
	_expect(car.burning >= 0.0 or car.wrecked, "불난 차는 체력이 타들어가 불붙는다 (체력 %.1f)" % car.health)
	await _frames(int((DamageModel.BURN_TIME + 0.5) * 60))
	_expect(car.wrecked, "불난 차는 끝내 터진다")
	await _free(main)


func _test_shoot_car() -> void:
	var main := _make_main()
	await _frames(2)
	var player: Player = main.player
	var car: Vehicle = main.start_vehicle     # 주인공 바로 왼쪽에 선 빈 세단
	player.arsenal.give(PISTOL, 24)
	player.facing = -PI * 0.5
	var exploded := [false]
	main.combat.vehicle_exploded.connect(func(v, by_player): exploded[0] = v == car and by_player)
	Input.action_press("fire")
	for f in 300:
		await _frames(1)
		if car.burning >= 0.0:
			break
	Input.action_release("fire")
	var used: int = 24 - player.arsenal.ammo_of(PISTOL)
	_expect(car.burning >= 0.0, "총에 맞아 체력이 0이 되면 불이 붙는다 (권총 %d발)" % used)
	_expect(used == ceili(SEDAN.durability / PISTOL.damage), "세단은 권총 %d발 (%d발)" % [ceili(SEDAN.durability / PISTOL.damage), used])
	_expect(main.director.nearest_enterable() != car, "불붙은 차에는 못 탄다")
	player.global_position += Vector2(0, -400)        # 피한다
	await _frames(int(DamageModel.BURN_TIME * 60) + 5)
	_expect(car.wrecked and exploded[0], "불붙은 차는 %.0f초 뒤 터진다 (주인공 탓)" % DamageModel.BURN_TIME)
	_expect(not player.is_dead() and player.health == Player.MAX_HEALTH, "멀리 피하면 다치지 않는다 (%.0f)" % player.health)
	player.global_position = car.door_position(false)
	await _frames(1)
	_expect(main.director.nearest_enterable() != car, "잔해에는 못 탄다")
	await _free(main)


func _test_npc_bails_out() -> void:
	var main := _make_main(3)
	await _frames(2)
	var traffic: TrafficSystem = main.traffic
	var car: Vehicle = traffic.ais[0].vehicle
	var peds_before: int = main.pedestrians.peds.size()
	car.take_damage(1000.0, false)
	await _frames(1)
	_expect(car.burning >= 0.0 and not car.has_driver and car.ai == null, "불붙은 NPC 차는 운전자가 내리고 AI가 빠진다")
	_expect(main.pedestrians.peds.size() == peds_before + 1, "뛰어내린 운전자가 보행자로 생긴다")
	_expect(main.pedestrians.peds[-1].state == Pedestrian.State.FLEE, "운전자는 도망친다")
	await _frames(int(DamageModel.BURN_TIME * 60) + 5)
	_expect(car.wrecked, "그리고 터진다")
	await _frames(180)
	_expect(traffic.ais.size() == 3, "교통은 새 차로 채운다 (%d대)" % traffic.ais.size())
	await _free(main)


func _park(main: Node2D, type: VehicleType, pos: Vector2, heading: float) -> Vehicle:
	var v := Vehicle.new()
	v.stats = type
	main.add_child(v)
	v.place(pos, heading)
	main.vehicles.append(v)
	return v


func _test_chain() -> void:
	var main := _make_main()
	await _frames(2)
	# 주인공·출발 차에서 먼 가로 도로 1번 위에 세단 넷을 75px 간격으로, 그 끝에서 500px 떨어진 곳에 하나 더
	var y := City.road_center(1) + 40.0
	var x0 := City.road_center(1) + 150.0
	var row: Array[Vehicle] = []
	for i in 4:
		row.append(_park(main, SEDAN, Vector2(x0 + i * 75.0, y), PI * 0.5))
	var far := _park(main, SEDAN, Vector2(x0 + 3 * 75.0 + 500.0, y), PI * 0.5)
	var near_ped: Pedestrian = main.pedestrians.peds[0]
	near_ped.global_position = Vector2(x0 - 30.0, y - 60.0)
	var far_ped: Pedestrian = main.pedestrians.peds[1]
	# 먼 사람은 건물 너머 윗 블록 인도에 세운다 (같은 길가면 폭발에 밀려 미끄러지는 잔해에 치일 수 있다)
	far_ped.global_position = Vector2(x0 + 3 * 75.0 + 300.0, City.road_center(0) + City.ROAD * 0.5 + 14.0)
	main.camera.target = null
	main.camera.global_position = Vector2(x0 + 300.0, y)
	await _frames(2)
	var times := {}
	main.combat.vehicle_exploded.connect(func(v, _p): times[v] = Time.get_ticks_msec())
	row[0].take_damage(1000.0, false, 0.1)
	await _frames(6 * 60)
	var blown := 0
	for v in row:
		if v.wrecked:
			blown += 1
	print("  연쇄 폭발: 줄 %d/4대, 먼 차 %s" % [blown, "터짐" if far.wrecked else "무사"])
	_expect(blown == 4, "폭발이 줄지어 선 차를 연쇄로 터뜨린다 (%d/4)" % blown)
	_expect(not far.wrecked, "500px 떨어진 차는 무사하다")
	_expect(times.size() >= 4 and times[row[3]] > times[row[0]], "차례로 터진다")
	_expect(near_ped.is_dead(), "가까운 사람은 죽는다")
	_expect(not far_ped.is_dead(), "먼 사람은 무사하다")
	_expect(main.police.wanted.level == 0, "주인공 탓이 아니면 수배 없음")
	await _free(main)


func _test_burning_with_player() -> void:
	# 안 내리면 차와 함께 죽는다
	var main := _make_main()
	await _frames(2)
	var car: Vehicle = main.start_vehicle
	main.director.enter_immediately(car)
	car.take_damage(1000.0, false)
	_expect(main.director.current_vehicle == car, "불이 붙어도 내리기 전엔 탄 채로")
	await _frames(int(DamageModel.BURN_TIME * 60) + 5)
	_expect(main.player.is_dead(), "불붙은 차에서 안 내리면 죽는다")
	_expect(main.director.current_vehicle == null, "잔해에서 끌려 나온다")
	await _frames(int(main.BUST_DELAY * 60) + 10)
	_expect(main.player.global_position.distance_to(City.hospital_position()) < 5.0, "병원에서 다시 시작")
	await _free(main)

	# 바로 내려 달아나면 산다
	main = _make_main()
	await _frames(2)
	car = main.start_vehicle
	main.director.enter_immediately(car)
	car.take_damage(1000.0, false)
	await _frames(10)
	main.director.request_enter_exit()
	await _frames(1)
	Input.action_press("accelerate")
	Input.action_press("sprint")
	await _frames(int(DamageModel.BURN_TIME * 60))
	Input.action_release("accelerate")
	Input.action_release("sprint")
	await _frames(10)
	_expect(car.wrecked, "차는 터진다")
	_expect(not main.player.is_dead(), "내려서 달아나면 산다 (체력 %.0f, 거리 %.0f)" % [main.player.health, main.player.global_position.distance_to(car.global_position)])
	await _free(main)


func _test_police_car_fire() -> void:
	var main := _make_main(0, 1)
	await _frames(2)
	var police: PoliceDispatcher = main.police
	var car: Vehicle = police.cars[0]
	main.camera.target = null
	main.camera.global_position = car.global_position
	car.take_damage(1000.0, false)
	await _frames(1)
	_expect(not police.owns(car), "불붙은 경찰차는 경찰 것에서 빠진다")
	_expect(police.officers.size() == 1, "탔던 경찰이 내린다 (%d명)" % police.officers.size())
	await _frames(int(DamageModel.BURN_TIME * 60) + 70)
	_expect(car.wrecked, "경찰차도 터진다")
	var patrols := 0
	for c in police.cars:
		if c.ai:
			patrols += 1
	_expect(patrols == 1, "순찰차는 새로 채운다 (%d대)" % patrols)
	await _free(main)


func _test_wreck_cleanup() -> void:
	var main := _make_main()
	await _frames(2)
	var car: Vehicle = main.vehicles[2]
	car.take_damage(1000.0, false, 0.05)
	await _frames(10)
	_expect(car.wrecked, "터졌다")
	await _frames(60)
	_expect(main.vehicles.has(car), "잔해는 바로 사라지지 않는다")
	main.combat._wrecks[car] = Combat.WRECK_TIME
	main.camera.target = null
	main.camera.global_position = car.global_position + Vector2(3000, 0)
	var before: int = main.vehicles.size()
	await _frames(3)
	_expect(not is_instance_valid(car) or car.is_queued_for_deletion(), "시간이 지나 화면 밖이면 치운다")
	_expect(main.vehicles.size() == before - 1, "목록에서도 빠진다")
	await _free(main)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
