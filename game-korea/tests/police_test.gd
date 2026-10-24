extends Node
## M3 완료 기준 검증.
##  1. 수배 계산: 범죄가 별을 올리고, 시야 밖에서 버티면 별이 내려간다.
##  2. 경찰이 본 범죄만 수배가 된다.
##  3. 경찰차가 도시 반대편에서 길을 찾아와 멈춰 선 주인공을 체포한다 → 벌금, 경찰서 재시작.
##  4. 도보 경찰: 달리면 따돌리고 걸으면 잡힌다.
##  5. 숨어 있으면 별이 내려가 0이 되고 경찰이 순찰로 돌아간다.
##  6. ★3 도로 봉쇄: 진행 방향 앞에 경찰차 두 대가 가로막고 한쪽에 좁은 틈이 있다.
##  7. ★3 도주(자동 운전 봇, 시드 여러 개): 3분을 버티는 판이 있지만, 절반 넘게는 잡힌다(차가 부서져 죽는 판도 잡힌 것으로 센다).
## 실행: godot --headless --fixed-fps 60 --path . res://tests/police_test.tscn [-- --seed=N]
## (--seed를 주면 도주 테스트도 그 시드 하나만 돌린다)

const SPORT := preload("res://data/vehicles/car_avela_r.tres")
const ESCAPE_SEEDS: Array[int] = [4242, 1, 7, 99, 2026, 31337]
const ESCAPE_TIME := 180.0

var _failures: Array[String] = []
var _seed := TrafficSystem.SEED
var _seed_given := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = arg.get_slice("=", 1).to_int()
			_seed_given = true
	_test_wanted_logic()
	await _test_witness()
	await _test_pursuit_and_bust()
	await _test_foot_chase()
	await _test_lose_stars()
	await _test_roadblock()
	await _test_escapes()
	if _failures.is_empty():
		print("police_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _make_main(cars: int, buses: int, patrols: int, seed := _seed) -> Node2D:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = cars
	main.bus_count = buses
	main.police_patrols = patrols
	main.traffic_seed = seed
	add_child(main)
	return main


func _free(main: Node2D) -> void:
	for a in ["accelerate", "brake", "steer_left", "steer_right", "handbrake", "sprint"]:
		Input.action_release(a)
	main.queue_free()
	await _frames(2)


func _test_wanted_logic() -> void:
	var w := WantedSystem.new()
	w.report(WantedSystem.Crime.CAR_THEFT)
	_expect(w.level == 1, "차량 탈취 → ★1 (%d)" % w.level)
	w.report(WantedSystem.Crime.HIT_OFFICER)
	_expect(w.level == 2, "경찰관을 치면 → ★2 (%d)" % w.level)
	w.update(13.0, false)
	_expect(w.level == 2, "★2는 14초 전엔 안 내려간다")
	w.update(1.5, false)
	_expect(w.level == 1, "시야 밖 14초 → ★1 (%d)" % w.level)
	w.update(9.0, false)
	w.update(1.0, true)
	w.update(9.0, false)
	_expect(w.level == 1, "다시 눈에 띄면 시간이 처음부터")
	w.update(1.5, false)
	_expect(w.level == 0, "시야 밖 10초 → ★0 (%d)" % w.level)
	w.report(WantedSystem.Crime.CAR_THEFT)
	for i in 80:
		w.update(1.0, true)
	_expect(w.level == 2, "눈에 띈 채 80초 도망치면 ★2 (%d)" % w.level)
	for i in 10:
		w.report(WantedSystem.Crime.HIT_OFFICER)
	_expect(w.level == WantedSystem.HEAT_LEVEL_CAP, "살인이 아니면 별은 ★%d까지 (%d)" % [WantedSystem.HEAT_LEVEL_CAP, w.level])
	for i in 300:
		w.update(1.0, true)
	_expect(w.level == WantedSystem.HEAT_LEVEL_CAP, "오래 쫓겨도 ★%d에서 멈춘다" % WantedSystem.HEAT_LEVEL_CAP)
	w.report(WantedSystem.Crime.KILL_OFFICER)
	_expect(w.level == 4, "열기가 쌓인 채 경찰을 죽이면 ★4 (%d)" % w.level)
	for i in 10:
		w.report(WantedSystem.Crime.KILL_OFFICER)
	_expect(w.level == 4, "경찰을 더 죽여도 ★4에서 멈춘다 — ★5는 특공대 사상부터 (%d)" % w.level)
	w.update(600.0, false)
	_expect(w.level == 4, "★4는 숨어 있어도 내려가지 않는다")
	w.lower(2)
	_expect(w.level == 2, "도색하면 별 둘이 떨어진다 (%d)" % w.level)
	# ★5~6: 특공대원 살해 → 헬기, 그 뒤 군인 살해·헬기 격추 → 군
	var hard := WantedSystem.new()
	hard.report(WantedSystem.Crime.KILL_SWAT)
	_expect(hard.level == 4, "특공대원 하나를 죽이면 ★4 (%d)" % hard.level)
	for i in 4:
		hard.report(WantedSystem.Crime.KILL_SWAT)
	_expect(hard.level == 5, "특공대원을 여럿 죽이면 ★5 (%d)" % hard.level)
	for i in 10:
		hard.report(WantedSystem.Crime.KILL_SWAT)
	_expect(hard.level == 5, "특공대원만으로는 ★5에서 멈춘다 (%d)" % hard.level)
	hard.report(WantedSystem.Crime.DOWN_HELI)
	_expect(hard.level == WantedSystem.MAX_LEVEL, "헬기를 떨어뜨리면 ★%d (%d)" % [WantedSystem.MAX_LEVEL, hard.level])
	hard.update(600.0, false)
	_expect(hard.level == WantedSystem.MAX_LEVEL, "★6은 숨어 있어도 내려가지 않는다")
	hard.lower(2)
	_expect(hard.level == WantedSystem.MAX_LEVEL and hard.locked(), "★6은 도색·보상으로도 안 떨어진다 (%d)" % hard.level)
	var five := WantedSystem.new()
	five.raise_to(WantedSystem.LOCK_LEVEL)
	five.update(600.0, false)
	five.lower(1)
	_expect(five.level == 5 and five.locked(), "★5부터는 별이 떨어지지 않는다 (%d)" % five.level)
	five.clear()
	_expect(five.level == 0 and not five.locked(), "체포·기절(clear)이면 풀린다")


## 경찰이 없으면 차를 빼앗아도 수배가 없고, 순찰차가 보고 있으면 ★1
func _test_witness() -> void:
	var main := _make_main(0, 0, 0)
	await _frames(1)
	var police: PoliceDispatcher = main.police
	var target: Vehicle = main.vehicles[1]    # 운전자가 타고 있는 주차 차
	_expect(target.has_driver, "탈취 대상에 운전자가 있다")
	main.director.enter_immediately(target)
	await _frames(5)
	_expect(police.wanted.level == 0, "경찰이 못 보면 수배 없음 (%d)" % police.wanted.level)
	await _free(main)

	main = _make_main(0, 0, 0)
	await _frames(1)
	police = main.police
	target = main.vehicles[1]
	var piece: LanePiece = main.traffic.graph.segment(Vector2i(3, 4), 0)   # 같은 도로 북행
	var patrol: Vehicle = main.traffic.spawn_at(PoliceDispatcher.POLICE_TYPE, piece, piece.length - 260.0)
	police._register(patrol)
	await _frames(1)
	_expect(police.sees(target.global_position), "순찰차가 주인공 쪽을 본다")
	main.director.enter_immediately(target)
	await _frames(5)
	_expect(police.wanted.level == 1, "순찰차 앞에서 탈취 → ★1 (%d)" % police.wanted.level)
	await _frames(90)
	_expect(patrol.pursuit != null and patrol.siren, "본 순찰차가 사이렌을 켜고 추격한다")
	await _free(main)


## 차에 탄 채 서 있으면 경찰차가 길을 찾아와 세우고, 경찰이 내려 끌어낸다
func _test_pursuit_and_bust() -> void:
	var main := _make_main(0, 0, 0)
	await _frames(1)
	var police: PoliceDispatcher = main.police
	var car: Vehicle = main.start_vehicle
	main.director.enter_immediately(car)
	police.last_known = car.global_position
	police.wanted.report(WantedSystem.Crime.CAR_THEFT)
	var busted := [-1]
	police.busted.connect(func(fine): busted[0] = fine)
	var reach_time := -1.0
	var start_money: int = main.wallet.money
	for f in 60 * 60:
		await _frames(1)
		if reach_time < 0.0:
			for c in police.cars:
				if c.global_position.distance_to(car.global_position) < 250.0:
					reach_time = f / 60.0
		if busted[0] >= 0:
			break
	print("  경찰 도착 %.1f초, 체포 %s" % [reach_time, busted[0] >= 0])
	_expect(reach_time > 0.0 and reach_time < 25.0, "경찰차가 25초 안에 찾아온다 (%.1f초)" % reach_time)
	_expect(busted[0] == PoliceDispatcher.FINE_PER_STAR, "서 있으면 체포된다 (벌금 %d)" % busted[0])
	await _frames(int(main.BUST_DELAY * 60) + 10)
	_expect(main.wallet.money == start_money - PoliceDispatcher.FINE_PER_STAR, "벌금을 낸다")
	_expect(main.director.current_vehicle == null, "체포되면 도보")
	_expect(main.player.global_position.distance_to(City.police_station_position()) < 5.0, "경찰서 앞에서 다시 시작")
	_expect(police.wanted.level == 0 and police.officers.is_empty() and police.pursuer_count() == 0, "체포 후 수배·추격 해제")
	_expect(main.player.input_enabled, "다시 움직일 수 있다")
	await _free(main)


## 도보 경찰(172px/s)은 달리는 주인공(190)은 못 잡고, 걷는 주인공(110)은 잡는다
func _test_foot_chase() -> void:
	var main := _make_main(0, 0, 0)
	await _frames(1)
	var police: PoliceDispatcher = main.police
	police.wanted.report(WantedSystem.Crime.CAR_THEFT)
	var player: Player = main.player
	var cop := police._spawn_officer(player.global_position + Vector2(0, -150), null, PoliceOfficer.Duty.CHASE)
	var busted := [false]
	police.busted.connect(func(_f): busted[0] = true)
	player.screen_walk = false       # 2.5D 화면 방향이 아니라 월드 남쪽으로 걷는다
	Input.action_press("brake")      # 도보에서는 아래로
	Input.action_press("sprint")
	await _frames(6 * 60)
	var gap := cop.global_position.distance_to(player.global_position)
	_expect(not busted[0], "달리면 도보 경찰을 따돌린다")
	_expect(gap > 200.0, "달리는 동안 거리가 벌어진다 (%.0f)" % gap)
	Input.action_release("sprint")
	var caught_at := -1.0
	var hits := 0
	var hp := player.health
	for f in 20 * 60:
		await _frames(1)
		if caught_at < 0.0 and police.officers.any(func(o): return o.global_position.distance_to(player.global_position) < PoliceDispatcher.BEAT_RANGE):
			caught_at = f / 60.0
		if player.health < hp:
			hits += 1
			if OS.get_environment("POLICE_DEBUG") != "":
				print("    매 t=%.2f 체력 %.0f 경찰 %d명" % [f / 60.0, player.health, police.officers.size()])
		hp = player.health
		if busted[0]:
			print("  걸어서 잡힘: 손 닿음 %.1f초, 체포 %.1f초, 매 %d대, 체력 %.0f" % [caught_at, f / 60.0, hits, player.health])
			break
	_expect(busted[0], "걸으면 잡힌다")
	_expect(hits >= 3 and player.knocked_down, "바로 잡히지 않고 곤봉에 몇 대 맞아 쓰러진 뒤 체포된다 (%d대)" % hits)
	await _free(main)


## 경찰이 못 보는 곳에 있으면 별이 내려가 0이 되고, 추격차는 순찰로 돌아간다
func _test_lose_stars() -> void:
	var main := _make_main(0, 0, 0)
	await _frames(1)
	var police: PoliceDispatcher = main.police
	police.last_known = LaneGraph.center(Vector2i(6, 6))     # 경찰은 엉뚱한 곳을 뒤진다
	police.wanted.report(WantedSystem.Crime.CAR_THEFT)
	var seen_frames := 0
	var cleared := -1.0
	for f in 40 * 60:
		await _frames(1)
		if police.seen:
			seen_frames += 1
		if police.wanted.level == 0:
			cleared = f / 60.0
			break
	_expect(cleared > 0.0 and cleared < 30.0, "숨어 있으면 별이 사라진다 (%.1f초, 들킨 프레임 %d)" % [cleared, seen_frames])
	await _frames(30)
	_expect(police.pursuer_count() == 0, "수배가 풀리면 추격을 멈춘다 (%d대)" % police.pursuer_count())
	await _free(main)


func _test_roadblock() -> void:
	var main := _make_main(0, 0, 0)
	await _frames(1)
	var police: PoliceDispatcher = main.police
	var from := Vector2(City.road_center(1) + 200.0, City.road_center(3) + 40.0)   # 가로 도로 3번을 동쪽으로
	main.player.global_position = from
	main.camera.snap()
	await _frames(1)
	_expect(police.place_roadblock(from, Vector2(600, 0)), "도로 봉쇄를 세운다")
	_expect(police.roadblocks.size() == 1, "봉쇄 1곳")
	if police.roadblocks.size() == 1:
		var rb: Dictionary = police.roadblocks[0]
		var ys: Array[float] = []
		for car: Vehicle in rb.cars:
			_expect(car.global_position.x > from.x + PoliceDispatcher.ROADBLOCK_MIN_AHEAD - 1.0, "주인공 앞쪽에 선다")
			_expect(absf(car.global_position.y - City.road_center(3)) < City.ROAD * 0.5, "도로 위에 선다")
			_expect(absf(car.motor.forward().dot(Vector2.DOWN)) > 0.99, "도로를 가로질러 선다")
			ys.append(car.global_position.y - City.road_center(3))
		ys.sort()
		var half := PoliceDispatcher.POLICE_TYPE.size.y * 0.5
		var gaps := [ys[0] - half + City.ROAD * 0.5, City.ROAD * 0.5 - (ys[1] + half)]
		var gap: float = maxf(gaps[0], gaps[1])
		print("  봉쇄 틈 %.0fpx (차 폭 %.0f)" % [gap, SPORT.size.x])
		_expect(gap > SPORT.size.x + 16.0 and gap < 80.0, "한쪽에 좁은 틈 (%.0fpx)" % gap)
	await _free(main)


## ★3 도주: "가능하되 쉽지 않다" — 시드마다 봇이 한 판씩 도망친다. 3분 버티는 판이 있어야 하고, 절반 넘게는 잡혀야 한다.
func _test_escapes() -> void:
	var seeds: Array[int] = ESCAPE_SEEDS
	if _seed_given:
		seeds = [_seed]
	var survived := 0
	for seed in seeds:
		if await _escape(seed) < 0.0:
			survived += 1
	var caught := seeds.size() - survived
	print("  ★3 도주 %d판: 3분 생존 %d, 체포 %d" % [seeds.size(), survived, caught])
	if not _seed_given:
		_expect(survived >= 1, "★3에서 3분 이상 도주할 수 있다 (생존 %d판)" % survived)
		_expect(caught * 2 >= seeds.size(), "쉽지 않다: 절반 이상은 잡힌다 (체포 %d판)" % caught)


## 자동 운전 봇이 ★3에서 스포츠카로 도망친다. 잡히거나 죽은 시각(초)을, 3분 버티면 -1을 돌려준다.
func _escape(seed: int) -> float:
	var main := _make_main(20, 2, PoliceDispatcher.PATROL_COUNT, seed)
	await _frames(1)
	var police: PoliceDispatcher = main.police
	var car: Vehicle = main.start_vehicle
	car.apply_stats(SPORT)
	main.director.enter_immediately(car)
	police.last_known = car.global_position
	for i in 3:
		police.wanted.report(WantedSystem.Crime.HIT_OFFICER)
	var bot := PursuitAI.new(car, main.vehicles)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	bot.target = _far_goal(car, police, rng)
	var busted := [-1.0]
	var frame := [0]
	police.busted.connect(func(_f):
		busted[0] = frame[0] / 60.0
		if OS.get_environment("POLICE_DEBUG") != "":
			for o in police.officers:
				print("    경찰 duty=%d pos=%s car=%s" % [o.duty, o.global_position.round(), o.car])
			for rb in police.roadblocks:
				for c: Vehicle in rb.cars:
					print("    봉쇄차 %s" % c.global_position.round())
			for c in police.cars:
				print("    경찰차 %s spd=%.0f pursuit=%s ai=%s driver=%s" % [c.global_position.round(), c.speed(), c.pursuit != null, c.ai != null, c.has_driver]))
	var died := [-1.0]
	main.player.died.connect(func(): died[0] = frame[0] / 60.0)
	var hits := [0]
	car.bumped.connect(func(o: Vehicle, _s): if police.owns(o): hits[0] += 1)
	var dodged := {}      # 이미 보고 길을 바꾼 도로 봉쇄 (봉쇄 차 → true)
	var seen := 0
	var level3 := 0
	var close := 0
	var total := int(ESCAPE_TIME * 60)
	for f in total:
		frame[0] = f
		await get_tree().physics_frame
		if busted[0] >= 0.0 or died[0] >= 0.0:
			break
		var rb_ahead := _roadblock_ahead(car, police)
		if rb_ahead and not dodged.has(rb_ahead):
			dodged[rb_ahead] = true
			bot.target = _side_goal(car, rng)
		elif car.global_position.distance_to(bot.target) < 900.0:   # 도착 전에 다음 목적지를 정해야 미리 감속해 꺾는다
			bot.target = _far_goal(car, police, rng)
		_drive_with_input(bot)
		if OS.get_environment("POLICE_DEBUG") != "" and f % 30 == 0:
			var near := INF
			for c in police.cars:
				near = minf(near, c.global_position.distance_to(car.global_position))
			print("  t=%.1f pos=%s spd=%.0f thr=%.2f st=%.2f wp=%s direct=%s 경찰 %.0f 도보 %d 체포 %.2f" % [f / 60.0, car.global_position.round(), car.speed(), car.throttle_input, car.steer_input, bot.waypoint, bot.direct, near, police.officers.size(), police._arrest])
		if police.seen:
			seen += 1
		if police.wanted.level == 3:
			level3 += 1
		for c in police.cars:
			if c.pursuit and c.global_position.distance_to(car.global_position) < 300.0:
				close += 1
				break
	var frames: int = frame[0] + 1
	var result := "3분 생존"
	if busted[0] >= 0.0:
		result = "체포 %.0f초" % busted[0]
	elif died[0] >= 0.0:
		result = "차 폭발로 사망 %.0f초" % died[0]
	print("  시드 %d ★3 도주: %s, 차 체력 %.0f, 경찰 시야 안 %.0f%%, ★3 유지 %.0f%%, 300px 안 추격 %.0f%%, 경찰차와 충돌 %d회, 도로 봉쇄 %d곳, 마지막 별 %d" % [
		seed, result, car.health,
		100.0 * seen / frames, 100.0 * level3 / frames, 100.0 * close / frames, hits[0], police.roadblocks_placed, police.wanted.level])
	_expect(busted[0] >= 0.0 or died[0] >= 0.0 or seen > 0, "시드 %d: 도주 중 경찰이 한 번은 따라붙는다" % seed)
	await _free(main)
	return busted[0] if busted[0] >= 0.0 else died[0]


## 도로 봉쇄를 봤다: 바로 앞 교차로에서 옆으로 꺾어 세 블록 가는 곳
func _side_goal(car: Vehicle, rng: RandomNumberGenerator) -> Vector2:
	var pos := car.global_position
	var forward := car.motor.forward()
	var ahead := RoadNav.cell_at(pos)
	for e in RoadNav.road_ends(pos):
		if (LaneGraph.center(e) - pos).dot(forward) > 0.0:
			ahead = e
	var sides: Array[int] = []
	for d in 4:
		if absf(Vector2(LaneGraph.STEPS[d]).dot(forward)) < 0.5 and LaneGraph.connected(ahead, d):
			sides.append(d)
	if sides.is_empty():
		return LaneGraph.center(ahead)
	var side := sides[rng.randi() % sides.size()]
	var goal := ahead
	for k in 3:
		if LaneGraph.connected(goal, side):
			goal += LaneGraph.STEPS[side]
	return LaneGraph.center(goal)


## 도망칠 곳: 먼 교차로 중 달리던 방향 쪽이고 경찰차가 적은 곳 (사람이 할 법한 선택)
func _far_goal(car: Vehicle, police: PoliceDispatcher, rng: RandomNumberGenerator) -> Vector2:
	var from := car.global_position
	var best := LaneGraph.center(Vector2i(0, 0))
	var best_score := -INF
	for attempt in 12:
		var c := LaneGraph.center(Vector2i(rng.randi_range(0, 6), rng.randi_range(0, 6)))
		if c.distance_to(from) < 1500.0:
			continue
		var score := (c - from).normalized().dot(car.motor.forward()) * 2.0
		for p in police.cars:
			if p.pursuit:
				score -= 600.0 / maxf(p.global_position.distance_to(c), 300.0)
		if score > best_score:
			best_score = score
			best = c
	return best


## 앞쪽 1000px 안에 보이는 도로 봉쇄의 차 하나 (없으면 null). 사람이라면 보고 길을 바꾼다.
func _roadblock_ahead(car: Vehicle, police: PoliceDispatcher) -> Vehicle:
	for rb in police.roadblocks:
		for c in rb.cars:
			if not is_instance_valid(c):
				continue
			var to: Vector2 = c.global_position - car.global_position
			if to.length() < 1000.0 and to.normalized().dot(car.motor.forward()) > 0.8:
				return rb.cars.filter(is_instance_valid)[0]
	return null


## 봇이 정한 입력을 실제 키 입력으로 넣는다 (차는 controlled 상태라 Input만 읽는다)
func _drive_with_input(bot: PursuitAI) -> void:
	bot.drive(1.0 / 60.0)
	var v := bot.vehicle
	_set_action("accelerate", maxf(v.throttle_input, 0.0))
	_set_action("brake", maxf(-v.throttle_input, 0.0))
	_set_action("steer_right", maxf(v.steer_input, 0.0))
	_set_action("steer_left", maxf(-v.steer_input, 0.0))
	_set_action("handbrake", 1.0 if v.handbrake_input else 0.0)


func _set_action(action: String, strength: float) -> void:
	if strength > 0.01:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
