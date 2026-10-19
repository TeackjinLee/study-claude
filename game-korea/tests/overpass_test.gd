extends Node
## 고가차도 (CityMap.OVERPASSES — 강남 가로 2번 도로가 교차로 (1,2)·(2,2)를 넘는다) 검증.
##  1. 지도: 경사로 입구는 땅 층, 경사로 위·상판은 고가 층, 넘는 교차로 상자는 층을 그대로 둔다. 높이는 입구 0 → 상판 OVER_HEIGHT,
##     넘는 교차로 밑은 0이고 위는 OVER_HEIGHT. 고가 구간·넘는 교차로를 바르게 안다.
##  2. 차선 그래프: 넘는 교차로는 직진만 있고 신호가 없으며, 예약 없이 지난다.
##  3. 길찾기: 넘는 교차로에서는 달리던 축으로만 나간다. 밑에 선 경찰은 고가 위 목표로 가는 길을 경사로로 찾는다.
##  4. 고가 위 차는 밑에 선 차·사람을 지나 넘어간다 (부딪히지도 치지도 않는다). 고가 위의 차끼리는 부딪힌다.
##  5. 밑의 길에서 고가 쪽으로 가면 교대에 막히고, 고가 위에서 옆으로 꺾으면 난간에 막힌다.
##  6. 교통 AI: 경사로로 올라간 차는 고가를 넘어 내려가고, 밑의 길로 온 차는 고가 밑을 곧장 지난다.
##  7. 그리는 순서: 고가 위 차는 그 밑 상판 조각보다 앞, 밑을 지나는 차는 위 상판 조각보다 뒤.
## 실행: godot --headless --fixed-fps 60 --path . res://tests/overpass_test.tscn

const SEDAN: VehicleType = preload("res://data/vehicles/car_avela.tres")
const CIV: NpcType = preload("res://data/npc/civ_m.tres")
const O := Vector4i(1, 2, 1, 2)

var _failures: Array[String] = []
var _rc := City.road_center(2)                 ## 고가 도로 가운데 y
var _east_lane := City.road_center(2) + LaneGraph.LANE_OFFSET


func _ready() -> void:
	_test_map()
	_test_lanes()
	_test_nav()
	var main := _make_main()
	await get_tree().physics_frame
	_test_parked(main)
	await _test_pass_over(main)
	await _test_deck_collision(main)
	await _test_walls(main)
	await _test_traffic(main)
	_test_draw_order(main)
	CityMap.set_chapter(1)
	if _failures.is_empty():
		print("overpass_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _make_main() -> Node2D:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = 0
	main.bus_count = 0
	main.police_patrols = 0
	main.save_prefix = "user://overpass_test_save_"
	main.chapter = 1
	add_child(main)
	main.player.died.disconnect(main._on_died)
	main.police.busted.disconnect(main._on_busted)
	return main


func _vehicle(main: Node2D, pos: Vector2, heading: float) -> Vehicle:
	var v := Vehicle.new()
	v.stats = SEDAN
	main.add_child(v)
	v.place(pos, heading)
	main.vehicles.append(v)
	return v


func _remove(main: Node2D, vs: Array) -> void:
	if main.director.current_vehicle:
		main.director.exit_vehicle()
	main.player.global_position = City.start_position()   # 내린 주인공이 고가 위에 서 있으면 교통 차가 기다린다
	main.player.set_level(0)
	for v: Vehicle in vs:
		main.traffic.remove_ai(v)
		main.vehicles.erase(v)
		v.queue_free()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _test_map() -> void:
	var ext := CityMap.over_extent(O)
	_expect(is_equal_approx(ext.x, City.ROAD) and is_equal_approx(ext.y, 3 * City.PITCH), "고가 입구·출구 %s" % ext)
	var mouth := Vector2(ext.x + 10.0, _east_lane)
	var ramp_top := Vector2(City.PITCH - 20.0, _east_lane)
	var deck := Vector2(1.5 * City.PITCH, _east_lane)
	var under := LaneGraph.center(Vector2i(1, 2))
	_expect(CityMap.level_zone(mouth) == 0, "경사로 입구는 땅 층")
	_expect(CityMap.level_zone(ramp_top) == 1, "경사로 위는 고가 층")
	_expect(CityMap.level_zone(deck) == 1, "넘는 교차로 사이 상판은 고가 층")
	_expect(CityMap.level_zone(under) == -1, "넘는 교차로 상자는 층을 그대로 둔다")
	_expect(CityMap.level_zone(Vector2(deck.x, _rc + City.ROAD)) == 0, "고가 옆 인도는 땅 층")
	_expect(CityMap.ground_height(mouth) < 1.0, "경사로 입구 높이 %.1f" % CityMap.ground_height(mouth))
	_expect(is_equal_approx(CityMap.ground_height(deck), CityMap.OVER_HEIGHT), "상판 높이")
	_expect(is_zero_approx(CityMap.ground_height(under, 0)), "넘는 교차로 밑은 땅 높이")
	_expect(is_equal_approx(CityMap.ground_height(under, 1), CityMap.OVER_HEIGHT), "넘는 교차로 위는 상판 높이")
	var last := 0.0
	var smooth := true
	for i in 41:
		var h := CityMap.ground_height(Vector2(lerpf(ext.x, City.PITCH, i / 40.0), _east_lane), 1)
		smooth = smooth and h >= last - 0.01 and h - last < 4.0
		last = h
	_expect(smooth, "경사로가 부드럽게 오른다")
	_expect(CityMap.over_axis(Vector2i(1, 2)) == 1 and CityMap.over_axis(Vector2i(2, 2)) == 1, "넘는 교차로 (1,2)·(2,2)")
	_expect(CityMap.over_axis(Vector2i(0, 2)) == -1 and CityMap.over_axis(Vector2i(3, 2)) == -1, "경사로 입구 교차로는 보통 교차로")
	_expect(CityMap.over_strip(Vector2i(0, 2), 1) and CityMap.over_strip(Vector2i(2, 2), 3) and CityMap.over_strip(Vector2i(3, 2), 3),
		"경사로·상판 구간")
	_expect(not CityMap.over_strip(Vector2i(3, 2), 1) and not CityMap.over_strip(Vector2i(1, 2), 2), "고가 밖 구간")
	_expect(CityMap.meet(mouth, 0, mouth + Vector2(20, 0), 1), "경사로 입구에서는 층이 달라도 만난다")
	_expect(not CityMap.meet(under, 0, under, 1), "넘는 교차로 위아래는 만나지 않는다")
	_expect(Layers.at(Layers.VEHICLES, 1) == Layers.DECK_VEHICLES and Layers.at(Layers.WORLD, 1) == Layers.DECK, "층 비트")


func _test_lanes() -> void:
	var g := LaneGraph.new()
	var c := Vector2i(1, 2)
	_expect(g.turn(c, 1, 1) != null and g.turn(c, 2, 2) != null, "넘는 교차로 직진 (고가 동행·밑 남행)")
	_expect(g.turn(c, 1, 2) == null and g.turn(c, 2, 1) == null and g.turn(c, 0, 3) == null, "넘는 교차로에서는 꺾지 못한다")
	_expect(g.exits(c, 1) == [1] and g.exits(c, 0) == [0], "넘는 교차로 출구는 직진뿐 %s %s" % [g.exits(c, 1), g.exits(c, 0)])
	_expect(g.exits(Vector2i(0, 2), 1).size() == 3, "경사로 입구 교차로는 그대로 꺾는다")
	var ctl := TrafficController.new(g)
	_expect(not ctl.is_signalized(c) and not ctl.is_signalized(Vector2i(2, 2)), "넘는 교차로는 신호가 없다")
	_expect(ctl.try_reserve(c, 1, 1, 1) and ctl.try_reserve(c, 2, 2, 2), "고가 위와 밑이 함께 지난다")


func _test_nav() -> void:
	var under := LaneGraph.center(Vector2i(1, 2))
	var east := RoadNav.next_cell(under, Vector2.RIGHT, LaneGraph.center(Vector2i(1, 4)), 1, 0)
	_expect(east == Vector2i(2, 2) or east == Vector2i(0, 2), "고가 위에서 동쪽으로 달리면 넘는 교차로에서 꺾지 않는다 (%s)" % east)
	var south := RoadNav.next_cell(under, Vector2.DOWN, LaneGraph.center(Vector2i(3, 2)), 0, 0)
	_expect(south == Vector2i(1, 3) or south == Vector2i(1, 1), "밑에서 남쪽으로 달리면 넘는 교차로에서 꺾지 않는다 (%s)" % south)
	var on_deck := Vector2(1.5 * City.PITCH, _east_lane)
	var up := RoadNav.next_cell(under, Vector2.ZERO, on_deck, 0, 1)
	_expect(up == Vector2i(1, 1) or up == Vector2i(1, 3), "밑에 선 경찰은 위로 곧장 못 간다 (%s)" % up)
	_expect(RoadNav._cost(RoadNav._key(up, 0), on_deck, 1) < 6 * City.PITCH, "밑에서 고가 위 목표까지 경사로로 가는 길이 있다")
	var stand := RoadNav.next_cell(on_deck, Vector2.ZERO, LaneGraph.center(Vector2i(1, 3)), 1, 0)
	_expect(stand == Vector2i(1, 2) or stand == Vector2i(2, 2), "고가 위에 선 차는 상판 구간 끝으로 간다 (%s)" % stand)


## 출발 차 등 미리 세운 차가 고가 위에 있지 않다
func _test_parked(main: Node2D) -> void:
	for v: Vehicle in main.vehicles:
		_expect(CityMap.overpass_at(v.global_position) < 0, "고가 위에 세운 차 %s %s" % [v.stats.id, v.global_position])


## 고가 위로 달려 밑에 선 차·사람 위를 지난다
func _test_pass_over(main: Node2D) -> void:
	var under := _vehicle(main, LaneGraph.center(Vector2i(1, 2)) + Vector2(-24, 0), PI)
	var ped := Pedestrian.new()
	ped.setup(CIV, RandomNumberGenerator.new(), City.sidewalk_loop(Vector2i(1, 1)), 0, 0.0, 1)
	ped.position = LaneGraph.center(Vector2i(2, 2)) + Vector2(0, 24)
	main.pedestrians.add(ped)
	ped._set_state(Pedestrian.State.IDLE, 100.0)
	var car := _vehicle(main, Vector2(60.0, _east_lane), PI * 0.5)
	main.director.enter_immediately(car)
	var under_at := under.global_position
	var top_level := 0
	var over_h := 0.0
	var max_y_off := 0.0
	Input.action_press("accelerate")
	for i in 900:
		await get_tree().physics_frame
		var x := car.global_position.x
		max_y_off = maxf(max_y_off, absf(car.global_position.y - _east_lane))
		if x > City.PITCH and x < City.PITCH + City.ROAD:
			top_level = maxi(top_level, car.level)
			over_h = car.ground
		if x > 3 * City.PITCH + 80.0:
			break
	Input.action_release("accelerate")
	_expect(car.global_position.x > 3 * City.PITCH, "고가를 넘어 내려왔다 (x %.0f)" % car.global_position.x)
	_expect(top_level == 1, "넘는 교차로 위에서 고가 층")
	_expect(absf(over_h - CityMap.OVER_HEIGHT) < 1.0, "넘는 교차로 위에서 상판 높이로 그린다 (%.1f)" % over_h)
	_expect(car.level == 0, "내려오면 땅 층")
	_expect(max_y_off < 12.0, "곧게 달렸다 (옆으로 %.1f)" % max_y_off)
	_expect(under.global_position.distance_to(under_at) < 1.0 and under.health >= under.max_health(), "밑에 선 차는 그대로다")
	_expect(under.level == 0 and car.collision_layer == Layers.VEHICLES, "밑의 차 층 %d, 내려온 차 충돌 %d" % [under.level, car.collision_layer])
	_expect(ped.health >= CIV.health and ped.state == Pedestrian.State.IDLE, "밑에 선 사람은 치이지 않는다")
	main.pedestrians.remove(ped)
	_remove(main, [under, car])
	await _frames(2)


## 고가 위의 차끼리는 부딪힌다
func _test_deck_collision(main: Node2D) -> void:
	var parked := _vehicle(main, Vector2(1.5 * City.PITCH, _east_lane), PI * 0.5)
	var car := _vehicle(main, Vector2(60.0, _east_lane), PI * 0.5)
	main.director.enter_immediately(car)
	var at := parked.global_position
	_expect(parked.level == 1 and parked.collision_layer == Layers.DECK_VEHICLES, "상판에 세운 차는 고가 층")
	Input.action_press("accelerate")
	await _frames(300)
	Input.action_release("accelerate")
	_expect(parked.global_position.distance_to(at) > 10.0 or parked.health < parked.max_health(),
		"고가 위에서 앞차를 들이받았다 (%.0f)" % parked.global_position.distance_to(at))
	_remove(main, [parked, car])
	await _frames(2)


## 밑의 길에서 고가 쪽으로 가면 교대, 고가 위에서 옆으로 꺾으면 난간
func _test_walls(main: Node2D) -> void:
	var box := LaneGraph.center(Vector2i(1, 2))
	var low := _vehicle(main, box, PI * 0.5)
	main.director.enter_immediately(low)
	Input.action_press("accelerate")
	await _frames(150)
	Input.action_release("accelerate")
	_expect(low.global_position.x < City.PITCH + City.ROAD + 5.0, "밑에서 경사로로 못 들어간다 (x %.0f)" % low.global_position.x)
	_expect(low.level == 0, "밑의 차는 땅 층 그대로")
	_remove(main, [low])
	var high := _vehicle(main, Vector2(1.3 * City.PITCH, _east_lane), PI * 0.5)
	main.director.enter_immediately(high)
	Input.action_press("accelerate")
	Input.action_press("steer_right")
	await _frames(150)
	Input.action_release("steer_right")
	Input.action_release("accelerate")
	_expect(high.global_position.y < _rc + City.ROAD * 0.5, "고가 위에서 난간 밖으로 못 나간다 (y %.0f)" % high.global_position.y)
	_expect(high.level == 1, "고가 위 차는 고가 층 그대로")
	_remove(main, [high])
	await _frames(2)


## 교통 AI가 고가를 넘고, 밑의 길을 곧장 지난다
func _test_traffic(main: Node2D) -> void:
	var g: LaneGraph = main.traffic.graph
	var over: Vehicle = main.traffic.spawn_at(SEDAN, g.segment(Vector2i(0, 2), 1), 20.0)
	var below: Vehicle = main.traffic.spawn_at(SEDAN, g.segment(Vector2i(1, 1), 2), 20.0)
	var over_top := 0
	var below_top := 0
	for i in 1500:
		await get_tree().physics_frame
		if CityMap.over_axis(RoadNav.cell_at(over.global_position)) >= 0:
			over_top = maxi(over_top, over.level)
		below_top = maxi(below_top, below.level)
		if over.global_position.x > 3 * City.PITCH + City.ROAD and below.global_position.y > 3 * City.PITCH:
			break
	_expect(over.global_position.x > 3 * City.PITCH + City.ROAD, "교통 차가 고가를 넘었다 (%s) %s" % [over.global_position, over.ai.debug_string()])
	_expect(over_top == 1, "교통 차가 넘는 교차로를 고가 위로 지났다")
	_expect(below.global_position.y > 3 * City.PITCH, "밑의 길 교통 차가 고가 밑을 지났다 (%s)" % below.global_position)
	_expect(below_top == 0, "밑의 길 교통 차는 땅 층")
	_expect(over.ai.red_runs == 0 and below.ai.red_runs == 0, "예약 없이 들어간 교차로 없음")
	_remove(main, [over, below])
	await _frames(2)


## 고가 위 차는 밑 상판 조각보다 앞, 밑을 지나는 차는 위 상판 조각보다 뒤
func _test_draw_order(main: Node2D) -> void:
	var slices := []
	for n in main.city.get_children():
		if n is OverpassView.Slice:
			slices.append(n)
	_expect(slices.size() > 50, "상판 조각 %d개" % slices.size())
	var at := LaneGraph.center(Vector2i(1, 2)) + Vector2(0, LaneGraph.LANE_OFFSET)
	var deck_z := -1
	var front_z := -1
	for s: OverpassView.Slice in slices:
		if at.x >= s.a0 and at.x < s.a1:
			if s.front:
				front_z = s.z_index
			else:
				deck_z = s.z_index
	_expect(deck_z > 0 and IsoView.z_at(at, 1) > deck_z, "고가 위 차가 상판 조각 앞 (%d > %d)" % [IsoView.z_at(at, 1), deck_z])
	_expect(IsoView.z_at(at, 0) < deck_z, "밑의 차가 상판 조각 뒤 (%d < %d)" % [IsoView.z_at(at, 0), deck_z])
	_expect(front_z > IsoView.z_at(at, 1), "앞 난간이 고가 위 차 앞 (%d > %d)" % [front_z, IsoView.z_at(at, 1)])
