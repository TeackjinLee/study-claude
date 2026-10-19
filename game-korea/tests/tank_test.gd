extends Node
## 군용 차량 (자주포·소형 전술차량) · 중장비 (굴삭기·불도저) 검증.
##  1. 무한궤도는 제자리에서 돈다 (VehicleMotor, 노드 없이).
##  2. 4장 부두 야적장에 자주포·전술차량이 서 있고 건물과 겹치지 않는다. 모형에 포탑·포신 부품이 있다.
##  3. 자주포를 타면 포탑이 겨눈 쪽으로 돌고, 멀리 겨눌수록 포신을 든다. 쏘면 포탄이 겨눈 땅으로 날아가 터진다 (건물 너머로).
##     장전 중에는 다시 못 쏜다.
##  4. 자주포는 차에 막히지 않고 깔고 넘는다: 깔린 차는 납작해지며 크게 다치고, 자주포는 그 위로 올라탄다. 밑에 든 사람은 죽는다.
##  5. 전술차량을 타면 지붕 기관총이 포탑처럼 돌고 그쪽으로 쏜다.
##  6. ★6 군 투입: 자주포·전술차량이 오고, 자주포는 주인공에게 포탄을 쏜다.
##  7. 자주포는 도시에 한 대만: 4장 부두에 서 있으면 ★6에도 새로 오지 않는다 (전술차량은 온다).
##  8. 굴삭기 팔 역기구학: 버킷 끝이 겨눈 (거리, 높이)에 간다 (노드 없이).
##  9. 4장 공단 도로 공사 현장: 굴삭기·불도저가 서 있고 건물과 겹치지 않는다. 라바콘·표지판·흙더미.
## 10. 굴삭기: 퍼 올리면 찍은 곳의 차를 집고(운전자는 내린다), 상부를 돌리면 차가 따라오고, 다시 퍼 올리면 놓아 떨어뜨린다
##     (떨어진 차는 다치고 다시 부딪힌다). 찍힌 사람은 넘어진다.
## 11. 불도저: 블레이드를 들고 내린다. 내린 채 밀고 가면 앞의 차가 다치며 밀린다.
## 실행: godot --headless --fixed-fps 60 --path . res://tests/tank_test.tscn

const SPG: VehicleType = preload("res://data/vehicles/army_spg.tres")
const JEEP: VehicleType = preload("res://data/vehicles/army_jeep.tres")
const SEDAN: VehicleType = preload("res://data/vehicles/car_avela.tres")
const CANNON: WeaponType = preload("res://data/weapons/tank_cannon.tres")
const CIV: NpcType = preload("res://data/npc/civ_m.tres")
const DIGGER: VehicleType = preload("res://data/vehicles/heavy_excavator.tres")
const DOZER: VehicleType = preload("res://data/vehicles/heavy_dozer.tres")

var _failures: Array[String] = []


func _ready() -> void:
	_test_pivot()
	await _test_dock_parking()
	await _test_cannon()
	await _test_crush()
	await _test_jeep()
	await _test_army()
	await _test_one_tank()
	_test_arm_ik()
	await _test_work_site()
	await _test_excavator()
	await _test_dozer()
	CityMap.set_chapter(1)
	if _failures.is_empty():
		print("tank_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _make_main(chapter: int) -> Node2D:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = 0
	main.bus_count = 0
	main.police_patrols = 0
	main.save_prefix = "user://tank_test_save_"
	main.chapter = chapter
	add_child(main)
	main.player.died.disconnect(main._on_died)
	main.police.busted.disconnect(main._on_busted)
	return main


func _vehicle(main: Node2D, t: VehicleType, pos: Vector2, heading := 0.0) -> Vehicle:
	var v := Vehicle.new()
	v.stats = t
	main.add_child(v)
	v.place(pos, heading)
	main.vehicles.append(v)
	return v


## 빈 도로 (교차로 사이 긴 직선) 가운데
func _open_road() -> Vector2:
	return LaneGraph.center(Vector2i(3, 2)) + Vector2(0, 300)


func _test_pivot() -> void:
	var m := VehicleMotor.new(SPG)
	for i in 60:
		m.step(0.0, 1.0, false, 1.0 / 60.0)
	_expect(absf(m.heading) > 0.5 and m.velocity.length() < 1.0, "무한궤도는 서서 제자리에서 돈다 (%.2f rad)" % m.heading)
	var car := VehicleMotor.new(SEDAN)
	for i in 60:
		car.step(0.0, 1.0, false, 1.0 / 60.0)
	_expect(absf(car.heading) < 0.01, "바퀴 차는 서서는 못 돈다")


func _test_dock_parking() -> void:
	var main := _make_main(4)
	await _frames(2)
	var found := {}
	for v: Vehicle in main.vehicles:
		if v.stats == SPG or v.stats == JEEP:
			found[v.stats.id] = v
	_expect(found.has(&"ARMY_SPG") and found.has(&"ARMY_JEEP"), "4장 부두에 자주포·전술차량 (%s)" % str(found.keys()))
	var space: PhysicsDirectSpaceState2D = main.get_world_2d().direct_space_state
	for v: Vehicle in found.values():
		var q := PhysicsShapeQueryParameters2D.new()
		q.shape = v._shape.shape
		q.transform = v.global_transform
		q.collision_mask = Layers.WORLD
		_expect(space.intersect_shape(q, 1).is_empty(), "%s: 건물·장애물과 겹치지 않게 세운다 %s" % [v.stats.display_name, v.global_position])
		_expect(v.usable() if v.has_method("usable") else true, "%s: 탈 수 있다" % v.stats.display_name)
	var parts: Array = VehicleModel.model(SPG)
	_expect(parts.any(func(p): return p.turret == 1) and parts.any(func(p): return p.turret == 2), "자주포 모형: 포탑·포신 부품")
	_expect(VehicleModel.model(JEEP).any(func(p): return p.turret == 1), "전술차량 모형: 지붕 기관총(포탑) 부품")
	main.queue_free()
	await _frames(2)


func _test_cannon() -> void:
	var main := _make_main(1)
	await _frames(2)
	var at := _open_road()
	var tank := _vehicle(main, SPG, at, 0.0)
	main.director.enter_immediately(tank)
	main.weapons.mouse_aim = false
	await _frames(2)
	# 포탑을 오른쪽으로 돌리고 멀리 겨눈다
	tank.turret_goal = PI * 0.5
	tank.aim_range = 300.0
	await _frames(60)
	var low := tank.elevation
	tank.aim_range = SPG.cannon_max
	await _frames(int(60 * 2.0 / SPG.turret_rate))
	_expect(absf(angle_difference(tank.turret, PI * 0.5)) < 0.05, "포탑이 겨눈 쪽으로 돈다 (%.2f)" % tank.turret)
	_expect(tank.elevation > low + 0.2, "멀리 겨누면 포신을 든다 (%.2f → %.2f)" % [low, tank.elevation])
	# 표적 차를 떨어질 곳에 세우고 쏜다
	tank.aim_range = 520.0
	await _frames(30)
	var target := _vehicle(main, SEDAN, tank.gun_target(), 0.0)
	var hp := target.health
	var shot: bool = main.weapons.shoot()
	_expect(shot and main.combat.shells_in_flight() == 1, "쏘면 포탄 한 발이 날아간다")
	_expect(not main.weapons.shoot(), "장전 중에는 다시 못 쏜다")
	_expect(tank.recoil > 0.5, "쏘면 포신이 뒤로 밀린다")
	var blasts: int = main.combat._blasts.size()
	for f in 60 * 3:
		await _frames(1)
		main.player.revive()
		if main.combat.shells_in_flight() == 0:
			break
	_expect(main.combat.shells_in_flight() == 0 and main.combat._blasts.size() > blasts, "포탄이 겨눈 땅에서 터진다")
	_expect(not is_instance_valid(target) or target.wrecked or target.health < hp * 0.5 or target.burning >= 0.0,
		"떨어진 곳의 차가 크게 다친다")
	main.queue_free()
	await _frames(2)


func _test_crush() -> void:
	var main := _make_main(1)
	await _frames(2)
	var at := _open_road()
	var tank := _vehicle(main, SPG, at, 0.0)       # 화면 위(−y)를 본다
	var car := _vehicle(main, SEDAN, at + Vector2(0, -110), PI * 0.5)
	var ped := Pedestrian.new()
	ped.setup(CIV, main.pedestrians.rng, City.sidewalk_loop(City.nearest_block(at)), 0, 0.0, 1)
	ped.position = at + Vector2(-12, -64)   # 바로 앞 (다가오면 겁먹고 도망치므로 붙여 세운다)
	main.pedestrians.add(ped)
	ped._set_state(Pedestrian.State.IDLE, 999.0)
	main.director.enter_immediately(tank)
	await _frames(2)
	var start := tank.global_position
	var hp := car.health
	var top := 0.0
	Input.action_press("accelerate")
	for f in 60 * 4:
		await _frames(1)
		main.player.revive()
		top = maxf(top, tank.climb)
		if tank.global_position.distance_to(start) > 280.0:
			break
	Input.action_release("accelerate")
	_expect(tank.global_position.distance_to(start) > 200.0, "자주포는 차에 막히지 않고 지나간다 (%.0f px)" % tank.global_position.distance_to(start))
	_expect(car.crushed > 0.5, "깔린 차는 납작해진다 (%.2f)" % car.crushed)
	_expect(car.health < hp * 0.6 or car.burning >= 0.0 or car.wrecked, "깔린 차는 크게 다친다 (%.0f / %.0f)" % [car.health, hp])
	_expect(top > 5.0, "자주포가 깔고 넘는 차 위로 올라탄다 (최고 %.1f px)" % top)
	_expect(ped.is_dead(), "무한궤도 밑에 든 사람은 죽는다")
	for f in 60 * 3:
		await _frames(1)
		main.player.revive()
	_expect(tank.climb < 1.0, "차를 지나면 땅으로 내려온다 (%.1f, 목표 %.1f, 차 %s 자주포 %s)" % [tank.climb, tank.climb_goal,
		car.global_position if is_instance_valid(car) else "없음", tank.global_position])
	main.queue_free()
	await _frames(2)


func _test_jeep() -> void:
	var main := _make_main(1)
	await _frames(2)
	var at := _open_road()
	var jeep := _vehicle(main, JEEP, at, 0.0)
	main.director.enter_immediately(jeep)
	main.weapons.mouse_aim = false
	await _frames(2)
	jeep.turret_goal = -PI * 0.5
	await _frames(60)
	_expect(absf(angle_difference(jeep.turret, -PI * 0.5)) < 0.05, "전술차량 기관총이 돈다 (%.2f)" % jeep.turret)
	var car := _vehicle(main, SEDAN, at + Vector2(-160, 0), 0.0)   # 왼쪽 (기관총이 겨눈 쪽)
	var hp := car.health
	for i in 40:
		main.weapons.shoot()
		await _frames(2)
	_expect(car.health < hp, "기관총이 겨눈 쪽 차를 맞힌다 (%.0f / %.0f)" % [car.health, hp])
	main.queue_free()
	await _frames(2)


func _test_army() -> void:
	var main := _make_main(2)
	await _frames(2)
	var police: PoliceDispatcher = main.police
	var player: Player = main.player
	player.global_position = City.hq_door() + Vector2(0, -120)
	police.last_known = player.global_position
	police.wanted.raise_to(6)
	var spg := false
	var jeep := false
	var shelled := false
	for f in 60 * 90:
		await _frames(1)
		police._arrest = 0.0
		player.revive()
		spg = spg or police._count_type(PoliceDispatcher.SPG_TYPE) > 0
		jeep = jeep or police._count_type(PoliceDispatcher.JEEP_TYPE) > 0
		shelled = shelled or main.combat._shells.any(func(p): return not p.by_player)
		if spg and jeep and shelled:
			break
	_expect(spg, "★6: 자주포가 온다")
	_expect(jeep, "★6: 소형 전술차량이 온다")
	_expect(shelled, "★6: 자주포가 주인공에게 포탄을 쏜다")
	main.queue_free()
	await _frames(2)


func _alive_tanks(main: Node2D) -> int:
	return main.vehicles.filter(func(v: Vehicle): return v.stats == SPG and not v.wrecked).size()


func _test_one_tank() -> void:
	var main := _make_main(4)
	await _frames(2)
	_expect(_alive_tanks(main) == 1, "4장: 부두에 자주포 한 대 (%d)" % _alive_tanks(main))
	var police: PoliceDispatcher = main.police
	var player: Player = main.player
	player.global_position = City.hq_door() + Vector2(0, -120)
	police.last_known = player.global_position
	police.wanted.raise_to(6)
	var most := 0
	var jeep := false
	for f in 60 * 60:
		await _frames(1)
		police._arrest = 0.0
		player.revive()
		most = maxi(most, _alive_tanks(main))
		jeep = jeep or police._count_type(PoliceDispatcher.JEEP_TYPE) > 0
		if jeep and f > 60 * 20:
			break
	_expect(most == 1, "★6에도 자주포는 한 대뿐이다 (최대 %d)" % most)
	_expect(jeep, "자주포가 있어도 전술차량은 온다")
	_expect(Vehicle.exists(main.vehicles, SPG) and not Vehicle.exists(main.vehicles, JEEP), "한 대만 있는 차종은 자주포뿐이다")
	main.queue_free()
	await _frames(2)


func _test_arm_ik() -> void:
	for r in [DIGGER.arm_reach.x, 70.0, DIGGER.arm_reach.y]:
		for z in [ExcavatorArm.CARRY_Z, ExcavatorArm.DIG_Z]:
			var tip := ExcavatorArm.tip(ExcavatorArm.solve(r, z))
			_expect(tip.distance_to(Vector2(r, z)) < 1.0, "굴삭기 팔: 버킷 끝이 (%.0f, %.0f)에 간다 (%s)" % [r, z, tip])


func _test_work_site() -> void:
	var main := _make_main(4)
	await _frames(2)
	var site := City.work_site()
	_expect(not site.is_empty() and site.cones.size() >= 8, "4장: 도로 공사 현장 (라바콘 %d개)" % (site.cones.size() if not site.is_empty() else 0))
	_expect(main.work_zone != null, "공사 현장 장식이 선다")
	var space: PhysicsDirectSpaceState2D = main.get_world_2d().direct_space_state
	for t in [DIGGER, DOZER]:
		var found: Array = main.vehicles.filter(func(v: Vehicle): return v.stats == t)
		_expect(found.size() == 1, "%s 한 대가 공사 현장에 선다 (%d)" % [t.display_name, found.size()])
		if found.is_empty():
			continue
		var q := PhysicsShapeQueryParameters2D.new()
		q.shape = found[0]._shape.shape
		q.transform = found[0].global_transform
		q.collision_mask = Layers.WORLD
		_expect(space.intersect_shape(q, 1).is_empty(), "%s: 건물·장애물과 겹치지 않는다" % t.display_name)
	main.queue_free()
	await _frames(2)
	var closed := _make_main(1)
	await _frames(2)
	_expect(City.work_site().is_empty() and closed.work_zone == null, "1장에는 공사 현장이 없다 (공단이 닫혀 있다)")
	closed.queue_free()
	await _frames(2)


func _test_excavator() -> void:
	var main := _make_main(1)
	await _frames(2)
	var at := _open_road()
	var digger := _vehicle(main, DIGGER, at, 0.0)
	main.director.enter_immediately(digger)
	main.weapons.mouse_aim = false
	await _frames(2)
	digger.aim_range = 70.0
	await _frames(60)
	var car := _vehicle(main, SEDAN, digger.bucket_ground(), PI * 0.5)
	car.has_driver = true
	var peds_before: int = main.pedestrians.peds.size()
	_expect(main.weapons.shoot(), "쏘기 버튼으로 퍼 올리기를 시작한다")
	_expect(not main.weapons.shoot(), "퍼 올리는 중에는 다시 못 한다")
	var lowest := 99.0
	for f in int(60 * ExcavatorArm.DIG_TIME) + 10:
		await _frames(1)
		lowest = minf(lowest, ExcavatorArm.tip(Vector2(digger.joints.x, digger.joints.y)).y)
	_expect(lowest < 6.0, "버킷이 땅까지 내려찍는다 (가장 낮은 끝 %.1f)" % lowest)
	_expect(digger.carried == car and car.carried_by == digger, "찍은 곳의 차를 집는다")
	_expect(not car.has_driver and main.pedestrians.peds.size() > peds_before, "집힌 차의 운전자는 뛰어내린다")
	_expect(car.airborne() and car.collision_layer == 0, "집힌 차는 들려 있다 (높이 %.1f)" % car.altitude)
	# 상부를 오른쪽으로 돌리면 차가 따라온다
	digger.turret_goal = PI * 0.5
	for f in 120:
		await _frames(1)
	_expect(car.global_position.distance_to(digger.bucket_ground()) < 30.0 and car.global_position.x > at.x + 30.0,
		"상부를 돌리면 든 차가 따라온다 %s" % car.global_position)
	var hp := car.health
	main.weapons.shoot()
	for f in 120:
		await _frames(1)
	_expect(digger.carried == null and car.carried_by == null, "다시 퍼 올리면 차를 놓는다")
	_expect(car.altitude == 0.0 and car.collision_layer == Layers.VEHICLES, "놓은 차는 떨어져 땅에 서고 다시 부딪힌다")
	_expect(car.health < hp, "떨어진 차는 다친다 (%.0f → %.0f)" % [hp, car.health])
	# 사람을 찍는다
	var ped := Pedestrian.new()
	ped.setup(CIV, main.pedestrians.rng, City.sidewalk_loop(City.nearest_block(at)), 0, 0.0, 1)
	ped.position = digger.bucket_ground()
	main.pedestrians.add(ped)
	ped._set_state(Pedestrian.State.IDLE, 999.0)
	main.weapons.shoot()
	for f in int(60 * ExcavatorArm.DIG_TIME):
		await _frames(1)
	_expect(ped.is_dead() or ped.state == Pedestrian.State.KNOCKED, "버킷에 찍힌 사람은 넘어진다")
	main.queue_free()
	await _frames(2)


func _test_dozer() -> void:
	var main := _make_main(1)
	await _frames(2)
	var at := _open_road()
	var dozer := _vehicle(main, DOZER, at, 0.0)
	main.director.enter_immediately(dozer)
	await _frames(2)
	dozer.blade_up = true
	await _frames(60)
	_expect(dozer.joints.x > 0.25, "블레이드를 든다 (%.2f)" % dozer.joints.x)
	dozer.blade_up = false
	await _frames(60)
	_expect(dozer.joints.x < 0.02, "블레이드를 내린다 (%.2f)" % dozer.joints.x)
	var car := _vehicle(main, SEDAN, at + Vector2(0, -75), PI * 0.5)
	var start := car.global_position
	var hp := car.health
	Input.action_press("accelerate")
	for f in 60 * 3:
		await _frames(1)
		main.player.revive()
	Input.action_release("accelerate")
	_expect(car.health < hp * 0.8, "내린 블레이드에 밀린 차가 다친다 (%.0f → %.0f)" % [hp, car.health])
	_expect(start.y - car.global_position.y > 60.0, "불도저가 차를 밀어붙인다 (%.0f px)" % (start.y - car.global_position.y))
	main.queue_free()
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
