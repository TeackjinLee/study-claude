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
	if "--only=hud" in OS.get_cmdline_user_args():
		await _frames(30)
		await _hud_shots(main)
		get_tree().quit()
		return
	if "--only=ems" in OS.get_cmdline_user_args():
		await _frames(30)
		await _ems_shots(main)
		get_tree().quit()
		return
	if "--only=air" in OS.get_cmdline_user_args():
		await _frames(30)
		await _air_shots(main)
		get_tree().quit()
		return
	if "--only=overpass" in OS.get_cmdline_user_args():
		await _frames(30)
		await _overpass_shots(main)
		get_tree().quit()
		return
	if "--only=river" in OS.get_cmdline_user_args():
		await _frames(30)
		await _river_shots(main)
		get_tree().quit()
		return
	if "--only=rifle" in OS.get_cmdline_user_args() or "--only=pistol" in OS.get_cmdline_user_args():
		await _frames(30)
		await _rifle_shots(main, "pistol" if "--only=pistol" in OS.get_cmdline_user_args() else "rifle")
		get_tree().quit()
		return
	if "--only=rocket" in OS.get_cmdline_user_args():
		await _frames(30)
		await _rocket_shots(main)
		get_tree().quit()
		return
	if "--only=heli_aim" in OS.get_cmdline_user_args():
		await _frames(30)
		await _heli_aim_shots(main)
		get_tree().quit()
		return
	if "--only=player_jump" in OS.get_cmdline_user_args():
		await _frames(30)
		await _player_jump_shots(main)
		get_tree().quit()
		return
	if "--only=citizen" in OS.get_cmdline_user_args():
		await _frames(30)
		await _citizen_shots(main)
		get_tree().quit()
		return
	if "--only=punch" in OS.get_cmdline_user_args():
		await _frames(30)
		await _punch_shots(main)
		get_tree().quit()
		return
	if "--only=menu" in OS.get_cmdline_user_args():
		await _frames(30)
		await _menu_shots(main)
		get_tree().quit()
		return
	if "--only=collect" in OS.get_cmdline_user_args():
		await _frames(30)
		await _collect_shots(main)
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


## 수집 요소 (`-- --only=collect`): 골목 안 비밀 패키지(collect_package, 강남 첫 패키지 · collect_package2, 종로),
## 인도의 광란 해골 아이콘(collect_rampage), 밟아서 시작한 광란 HUD(collect_rampage_on)
func _collect_shots(main: Node2D) -> void:
	var cam: ChaseCamera = main.camera
	var player: Player = main.player
	main.street_events.enabled = false
	main.sky.paused_clock = true
	main.sky.set_hour(14.0)
	main.set_chapter(4)
	var spots := HiddenPackages.SET.spots
	player.global_position = spots[0] + Vector2(-22, 0)
	cam.snap()
	await _frames(30)
	await _save("collect_package")
	player.global_position = spots[12] + Vector2(-22, 0)
	cam.snap()
	await _frames(30)
	await _save("collect_package2")
	var r: RampageType = RampageList.ALL[0]
	player.global_position = r.position() + Vector2(-70, 0)
	cam.snap()
	await _frames(30)
	await _save("collect_rampage")
	player.global_position = r.position()
	await _frames(40)
	await _save("collect_rampage_on")


## 일시정지 메뉴 (`-- --only=menu`): menu_main · menu_map(서울 지도) · menu_settings · menu_settings_en(영어로 바꾼 설정) ·
## hud_en(영어 HUD, 차에 타서 라디오 채널 이름과 DJ 자막)
func _menu_shots(main: Node2D) -> void:
	var menu: PauseMenu = main.pause_menu
	main.street_events.enabled = false
	menu.open()
	await get_tree().process_frame
	await _save("menu_main")
	main.missions.start(main.missions.by_id(&"gangnam_06"))   # 지도의 노란 길·핀
	menu._show_map()
	for i in 3:
		await get_tree().process_frame
	await _save("menu_map")
	menu._show_settings()
	await get_tree().process_frame
	await _save("menu_settings")
	Settings.values["lang"] = "en"
	Settings.apply()
	menu._show_settings()
	await get_tree().process_frame
	await _save("menu_settings_en")
	menu.visible = false
	get_tree().paused = false
	main.director.enter_immediately(main.vehicles[0])
	await _frames(20)
	main.radio._dj_wait = 0.0
	await _frames(10)
	await _save("hud_en")
	Settings.values["lang"] = "ko"
	Settings.apply()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + name + ".png"))
	print("saved ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## 주인공 총 자세 (`-- --only=rifle` 소총 · `--only=pistol` 권총): 실제 입력(fire 누르기)으로 쏜다. 화면 →·↘·←·↖·↑ 쪽 발사 장면
## (<무기>_<방향>)과 서서 겨눈 장면(<무기>_aim). 권총은 겨눈 채 걷는 장면(pistol_walk)도
func _rifle_shots(main: Node2D, id := "rifle") -> void:
	var cam: ChaseCamera = main.camera
	var player: Player = main.player
	var weapons: PlayerWeapons = main.weapons
	if main.director.current_vehicle:
		main.director.exit_vehicle()
	await _frames(20)
	var rifle: WeaponType = load("res://data/weapons/%s.tres" % id)
	player.arsenal.give(rifle, 180)
	player.arsenal.index = player.arsenal.weapons.find(rifle)
	cam.target = null
	cam.global_position = player.global_position
	cam.zoom = Vector2(4.0, 4.0)
	await _frames(30)
	await _save(id + "_aim")
	for spec in [[0, "e"], [1, "se"], [2, "s"], [4, "w"], [5, "nw"], [6, "n"]]:
		var world_dir := IsoView.BASIS.affine_inverse().basis_xform(Vector2.RIGHT.rotated(spec[0] * PI / 4.0)).normalized()
		weapons.mouse_aim = false   # 창 위에 놓인 실제 마우스가 조준을 빼앗지 않게
		player.facing = Vector2.UP.angle_to(world_dir)
		await _frames(5)
		var before := player.arsenal.ammo_of(rifle)
		Input.action_press("fire")
		await _frames(2)   # 쏜 직후 (반동 장면·총구 불꽃이 남아 있을 때)
		await _save(id + "_" + spec[1])
		await _frames(40)
		Input.action_release("fire")
		print("  %s_%s: 0.75초 누름 → %d발" % [id, spec[1], before - player.arsenal.ammo_of(rifle)])
		await _frames(20)
	if id == "pistol":
		# 겨눈 채 걷기: 화면 → 쪽으로 걸으며 마우스 없이 바라보는 쪽을 지킨다
		player.screen_walk = true
		Input.action_press("steer_right")
		await _frames(25)
		cam.global_position = player.global_position
		await _frames(1)
		await _save("pistol_walk")
		Input.action_release("steer_right")


## 주인공 로켓포 (`-- --only=rocket`): 실제 입력으로 쏜다. 서서 겨눈 장면(rocket_aim), 방향마다 쏜 순간(rocket_<방향>_0 — 앞 불꽃·뒤 불길),
## 로켓이 날아가는 중(_1 — 꼬리 연기·후폭풍 연기·빈 발사관 반동), 조금 더 뒤(_2)
func _rocket_shots(main: Node2D) -> void:
	var cam: ChaseCamera = main.camera
	var player: Player = main.player
	var weapons: PlayerWeapons = main.weapons
	if main.director.current_vehicle:
		main.director.exit_vehicle()
	await _frames(20)
	var rocket: WeaponType = load("res://data/weapons/rocket.tres")
	player.arsenal.give(rocket, 20)
	player.arsenal.index = player.arsenal.weapons.find(rocket)
	cam.target = null
	cam.global_position = player.global_position
	cam.zoom = Vector2(3.0, 3.0)
	await _frames(30)
	await _save("rocket_aim")
	for spec in [[0, "e"], [1, "se"], [2, "s"], [4, "w"], [5, "nw"], [6, "n"], [7, "ne"]]:
		var world_dir := IsoView.BASIS.affine_inverse().basis_xform(Vector2.RIGHT.rotated(spec[0] * PI / 4.0)).normalized()
		weapons.mouse_aim = false
		player.facing = Vector2.UP.angle_to(world_dir)
		player.revive()
		for v: Vehicle in main.vehicles:   # 바로 옆 차에 맞아 제 로켓에 죽지 않게
			if is_instance_valid(v) and v.global_position.distance_to(player.global_position) < 260.0:
				v.global_position += Vector2(3000, 3000)
		await _frames(10)
		Input.action_press("fire")
		await _frames(2)
		Input.action_release("fire")
		await _save("rocket_%s_0" % spec[1])
		await _frames(9)
		await _save("rocket_%s_1" % spec[1])
		await _frames(14)
		await _save("rocket_%s_2" % spec[1])
		await _frames(70)


## 경찰 헬기 겨누기 (`-- --only=heli_aim`): ★5 도보 소총. 커서를 헬기 그림에 대고 실제 입력으로 쏜다(heli_aim·heli_fire),
## 커서를 몸통에서 얼마나 떨어뜨려도 헬기를 고르는지, 키보드 자동 조준으로도 맞는지(heli_keyboard)를 출력한다
func _heli_aim_shots(main: Node2D) -> void:
	var player: Player = main.player
	var weapons: PlayerWeapons = main.weapons
	var police: PoliceDispatcher = main.police
	if main.director.current_vehicle:
		main.director.exit_vehicle()
	player.global_position = City.block_rect(1, 1).get_center()   # 탁 트인 드리프트 연습장
	var rifle: WeaponType = load("res://data/weapons/rifle.tres")
	player.arsenal.give(rifle, 600)
	player.arsenal.index = player.arsenal.weapons.find(rifle)
	police.last_known = player.global_position
	police.wanted.raise_to(5)
	var heli: PoliceHeli = null
	for f in 60 * 20:
		await _frames(1)
		police._arrest = 0.0
		player.revive()
		if not police.helis.is_empty():
			heli = police.helis[0]
			if heli.global_position.distance_to(player.global_position) < 320.0:
				break
	if heli == null:
		print("  경찰 헬기가 오지 않았다")
		return
	var vp := get_viewport()
	var body := func() -> Vector2:
		return vp.canvas_transform * (heli.global_position + IsoView.lift(heli.altitude()))
	# 커서를 몸통에서 화면 오른쪽으로 떨어뜨리며 헬기를 고르는지
	var ct := vp.canvas_transform
	var zoom := ct.basis_xform(IsoView.LIFT).length()
	var pick := (heli.hit_radius() * PlayerWeapons.HELI_PICK + PlayerWeapons.AIM_PICK) * zoom
	print("  헬기 몸통 화면 길이 약 %.0fpx, 고르는 반경 %.0fpx (줌 %.2f)" % [heli.stats.size.y * zoom, pick, zoom])
	for k in [0.0, 20.0, 40.0, 60.0, 80.0, 100.0]:
		var m: Vector2 = body.call() + Vector2(k, 0)
		var hit := weapons.screen_point(player.global_position, m, ct) == heli.global_position
		print("    몸통에서 %3.0fpx: %s" % [k, "헬기를 겨눈다" if hit else "땅을 겨눈다"])
	# 마우스: 커서를 헬기 그림에 대고 쏜다
	var hp := heli.health
	Input.warp_mouse(body.call())
	weapons.mouse_aim = true
	await _frames(3)
	await _save("heli_aim")
	Input.action_press("fire")
	for f in 30:
		Input.warp_mouse(body.call())
		police._arrest = 0.0
		player.revive()
		await _frames(1)
		if f == 1:
			await _save("heli_fire")
	Input.action_release("fire")
	print("  마우스로 0.5초 쏨: 헬기 체력 %.0f → %.0f" % [hp, heli.health])
	# 키보드: 헬기 쪽에서 30° 틀어 서서 쏜다 (자동 조준이 헬기로 돌린다)
	await _frames(30)
	hp = heli.health
	weapons.mouse_aim = false
	var to_heli := heli.global_position - player.global_position
	player.facing = Vector2.UP.angle_to(to_heli.rotated(0.5))
	Input.action_press("fire")
	for f in 30:
		weapons.mouse_aim = false   # 창 위에 놓인 실제 마우스가 조준을 빼앗지 않게
		police._arrest = 0.0
		player.revive()
		await _frames(1)
		if f == 3:
			await _save("heli_keyboard")
	Input.action_release("fire")
	print("  키보드로 0.5초 쏨: 헬기 체력 %.0f → %.0f" % [hp, heli.health])


## 주인공 주먹 (`-- --only=punch`): 실제 입력(fire 누르기)으로 친다. 화면 →·↙·↖·↑ 쪽 잽 타격 장면, → 쪽 어퍼컷·카운터 타격 장면,
## 앞에 선 시민이 타격 장면에 한 번만 맞는지, 길게 누르면 공격 하나·빠른 연타는 다음 공격 하나만 이어지는지를 출력한다
## 주인공 제자리 점프 (Space): 방향마다 웅크림·꼭대기·닿기 장면, 마지막은 달리며 뛰기
func _player_jump_shots(main: Node2D) -> void:
	var cam: ChaseCamera = main.camera
	var player: Player = main.player
	if main.director.current_vehicle:
		main.director.exit_vehicle()
	await _frames(20)
	cam.target = null
	cam.global_position = player.global_position
	cam.zoom = Vector2(4.0, 4.0)
	var peak := Player.JUMP_PRE + Player.JUMP_AIR * 0.5
	for k in [2, 1, 0, 5, 6]:
		var world_dir := IsoView.BASIS.affine_inverse().basis_xform(Vector2.RIGHT.rotated(k * PI / 4.0)).normalized()
		player.facing = Vector2.UP.angle_to(world_dir)
		await _frames(10)
		Input.action_press("handbrake")
		await _frames(int(Player.JUMP_PRE * 0.7 * 60.0))
		await _save("pjump_%s_crouch" % PersonRig.DIR8[k])
		await _frames(int((peak - Player.JUMP_PRE * 0.7) * 60.0))
		await _save("pjump_%s_peak" % PersonRig.DIR8[k])
		await _frames(int((Player.JUMP_AIR * 0.5 + 0.05) * 60.0))
		await _save("pjump_%s_land" % PersonRig.DIR8[k])
		Input.action_release("handbrake")
		await _frames(40)
		print("  %s: 끝난 뒤 점프 중 %s" % [PersonRig.DIR8[k], player.jumping()])
	# 달리며 뛰기: 뛴 방향·속도로 간다
	var start := player.global_position
	Input.action_press("steer_right")
	Input.action_press("sprint")
	await _frames(20)
	Input.action_press("handbrake")
	await _frames(int(peak * 60.0))
	cam.global_position = player.global_position
	await _save("pjump_run_peak")
	Input.action_release("handbrake")
	await _frames(40)
	Input.action_release("steer_right")
	Input.action_release("sprint")
	print("  달리며 뛰기: %.0fpx 갔다" % start.distance_to(player.global_position))


func _punch_shots(main: Node2D) -> void:
	var cam: ChaseCamera = main.camera
	var player: Player = main.player
	var weapons: PlayerWeapons = main.weapons
	if main.director.current_vehicle:
		main.director.exit_vehicle()
	await _frames(20)
	var ped: Pedestrian = main.pedestrians.peds[0]
	cam.target = null   # 카메라가 걷는 주인공 줌으로 돌아가지 않게 붙들어 둔다
	cam.global_position = player.global_position
	cam.zoom = Vector2(4.0, 4.0)
	var attacks := PersonRig.punch_attacks()
	var hit_time := func(i: int) -> float:
		var a: Dictionary = attacks[i]
		return float(a["duration"]) * (float(a["hit_frame"]) + 0.5) / float(a["frames"])
	# 방향마다 잽 한 번 (앞 시민은 → 쪽에만 세운다)
	for spec in [[0, "punch_e"], [3, "punch_sw"], [5, "punch_nw"], [6, "punch_n"]]:
		var screen_dir := Vector2.RIGHT.rotated(spec[0] * PI / 4.0)
		var world_dir := IsoView.BASIS.affine_inverse().basis_xform(screen_dir).normalized()
		weapons._cancel_punch()
		await _frames(60)   # 콤보 유지 시간이 지나 다음 입력은 잽부터
		weapons.mouse_aim = false   # 창 위에 놓인 실제 마우스가 조준을 빼앗지 않게
		player.facing = Vector2.UP.angle_to(world_dir)
		ped.global_position = player.global_position + world_dir * 400.0
		if spec[0] == 0:
			ped.global_position = player.global_position + world_dir * 18.0
			ped.health = 20.0
			ped.state = Pedestrian.State.IDLE
		var before := ped.health
		Input.action_press("fire")
		await _frames(int(hit_time.call(0) * 60.0))
		await _save(spec[1])
		await _frames(int((float(attacks[0]["duration"]) - hit_time.call(0)) * 60.0) + 120)
		Input.action_release("fire")
		print("  %s: 길게 2초 누름 → 공격 끝 %s, 시민 체력 %.0f → %.0f" % [spec[1], not weapons._punch_active, before, ped.health])
	# → 쪽 어퍼컷·카운터: 빠르게 연타해 다음 공격을 이어 낸다
	var e_dir := IsoView.BASIS.affine_inverse().basis_xform(Vector2.RIGHT).normalized()
	weapons._cancel_punch()
	await _frames(60)
	weapons.mouse_aim = false
	player.facing = Vector2.UP.angle_to(e_dir)
	ped.global_position = player.global_position + e_dir * 400.0
	var seen := []
	for k in 4:
		# 공격이 끝나자마자 한 번 누른다 (콤보 유지 시간 안) → 다음 공격
		weapons.mouse_aim = false
		Input.action_press("fire")
		await _frames(2)
		Input.action_release("fire")
		seen.append(weapons._punch_index)
		var a: Dictionary = attacks[weapons._punch_index]
		await _frames(maxi(int(hit_time.call(weapons._punch_index) * 60.0) - 2, 1))
		if weapons._punch_index >= 2:
			await _save("punch_" + String(a["name"]))
		while weapons._punch_active:
			await _frames(1)
	print("  한 번씩 누름: 공격 순서 ", seen, " (기대 [0, 1, 2, 3])")
	# 빠른 연타: 다섯 번 두드려도 잽 + 예약 한 번(스트레이트)만
	weapons._cancel_punch()
	await _frames(60)
	seen = []
	for tap in 5:
		Input.action_press("fire")
		await _frames(2)
		Input.action_release("fire")
		await _frames(3)
	while weapons._punch_active:
		if seen.is_empty() or seen[-1] != weapons._punch_index:
			seen.append(weapons._punch_index)
		await _frames(1)
	print("  다섯 번 연타: 공격 순서 ", seen, " (기대 [0, 1] — 예약은 한 번만)")


## 한강 (`-- --only=river`): 강변 가까이(호안·물거품·밤 불빛) → 넓게 → 낮 → 북쪽 둑 옹벽 → 비 → 밤 둑 가로등 → 0.5초 뒤 (물살이 흘렀는지)
func _river_shots(main: Node2D) -> void:
	var cam: ChaseCamera = main.camera
	var cx := City.road_center(2)
	var span: Vector2 = CityMap.bridge_spans(2)[-1]
	cam.target = null
	cam.global_position = Vector2(cx + 520.0, span.y - 120.0)
	cam.zoom = Vector2(1.4, 1.4)
	await _frames(5)
	await _save("river_shore")
	await _frames(30)
	await _save("river_shore_later")
	cam.global_position = Vector2(cx + 300.0, (span.x + span.y) * 0.5)
	cam.zoom = Vector2(0.55, 0.55)
	await _frames(3)
	await _save("river_wide")
	main.sky.paused_clock = true
	main.sky.set_hour(13.0)
	cam.global_position = Vector2(cx + 520.0, span.y - 160.0)
	cam.zoom = Vector2(1.0, 1.0)
	await _frames(5)
	await _save("river_day")
	# 북쪽 둑: 옹벽 면이 보이는 쪽 (`RiverBank`)
	cam.global_position = Vector2(cx + 420.0, span.x + 220.0)
	await _frames(5)
	await _save("river_bank")
	cam.zoom = Vector2(2.2, 2.2)
	await _frames(3)
	await _save("river_bank_close")
	cam.zoom = Vector2(1.0, 1.0)
	cam.global_position = Vector2(cx + 520.0, span.y - 160.0)
	main.sky.rain = 1.0
	main.sky.set_hour(13.0)
	await _frames(5)
	await _save("river_rain")
	main.sky.rain = 0.0
	main.sky.set_hour(21.0)
	# 밤 북쪽 둑: 둑 가로등 불빛이 옹벽·물에 비친다
	cam.global_position = Vector2(cx + 420.0, span.x + 220.0)
	await _frames(5)
	await _save("river_bank_night")


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


## 고가차도 (`-- --only=overpass`): 교통이 다니는 모습 → 고가 위 차와 밑을 지나는 차가 겹친 모습 → 경사로를 올라 고가 위를 달리는 모습 → 고가 뒤에 선 주인공(가리는 상판이 흐려진다)
func _overpass_shots(main: Node2D) -> void:
	var cam: ChaseCamera = main.camera
	main.player.died.disconnect(main._on_died)
	var o: Vector4i = CityMap.OVERPASSES[0]
	var cell := Vector2i(o.z, o.y)
	var lane := City.road_center(o.y) + LaneGraph.LANE_OFFSET
	cam.target = null
	cam.global_position = LaneGraph.center(cell) + Vector2(300, 0)
	await _frames(400)
	await _save("overpass_view")
	# 겹친 모습: 넘는 교차로 위와 밑에 차를 세운다
	var top := Vehicle.new()
	top.stats = load("res://data/vehicles/car_taxi.tres")
	main.add_child(top)
	top.place(LaneGraph.center(cell) + Vector2(10, LaneGraph.LANE_OFFSET), PI * 0.5)
	top.level = 1
	main.vehicles.append(top)
	var low := Vehicle.new()
	low.stats = load("res://data/vehicles/trk_bongo.tres")
	main.add_child(low)
	low.place(LaneGraph.center(cell) + Vector2(-LaneGraph.LANE_OFFSET, 40), PI)
	main.vehicles.append(low)
	# 앞(남동쪽) 블록 건물에 가리므로 잠깐 숨긴다
	var hidden: Array = []
	for b in [cell, cell + Vector2i(1, 0)]:
		for idx in main.city._by_block.get(b, []):
			for view in main.city._views.get(idx, []):
				view.visible = false
				hidden.append(view)
	cam.global_position = LaneGraph.center(cell)
	cam.zoom = Vector2(1.8, 1.8)
	await _frames(20)
	await _save("overpass_stack")
	cam.global_position = LaneGraph.center(cell) + Vector2(150, 150)
	cam.zoom = Vector2(1.0, 1.0)
	await _frames(5)
	await _save("overpass_side")
	for view in hidden:
		view.visible = true
	cam.zoom = Vector2(ChaseCamera.BASE_ZOOM, ChaseCamera.BASE_ZOOM)
	# 경사로를 올라 고가 위를 달린다
	var car := Vehicle.new()
	car.stats = load("res://data/vehicles/car_sonato.tres")
	main.add_child(car)
	car.place(Vector2(CityMap.over_extent(o).x - 60.0, lane), PI * 0.5)
	main.vehicles.append(car)
	main.director.enter_immediately(car)
	cam.target = car
	cam.snap()
	Input.action_press("accelerate")
	var shots := ["overpass_ramp", "overpass_deck"]
	while not shots.is_empty():
		await _frames(1)
		main.player.revive()
		var x := car.global_position.x
		if shots[0] == "overpass_ramp" and x > CityMap.over_extent(o).x + City.BLOCK * 0.55:
			await _save(shots.pop_front())
		elif shots[0] == "overpass_deck" and x > (o.z + 0.6) * City.PITCH:
			await _save(shots.pop_front())
	Input.action_release("accelerate")
	# 고가 뒤(북쪽 인도)에 선 주인공: 가리는 상판 조각이 흐려진다
	main.director.exit_vehicle()
	main.player.global_position = Vector2((o.z + 0.5) * City.PITCH, City.road_center(o.y) - City.ROAD * 0.5 - 14.0)
	cam.target = main.player
	cam.snap()
	cam.zoom = Vector2(1.6, 1.6)
	await _frames(60)
	await _save("overpass_behind")
	# 비교: 같은 자리에서 고가 앞(남쪽 인도)에 서면 흐려지지 않는다
	var at := cam.global_position
	cam.target = null
	cam.global_position = at
	main.player.global_position += Vector2(0.0, City.ROAD + 28.0)
	await _frames(60)
	await _save("overpass_front")
	cam.zoom = Vector2(ChaseCamera.BASE_ZOOM, ChaseCamera.BASE_ZOOM)


## 구급대 (`-- --only=ems`): 병원 옥상에 선 구급헬기(ems_pad) → 기절한 사람(ems_ko, 머리 위 별) → 들것으로 옮기는 대원(ems_stretcher)
## → 11명이 쓰러져 뜬 헬기가 줄로 끌어올리는 모습(ems_hoist) → 옥상에 돌아와 내려앉은 헬기(ems_back)
func _ems_shots(main: Node2D) -> void:
	var cam: ChaseCamera = main.camera
	var player: Player = main.player
	var ems: EmsDispatcher = main.ems
	var peds: PedestrianManager = main.pedestrians
	main.street_events.enabled = false
	main.sky.paused_clock = true
	main.sky.set_hour(14.0)
	cam.target = null
	cam.global_position = ems.pad + IsoView.lift(ems.pad_height)
	await _frames(20)
	await _save("ems_pad")
	cam.target = player
	cam.snap()
	var loop := City.sidewalk_loop(City.nearest_block(player.global_position))
	var spot := loop[0].lerp(loop[1], 0.5)
	var rng := RandomNumberGenerator.new()
	var p := Pedestrian.new()
	p.setup(PedestrianManager.NPC_TYPES[0], rng, loop, 0, 0.0, 1)
	p.position = spot
	peds.add(p)
	peds.damage(p, 999.0, Vector2.RIGHT, false, true)
	cam.target = null
	cam.global_position = spot
	await _frames(20)
	await _save("ems_ko")
	for f in 60 * 60:
		await _frames(1)
		player.revive()
		if is_instance_valid(p) and p.carried:
			break
	await _frames(25)
	if is_instance_valid(p):
		cam.global_position = p.global_position
	await _frames(2)
	await _save("ems_stretcher")
	for i in 11:
		var q := Pedestrian.new()
		q.setup(PedestrianManager.NPC_TYPES[i % 3], rng, loop, 0, 0.0, 1)
		q.position = spot + Vector2(0, 120) + Vector2.from_angle(i * TAU / 11.0) * 60.0
		peds.add(q)
		peds.damage(q, 999.0, Vector2.RIGHT, false, true)
	for f in 60 * 60:
		await _frames(1)
		player.revive()
		if ems.hoisting != null and ems._hoist > EmsDispatcher.HOIST_TIME * 0.5:
			break
	cam.global_position = ems.heli.global_position + IsoView.lift(ems.heli.altitude() * 0.5)
	await _frames(2)
	await _save("ems_hoist")
	for f in 60 * 120:
		await _frames(1)
		player.revive()
		if ems.air == EmsDispatcher.Air.PARKED:
			break
	cam.global_position = ems.pad + IsoView.lift(ems.pad_height)
	await _frames(10)
	await _save("ems_back")
	cam.target = player


## HUD (`-- --only=hud`): 왼쪽 아래 원형 미니맵·오른쪽 위 무기 칸, 주인공 발밑 진행 방향 원,
## 다친 시민·조직원 머리 위 체력 막대·조직 색 삼각형 (hud_foot), 차를 몰 때 (hud_drive)
func _hud_shots(main: Node2D) -> void:
	var cam: ChaseCamera = main.camera
	var player: Player = main.player
	var peds: PedestrianManager = main.pedestrians
	main.street_events.enabled = false
	main.sky.paused_clock = true
	main.sky.set_hour(21.0)
	main.missions.start(main.missions.by_id(&"gangnam_06"))   # 왼쪽 위 미션 상자
	player.arsenal.give(load("res://data/weapons/smg.tres"), 30)
	cam.target = player
	cam.snap()
	var loop := City.sidewalk_loop(City.nearest_block(player.global_position))
	var rng := RandomNumberGenerator.new()
	var at := player.global_position
	for k in 3:
		var p := Pedestrian.new()
		p.setup(PedestrianManager.NPC_TYPES[k], rng, loop, 0, 0.0, 1)
		p.position = at + Vector2(40.0 + k * 24.0, -30.0 + k * 20.0)
		peds.add(p)
		p.health = p.npc.health * (0.8 - k * 0.25)
	var gang: GangType = main.missions.gangs.gangs[0]
	var g := GangMember.new()
	g.setup(gang.member, rng, loop, 0, 0.0, 1)
	g.gang = gang
	g.guard = true
	g.position = at + Vector2(-50, 20)
	peds.add(g)
	Input.action_press("steer_right")
	await _frames(20)
	Input.action_release("steer_right")
	await _frames(3)
	for q: Pedestrian in peds.peds:
		q.queue_redraw()
	await _frames(2)
	await _save("hud_foot")
	player.global_position = at     # 걸어서 멀어진 차 옆으로 되돌린다
	await _frames(2)
	main.director.request_enter_exit()
	await _frames(20)
	Input.action_press("accelerate")
	await _frames(70)
	Input.action_press("steer_right")
	await _frames(20)
	var ch: RadioChannel = load("res://data/radio/" + DirAccess.get_files_at("res://data/radio")[0].trim_suffix(".remap"))
	main.hud.show_dj(ch, "비 오는 밤, 강남대로를 달리는 분들께 다음 곡 보내 드립니다.")   # 오른쪽 아래 라디오 상자
	await _frames(2)
	await _save("hud_drive")
	for a in ["accelerate", "steer_right"]:
		Input.action_release(a)


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
	# 땅에서 위로 쏜 총알 궤적 (헬기 그림까지 올라간다)
	Input.action_release("accelerate")
	await _frames(90)
	var pistol: WeaponType = load("res://data/weapons/police_pistol.tres")
	var none: Array[RID] = []
	for k in 3:
		var from := heli.global_position + Vector2(-160.0 + k * 140.0, 170.0)
		main.combat.fire(from, (heli.global_position - from).normalized(), pistol, false, none)
	await _frames(1)
	await _save("heli_shot")
	# 헬기에서 내려쏜 궤적 (헬기 몸에서 땅으로)
	await _frames(10)
	# 한 발이 날아가는 모습: 총구 불꽃 → 빛줄기 → 맞은 곳 불똥
	var gun: WeaponType = load("res://data/weapons/pistol.tres")
	main.combat.fire_down(heli, heli.global_position + Vector2(-60.0, 260.0), gun, true)
	await _frames(2)
	await _save("heli_fire_down")
	await _frames(4)
	await _save("heli_fire_down_2")
	await _frames(5)
	await _save("heli_fire_down_3")
	Input.action_press("accelerate")
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



## 거리 시민 걷기·달리기 (`-- --only=citizen`): 주인공 가까운 시민(남·여)을 카메라로 따라가며 0.1초마다 8장씩 —
## 걷는 장면(citizen_<id>_walk_N), 놀라 달아나는 장면(citizen_<id>_run_N)
func _citizen_shots(main: Node2D) -> void:
	var cam: ChaseCamera = main.camera
	var player: Player = main.player
	if main.director.current_vehicle:
		main.director.exit_vehicle()
	await _frames(20)
	cam.target = null
	cam.zoom = Vector2(3.0, 3.0)
	for id in ["civ_m", "civ_f"]:
		var ped: Pedestrian = null
		for wait in 40:
			var best := INF
			for p in main.pedestrians.peds:
				if is_instance_valid(p) and p.npc and p.velocity.length() > 10.0:
					var d: float = p.global_position.distance_to(player.global_position)
					if d < best:
						best = d
						ped = p
			if ped:
				break
			await _frames(15)
		if ped == null:
			print("  %s: 걷는 사람을 못 찾음" % id)
			continue
		ped.npc = load("res://data/npc/%s.tres" % id)   # 가까이 걷는 보행자를 그 시민 모습으로
		for k in 8:
			cam.global_position = ped.global_position
			await _frames(6)
			await _save("citizen_%s_walk_%d" % [id, k])
		ped.panic(ped.global_position + Vector2(40, 30), true)
		await _frames(10)
		for k in 8:
			cam.global_position = ped.global_position
			await _frames(6)
			await _save("citizen_%s_run_%d" % [id, k])
		print("  %s: 걷기·달리기 %.0f px/s" % [id, ped.velocity.length()])
