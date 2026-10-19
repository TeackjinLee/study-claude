extends Node
## 탈 수 있는 헬기 (4장 부두) 검증.
##  1. 헬기는 4장 부두 헬기장에만 있다. 1장에는 없고, 장이 4장으로 열리면 그때 생긴다 (한 대만).
##  2. 타면 떠오르고, 이륙 높이 전에는 움직이지 않는다. 떠 있으면 건물 위를 그대로 지나간다 (부딪히지 않는다).
##  3. F: 건물 위에서는 내려앉지 못하고 떠서 기다린다 (다시 누르면 취소). 빈 도로 위에서는 내려앉아 내린다.
##  4. 떠 있는 헬기는 교통이 피하지 않고, 보행자를 치지 않는다. 지도 밖으로 못 나간다.
##  5. 공중에서 억지로 내리면(사망·체포·리셋) 주인공은 빈 땅에 서고, 건물 위의 버려진 헬기는 떨어져 부서진다.
##  6. 땅에서 쏜 총알은 떠 있는 헬기에 맞는다 (건물 벽은 넘어간다). 아래에서 위로 쏘니 높을수록 피해가 약하다.
##  7. 소리: 세워 둔 헬기는 조용하고, 타면 날개가 빨라진다. 합성 소리는 날개가 지날 때마다 "두두두" 박자로 터진다.
##  7. 큰불이면 119 구조헬기가 날아와 불 위에서 물을 쏟아 끄고, 다 끄면 돌아간다 (Fires).
##  8. NPC 헬기(경찰·군·119)는 입체 모형으로 그린다: 모형 차종이 있고, 기수가 진행 방향으로 돌고, 돌면 기운다.
## 실행: godot --headless --fixed-fps 60 --path . res://tests/heli_test.tscn

const SEDAN: VehicleType = preload("res://data/vehicles/car_avela.tres")
const PISTOL: WeaponType = preload("res://data/weapons/police_pistol.tres")

var _failures: Array[String] = []


func _ready() -> void:
	_test_synth()
	await _test_chapter_gate()
	await _test_flight()
	await _test_rescue_heli()
	_test_npc_heli_look()
	CityMap.set_chapter(1)
	if _failures.is_empty():
		print("heli_test: PASS")
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
	main.save_prefix = "user://heli_test_save_"
	main.chapter = chapter
	add_child(main)
	return main


func _helis(main: Node2D) -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	for v: Vehicle in main.vehicles:
		if v.stats.flies:
			out.append(v)
	return out


func _test_chapter_gate() -> void:
	var main := _make_main(1)
	await _frames(2)
	_expect(_helis(main).is_empty(), "1장에는 탈 수 있는 헬기가 없다")
	main.set_chapter(4)
	await _frames(1)
	_expect(_helis(main).size() == 1, "4장이 열리면 헬기가 한 대 생긴다 (%d)" % _helis(main).size())
	main.set_chapter(4)
	_expect(_helis(main).size() == 1, "장을 다시 정해도 겹쳐 세우지 않는다 (%d)" % _helis(main).size())
	main.queue_free()
	await _frames(2)


func _test_flight() -> void:
	var main := _make_main(4)
	await _frames(2)
	var helis := _helis(main)
	_expect(helis.size() == 1, "4장 시작: 헬기 한 대 (%d)" % helis.size())
	if helis.is_empty():
		return
	var heli := helis[0]
	var d: Director = main.director
	var dock := CityMap.district(&"industrial")
	_expect(CityMap.district_at(heli.global_position) == dock, "헬기는 외곽 공단(부두)에 있다 %s" % heli.global_position)
	_expect(heli.can_land_here(), "헬기장 자리는 건물·차와 겹치지 않는다")
	_expect(heli.usable() and not heli.airborne(), "세워 둔 헬기는 땅에 있고 탈 수 있다")
	await _frames(10)
	_expect(heli.sound != null and heli.sound.spin == 0.0, "세워 둔 헬기는 조용하다")
	main.player.global_position = heli.door_position(false)
	_expect(d.nearest_enterable() == heli, "헬기 문 앞에서 가장 가까운 탈것은 헬기")
	var impacts := [0]
	heli.impacted.connect(func(_s): impacts[0] += 1)

	# 이륙: 높이가 차기 전에는 움직이지 않는다
	d.enter_immediately(heli)
	var start := heli.global_position
	Input.action_press("accelerate")
	await _frames(20)
	_expect(heli.altitude > 0.0 and heli.global_position.distance_to(start) < 3.0,
		"이륙 중엔 제자리에서 뜬다 (높이 %.0f, 움직임 %.1f)" % [heli.altitude, heli.global_position.distance_to(start)])
	await _frames(100)
	_expect(heli.airborne() and heli.collision_layer == 0 and heli.collision_mask == 0, "떠 있으면 충돌체가 꺼진다")
	_expect(heli.global_position.distance_to(start) > 60.0, "이륙하면 앞으로 난다 (%.0f)" % heli.global_position.distance_to(start))
	_expect(heli.z_index == IsoView.Z_AIR, "떠 있는 헬기는 건물 위에 그린다 (z %d)" % heli.z_index)
	_expect(heli.pitch > heli.stats.pitch_angle * 0.5, "가속하는 동안 앞으로 숙인다 (%.2f)" % heli.pitch)
	_expect(heli.sound != null and heli.sound.spin > 0.6, "타면 날개 소리가 빨라진다 (%.2f)" % (heli.sound.spin if heli.sound else -1.0))

	# 빠르게 돌면 도는 쪽으로 기운다
	_expect(absf(heli.bank) < 0.05, "곧게 날면 수평이다 (%.2f)" % heli.bank)
	await _frames(120)
	_expect(absf(heli.pitch) < 0.05, "최고 속도에 닿으면 숙였던 몸을 편다 (%.2f)" % heli.pitch)
	Input.action_press("steer_right")
	await _frames(40)
	_expect(heli.bank > heli.stats.bank_angle * 0.5, "빠르게 오른쪽으로 돌면 오른쪽으로 기운다 (%.2f)" % heli.bank)
	Input.action_release("steer_right")
	Input.action_press("steer_left")
	await _frames(70)
	_expect(heli.bank < -heli.stats.bank_angle * 0.5, "왼쪽으로 돌면 왼쪽으로 기운다 (%.2f)" % heli.bank)
	Input.action_release("steer_left")
	await _frames(70)
	_expect(absf(heli.bank) < 0.05, "핸들을 놓으면 다시 수평 (%.2f)" % heli.bank)
	Input.action_release("accelerate")
	Input.action_press("brake")
	await _frames(30)
	_expect(heli.pitch < -heli.stats.pitch_angle * 0.5, "브레이크를 밟으면 코를 든다 (%.2f)" % heli.pitch)
	Input.action_release("brake")
	Input.action_press("accelerate")
	await _frames(150)

	# 건물 위를 지나간다
	var b := _big_building(main)
	heli.place(Vector2(b.get_center().x, b.end.y + 120.0), 0.0)   # 건물 남쪽에서 북쪽(화면 위)을 본다
	var over := false
	for f in 150:
		await _frames(1)
		over = over or b.has_point(heli.global_position)
	_expect(over, "떠 있는 헬기는 건물 위를 지나간다 %s" % b)
	_expect(impacts[0] == 0, "날면서 아무것과도 부딪히지 않는다 (%d회)" % impacts[0])

	# 건물 위에서 F: 내려앉지 못하고 떠서 기다린다
	Input.action_release("accelerate")
	heli.place(b.get_center(), 0.0)
	var blocked := [0]
	heli.landing_blocked.connect(func(): blocked[0] += 1)
	d.request_enter_exit()
	_expect(heli.landing, "떠 있을 때 F를 누르면 착륙을 시작한다")
	await _frames(240)
	_expect(d.current_vehicle == heli and heli.airborne(), "건물 위에서는 내려앉지 않고 떠서 기다린다 (높이 %.1f)" % heli.altitude)
	_expect(blocked[0] == 1, "막혔다고 한 번 알린다 (%d)" % blocked[0])
	d.request_enter_exit()
	_expect(not heli.landing, "다시 누르면 착륙 취소")
	await _frames(150)
	_expect(heli.altitude > heli.stats.fly_height * 0.9, "취소하면 다시 날 높이로 오른다 (%.0f)" % heli.altitude)

	# 땅에서 쏘면 건물 너머 하늘의 헬기에도 맞는다 — 피해는 약하다
	var combat: Combat = main.combat
	var shooter := Vector2(b.get_center().x, b.end.y + 40.0)
	var before := heli.health
	combat.fire(shooter, (heli.global_position - shooter).normalized(), PISTOL, false, [])
	var dealt := before - heli.health
	var want := PISTOL.damage * heli.stats.ground_fire_damage
	_expect(absf(dealt - want) < PISTOL.damage * 0.1,
		"땅에서 쏜 총알이 건물 위 헬기에 약하게 맞는다 (피해 %.1f, 기대 %.1f / 땅에서는 %.0f)" % [dealt, want, PISTOL.damage])
	before = heli.health
	combat.fire(shooter, (heli.global_position - shooter).normalized().rotated(PI * 0.5), PISTOL, false, [])
	_expect(heli.health == before, "헬기 옆으로 쏘면 안 맞는다")
	_expect(is_equal_approx(heli.ground_fire_factor(), heli.stats.ground_fire_damage), "날 높이에서 피해 배율 %.2f" % heli.ground_fire_factor())
	var alt := heli.altitude
	heli.altitude = heli.stats.fly_height * 0.25
	_expect(heli.ground_fire_factor() > 0.8, "낮게 뜨면 덜 약해진다 (%.2f)" % heli.ground_fire_factor())
	heli.altitude = alt
	heli.health = heli.max_health()

	# 떠 있는 헬기는 교통이 피하지 않는다
	var t: TrafficSystem = main.traffic
	var piece := t.graph.segment(Vector2i(2, 4), 1)
	var car := t.spawn_at(SEDAN, piece, 60.0)
	await _frames(1)
	heli.place(piece.point_at(150.0), 0.0)
	await _frames(1)
	_expect(t.scan_ahead(car.ai).is_empty(), "앞에 떠 있는 헬기는 교통의 장애물이 아니다")
	t.remove_ai(car)
	main.vehicles.erase(car)
	car.queue_free()

	# 머리 위로 빠르게 지나가도 보행자를 치지 않는다
	var ped: Pedestrian = main.pedestrians.peds[0]
	ped.set_active(true)
	heli.place(Vector2(b.get_center().x, b.end.y + 400.0), 0.0)
	ped.global_position = heli.global_position + Vector2(0, -160)
	ped.resume_walking()
	Input.action_press("accelerate")
	var hit := false
	for f in 90:
		await _frames(1)
		ped.global_position = heli.global_position + Vector2(0, -160 + f * 4.0) if f < 40 else ped.global_position
		hit = hit or ped.state == Pedestrian.State.KNOCKED or ped.is_dead()
	Input.action_release("accelerate")
	_expect(heli.speed() > Pedestrian.RADIUS and not hit, "떠 있는 헬기는 보행자를 치지 않는다 (속도 %.0f)" % heli.speed())

	# 지도 밖으로 못 나간다
	var r := CityMap.world_rect()
	heli.place(Vector2(r.get_center().x, r.position.y + 80.0), 0.0)   # 북쪽 끝에서 북쪽으로
	Input.action_press("accelerate")
	await _frames(120)
	Input.action_release("accelerate")
	_expect(r.has_point(heli.global_position), "지도 밖으로 못 나간다 %s" % heli.global_position)

	# 빈 도로 위에서 F: 내려앉아 내린다
	var road := LaneGraph.center(Vector2i(3, 3))   # (2,2)는 고가차도 밑 — 헬기가 내려앉지 못한다
	heli.place(road, 0.0)
	await _frames(30)
	d.request_enter_exit()
	var landed := false
	for f in 400:
		await _frames(1)
		if d.current_vehicle == null:
			landed = true
			break
	_expect(landed, "빈 도로 위에서는 내려앉아 내린다")
	_expect(not heli.airborne() and heli.altitude == 0.0, "내려앉은 헬기는 땅에 있다 (높이 %.1f)" % heli.altitude)
	_expect(heli.collision_layer == Layers.VEHICLES, "땅에 앉으면 다시 부딪힌다")
	_expect(main.player.visible and main.player.global_position.distance_to(heli.global_position) < 80.0,
		"주인공은 헬기 옆에 내린다 (%.0f)" % main.player.global_position.distance_to(heli.global_position))
	_expect(heli.global_position.distance_to(road) < 60.0, "그 자리에 내려앉는다 (%.0f)" % heli.global_position.distance_to(road))

	# 공중에서 억지로 내리면: 주인공은 빈 땅에, 건물 위의 버려진 헬기는 떨어져 부서진다
	d.enter_immediately(heli)
	await _frames(180)
	heli.place(b.get_center(), 0.0)
	await _frames(1)
	d.exit_vehicle()
	_expect(not main.player.blocked_at(main.player.global_position), "공중에서 내리면 주인공은 빈 땅에 선다 %s" % main.player.global_position)
	var crashed := false
	for f in 300:
		await _frames(1)
		if heli.burning >= 0.0 or heli.wrecked:
			crashed = true
			break
	_expect(crashed, "건물 위의 버려진 헬기는 떨어져 부서진다")
	_expect(heli.collision_layer == 0, "건물에 떨어진 헬기는 충돌체를 끈 채로 둔다")
	_expect(not heli.usable(), "부서진 헬기에는 못 탄다")
	main.queue_free()
	await _frames(2)


## 큰불(동시에 여러 곳) → 119 헬기 출동 → 불 위에서 물 → 불이 꺼지고 헬기는 돌아간다
func _test_rescue_heli() -> void:
	var main := _make_main(1)
	await _frames(2)
	var fires: Fires = main.fires
	var spot := LaneGraph.center(Vector2i(3, 2)) + Vector2(0, 260)
	main.player.global_position = spot + Vector2(0, 500)
	# 큰불: 네 곳에 동시에 (연쇄 폭발처럼) — 소방차 한 대가 오래 걸리는 불
	for i in Fires.HELI_FIRES:
		fires.start(spot + Vector2(i * 45.0 - 70.0, 0), 40.0, false, 30.0)
	var watered := false
	var gone := false
	for f in 60 * 50:
		await _frames(1)
		main.player.revive()
		if fires.heli and is_instance_valid(fires.heli) and fires.heli.water:
			watered = true
		if watered and fires.fires.is_empty() and fires.heli == null:
			gone = true
			break
	_expect(fires.heli_calls >= 1, "큰불이면 119 헬기가 출동한다")
	_expect(watered, "119 헬기가 불 위에서 물을 쏟는다")
	_expect(fires.fires.is_empty(), "119 헬기·소방차가 불을 끈다 (남은 불 %d)" % fires.fires.size())
	_expect(gone, "불이 꺼지면 119 헬기는 돌아가 없어진다")
	main.queue_free()
	await _frames(2)


## NPC 헬기 모습: 차종별 모형이 따로 있고, 진행 방향으로 기수가 돌며 돌면 기운다 (노드만 — 그리기는 화면 도구로 본다)
func _test_npc_heli_look() -> void:
	for path in ["res://data/vehicles/police_heli.tres", "res://data/vehicles/army_heli.tres", "res://data/vehicles/sp_fire_heli.tres"]:
		var t: VehicleType = load(path)
		_expect(t.flies and not t.enterable, "%s: 나는 NPC 헬기 (탈 수 없다)" % t.display_name)
		_expect(VehicleModel.model(t).size() > 20, "%s: 입체 모형 부품 (%d)" % [t.display_name, VehicleModel.model(t).size()])
		_expect(VehicleModel.model(t).any(func(p): return p.blade), "%s: 주 회전날개" % t.display_name)
	var h := PoliceHeli.new()
	add_child(h)
	h.target = Vector2(2000, 0)
	for i in 120:
		h._physics_process(1.0 / 60.0)
	_expect(absf(angle_difference(h.heading, Vector2.UP.angle_to(h.velocity))) < 0.3,
		"경찰 헬기 기수가 진행 방향을 본다 (%.2f vs %.2f)" % [h.heading, Vector2.UP.angle_to(h.velocity)])
	var banked := false
	h.target = h.global_position + h.velocity.orthogonal().normalized() * 900.0
	for i in 90:
		h._physics_process(1.0 / 60.0)
		banked = banked or absf(h._look.bank) > 0.05
	_expect(banked, "경찰 헬기가 돌면 옆으로 기운다")
	h.queue_free()


## 도시에서 가운데가 꽉 막힌 큰 건물 하나 (월드 사각형). 랜드마크 공터처럼 가운데가 비어 있으면 내려앉을 수 있으니 뺀다
## 합성 소리: 멈추면 무음, 돌면 들릴 만큼 크고 찢어지지 않으며, 1초에 날개 박자(BLADE_HZ)만큼 터진다
func _test_synth() -> void:
	var synth := RotorSynth.new()
	var rate := int(RotorSynth.MIX_RATE)
	var quiet := synth.fill(rate / 10, 0.0, 0.0)
	var silent := true
	for v in quiet:
		silent = silent and v == Vector2.ZERO
	_expect(silent, "날개가 멈추면 소리가 없다")
	var buf := synth.fill(rate, 1.0, 1.0)
	var sum := 0.0
	var peak := 0.0
	for v in buf:
		sum += v.x * v.x
		peak = maxf(peak, absf(v.x))
	var rms := sqrt(sum / buf.size())
	_expect(rms > 0.05 and peak < 1.0, "다 돌면 들릴 만큼 크고 찢어지지 않는다 (rms %.3f, 최대 %.2f)" % [rms, peak])
	# 30ms 토막마다 소리 크기 → 커졌다 작아지는 박자 수를 센다 (토막이 짧으면 낮은 쿵 소리 한 번의 출렁임까지 센다)
	var block := rate * 3 / 100
	var energy: Array[float] = []
	for b in buf.size() / block:
		var e := 0.0
		for i in block:
			e += absf(buf[b * block + i].x)
		energy.append(e / block)
	var mean := 0.0
	for e in energy:
		mean += e / energy.size()
	var beats := 0
	var high := false
	for e in energy:
		if not high and e > mean * 1.3:
			beats += 1
			high = true
		elif high and e < mean * 0.9:
			high = false
	var expect := roundi(RotorSynth.BLADE_HZ)
	_expect(absi(beats - expect) <= 1, "날개 박자: 1초에 %d번 \"두\" (기대 %d)" % [beats, expect])


func _big_building(main: Node2D) -> Rect2:
	var best := Rect2()
	var box := RectangleShape2D.new()
	box.size = Vector2(40, 80)   # 헬기 크기 (sp_heli.tres)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = box
	query.collision_mask = Layers.WORLD
	var space: PhysicsDirectSpaceState2D = main.get_world_2d().direct_space_state
	for r: Rect2 in main.city.buildings:
		if not CityMap.is_open_block(CityMap.block_at(r.get_center())) or r.size.y < 150.0 or r.size.x < 120.0 \
				or r.get_area() <= best.get_area():
			continue
		query.transform = Transform2D(0.0, r.get_center())
		if not space.intersect_shape(query, 1).is_empty():
			best = r
	return best


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
