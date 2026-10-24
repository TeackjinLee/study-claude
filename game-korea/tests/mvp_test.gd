extends Node
## MVP 콘텐츠 검증 (docs/00 §6: NPC 12종 · 차량 10종 · 건물 8종 · 수배 ★4).
##  1. 콘텐츠 수: data/npc 12종↑, data/vehicles 10종↑, 건물 8종이 도시에 모두 서 있다.
##  2. 차를 빼앗으면 차종에 맞는 운전자가 내린다 (택시 기사·배달원·구급대원·버스 기사).
##  3. 구급차에 타고 있으면 체력이 찬다.
##  4. ★4: 특공대 차량이 와서 대원 넷이 내려 쏜다. ★4는 숨어도 안 내려간다.
##  5. 카센터: 경찰 눈 밖에서 들어오면 돈을 내고 별 둘이 떨어지고, 차가 고쳐지고 색이 바뀐다. 보는 앞에서는 안 된다.
##  6. 폭력배(구도심 건달파)가 구역을 돌고, 건달파와 척지면 주먹으로 덤빈다.
## 실행: godot --headless --fixed-fps 60 --path . res://tests/mvp_test.tscn

const TAXI: VehicleType = preload("res://data/vehicles/car_taxi.tres")
const BIKE: VehicleType = preload("res://data/vehicles/etc_bike.tres")
const AMBULANCE: VehicleType = preload("res://data/vehicles/sp_ambulance.tres")
const SEDAN: VehicleType = preload("res://data/vehicles/car_avela.tres")
const OLDTOWN: GangType = preload("res://data/gangs/oldtown.tres")

var _failures: Array[String] = []


func _ready() -> void:
	_test_counts()
	await _test_drivers()
	await _test_ambulance()
	await _test_swat()
	await _test_spray_shop()
	await _test_thugs()
	await _test_gang_punch()
	if _failures.is_empty():
		print("mvp_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _make_main(patrols := 0) -> Node2D:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = 0
	main.bus_count = 0
	main.police_patrols = patrols
	add_child(main)
	return main


func _free(main: Node2D) -> void:
	main.queue_free()
	await _frames(2)


func _test_counts() -> void:
	var npcs := _count("res://data/npc/")
	var cars := _count("res://data/vehicles/")
	_expect(npcs >= 12, "NPC 12종 이상 (%d)" % npcs)
	_expect(cars >= 10, "차량 10종 이상 (%d)" % cars)
	var city := City.new()
	city._build_layout()
	var used := {}
	for k in city.kinds + city.park_kinds:
		if k:
			used[k.id] = used.get(k.id, 0) + 1
	city.free()
	_expect(City.BUILDING_TYPES.size() >= 8, "건물 8종 이상 (%d)" % City.BUILDING_TYPES.size())
	for t in City.BUILDING_TYPES:
		_expect(used.has(t.id), "건물 %s(%s)가 도시에 있다" % [t.display_name, t.id])
	print("  NPC %d종, 차량 %d종, 건물 %d종 %s" % [npcs, cars, City.BUILDING_TYPES.size(), used])


func _count(dir: String) -> int:
	var n := 0
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tres"):
			n += 1
	return n


func _test_drivers() -> void:
	var main := _make_main()
	await _frames(2)
	for type: VehicleType in [TAXI, BIKE, AMBULANCE, preload("res://data/vehicles/bus_city.tres")]:
		var v := Vehicle.new()
		v.stats = type
		v.has_driver = true
		main.add_child(v)
		v.place(main.player.global_position + Vector2(-60, 0), 0.0)
		main.vehicles.append(v)
		var stolen := [null]
		main.director.vehicle_stolen.connect(func(_v, d): stolen[0] = d, CONNECT_ONE_SHOT)
		main.director.enter_immediately(v)
		var d: Pedestrian = stolen[0]
		_expect(d != null and d.npc == type.driver_npc, "%s를 빼앗으면 %s가 내린다 (%s)" % [type.display_name,
			type.driver_npc.display_name, d.npc.display_name if d else "없음"])
		main.director.exit_vehicle()
		await _frames(2)
	await _free(main)


func _test_ambulance() -> void:
	var main := _make_main()
	await _frames(2)
	var player: Player = main.player
	var v := Vehicle.new()
	v.stats = AMBULANCE
	main.add_child(v)
	v.place(player.global_position + Vector2(-60, 0), 0.0)
	main.vehicles.append(v)
	player.take_damage(50.0)
	main.director.enter_immediately(v)
	await _frames(120)
	_expect(player.health >= 50.0 + AMBULANCE.heal_rate * 1.8, "구급차에서 체력이 찬다 (%.0f)" % player.health)
	await _free(main)


func _test_swat() -> void:
	var main := _make_main()
	await _frames(2)
	var police: PoliceDispatcher = main.police
	var player: Player = main.player
	player.global_position = City.hq_door() + Vector2(0, -120)
	police.last_known = player.global_position
	for i in 4:
		police.wanted.report(WantedSystem.Crime.KILL_OFFICER)
	_expect(police.wanted.level == 4, "경찰을 여럿 죽이면 ★4 (%d)" % police.wanted.level)
	var swat_seen := false
	var shots := [0]
	main.combat.gunfire.connect(func(_p, by_player): if not by_player: shots[0] += 1)
	var swat_officers := 0
	for f in 60 * 60:
		await _frames(1)
		swat_seen = swat_seen or police.swat_count() > 0
		swat_officers = 0
		for o in police.officers:
			if o.npc == PoliceDispatcher.SWAT_NPC:
				swat_officers += 1
		if swat_officers >= PoliceDispatcher.SWAT_CREW and shots[0] > 0:
			break
		player.revive()   # 체포·사망 없이 끝까지 지켜본다
		police._arrest = 0.0
		if OS.get_environment("MVP_DEBUG") != "" and f % 120 == 0:
			for c in police.cars:
				print("  t=%d %s %s spd=%.0f d=%.0f driver=%s direct=%s" % [f / 60, c.stats.id, c.global_position.round(), c.speed(),
					c.global_position.distance_to(player.global_position), c.has_driver, c.pursuit.direct if c.pursuit else null])
	_expect(swat_seen, "★4면 특공대 차량이 온다")
	_expect(swat_officers >= PoliceDispatcher.SWAT_CREW, "특공대 넷이 내린다 (%d)" % swat_officers)
	_expect(shots[0] > 0, "특공대가 쏜다 (%d발)" % shots[0])
	await _free(main)


func _test_spray_shop() -> void:
	var main := _make_main()
	await _frames(2)
	var police: PoliceDispatcher = main.police
	var shop: SprayShop = main.spray_shop
	var car: Vehicle = main.start_vehicle
	var notices := []
	shop.notice.connect(func(t): notices.append(t))
	main.director.enter_immediately(car)
	car.take_damage(60.0, false)
	var color := car.paint
	for i in 4:
		police.wanted.report(WantedSystem.Crime.KILL_OFFICER)
	await _frames(2)     # 경찰차는 아직 멀리 있다 — 아무도 못 본다
	var money: int = main.wallet.money
	car.global_position = City.spray_bay()
	car.motor.velocity = Vector2.ZERO
	await _frames(3)
	_expect(police.wanted.level == 2, "도색하면 ★4 → ★2 (%d, %s)" % [police.wanted.level, notices])
	_expect(main.wallet.money == money - SprayShop.PRICE, "도색비 %d원" % SprayShop.PRICE)
	_expect(car.health == car.stats.durability and car.paint != color, "차가 고쳐지고 색이 바뀐다")

	# 경찰이 보는 앞에서는 안 된다
	car.global_position = City.spray_bay() + Vector2(0, 300)
	await _frames(3)
	var cop := police._spawn_officer(City.spray_bay() + Vector2(60, 0), null, PoliceOfficer.Duty.GUARD)
	cop.set_physics_process(false)
	await _frames(3)
	car.global_position = City.spray_bay()
	await _frames(3)
	_expect(police.wanted.level == 2 and notices.back().contains("경찰"), "경찰이 보고 있으면 도색하지 않는다 (%s)" % notices.back())

	# ★5부터는 고치고 칠해 주지만 별은 못 뗀다
	cop.global_position = City.spray_bay() + Vector2(6000, 0)    # 경찰을 멀리 (목록에서 빼면 경찰 코드가 지워진 사람을 만진다)
	car.global_position = City.spray_bay() + Vector2(0, 300)
	await _frames(3)
	police.wanted.raise_to(WantedSystem.LOCK_LEVEL)
	car.take_damage(30.0, false)
	car.global_position = City.spray_bay()
	await _frames(3)
	_expect(police.wanted.level == 5 and car.health == car.stats.durability and notices.back().contains("★5"),
		"★5에서 도색하면 고쳐지지만 별은 그대로 (%d, %s)" % [police.wanted.level, notices.back()])
	await _free(main)


func _test_thugs() -> void:
	var main := _make_main()
	await _frames(2)
	var gangs: GangManager = main.gangs
	var player: Player = main.player
	var thugs: Array[GangMember] = []
	for m in gangs.members:
		if m.gang == OLDTOWN and m.resident:
			thugs.append(m)
	_expect(thugs.size() == OLDTOWN.member_count and thugs[0].npc.id == &"THUG", "폭력배 %d명이 구역을 돈다 (%d)" % [OLDTOWN.member_count, thugs.size()])
	main.respect.set_value(OLDTOWN.id, OLDTOWN.hostile_respect)
	var t := thugs[0]
	t.global_position = player.global_position + Vector2(0, -150)
	for f in 300:
		await _frames(1)
		if player.health < Player.MAX_HEALTH:
			break
	_expect(player.health < Player.MAX_HEALTH, "건달파와 척지면 폭력배가 달려와 주먹질한다 (체력 %.0f)" % player.health)
	_expect(t.global_position.distance_to(player.global_position) < 40.0, "바짝 붙어서 때린다")
	await _free(main)


## 총 든 보스도 걸어서 바짝 붙은 주인공에게는 주먹 — 주먹 그림(스트레이트)을 넘기고 타격 장에 친다
func _test_gang_punch() -> void:
	var boss: NpcType = load("res://data/npc/boss.tres")
	_expect(not PersonRig.npc_punch(boss).is_empty(), "보스는 자기 주먹 그림이 있다")
	var main := _make_main()
	await _frames(2)
	var player: Player = main.player
	var m: GangMember = main.gangs.spawn_guard(boss, player.global_position + Vector2(0, -20))
	var punched := false
	var hit_at := -1
	for f in 240:
		await _frames(1)
		punched = punched or m.has_meta(&"punch_state")
		if player.health < Player.MAX_HEALTH:
			hit_at = f
			break
	_expect(punched, "보스가 주먹 그림을 넘긴다")
	_expect(hit_at >= 0, "바짝 붙은 주인공을 주먹으로 친다 (체력 %.0f)" % player.health)
	await _free(main)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
