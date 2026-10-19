extends Node
## M2 완료 기준 검증.
##  1. 빨간불이면 정지선 앞에 서고, 초록불이 되면 지나간다.
##  2. 차선을 막은 빈 차 뒤에서 잠시 서 있다가 바깥 차로로 비켜 간다.
##  3. NPC 차 20대 + 버스 2대 + 경찰 순찰차 3대가 10분 동안 달려도 NPC끼리 충돌 0건, 신호·예약 위반 0건, 정체 없음.
## 실행: godot --headless --fixed-fps 60 --path . res://tests/traffic_test.tscn [-- --minutes=1 --seed=7 --chapter=4]
## (--chapter=4면 모든 구역이 열려 다리·공단까지 차가 다닌다)
## (--fixed-fps 60 이 있어야 실시간보다 빠르게 돈다)

var _failures: Array[String] = []
var _minutes := 10.0
var _seed := TrafficSystem.SEED
var _chapter := 1


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--minutes="):
			_minutes = arg.get_slice("=", 1).to_float()
		if arg.begins_with("--seed="):
			_seed = arg.get_slice("=", 1).to_int()
		if arg.begins_with("--chapter="):
			_chapter = arg.get_slice("=", 1).to_int()
	await _test_red_light()
	await _test_pass_blocker()
	await _test_steal_traffic_car()
	await _test_long_run()
	if _failures.is_empty():
		print("traffic_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _make_main(cars: int, buses: int, patrols := 0) -> Node2D:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = cars
	main.bus_count = buses
	main.police_patrols = patrols
	main.traffic_seed = _seed
	main.chapter = _chapter
	add_child(main)
	return main


func _test_red_light() -> void:
	var main := await _make_main(0, 0)
	await _frames(1)
	var t: TrafficSystem = main.traffic
	var cell := Vector2i(2, 3)   # (2,2)는 고가차도가 넘는 무신호 교차로
	_expect(t.controller.is_signalized(cell), "(2,3)는 신호 교차로")
	var piece := t.graph.segment(Vector2i(2, 4), 0)   # 북행, (2,3)로 들어간다
	# 북행(남북 축)이 빨간불인 시각으로 맞춘다
	var c := t.controller
	for k in 1000:   # 신호가 없으면 끝없이 돌지 않게
		if c.light(cell, 0) == TrafficController.Light.RED:
			break
		c.advance(0.1)
	var v := t.spawn_at(TrafficSystem.TRAFFIC_TYPES[0], piece, 60.0)
	await _frames(240)
	var ai := v.ai
	var stopped_s := ai.s
	_expect(ai.route[0] == piece, "빨간불에 교차로로 들어가지 않는다")
	_expect(v.speed() < 5.0, "빨간불 앞에서 멈춘다 (속도 %.0f)" % v.speed())
	_expect(piece.length - stopped_s - ai.half_length() < 60.0, "정지선 가까이 선다 (남은 거리 %.0f)" % (piece.length - stopped_s - ai.half_length()))
	_expect(stopped_s + ai.half_length() <= piece.length, "앞범퍼가 정지선을 넘지 않는다")
	for k in 1000:
		if c.light(cell, 0) == TrafficController.Light.GREEN:
			break
		c.advance(0.1)
	await _frames(240)
	_expect(ai.route[0] != piece, "초록불이 되면 출발해 교차로를 지난다")
	_expect(ai.red_runs == 0, "신호 위반 0")
	main.queue_free()
	await _frames(1)


func _test_pass_blocker() -> void:
	var main := await _make_main(0, 0)
	await _frames(1)
	var t: TrafficSystem = main.traffic
	var piece := t.graph.segment(Vector2i(2, 4), 1)   # 동행 (가로 2번 도로는 고가차도라 4번 도로에서)
	var blocker: Vehicle = main.start_vehicle          # 빈 차를 안쪽 차로 한가운데 세운다
	blocker.place(piece.point_at(200.0), PI * 0.5)
	var v := t.spawn_at(TrafficSystem.TRAFFIC_TYPES[0], piece, 60.0)
	var hits := [0]
	v.bumped.connect(func(o, _s): if o == blocker: hits[0] += 1)
	blocker.bumped.connect(func(o, _s): if o == v: hits[0] += 1)
	var honked := false
	for f in 600:
		await _frames(1)
		honked = honked or v.ai.honking or v.ai.pass_target > 0.0
		if v.ai.route[0] != piece:
			break
	_expect(honked, "막히면 경적을 울리거나 추월을 시작한다")
	_expect(v.ai.route[0] != piece or v.ai.s > 200.0 + 60.0, "막은 차를 비켜 지나간다 (s=%.0f)" % v.ai.s)
	_expect(hits[0] == 0, "비켜 가면서 부딪히지 않는다 (%d회)" % hits[0])
	main.queue_free()
	await _frames(1)


## 신호 대기 중인 NPC 차를 빼앗으면: 운전자가 도망치고, 차는 플레이어 것이 되고, 교통은 다른 차로 보충된다
func _test_steal_traffic_car() -> void:
	var main := await _make_main(0, 0)
	await _frames(1)
	var t: TrafficSystem = main.traffic
	t.traffic_count = 1
	var piece := t.graph.segment(Vector2i(2, 3), 0)
	var v := t.spawn_at(TrafficSystem.TRAFFIC_TYPES[0], piece, 200.0)
	await _frames(1)
	var p: Player = main.player
	p.global_position = v.door_position(false) + Vector2(-30, 0)
	main.director.request_enter_exit()
	await _frames(30)
	_expect(main.director.current_vehicle == v, "NPC 차 탈취")
	_expect(v.ai == null and not v.has_driver, "빼앗은 차에서는 AI가 빠진다")
	Input.action_press("accelerate")
	await _frames(40)
	Input.action_release("accelerate")
	_expect(v.speed() > 150.0, "빼앗은 차를 몬다 (속도 %.0f)" % v.speed())
	await _frames(150)
	_expect(t.ais.size() == 1, "교통이 다른 차로 보충된다 (NPC 차 %d대)" % t.ais.size())
	main.queue_free()
	await _frames(1)


func _test_long_run() -> void:
	var main := await _make_main(20, 2, PoliceDispatcher.PATROL_COUNT)
	await _frames(1)
	var t: TrafficSystem = main.traffic
	var collisions := {}
	var seen_pairs := {}
	var other_hits := [0]
	var frame := [0]
	var watch := func(v: Vehicle):
		v.bumped.connect(func(o: Vehicle, _s):
			if v.ai and o.ai:
				var pair := "%d-%d" % [mini(v.get_instance_id(), o.get_instance_id()), maxi(v.get_instance_id(), o.get_instance_id())]
				if not seen_pairs.has(pair):
					seen_pairs[pair] = true
					print("  첫 충돌 f=%d at %s\n    A: %s\n    B: %s" % [frame[0], v.global_position, v.ai.debug_string(), o.ai.debug_string()])
				collisions["%d-%s" % [frame[0], pair]] = true
			else:
				other_hits[0] += 1)
	for v in main.vehicles:
		watch.call(v)
	t.vehicle_spawned.connect(watch)
	t.vehicle_teleported.connect(func(ai: TrafficAI):
		var near := []
		for o in t.ais:
			if o != ai and o.vehicle.global_position.distance_to(ai.vehicle.global_position) < 200.0:
				near.append(o.debug_string())
		print("  갇힘 f=%d at %s: %s\n    근처: %s" % [frame[0], ai.vehicle.global_position, ai.debug_string(), near]))

	var start := Time.get_ticks_msec()
	var total := int(_minutes * 3600)
	var moving_samples := 0
	var moving_count := 0
	for f in total:
		frame[0] = f
		await get_tree().physics_frame
		if f > total - 3600 and f % 60 == 0:
			for ai in t.ais:
				moving_samples += 1
				if ai.vehicle.speed() > 20.0:
					moving_count += 1
	var seconds := (Time.get_ticks_msec() - start) / 1000.0

	# 도시가 넓어 멀어진 차는 치우고 새로 세운다. 그래서 거리는 '분당 달린 거리'로 본다 (1분 이상 산 차만)
	var red_runs := 0
	var min_dist := INF
	var sum_dist := 0.0
	var judged := 0
	for ai in t.ais:
		red_runs += ai.red_runs
		if ai.age < 60.0:
			continue
		var per_minute := ai.distance / ai.age * 60.0
		min_dist = minf(min_dist, per_minute)
		sum_dist += per_minute
		judged += 1
	var moving := float(moving_count) / maxi(moving_samples, 1)
	print("%.1f분 시뮬레이션 (실제 %.1f초): NPC끼리 충돌 %d, 기타 접촉 %d, 신호·예약 위반 %d, 순간이동 %d, 분당 주행 평균 %.0fpx·최소 %.0fpx (%d대), 마지막 1분 주행 중 비율 %.0f%%" % [
		_minutes, seconds, collisions.size(), other_hits[0], red_runs, t.teleports,
		sum_dist / maxi(judged, 1), min_dist, judged, moving * 100.0])
	for ai in t.ais:
		if ai.age >= 60.0 and ai.distance / ai.age * 60.0 < 3000.0:
			print("  느린 차: ", ai.debug_string(), " 주행 %.0f / %.0f초" % [ai.distance, ai.age])
	_expect(collisions.is_empty(), "NPC끼리 충돌 0건 (실제 %d)" % collisions.size())
	_expect(red_runs == 0, "신호·예약 위반 0건 (실제 %d)" % red_runs)
	_expect(t.teleports <= 2, "갇혀서 옮겨진 차 2대 이하 (실제 %d)" % t.teleports)
	_expect(judged >= 5, "1분 이상 달린 차가 판단할 만큼 있다 (%d대)" % judged)
	_expect(min_dist > 3000.0, "갇힌 차 없음: 모든 차가 분당 3000px 이상 달린다 (최소 %.0f)" % min_dist)
	_expect(moving > 0.4, "마지막 1분 동안 40%% 이상이 달리는 중 — 신호 대기 외 정체 없음 (%.0f%%)" % (moving * 100.0))
	main.queue_free()
	await _frames(1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
