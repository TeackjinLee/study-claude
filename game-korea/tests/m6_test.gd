extends Node
## M6 콘텐츠 확장 검증.
##  1. 지도: 구역 9개(잠실·광진 포함)·한강·다리 4개. 장마다 열린 도로가 하나로 이어져 있고, 들어간 교차로에서 늘 나갈 길이 있다.
##     1장엔 다리가 통제되고, 4장엔 잠긴 곳이 없다.
##  2. 장: 목표 금액을 모으면 다음 장이 열리고(구역·바리케이드), 자동 저장 칸에 저장된다. 불러오면 그 장이다.
##  3. 은신처: 아직 안 산 곳은 살지 묻고, 사면 거기서 저장하고 불러오면 거기서 시작한다.
##  4. 다른 구역에 들어서면 구역 이름이 뜬다.
##  5. ★5: 경찰 헬기가 와서 탐조등으로 위치를 잡고 쏜다. 총으로 떨어뜨리면 터지고 ★6이 된다.
##  6. ★6: 군 트럭이 와서 군인이 내린다. ★4부터는 가까운 다리 끝에 검문소가 선다.
##  7. 콘텐츠 수: NPC 30종 · 차량 27종 · 건물 15종 · 무기 12종 · 미션 60개, 아이는 다치지 않는다.
##  8. 무기: 수류탄은 멈췄다 터지고, 화염병은 불을 놓고, 로켓은 차를 날리고, 화염방사기는 태우고,
##     물대포(소방차)는 불을 끄고 사람을 넘어뜨린다. 소총은 둘을 꿰뚫고, 차량 기관총은 앞으로만 쏜다.
##     불이 오래 타면 소방차가 와서 끈다. 쓰러진 군인은 소총을 떨어뜨린다.
##  9. 부업 6종: 택시는 손님을 태워 내려 주면 보상, 차에서 오래 내리면 끝, 10단계를 끝내면 보너스(저장된다).
##     자경단은 수배를 풀고 범인 차를 부수게 하고, 소방은 소방차 물대포로 불을 끈다.
## 10. 시간대·날씨: 밤·낮 색이 다르고, 비가 오면 노면이 미끄럽다. 밤에만 나오는 사람(DJ)이 있다.
## 실행: godot --headless --fixed-fps 60 --path . res://tests/m6_test.tscn

const SAVE_PREFIX := "user://m6_test_save_"
const SEDAN: VehicleType = preload("res://data/vehicles/car_avela.tres")
const PISTOL: WeaponType = preload("res://data/weapons/pistol.tres")
const CHILD: NpcType = preload("res://data/npc/child.tres")
const CIV: NpcType = preload("res://data/npc/civ_m.tres")
const SOLDIER: NpcType = preload("res://data/npc/soldier.tres")
const W := "res://data/weapons/"
const PLAYER_WEAPONS := ["fist", "bat", "pistol", "smg", "shotgun", "rifle", "flamethrower", "rocket", "molotov", "grenade", "car_mg", "water_cannon"]

var _failures: Array[String] = []


func _ready() -> void:
	_remove_saves()
	_test_map()
	_test_counts()
	await _test_chapters()
	await _test_chapter_back()
	await _test_hideouts()
	await _test_district_banner()
	await _test_child()
	await _test_heli()
	await _test_army_and_checkpoint()
	await _test_weapons()
	await _test_fire_department()
	await _test_side_jobs()
	_test_day_night()
	_remove_saves()
	CityMap.set_chapter(1)
	if _failures.is_empty():
		print("m6_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _make_main(chapter := 1, patrols := 0) -> Node2D:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = 0
	main.bus_count = 0
	main.police_patrols = patrols
	main.save_prefix = SAVE_PREFIX
	main.chapter = chapter
	add_child(main)
	return main


## 체포·사망으로 다시 시작하지 않게 한다 (경찰이 끝까지 오는지 지켜본다)
func _immortal(main: Node2D) -> void:
	main.player.died.disconnect(main._on_died)
	main.police.busted.disconnect(main._on_busted)


## n프레임 지켜본다 — 그동안 체포되거나 죽지 않게 한다
func _hold(main: Node2D, n: int) -> void:
	for i in n:
		await _frames(1)
		main.police._arrest = 0.0
		main.player.revive()


func _free(main: Node2D) -> void:
	main.queue_free()
	await _frames(2)


# ── 지도 ──────────────────────────────────────────────────

func _test_map() -> void:
	_expect(CityMap.DISTRICTS.size() == 9, "구역 9개 (%d)" % CityMap.DISTRICTS.size())
	var bridge_segments := 0
	for k in CityMap.BRIDGES:
		for j in range(CityMap.MIN.y, CityMap.MAX.y + 1):
			if CityMap.is_bridge(Vector2i(k, j), 2):
				bridge_segments += 1
	_expect(bridge_segments > 0 and PoliceDispatcher.bridge_ends().size() == CityMap.BRIDGES.size() * 2 + 2,
		"다리 4개, 끝 %d곳 (여의도 섬을 지나는 다리는 끝이 넷)" % PoliceDispatcher.bridge_ends().size())
	for chapter in range(1, CityMap.LAST_CHAPTER + 1):
		CityMap.set_chapter(chapter)
		var nodes := []
		for j in range(CityMap.MIN.y, CityMap.MAX.y + 2):
			for i in range(CityMap.MIN.x, CityMap.MAX.x + 2):
				if CityMap.is_open_node(Vector2i(i, j)):
					nodes.append(Vector2i(i, j))
		# 출발점 교차로에서 열린 도로로 모든 열린 교차로에 닿는다
		var start := Vector2i(3, 3)
		var seen := {start: true}
		var queue: Array[Vector2i] = [start]
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			for d in 4:
				if CityMap.open_road(c, d) and not seen.has(c + CityMap.STEPS[d]):
					seen[c + CityMap.STEPS[d]] = true
					queue.append(c + CityMap.STEPS[d])
		var dead_ends := 0
		var graph := LaneGraph.new()
		for c: Vector2i in nodes:
			for d in 4:
				# c에서 d로 들어온 차가 나갈 길이 없으면 막다른 길
				if CityMap.open_road(c - CityMap.STEPS[d], d) and graph.exits(c, d).is_empty():
					dead_ends += 1
		_expect(seen.size() == nodes.size(), "%d장: 열린 교차로가 다 이어져 있다 (%d/%d)" % [chapter, seen.size(), nodes.size()])
		_expect(dead_ends == 0, "%d장: 막다른 교차로 없음 (%d)" % [chapter, dead_ends])
		var locked := 0
		for d in CityMap.DISTRICTS:
			if d.chapter > chapter:
				locked += 1
		print("  %d장: 열린 교차로 %d, 잠긴 구역 %d" % [chapter, nodes.size(), locked])
	CityMap.set_chapter(1)
	_expect(not CityMap.open_road(Vector2i(2, 0), 0), "1장: 강남→종로 다리는 통제")
	CityMap.set_chapter(2)
	_expect(CityMap.open_road(Vector2i(2, 0), 0), "2장: 강남→종로 다리가 열린다")
	_expect(not CityMap.open_road(Vector2i(-3, -4), 2), "2장: 여의도 다리는 아직 통제")
	CityMap.set_chapter(1)


func _test_counts() -> void:
	var npcs := DirAccess.get_files_at("res://data/npc/").size()
	var cars := DirAccess.get_files_at("res://data/vehicles/").size()
	var weapons := DirAccess.get_files_at("res://data/weapons/").size()
	var buildings := 0
	for t in City.BUILDING_TYPES:
		if t.solid:
			buildings += 1
	_expect(npcs >= 30, "NPC 30종 이상 (%d)" % npcs)
	_expect(cars >= 27, "차량 27종 이상 (%d)" % cars)
	_expect(buildings >= 15, "건물 15종 이상 (%d)" % buildings)
	_expect(MissionSystem.MISSIONS.size() == 60, "미션 60개 (%d)" % MissionSystem.MISSIONS.size())
	for id in PLAYER_WEAPONS:
		_expect(ResourceLoader.exists(W + id + ".tres"), "무기 %s" % id)
	var city := City.new()
	city._build_layout()
	var used := {}
	for k in city.kinds:
		if k:
			used[k.id] = true
	city.free()
	for t in City.BUILDING_TYPES:
		if t.solid:
			_expect(used.has(t.id), "건물 %s가 도시에 있다" % t.display_name)
	print("  NPC %d종, 차량 %d종, 무기 파일 %d개, 건물 %d종" % [npcs, cars, weapons, buildings])


# ── 장 · 자동 저장 ────────────────────────────────────────

func _test_chapters() -> void:
	var main := _make_main()
	await _frames(2)
	var city: City = main.city
	var locked_ch1 := city.locked_blocks.size()
	_expect(main.chapter == 1 and not city.barriers.is_empty() and not city.locked_blocks.is_empty(), "1장: 통제 구역과 바리케이드")
	_expect(main.hud.goal_text.contains("1장") and main.hud.goal_text.contains("1,000,000"), "HUD에 장 목표 (%s)" % main.hud.goal_text)
	main.wallet.earn(main.chapter_type().target - main.wallet.money)
	await _frames(3)
	_expect(main.chapter == 2, "목표 금액을 모으면 2장 (%d)" % main.chapter)
	_expect(main.hud.banner_visible(), "새 장 화면이 뜬다")
	_expect(FileAccess.file_exists(SaveGame.slot_path(SAVE_PREFIX, SaveGame.AUTO_SLOT)), "장이 열리면 자동 저장")
	_expect(main.auto_line().begins_with("2장"), "자동 저장 칸 요약 (%s)" % main.auto_line())
	# 다리 통제가 풀려 차로 건널 수 있다
	var car: Vehicle = main.start_vehicle
	main.director.enter_immediately(car)
	car.place(LaneGraph.center(Vector2i(2, 0)) + Vector2(24, 60), 0.0)
	Input.action_press("accelerate")
	await _frames(150)
	Input.action_release("accelerate")
	_expect(car.global_position.y < LaneGraph.center(Vector2i(2, -1)).y, "2장: 다리를 건너 북쪽으로 간다 (y=%.0f)" % car.global_position.y)
	await _free(main)
	# 새 게임에서 자동 저장을 불러오면 2장이고, 1장에는 다리가 막혀 있다
	var main2 := _make_main()
	await _frames(2)
	var car2: Vehicle = main2.start_vehicle
	main2.director.enter_immediately(car2)
	car2.place(LaneGraph.center(Vector2i(2, 0)) + Vector2(24, 60), 0.0)
	Input.action_press("accelerate")
	await _frames(150)
	Input.action_release("accelerate")
	_expect(car2.global_position.y > LaneGraph.center(Vector2i(2, 0)).y - 120.0, "1장: 다리 바리케이드에 막힌다 (y=%.0f)" % car2.global_position.y)
	main2.director.exit_vehicle()
	_expect(main2.load_game(SaveGame.AUTO_SLOT) and main2.chapter == 2 and CityMap.chapter == 2, "자동 저장을 불러오면 2장")
	_expect(main2.city.locked_blocks.size() < locked_ch1, "불러온 장에 맞게 통제 구역이 줄어든다 (%d → %d)" % [locked_ch1, main2.city.locked_blocks.size()])
	# 마지막 장 목표 → 엔딩
	main2.set_chapter(CityMap.LAST_CHAPTER)
	main2.wallet.earn(main2.chapter_type().target)
	await _frames(3)
	_expect(main2.finished and main2.hud.goal_text.contains("엔딩"), "마지막 목표를 모으면 엔딩")
	await _free(main2)


## 더 이른 장의 세이브를 불러오면 통제 구역 안의 차·시민이 치워지고, 교통이 막다른 길에서 멈추지 않는다
func _test_chapter_back() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = 20
	main.bus_count = 0
	main.police_patrols = 0
	main.save_prefix = SAVE_PREFIX
	main.chapter = CityMap.LAST_CHAPTER
	add_child(main)
	main.player.global_position = LaneGraph.center(Vector2i(0, 2))   # 강남·공단 경계
	await _frames(60 * 20)
	main.set_chapter(1)
	await _frames(60 * 20)
	var closed := 0
	for ai: TrafficAI in main.traffic.ais:
		var p := ai.route[0]
		if not CityMap.is_open_node(p.from_cell) or not CityMap.is_open_node(p.to_cell):
			closed += 1
	var walkers := 0
	for p: Pedestrian in main.pedestrians.peds:
		if main.pedestrians.is_alive_civilian(p) and not CityMap.is_open_block(City.nearest_block(p.global_position)):
			walkers += 1
	_expect(closed == 0 and walkers == 0, "장을 되돌리면 통제 구역 안의 차·시민이 없다 (차 %d, 시민 %d)" % [closed, walkers])
	await _free(main)


# ── 은신처 ────────────────────────────────────────────────

func _test_hideouts() -> void:
	var main := _make_main(2)
	await _frames(2)
	var player: Player = main.player
	var camp: Hideout = main.hideout_by_id(&"riverside_camp")
	var gosiwon: Hideout = main.hideout_by_id(&"hongdae_gosiwon")
	var house: Hideout = main.hideout_by_id(&"outskirts_house")
	_expect(gosiwon.owned and not camp.owned, "고시원은 처음부터 내 것, 캠핑장은 산다")
	await _frames(2)
	_expect(gosiwon.visible and camp.visible and not house.visible, "2장: 변두리 은신처는 아직 안 보인다")
	var money: int = main.wallet.money
	player.global_position = camp.type.door
	await _frames(3)
	var menu: SaveMenu = main.save_menu
	_expect(menu.is_open() and menu.mode == SaveMenu.Mode.CONFIRM, "안 산 은신처를 밟으면 살지 묻는다")
	menu.choose(1)
	await _frames(1)
	_expect(camp.owned and main.wallet.money == money - camp.type.price, "산다 → ₩%d (지갑 %d)" % [camp.type.price, main.wallet.money])
	player.global_position = camp.type.door + Vector2(120, 0)
	await _frames(2)
	player.global_position = camp.type.door
	await _frames(3)
	_expect(menu.is_open() and menu.mode == SaveMenu.Mode.SAVE, "산 은신처를 밟으면 저장 메뉴")
	menu.choose(1)
	await _frames(1)
	var camp_door := camp.type.door
	await _free(main)
	var main2 := _make_main()
	await _frames(2)
	_expect(main2.load_game(1), "슬롯 1 불러오기")
	_expect(main2.hideout_by_id(&"riverside_camp").owned, "산 은신처는 저장된다")
	_expect(main2.player.global_position.distance_to(camp_door) < 60.0, "저장한 은신처에서 시작한다 (%s)" % main2.player.global_position)
	await _free(main2)


func _test_district_banner() -> void:
	var main := _make_main(2)
	await _frames(3)
	_expect(not main.hud.district_visible(), "시작할 때는 구역 이름을 띄우지 않는다")
	main.player.global_position = City.block_rect(1, -7).position + Vector2(-14, 100)
	await _frames(3)
	_expect(main.hud.district_visible() and main.hud._district.text == "종로 구도심", "종로에 들어서면 이름이 뜬다 (%s)" % main.hud._district.text)
	await _free(main)


## 아이는 차에 치이지도, 총에 맞지도 않는다
func _test_child() -> void:
	var main := _make_main()
	await _frames(2)
	var kid := Pedestrian.new()
	kid.setup(CHILD, main.pedestrians.rng, City.sidewalk_loop(Vector2i(2, 2)), 0, 0.5, 1)
	main.pedestrians.add(kid)
	main.pedestrians.damage(kid, 1000.0, Vector2.UP, true, true)
	await _frames(2)
	_expect(not kid.is_dead() and main.police.wanted.level == 0, "아이는 다치지 않는다")
	await _free(main)


# ── ★5 헬기 ───────────────────────────────────────────────

func _test_heli() -> void:
	var main := _make_main()
	await _frames(2)
	var police: PoliceDispatcher = main.police
	var player: Player = main.player
	_immortal(main)
	player.global_position = City.block_rect(1, 1).get_center()   # 드리프트 연습장 (탁 트인 곳)
	police.last_known = player.global_position
	police.wanted.raise_to(5)
	var lit := false
	var shots := [0]
	main.combat.gunfire.connect(func(_p, _b): pass)
	var hurt_before := player.health
	for f in 60 * 20:
		await _frames(1)
		police._arrest = 0.0
		player.revive()
		for h in police.helis:
			if h.lit(player.global_position):
				lit = true
				if police.seen:
					shots[0] += 1
		if lit and shots[0] > 30:
			break
	_expect(police.helis.size() == 1, "★5면 경찰 헬기 1대 (%d)" % police.helis.size())
	_expect(lit, "헬기 탐조등이 주인공을 잡는다")
	_expect(shots[0] > 0, "탐조등 안이면 경찰이 위치를 안다")
	var heli: PoliceHeli = police.helis[0]
	# 겨누기: 키보드 자동 조준이 헬기를 고르고, 커서를 헬기 그림(떠 있는 몸통)에 대면 그 헬기를 겨눈다
	heli.global_position = player.global_position + Vector2(0, -260)
	var ct := main.get_viewport().canvas_transform
	var body := ct * (heli.global_position + IsoView.lift(heli.altitude()))
	_expect(main.weapons.target(player.global_position, Vector2.UP, 600.0, null) == heli.global_position, "자동 조준이 경찰 헬기를 고른다")
	_expect(main.weapons.screen_point(player.global_position, body, ct) == heli.global_position, "커서를 헬기 그림에 대면 그 헬기를 겨눈다")
	# 위로 쏘는 총알이라 사이의 건물 벽에 막히지 않는다
	var wall := StaticBody2D.new()
	wall.collision_layer = Layers.WORLD
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	(shape.shape as RectangleShape2D).size = Vector2(300, 30)
	wall.add_child(shape)
	main.add_child(wall)
	var hp := heli.health
	for i in 3:
		wall.global_position = player.global_position.lerp(heli.global_position, 0.4)
		await _frames(2)
		var up := (heli.global_position - player.global_position).normalized()
		var ex: Array[RID] = [player.get_rid()]
		main.combat.fire(player.global_position + up * 10.0, up, PISTOL, true, ex)
		if heli.health < hp:
			break
	_expect(heli.health < hp, "사이에 벽이 있어도 경찰 헬기를 맞힌다 (체력 %.0f → %.0f)" % [hp, heli.health])
	wall.queue_free()
	# 권총으로 헬기를 떨어뜨린다
	player.arsenal.give(PISTOL, 60)
	var exploded := [0]
	for f in 60 * 15:
		if heli.down:
			break
		var dir := (heli.global_position - player.global_position).normalized()
		var ex: Array[RID] = [player.get_rid()]
		main.combat.fire(player.global_position + dir * 10.0, dir, PISTOL, true, ex)
		await _hold(main, 6)
	_expect(heli.down, "총에 맞아 헬기가 떨어진다 (체력 %.0f)" % heli.health)
	await _hold(main, 120)
	_expect(not is_instance_valid(heli), "떨어진 헬기는 땅에 부딪혀 없어진다")
	_expect(police.wanted.level == 6, "헬기를 떨어뜨리면 ★6 (%d)" % police.wanted.level)
	await _free(main)


# ── ★6 군 · ★4 검문소 ─────────────────────────────────────

func _test_army_and_checkpoint() -> void:
	var main := _make_main(2)
	await _frames(2)
	var police: PoliceDispatcher = main.police
	var player: Player = main.player
	_immortal(main)
	player.global_position = City.hq_door() + Vector2(0, -120)
	police.last_known = player.global_position
	police.wanted.raise_to(4)
	for f in 60 * 3:
		await _frames(1)
		police._arrest = 0.0
		player.revive()
	var checkpoints := police.roadblocks.filter(func(rb): return rb.checkpoint)
	_expect(not checkpoints.is_empty(), "★4: 가까운 다리 끝에 검문소 (%d곳)" % checkpoints.size())
	# 차단봉: 내려가 있을 때 달리는 차가 닿으면 부러진다 (그림만, 충돌 없음)
	if not checkpoints.is_empty():
		var cp: CheckpointVisual = checkpoints[0].visual
		cp.open = 0.0
		var car := Vehicle.new()
		car.stats = load("res://data/vehicles/car_sonato.tres")
		main.add_child(car)
		car.place(cp.pivot + cp.reach * CheckpointVisual.ARM_LENGTH * 0.6, Vector2.UP.angle_to(cp.dir))
		main.vehicles.append(car)
		car.motor.velocity = cp.dir * 300.0
		cp.check_hits()
		_expect(cp.broken, "검문소 차단봉: 달리는 차가 부딪치면 부러진다")
		main.vehicles.erase(car)
		car.queue_free()
	police.wanted.raise_to(6)
	var trucks := false
	var soldiers := 0
	for f in 60 * 60:
		await _frames(1)
		police._arrest = 0.0
		player.revive()
		trucks = trucks or police.army_count() > 0
		soldiers = 0
		for o in police.officers:
			if o.npc == PoliceDispatcher.SOLDIER_NPC:
				soldiers += 1
		if soldiers >= PoliceDispatcher.ARMY_CREW:
			break
	_expect(trucks, "★6: 군 트럭이 온다")
	_expect(soldiers >= PoliceDispatcher.ARMY_CREW, "군인 넷이 내린다 (%d)" % soldiers)
	_expect(police.helis.size() == 2, "★6: 헬기 2대 (%d)" % police.helis.size())
	_expect(police.helis.any(func(h: PoliceHeli): return h.stats == PoliceDispatcher.ARMY_HELI_TYPE), "★6: 헬기 한 대는 군 기동헬기")
	_expect(police.helis.any(func(h: PoliceHeli): return h.stats == PoliceHeli.POLICE_TYPE), "★6: 경찰 헬기도 남는다")
	await _free(main)


# ── 무기 ──────────────────────────────────────────────────

func _civ(main: Node2D, pos: Vector2) -> Pedestrian:
	var p := Pedestrian.new()
	p.setup(CIV, main.pedestrians.rng, City.sidewalk_loop(City.nearest_block(pos)), 0, 0.0, 1)
	p.position = pos
	main.pedestrians.add(p)
	p._set_state(Pedestrian.State.IDLE, 999.0)   # 제자리에 서 있게
	return p


func _park(main: Node2D, pos: Vector2) -> Vehicle:
	var v := Vehicle.new()
	v.stats = SEDAN
	main.add_child(v)
	v.place(pos, 0.0)
	main.vehicles.append(v)
	return v


func _test_weapons() -> void:
	var main := _make_main()
	await _frames(2)
	_immortal(main)
	var combat: Combat = main.combat
	var player: Player = main.player
	var lot := City.block_rect(City.PLAZA.x, City.PLAZA.y).grow(-60)   # 탁 트인 주차장
	var o := lot.position + Vector2(40, 60)
	player.global_position = o + Vector2(-300, 0)
	var ex: Array[RID] = [player.get_rid()]
	# 소총: 줄 선 둘을 한 발로
	var a := _civ(main, o + Vector2(150, 450))
	var b := _civ(main, o + Vector2(190, 450))
	a.health = 10.0
	b.health = 10.0
	await _frames(1)   # 새로 세운 사람의 충돌체가 물리 서버에 올라가게
	combat.fire(o + Vector2(0, 450), Vector2.RIGHT, load(W + "rifle.tres"), true, ex)
	await _frames(1)
	_expect(a.is_dead() and b.is_dead(), "소총은 둘을 꿰뚫는다 (%s %s)" % [a.is_dead(), b.is_dead()])
	# 수류탄: 날아가 멈췄다가 터진다
	var target := _civ(main, o + Vector2(200, 0))
	combat.fire(o, Vector2.RIGHT, load(W + "grenade.tres"), true, ex)
	await _frames(30)
	_expect(not target.is_dead() and combat._projectiles.size() == 1, "수류탄은 바로 안 터진다")
	await _frames(90)
	_expect(target.is_dead() and combat._projectiles.is_empty(), "수류탄이 터져 근처 사람이 죽는다")
	# 화염병: 떨어진 곳에 불 (사람은 불을 보면 도망치니 세워 둔 차로 본다)
	var burn := _park(main, o + Vector2(300, 120))
	combat.fire(o + Vector2(0, 120), Vector2.RIGHT, load(W + "molotov.tres"), true, ex)
	await _frames(90)
	_expect(main.fires.fires.size() >= 1, "화염병이 불을 놓는다 (%d)" % main.fires.fires.size())
	await _frames(120)
	_expect(burn.health < SEDAN.durability, "불 속 차는 탄다 (%.0f)" % burn.health)
	# 물대포로 불을 끈다
	var water: WeaponType = load(W + "water_cannon.tres")
	var fire_pos: Vector2 = main.fires.fires[0].pos
	for i in 40:
		combat.fire(fire_pos - Vector2(150, 0), Vector2.RIGHT, water, true, ex)
		await _frames(2)
	_expect(not main.fires.burning_at(fire_pos), "물대포가 불을 끈다")
	var wet := _civ(main, o + Vector2(100, 240))
	combat.fire(o + Vector2(0, 240), Vector2.RIGHT, water, true, ex)
	await _frames(1)
	_expect(wet.state == Pedestrian.State.KNOCKED and not wet.is_dead(), "물대포는 사람을 넘어뜨리지만 다치게 하진 않는다")
	# 로켓: 차를 날린다
	var car := _park(main, o + Vector2(400, 360))
	combat.fire(o + Vector2(0, 360), Vector2.RIGHT, load(W + "rocket.tres"), true, ex)
	await _frames(60)
	_expect(car.burning >= 0.0 or car.wrecked, "로켓 한 방에 차가 불탄다")
	# 화염방사기: 한 번 맞은 사람은 도망치므로, 차가 타는지와 사람이 다치는지 따로 본다
	var flamed := _civ(main, o + Vector2(400, 40))
	var torched := _park(main, o + Vector2(400, 80))
	for i in 20:
		combat.fire(o + Vector2(300, 60), Vector2.RIGHT, load(W + "flamethrower.tres"), true, ex)
		await _frames(2)
	_expect(flamed.health < CIV.health, "화염방사기에 사람이 다친다 (%.0f)" % flamed.health)
	_expect(torched.health < SEDAN.durability * 0.6, "화염방사기에 차가 탄다 (%.0f)" % torched.health)
	# 방망이: 한 번 얻으면 계속
	var bat: WeaponType = load(W + "bat.tres")
	player.arsenal.give(bat, 0)
	_expect(player.arsenal.has(bat) and player.arsenal.ammo_of(bat) == -1, "방망이는 탄 없이 계속 쓴다")
	# 차량 기관총: 도보로는 못 쏘고, 차에서는 앞으로
	var mg: WeaponType = load(W + "car_mg.tres")
	player.arsenal.give(mg, 100)
	while player.arsenal.current() != mg:
		player.arsenal.cycle(1)
	# 주차장 안에서 (바로 밑 가로 2번 도로는 고가 상판이라 층이 달라 주차장 사람을 못 맞힌다)
	player.global_position = o + Vector2(0, 380)
	player.arsenal.cooldown = 0.0
	_expect(not main.weapons.shoot(), "차량 기관총은 도보로 못 쏜다")
	var mine := _park(main, o + Vector2(0, 380))
	main.director.enter_immediately(mine)
	var front := _civ(main, mine.global_position + Vector2(0, -160))
	for i in 10:
		player.arsenal.cooldown = 0.0
		main.weapons.shoot()
		await _frames(1)
	_expect(front.is_dead() or front.health < CIV.health, "차량 기관총은 앞으로 쏜다")
	main.director.exit_vehicle()
	# 쓰러진 군인은 소총을 떨어뜨린다
	var crates: int = main.pickups.crates.size()
	var soldier := Pedestrian.new()
	soldier.setup(SOLDIER, main.pedestrians.rng, City.sidewalk_loop(Vector2i(1, 1)), 0, 0.0, 1)
	main.pedestrians.add(soldier)
	main.pedestrians.damage(soldier, 1000.0, Vector2.UP, true, false)
	await _frames(1)
	_expect(main.pickups.crates.size() == crates + 1 and main.pickups.crates[-1].weapon.id == &"RIFLE", "군인이 소총을 떨어뜨린다")
	await _free(main)


## 불이 오래 타면 소방차가 와서 끈다
func _test_fire_department() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = 6
	main.bus_count = 0
	main.police_patrols = 0
	main.save_prefix = SAVE_PREFIX
	add_child(main)
	await _frames(2)
	var fires: Fires = main.fires
	var spot := LaneGraph.center(Vector2i(3, 2)) + Vector2(0, 260)
	main.player.global_position = spot + Vector2(0, 400)
	var out := false
	var arrived := false
	for f in 60 * 60:
		if f % 60 == 0 and not out:
			fires.start(spot, 40.0, false, 6.0)   # 계속 타게 다시 붙인다 (끄러 오는지 본다)
		await _frames(1)
		var t := fires.truck
		arrived = arrived or (t != null and is_instance_valid(t) and t.global_position.distance_to(spot) < Fires.SPRAY_RANGE)
		if arrived and f % 60 == 59:
			out = true
		if out and fires.fires.is_empty():
			break
	_expect(fires.dispatches >= 1, "불이 나면 소방차가 출동한다")
	_expect(arrived, "소방차가 불 앞까지 온다")
	_expect(fires.fires.is_empty(), "소방차가 불을 끈다 (남은 불 %d)" % fires.fires.size())
	await _free(main)


# ── 부업 ──────────────────────────────────────────────────

func _vehicle_of(main: Node2D, path: String, pos: Vector2) -> Vehicle:
	var v := Vehicle.new()
	v.stats = load(path)
	main.add_child(v)
	v.place(pos, 0.0)
	main.vehicles.append(v)
	return v


## 미션 테스트처럼 지금 차를 목표에 세운다
func _arrive(main: Node2D, at: Vector2) -> void:
	var v: Vehicle = main.director.current_vehicle
	v.global_position = at
	v.motor.velocity = Vector2.ZERO
	await _frames(3)


func _test_side_jobs() -> void:
	var main := _make_main(2)
	await _frames(2)
	_immortal(main)
	var jobs: SideJobs = main.jobs
	var wallet: Wallet = main.wallet
	var start := City.curb_vertical(3, 3, 0.3)
	# 택시: 손님 태우고 내려 주기
	var taxi := _vehicle_of(main, "res://data/vehicles/car_taxi.tres", start)
	main.director.enter_immediately(taxi)
	await _frames(2)
	_expect(jobs.available() != null and jobs.available().id == &"taxi", "택시에 타면 택시 부업을 할 수 있다")
	jobs.start(jobs.available())
	await _frames(2)
	_expect(jobs.active() and jobs.passenger != null, "손님이 기다린다")
	var money := wallet.money
	await _arrive(main, jobs.goal)
	_expect(jobs.stage == 1 and jobs.passenger == null, "손님을 태웠다")
	await _arrive(main, jobs.goal)
	_expect(jobs.level == 1 and wallet.money == money + jobs.job.reward(0), "내려 주면 보상 (₩%d)" % (wallet.money - money))
	main.director.exit_vehicle()
	await _frames(int(SideJobs.OUT_OF_CAR * 60) + 10)
	_expect(not jobs.active() and jobs.best.get(&"taxi", 0) == 1, "차에서 오래 내리면 교대가 끝난다 (최고 1단계)")
	# 버스: 10단계를 다 끝내면 보너스 — 버스 체력 +50%
	var bus := _vehicle_of(main, "res://data/vehicles/bus_city.tres", start + Vector2(0, 200))
	main.director.enter_immediately(bus)
	await _frames(2)
	jobs.start(jobs.available())
	for n in 10:
		for stop in jobs.job.stops:
			await _arrive(main, jobs.goal)
	_expect(not jobs.active() and jobs.has_bonus(&"bus"), "버스 10단계 → 보너스")
	var bus2 := _vehicle_of(main, "res://data/vehicles/bus_city.tres", start + Vector2(0, 400))
	_expect(is_equal_approx(bus2.health, bus2.stats.durability * 1.5), "보너스: 버스 체력 +50%% (%.0f)" % bus2.health)
	main.director.exit_vehicle()
	# 자경단: 수배를 풀고 범인 차를 부숴라
	var cop := _vehicle_of(main, "res://data/vehicles/police_patrol.tres", start + Vector2(0, -300))
	main.director.enter_immediately(cop)
	main.police.wanted.raise_to(WantedSystem.LOCK_LEVEL)
	_expect(jobs.available() == null, "★5부터는 자경단 등록으로도 수배를 못 푼다")
	main.police.wanted.clear()
	main.police.wanted.raise_to(2)
	await _frames(2)
	jobs.start(jobs.available())
	_expect(main.police.wanted.level == 0 and jobs.target != null, "자경단: 수배가 풀리고 범인 차가 나온다")
	jobs.target.take_damage(1000.0, true, 0.1)
	await _frames(20)
	_expect(jobs.level == 1, "범인 차를 부수면 단계를 넘긴다")
	jobs.end("테스트")
	main.director.exit_vehicle()
	# 소방: 소방차 물대포로 끈다
	var truck := _vehicle_of(main, "res://data/vehicles/sp_fire.tres", start + Vector2(0, 600))
	main.director.enter_immediately(truck)
	await _frames(2)
	jobs.start(jobs.available())
	var fire_at := jobs.goal
	_expect(main.fires.burning_at(fire_at), "소방: 불이 난다")
	# 불이 있는 도로를 따라 뒤쪽에 불을 바라보고 세운다
	var lane: LanePiece = main.traffic.graph.nearest_segment(fire_at, Vector2.ZERO)
	var along: Vector2 = lane.tangent_at(lane.project(fire_at).x)
	truck.place(fire_at - along * 170.0, Vector2.UP.angle_to(along))
	await _frames(2)
	for i in 120:
		Input.action_press("fire")
		await _frames(1)
	Input.action_release("fire")
	await _frames(2)
	_expect(jobs.level == 1, "소방차 물대포로 불을 끄면 단계를 넘긴다 (불 %s)" % main.fires.burning_at(fire_at))
	jobs.end("테스트")
	main.director.exit_vehicle()
	# 저장하면 부업 기록·보너스가 남는다
	_expect(main.save_game(2), "저장")
	await _free(main)
	var main2 := _make_main()
	await _frames(2)
	main2.load_game(2)
	_expect(main2.jobs.has_bonus(&"bus") and main2.jobs.best.get(&"taxi", 0) == 1, "부업 기록·보너스를 불러온다")
	await _free(main2)
	Vehicle.durability_bonus = {}


func _test_day_night() -> void:
	_expect(DayNight.tint(0.0) != DayNight.tint(12.0), "밤과 낮 색이 다르다")
	_expect(DayNight.is_night(21.0) and not DayNight.is_night(12.0), "21시는 밤, 12시는 낮")
	var dj: NpcType = load("res://data/npc/dj.tres")
	_expect(PedestrianManager.in_hours(dj.hours, 23.0) and not PedestrianManager.in_hours(dj.hours, 12.0), "DJ는 밤에만 나온다")
	var main := _make_main()
	var sky: DayNight = main.sky
	sky.paused_clock = true
	sky.set_raining(true)
	sky.rain = 1.0
	sky._apply()
	_expect(VehicleMotor.road_grip < 1.0, "비가 오면 노면이 미끄럽다 (%.2f)" % VehicleMotor.road_grip)
	main.free()
	VehicleMotor.road_grip = 1.0


func _remove_saves() -> void:
	for slot in [1, 2, 3, SaveGame.AUTO_SLOT]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.slot_path(SAVE_PREFIX, slot)))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
