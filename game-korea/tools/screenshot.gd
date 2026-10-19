extends Node
## 게임을 잠깐 굴려 화면을 .screenshots/에 저장한다 (창이 잠깐 뜬다).
## 실행: godot --path . res://tools/screenshot.tscn

const OUT_DIR := "res://.screenshots/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.save_prefix = "user://screenshot_save_"   # 실제 세이브는 건드리지 않는다
	for slot in range(1, SaveGame.SLOTS + 1):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.slot_path(main.save_prefix, slot)))
	var heli_only := "--only=heli" in OS.get_cmdline_user_args()
	var army_only := "--only=army" in OS.get_cmdline_user_args()
	var heavy_only := "--only=heavy" in OS.get_cmdline_user_args()
	if heli_only or army_only or heavy_only:
		main.chapter = 4   # 헬기·군용 차량은 4장 부두에 있다
	add_child(main)
	if heli_only:
		await _frames(30)
		await _heli_ride_shots(main)
		get_tree().quit()
		return
	if "--only=iso" in OS.get_cmdline_user_args():
		await _frames(30)
		await _iso_shots(main)
		get_tree().quit()
		return
	if heavy_only:
		await _frames(30)
		await _heavy_shots(main)
		get_tree().quit()
		return
	if army_only:
		await _frames(30)
		await _army_shots(main)
		get_tree().quit()
		return
	if "--only=air" in OS.get_cmdline_user_args():
		await _frames(30)
		await _air_shots(main)
		get_tree().quit()
		return
	if "--only=m6" in OS.get_cmdline_user_args():
		await _frames(30)
		await _m6_shots(main)
		get_tree().quit()
		return
	# 보행자 몇 명을 출발점 인도로 불러와 화면에 담는다
	var loop := City.sidewalk_loop(Vector2i(3, 3))
	for i in 5:
		var p: Pedestrian = main.pedestrians.peds[i]
		p.global_position = loop[0] + Vector2(0, 120 + i * 45)
		p.resume_walking()
	await _frames(40)
	await _save("m1_foot")

	# 교통이 돌아가는 모습: 출발점 근처 교차로를 넓게
	await _frames(600)
	var cam: ChaseCamera = main.camera
	cam.target = null
	cam.global_position = LaneGraph.center(Vector2i(3, 3))
	cam.zoom = Vector2(0.55, 0.55)
	await _frames(2)
	await _save("m2_overview")
	cam.global_position = LaneGraph.center(Vector2i(3, 3)) + Vector2(0, 120)
	cam.zoom = Vector2(1.1, 1.1)
	await _frames(2)
	await _save("m2_intersection")
	cam.target = main.player
	cam.snap()
	main.reset()
	await _frames(5)

	main.director.request_enter_exit()
	await _frames(20)
	Input.action_press("accelerate")
	await _frames(70)
	Input.action_press("steer_right")
	Input.action_press("handbrake")
	await _frames(30)
	await _save("m1_drift")
	for a in ["accelerate", "steer_right", "handbrake"]:
		Input.action_release(a)
	await _frames(30)
	await _police_shots(main)
	await _combat_shots(main)
	await _mission_shots(main)
	await _mvp_shots(main)
	await _m6_shots(main)
	get_tree().quit()


## M3: 수배 ★2로 차에 앉아 있으면 경찰차가 와서 세우고, 경찰이 내려 체포한다
func _police_shots(main: Node2D) -> void:
	var police: PoliceDispatcher = main.police
	main.reset()
	main.director.enter_immediately(main.start_vehicle)
	police.last_known = main.start_vehicle.global_position
	police.wanted.report(WantedSystem.Crime.HIT_OFFICER)
	var chase_saved := false
	var officers_saved := false
	var busted := [false]
	police.busted.connect(func(_f): busted[0] = true, CONNECT_ONE_SHOT)
	for f in 60 * 40:
		await _frames(1)
		if not chase_saved:
			for c in police.cars:
				if c.pursuit and c.global_position.distance_to(main.start_vehicle.global_position) < 260.0:
					chase_saved = true
					await _save("m3_chase")
					break
		if not officers_saved and police.officers.size() >= 2:
			officers_saved = true
			await _frames(20)
			await _save("m3_officers")
		if busted[0]:
			break
	await _frames(30)
	await _save("m3_busted")
	await _frames(int(main.BUST_DELAY * 60))
	await _save("m3_station")

	# 도로 봉쇄: 가로 도로 3번을 동쪽으로 달린다고 치고 세운 뒤 카메라를 그쪽으로
	var cam: ChaseCamera = main.camera
	cam.target = null
	cam.global_position = Vector2(City.road_center(1), City.road_center(3))
	await _frames(1)
	if police.place_roadblock(cam.global_position, Vector2(600, 0)):
		var car: Vehicle = police.roadblocks[0].cars[0]
		cam.global_position = car.global_position + Vector2(-150, 0)
		cam.zoom = Vector2(1.1, 1.1)
		await _frames(10)
		await _save("m3_roadblock")


## M4: SMG로 주차된 차를 쏘고, 불붙은 차가 터지며 옆 차들이 연쇄로 터진다. 그리고 차 안에서 죽어 병원으로.
func _combat_shots(main: Node2D) -> void:
	var cam: ChaseCamera = main.camera
	main.police.reset()
	cam.target = main.player
	cam.zoom = Vector2.ONE
	main.reset()
	await _frames(5)
	var player: Player = main.player
	player.arsenal.give(load("res://data/weapons/smg.tres"), 30)
	# 출발 차 위쪽 갓길에 세단 셋을 줄지어 세운다
	var row: Array[Vehicle] = []
	for i in 3:
		var v := Vehicle.new()
		v.stats = main.VEHICLE_TYPES[i % 2]
		main.add_child(v)
		v.place(main.start_vehicle.global_position + Vector2(0, -80 - i * 72), 0.0)
		main.vehicles.append(v)
		row.append(v)
	var car := row[1]
	player.global_position = car.global_position + Vector2(-90, 0)   # 차도 쪽에서 오른쪽을 보고 쏜다
	player.facing = PI * 0.5
	cam.snap()
	await _frames(5)
	for f in 14:
		main.weapons.shoot()
		await _frames(1)
	await _save("m4_shoot")
	for f in 120:
		main.weapons.shoot()
		await _frames(1)
		if car.burning >= 0.0:
			break
	# 건너편 인도 위쪽으로 피한다 (연쇄 폭발은 아래쪽 주차 차들로 번진다)
	player.global_position = row[2].global_position + Vector2(-185, -200)
	await _frames(30)
	await _save("m4_burning")
	while not car.wrecked:
		await _frames(1)
	await _frames(8)
	await _save("m4_explosion")
	await _frames(70)
	await _save("m4_chain")

	# 불붙은 차에 탄 채로 있다가 죽는다 → 병원
	var other: Vehicle = main.vehicles[3]
	main.director.enter_immediately(other)
	other.take_damage(1000.0, false)
	await _frames(int(DamageModel.BURN_TIME * 60) + 20)
	await _save("m4_dead")
	await _frames(int(main.BUST_DELAY * 60) + 10)
	await _save("m4_hospital")


## M5: 본부 앞 공중전화 · 미션 시작 · 화면 밖 목표 화살표 · 경호원과 총격 · 미션 성공 · 은신처 저장
func _mission_shots(main: Node2D) -> void:
	var cam: ChaseCamera = main.camera
	var missions: MissionSystem = main.missions
	var player: Player = main.player
	cam.target = player
	main.reset()
	player.global_position = City.hq_door() + Vector2(0, -30)
	player.facing = PI
	cam.snap()
	await _frames(30)
	await _save("m5_phones")

	# 첫 심부름은 끝낸 셈 치고, 쉬운 전화에서 '포르타 배달'을 받는다
	missions.completed[&"gangnam_01"] = true
	player.global_position = missions.phones[0].pos
	await _frames(20)
	await _save("m5_mission_start")
	await _frames(int(3.5 * 60))
	main.director.enter_immediately(missions.vehicle)
	cam.snap()
	await _frames(40)
	await _save("m5_deliver_arrow")
	var dock := City.warehouse_dock()
	missions.vehicle.global_position = dock + Vector2(-260, 0)
	missions.vehicle.motor.heading = PI * 0.5
	cam.snap()
	await _frames(20)
	missions.vehicle.global_position = dock
	missions.vehicle.motor.velocity = Vector2.ZERO
	await _frames(30)
	await _save("m5_passed")
	main.director.exit_vehicle()
	await _frames(int(3.0 * 60))

	# 보통 미션 '빚 독촉': 건달파 셋이 총을 들고 맞선다
	main.respect.set_value(&"gangnam", 20)
	missions.start(missions.by_id(&"gangnam_06"))
	await _frames(int(3.5 * 60))
	var guard: GangMember = missions.targets[1]
	player.global_position = guard.global_position + Vector2(0, -190)   # 길 건너 차도에서
	player.arsenal.give(load("res://data/weapons/smg.tres"), 30)
	player.facing = PI
	cam.snap()
	for f in 100:
		if f > 80:
			main.weapons.shoot()
		await _frames(1)
	await _save("m5_gang_fight")
	missions.fail("테스트")
	player.revive()
	main.police.reset()
	main.gangs.calm()
	await _frames(int(2.5 * 60))

	player.global_position = City.hideout_door() + Vector2(0, 80)
	cam.snap()
	await _frames(5)
	player.global_position = City.hideout_door()
	await _frames(5)
	await _save("m5_save_menu")
	main.save_menu.choose(1)
	await _frames(20)
	await _save("m5_hideout_save")
	# 게임을 켤 때의 이어 하기 메뉴
	main.save_menu.open_load(main.slot_lines())
	await _frames(3)
	await _save("m5_load_menu")
	main.save_menu.choose(0)


## MVP 콘텐츠: 차종 줄 세우기 · 건물 종류 · ★4 특공대 · 카센터 도색
func _mvp_shots(main: Node2D) -> void:
	var cam: ChaseCamera = main.camera
	var player: Player = main.player
	main.missions.fail("테스트")
	main.police.reset()
	await _frames(int(3.0 * 60))
	# 드리프트 연습장에 모든 차종을 세운다
	var lot := City.block_rect(City.PLAZA.x, City.PLAZA.y).grow(-City.SIDEWALK)
	var k := 0
	for file in DirAccess.get_files_at("res://data/vehicles/"):
		var v := Vehicle.new()
		v.stats = load("res://data/vehicles/" + file)
		v.has_driver = k % 3 == 0
		main.add_child(v)
		v.place(lot.position + Vector2(50 + (k % 7) * 70, 110 + (k / 7) * 150), 0.0)
		main.vehicles.append(v)
		k += 1
	cam.target = null
	cam.global_position = lot.position + Vector2(260, 190)
	cam.zoom = Vector2(1.3, 1.3)
	await _frames(5)
	await _save("mvp_vehicles")

	# 건물 종류: 위에서 넓게
	cam.global_position = City.block_rect(3, 1).position + Vector2(0, 100)
	cam.zoom = Vector2(0.42, 0.42)
	await _frames(5)
	await _save("mvp_buildings")
	cam.global_position = City.block_rect(0, 3).position + Vector2(300, 300)
	cam.zoom = Vector2(0.6, 0.6)
	await _frames(5)
	await _save("mvp_buildings2")

	# ★4: 특공대가 내린다 (체포는 막고 지켜본다)
	cam.target = player
	cam.zoom = Vector2.ONE
	main.reset()
	player.global_position = City.sidewalk_loop(Vector2i(4, 1))[3] + Vector2(0, -150)
	cam.snap()
	var police: PoliceDispatcher = main.police
	police.last_known = player.global_position
	for i in 4:
		police.wanted.report(WantedSystem.Crime.KILL_OFFICER)
	player.died.disconnect(main._on_died)   # 촬영 동안은 죽거나 잡히지 않는다
	police.busted.disconnect(main._on_busted)
	for f in 60 * 40:
		await _frames(1)
		player.health = Player.MAX_HEALTH
		police._arrest = 0.0
		police._bust_pending = false
		var n := 0
		for o in police.officers:
			if o.npc == PoliceDispatcher.SWAT_NPC:
				n += 1
		if n >= PoliceDispatcher.SWAT_CREW:
			await _frames(8)
			break
	await _save("mvp_swat")
	player.died.connect(main._on_died)
	police.busted.connect(main._on_busted)
	police._bust_pending = false
	player.revive()
	player.input_enabled = true

	# 카센터: 경찰을 물리고(★4 그대로) 정비 칸에 들어간다
	police.reset()
	for i in 4:
		police.wanted.report(WantedSystem.Crime.KILL_OFFICER)
	var car := Vehicle.new()
	car.stats = main.VEHICLE_TYPES[3]
	main.add_child(car)
	main.vehicles.append(car)
	main.director.enter_immediately(car)
	car.take_damage(80.0, false)
	car.place(City.spray_bay() + Vector2(0, 160), 0.0)
	cam.snap()
	await _frames(20)
	await _save("mvp_spray_before")
	car.global_position = City.spray_bay()
	car.motor.velocity = Vector2.ZERO
	await _frames(30)
	await _save("mvp_spray_after")


## M6: 구역 7개·한강·다리. 1장에는 다리가 통제되어 있고, 모든 장을 열면 구역마다 모습이 다르다
func _m6_shots(main: Node2D) -> void:
	var cam: ChaseCamera = main.camera
	cam.target = null
	main.set_chapter(1)
	cam.zoom = Vector2(0.4, 0.4)
	cam.global_position = LaneGraph.center(Vector2i(2, 0)) + Vector2(0, -500)
	await _frames(3)
	await _save("m6_bridge_locked")
	main.set_chapter(CityMap.LAST_CHAPTER)
	await _frames(3)
	await _save("m6_bridge_open")
	cam.zoom = Vector2(0.32, 0.32)
	for d in CityMap.DISTRICTS:
		var a := City.block_rect(d.blocks.position.x, d.blocks.position.y).position
		var b := City.block_rect(d.blocks.end.x - 1, d.blocks.end.y - 1).end
		cam.global_position = (a + b) * 0.5
		await _frames(3)
		await _save("m6_%s" % d.id)
	cam.zoom = Vector2(0.55, 0.55)
	cam.global_position = City.block_rect(1, -7).get_center()
	await _frames(3)
	await _save("m6_jongno_close")
	cam.global_position = City.block_rect(-3, 2).get_center()
	await _frames(3)
	await _save("m6_industrial_close")
	cam.global_position = City.block_rect(-2, -5).get_center()
	await _frames(3)
	await _save("m6_riverside_close")
	main.set_chapter(1)
	cam.target = main.player
	cam.zoom = Vector2.ONE
	cam.snap()
	await _m6_play_shots(main)


## M6 게임 장면: 구역 이름표, 비 오는 낮, 화재와 소방차, ★5 헬기 탐조등, 택시 부업
func _m6_play_shots(main: Node2D) -> void:
	var cam: ChaseCamera = main.camera
	var player: Player = main.player
	main.player.died.disconnect(main._on_died)
	main.police.busted.disconnect(main._on_busted)
	main.set_chapter(2)
	main.reset()
	await _frames(5)
	# 종로로 들어서면 구역 이름
	player.global_position = City.block_rect(1, -7).position + Vector2(-14, 300)
	cam.snap()
	await _frames(20)
	await _save("m6_district_name")
	# 비 오는 낮
	main.sky.paused_clock = true
	main.sky.set_hour(13.0)
	main.sky.set_raining(true)
	main.sky.rain = 1.0
	await _frames(10)
	await _save("m6_rain_day")
	main.sky.set_raining(false)
	main.sky.rain = 0.0
	main.sky.set_hour(21.0)
	# 화염병 불 → 소방차
	player.global_position = City.start_position()
	cam.snap()
	var spot := LaneGraph.center(Vector2i(3, 2)) + Vector2(0, 260)
	for f in 60 * 25:
		if f % 60 == 0:
			main.fires.start(spot, 50.0, false, 6.0)
		await _frames(1)
		var t: Vehicle = main.fires.truck
		if t and is_instance_valid(t) and t.global_position.distance_to(spot) < Fires.SPRAY_RANGE:
			cam.target = null
			cam.global_position = (spot + t.global_position) * 0.5
			await _frames(30)
			break
	await _save("m6_fire_truck")
	cam.target = player
	# ★5 헬기 탐조등
	player.global_position = City.block_rect(1, 1).get_center()
	cam.snap()
	main.police.last_known = player.global_position
	main.police.wanted.raise_to(5)
	for f in 60 * 20:
		await _frames(1)
		main.police._arrest = 0.0
		player.revive()
		if not main.police.helis.is_empty() and main.police.helis[0].lit(player.global_position) \
				and main.police.helis[0].global_position.distance_to(player.global_position) < 260.0:
			break
	await _save("m6_heli")
	main.police.reset()
	await _frames(5)
	# 택시 부업
	var taxi := Vehicle.new()
	taxi.stats = load("res://data/vehicles/car_taxi.tres")
	main.add_child(taxi)
	taxi.place(City.curb_vertical(3, 3, 0.3), 0.0)
	main.vehicles.append(taxi)
	main.director.enter_immediately(taxi)
	await _frames(5)
	await _save("m6_taxi_prompt")
	main.jobs.start(main.jobs.available())
	taxi.global_position = main.jobs.goal + Vector2(0, 160)
	cam.snap()
	await _frames(30)
	await _save("m6_taxi_job")
	main.jobs.end("촬영")
	main.director.exit_vehicle()
	main.set_chapter(1)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + name + ".png"))
	print("saved ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## 군용 차량 (`-- --only=army`): 부두에 선 자주포·전술차량 → 자주포 포탑 조준(조준점) → 포격(포구 불꽃·포탄) → 차를 깔고 올라탄 모습 → 전술차량 기관총
func _army_shots(main: Node2D) -> void:
	var cam: ChaseCamera = main.camera
	var player: Player = main.player
	main.player.died.disconnect(main._on_died)
	var spg: Vehicle = null
	var jeep: Vehicle = null
	for v: Vehicle in main.vehicles:
		if v.stats.id == &"ARMY_SPG":
			spg = v
		elif v.stats.id == &"ARMY_JEEP":
			jeep = v
	if spg == null:
		print("자주포가 없다")
		return
	cam.target = null
	cam.global_position = spg.global_position + Vector2(-60, 60)
	await _frames(20)
	await _save("army_dock")
	main.director.enter_immediately(spg)
	main.weapons.set_process_input(false)   # 창 모드에서 마우스 위치가 조준을 덮어쓰지 않게
	main.weapons.mouse_aim = false
	cam.target = spg
	spg.turret_goal = -PI * 0.6
	spg.aim_range = 700.0
	for f in 150:
		await _frames(1)
		player.revive()
	await _save("army_aim")
	main.weapons.shoot()
	await _frames(8)
	await _save("army_fire")
	for f in 120:
		await _frames(1)
		player.revive()
	await _save("army_impact")
	# 탁 트인 드리프트 연습장에서 차를 깔고 넘는다
	var road := City.block_rect(City.PLAZA.x, City.PLAZA.y).get_center() + Vector2(0, 120)
	main.director.exit_vehicle()
	spg.place(road, 0.0)
	spg.turret_goal = 0.0
	var car := Vehicle.new()
	car.stats = load("res://data/vehicles/car_sonato.tres")
	main.add_child(car)
	car.place(road + Vector2(0, -120), PI * 0.5)
	main.vehicles.append(car)
	main.director.enter_immediately(spg)
	cam.snap()
	Input.action_press("accelerate")
	for f in 60 * 4:
		await _frames(1)
		player.revive()
		if spg.climb > 8.0 and spg.global_position.y < car.global_position.y + 30.0:
			break
	Input.action_release("accelerate")
	await _save("army_crush")
	for f in 40:
		await _frames(1)
		player.revive()
	await _save("army_crush_after")
	if jeep:
		main.director.exit_vehicle()
		jeep.place(road + Vector2(-160, -60), PI * 0.25)
		main.director.enter_immediately(jeep)
		jeep.turret_goal = -PI * 0.5
		cam.snap()
		for f in 60:
			await _frames(1)
			player.revive()
		for i in 6:
			main.weapons.shoot()
			await _frames(2)
		await _save("army_jeep")


## 중장비 (`-- --only=heavy`, 4장): 공단 도로 공사 현장 → 굴삭기가 차를 찍어 든다 → 든 채 상부를 돌린다 → 놓는다 → 불도저가 블레이드로 민다
func _heavy_shots(main: Node2D) -> void:
	var cam: ChaseCamera = main.camera
	var player: Player = main.player
	main.player.died.disconnect(main._on_died)
	var digger: Vehicle = null
	var dozer: Vehicle = null
	for v: Vehicle in main.vehicles:
		if v.stats.id == &"HEAVY_EXCAVATOR":
			digger = v
		elif v.stats.id == &"HEAVY_DOZER":
			dozer = v
	if digger == null or dozer == null:
		print("중장비가 없다")
		return
	cam.target = null
	cam.global_position = (digger.global_position + dozer.global_position) * 0.5
	await _frames(20)
	await _save("heavy_site")
	# 탁 트인 곳에서 작동 (공사 현장 옆 도로는 건물에 가린다)
	var lot := City.block_rect(City.PLAZA.x, City.PLAZA.y).get_center()
	digger.place(lot, 0.0)
	main.director.enter_immediately(digger)
	main.weapons.set_process_input(false)   # 창 모드에서 마우스 위치가 조준을 덮어쓰지 않게
	main.weapons.mouse_aim = false
	cam.target = digger
	cam.snap()
	digger.aim_range = 72.0
	for f in 50:
		await _frames(1)
	var car := Vehicle.new()
	car.stats = load("res://data/vehicles/car_rumi.tres")
	main.add_child(car)
	car.place(digger.bucket_ground(), PI * 0.5)
	main.vehicles.append(car)
	await _frames(5)
	await _save("heavy_reach")
	main.weapons.shoot()
	await _frames(int(60 * ExcavatorArm.DIG_TIME * 0.5))
	await _save("heavy_dig")
	for f in 40:
		await _frames(1)
	await _save("heavy_lift")
	digger.turret_goal = PI * 0.6
	digger.aim_range = 84.0
	for f in 110:
		await _frames(1)
		player.revive()
	await _save("heavy_carry")
	main.weapons.shoot()
	for f in 70:
		await _frames(1)
	await _save("heavy_drop")
	main.director.exit_vehicle()
	dozer.place(lot + Vector2(-260, 160), 0.0)
	var victim := Vehicle.new()
	victim.stats = load("res://data/vehicles/car_avela.tres")
	main.add_child(victim)
	victim.place(lot + Vector2(-260, 85), PI * 0.5)
	main.vehicles.append(victim)
	main.director.enter_immediately(dozer)
	cam.target = dozer
	cam.snap()
	Input.action_press("accelerate")
	for f in 100:
		await _frames(1)
		player.revive()
	Input.action_release("accelerate")
	await _save("heavy_dozer")


## NPC 헬기 (입체 모형): ★5 경찰 헬기 탐조등 → ★6 군 기동헬기 → 큰불에 물을 쏟는 119 구조헬기 (`-- --only=air`)
func _air_shots(main: Node2D) -> void:
	var cam: ChaseCamera = main.camera
	var player: Player = main.player
	player.global_position = City.block_rect(1, 1).get_center()
	cam.snap()
	main.police.last_known = player.global_position
	main.police.wanted.raise_to(5)
	for f in 60 * 20:
		await _frames(1)
		main.police._arrest = 0.0
		player.revive()
		if not main.police.helis.is_empty() and main.police.helis[0].lit(player.global_position) \
				and main.police.helis[0].global_position.distance_to(player.global_position) < 220.0:
			break
	await _save("air_police")
	main.police.wanted.raise_to(6)
	for f in 60 * 25:
		await _frames(1)
		main.police._arrest = 0.0
		player.revive()
		var army: Array = main.police.helis.filter(func(h: PoliceHeli): return h.stats == PoliceDispatcher.ARMY_HELI_TYPE)
		if not army.is_empty() and army[0].global_position.distance_to(player.global_position) < 220.0:
			break
	await _save("air_army")
	main.police.reset()
	await _frames(60)
	var spot := player.global_position + Vector2(0, 200)
	for i in Fires.HELI_FIRES:
		main.fires.start(spot + Vector2(i * 45.0 - 70.0, 0), 45.0, false, 30.0)
	for f in 60 * 25:
		await _frames(1)
		player.revive()
		var h: PoliceHeli = main.fires.heli
		if h and is_instance_valid(h) and h.water:
			cam.target = null
			cam.global_position = h.global_position + IsoView.lift(h.altitude() * 0.5)
			await _frames(40)
			break
	await _save("air_119")
	cam.target = player


## 4장 부두 헬기: 헬기장에 선 모습 → 떠올라 건물 위를 나는 모습(낮) → 위에서 보기
func _heli_ride_shots(main: Node2D) -> void:
	var heli: Vehicle = null
	for v: Vehicle in main.vehicles:
		if v.stats.flies:
			heli = v
	var player: Player = main.player
	var cam: ChaseCamera = main.camera
	main.sky.paused_clock = true
	main.sky.set_hour(14.0)
	player.global_position = heli.door_position(false) + Vector2(-30, 10)
	cam.snap()
	await _frames(10)
	await _save("heli_parked")
	main.director.enter_immediately(heli)
	Input.action_press("accelerate")
	await _frames(40)
	await _save("heli_takeoff")
	await _frames(200)
	Input.action_press("steer_right")
	await _frames(30)
	Input.action_release("steer_right")
	await _frames(30)
	await _save("heli_flying")
	Input.action_press("steer_left")
	await _frames(45)
	await _save("heli_bank_left")
	Input.action_release("steer_left")
	Input.action_press("steer_right")
	await _frames(80)
	await _save("heli_bank_right")
	Input.action_release("steer_right")
	await _frames(70)
	Input.action_release("accelerate")
	main.set_iso(false)
	await _frames(5)
	await _save("heli_topdown")
	main.set_iso(true)


## 2.5D 화면: 도보·교차로·전경·주행·낮·헬기, 그리고 F9로 바꾼 위에서 보기 비교
## 2.5D 다리: 강 위로 뜬 상판·경사로·교각, 그 위의 차와 사람
func _bridge_shots(main: Node2D) -> void:
	var cam: ChaseCamera = main.camera
	var cx := City.road_center(2)
	var span: Vector2 = CityMap.bridge_spans(2)[-1]
	var placed: Array[Vehicle] = []
	var ids := ["bus_city", "car_sonato", "trk_bongo", "car_taxi", "police_patrol"]
	for i in ids.size():
		var v := Vehicle.new()
		v.stats = load("res://data/vehicles/%s.tres" % ids[i])
		main.add_child(v)
		var north := i % 2 == 0
		v.place(Vector2(cx + (48.0 if north else -48.0), span.y - 60.0 - i * 150.0), 0.0 if north else PI)
		placed.append(v)
	var ped: Pedestrian = main.pedestrians.peds[7]
	ped.global_position = Vector2(cx + 80.0, span.y - 420.0)
	cam.target = null
	cam.global_position = Vector2(cx, span.y - 380.0)
	cam.zoom = Vector2(1.0, 1.0)
	await _frames(5)
	await _save("iso_bridge")
	cam.global_position = Vector2(cx, (span.x + span.y) * 0.5)
	cam.zoom = Vector2(0.4, 0.4)
	await _frames(3)
	await _save("iso_bridge_wide")
	for v in placed:
		v.queue_free()


func _iso_shots(main: Node2D) -> void:
	var cam: ChaseCamera = main.camera
	var player: Player = main.player
	main.player.died.disconnect(main._on_died)
	main.police.busted.disconnect(main._on_busted)
	# 28종 차량 입체 모형 (docs/12): 드리프트 연습장에 네 방향으로 세워 둔다
	var plaza := City.block_rect(1, 1).grow(-80)
	var ids: Array = []
	for f in DirAccess.get_files_at("res://data/vehicles"):
		if f.ends_with(".tres"):
			ids.append(f.get_basename())
	var shown: Array[Vehicle] = []
	for i in ids.size():
		var v := Vehicle.new()
		v.stats = load("res://data/vehicles/%s.tres" % ids[i])
		main.add_child(v)
		v.place(plaza.position + Vector2(40 + (i % 7) * 66, 40 + (i / 7) * 110), [0.0, PI * 0.5, PI, PI * 1.5][i % 4])
		shown.append(v)
	cam.target = null
	cam.global_position = plaza.position + Vector2(240, 210)
	cam.zoom = Vector2(1.3, 1.3)
	await _frames(5)
	await _save("iso_vehicles")
	for v in shown:
		v.queue_free()
	await _bridge_shots(main)
	cam.target = player
	cam.snap()
	var loop := City.sidewalk_loop(Vector2i(3, 3))
	for i in 5:
		var p: Pedestrian = main.pedestrians.peds[i]
		p.global_position = loop[0] + Vector2(0, 120 + i * 45)
		p.resume_walking()
	await _frames(40)
	await _save("iso_foot")
	await _frames(400)
	cam.target = null
	cam.global_position = LaneGraph.center(Vector2i(3, 3)) + Vector2(60, 60)
	cam.zoom = Vector2(0.8, 0.8)
	await _frames(2)
	await _save("iso_intersection")
	cam.zoom = Vector2(0.45, 0.45)
	await _frames(2)
	await _save("iso_overview")
	# 기능 건물: 경찰서·강남 조직 사옥, 정비소·병원
	cam.global_position = (City.block_rect(4, 2).get_center() + City.block_rect(3, 3).get_center()) * 0.5
	cam.zoom = Vector2(0.6, 0.6)
	await _frames(2)
	await _save("iso_special_police_hq")
	cam.global_position = (City.block_rect(1, 3).get_center() + City.block_rect(1, 4).get_center()) * 0.5
	await _frames(2)
	await _save("iso_special_hospital")
	main.set_iso(false)
	await _frames(2)
	await _save("iso_off_topdown")
	main.set_iso(true)
	cam.target = player
	cam.snap()
	main.reset()
	await _frames(5)
	main.director.request_enter_exit()
	await _frames(20)
	Input.action_press("accelerate")
	await _frames(90)
	Input.action_press("steer_right")
	await _frames(25)
	await _save("iso_drive")
	for a in ["accelerate", "steer_right"]:
		Input.action_release(a)
	await _frames(30)
	main.sky.paused_clock = true
	main.sky.set_hour(13.0)
	await _frames(5)
	await _save("iso_day")
	main.sky.set_hour(18.7)   # 해 질 녘: 창에 불이 하나둘 켜지는 중
	await _frames(5)
	await _save("iso_dusk")
	main.sky.set_hour(21.0)
	if main.director.current_vehicle:
		main.director.request_enter_exit()
		await _frames(30)
	player.global_position = City.block_rect(1, 1).get_center() + Vector2(0, 300)
	cam.snap()
	main.police.last_known = player.global_position
	main.police.wanted.raise_to(5)
	for f in 60 * 20:
		await _frames(1)
		main.police._arrest = 0.0
		player.revive()
		if not main.police.helis.is_empty() and main.police.helis[0].global_position.distance_to(player.global_position) < 300.0:
			break
	await _frames(20)
	await _save("iso_heli")
	main.police.reset()
