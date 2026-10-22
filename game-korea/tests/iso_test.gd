extends Node
## 2.5D 화면 검증 (물리는 2D 그대로, 그림만 사선).
##  1. 수식: 높이는 화면 위로 올라가고, 깊이(x+y)가 클수록 앞에 그린다. W는 화면 위(월드 북서)로 걷는다.
##  2. 카메라: 화면 변환이 사선이고, 조종 대상이 화면 가운데 근처에 보인다. 마우스 역변환이 월드 좌표로 돌아온다.
##  3. 건물: 충돌 건물마다 입체 조각이 있고, 조각은 정사각형에 가깝다. 지붕은 한 조각만 그린다.
##     건물 바로 동·남쪽 인도에 선 사람은 그 건물보다 앞에, 북·서쪽은 뒤에 그린다.
##  4. 주인공이 건물 뒤에 가면 그 건물이 흐려지고, 나오면 다시 진해진다.
##  5. F9: 위에서 보는 화면으로 바꾸면 변환이 회전·기울기 없는 확대로 돌아오고 입체 건물이 숨는다.
##  6. 다리: 강 위 다리 구간만 떠 있고(가운데 DECK_HEIGHT), 양끝 경사로는 땅에서 매끈하게 오른다.
##     다리 위에 세운 차는 그 높이로 그리고, 위에서 보기에선 0이다.
##  7. 랜드마크 부지: 건물·기둥·좌판만 막고 공터(광장·골목·승강장·하역장)는 걷는다. 터미널 승강장엔 고속버스가 서 있다.
## 실행: godot --headless --fixed-fps 60 --path . res://tests/iso_test.tscn

var _failures: Array[String] = []


func _ready() -> void:
	IsoView.enabled = true
	_test_math()
	await _test_camera_and_walk()
	await _test_buildings()
	await _test_fade()
	await _test_toggle()
	_test_bridge_heights()
	await _test_bridge_vehicle()
	await _test_landmarks()
	IsoView.enabled = true
	if _failures.is_empty():
		print("iso_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _make_main(chapter := 1) -> Node2D:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.chapter = chapter
	main.traffic_count = 0
	main.bus_count = 0
	main.police_patrols = 0
	main.save_prefix = "user://iso_test_save_"
	add_child(main)
	return main


func _test_math() -> void:
	var up := IsoView.BASIS.basis_xform(IsoView.lift(10.0))
	_expect(up.is_equal_approx(Vector2(0, -10)), "높이 10은 화면 위로 10px (%s)" % up)
	var w := IsoView.walk_dir(Vector2(0, -1))
	_expect(w.is_equal_approx(Vector2(-1, -1).normalized()), "W는 월드 북서쪽 (%s)" % w)
	_expect(IsoView.to_screen_dir(w).normalized().is_equal_approx(Vector2.UP), "북서쪽은 화면 바로 위")
	_expect(IsoView.walk_dir(Vector2(1, 0)).length() <= 1.0001, "걷기 세기는 1을 넘지 않는다")
	_expect(IsoView.z_of(Vector2(100, 100)) > IsoView.z_of(Vector2(0, 0)), "x+y가 크면 앞")
	var corners := CityMap.world_rect()
	var lo := IsoView.z_of(corners.position)
	var hi := IsoView.z_of(corners.end)
	_expect(lo > IsoView.Z_MIN and hi < IsoView.Z_MAX, "지도 전체가 정렬 범위 안 (%d~%d)" % [lo, hi])
	_expect(IsoView.Z_MAX < IsoView.Z_EFFECTS and IsoView.Z_EFFECTS < IsoView.Z_AIR and IsoView.Z_AIR <= 4096, "효과·헬기는 정렬 위")
	_expect(IsoView.faces_viewer(Vector2.RIGHT) and IsoView.faces_viewer(Vector2.DOWN), "동·남 벽이 보인다")
	_expect(not IsoView.faces_viewer(Vector2.UP) and not IsoView.faces_viewer(Vector2.LEFT), "북·서 벽은 안 보인다")


func _test_camera_and_walk() -> void:
	var main := _make_main()
	await _frames(3)
	await get_tree().process_frame
	var t: Transform2D = get_viewport().canvas_transform
	_expect(absf(t.x.y) > 0.01 and absf(t.y.x) > 0.01, "화면 변환이 사선이다 (%s)" % t)
	var player: Player = main.player
	var screen := t * player.global_position
	var view := get_viewport().get_visible_rect().size
	_expect(screen.distance_to(view * Vector2(0.5, 0.56)) < 40.0, "주인공이 화면 가운데 (%s)" % screen)
	_expect((t.affine_inverse() * screen).distance_to(player.global_position) < 0.01, "화면 → 월드 역변환")
	_expect(ChaseCamera.current_cam() == main.camera, "다른 시스템이 카메라를 찾는다")
	# W: 화면 위 = 월드 북서쪽으로 걷는다 (막힌 데 없는 교차로 한가운데서)
	player.global_position = LaneGraph.center(Vector2i(3, 3))
	var start := player.global_position
	Input.action_press("accelerate")
	await _frames(20)
	Input.action_release("accelerate")
	var moved := player.global_position - start
	_expect(moved.length() > 20.0 and moved.x < -10.0 and moved.y < -10.0 and absf(moved.x - moved.y) < 6.0,
		"W를 누르면 북서쪽으로 (%s)" % moved)
	_expect(player.z_index == IsoView.z_of(player.global_position) and not player.z_as_relative, "주인공도 깊이로 정렬")
	await _free(main)


func _test_buildings() -> void:
	var main := _make_main()
	await _frames(2)
	var city: City = main.city
	var views: Array[BuildingView] = []
	for c in city.get_children():
		if c is BuildingView:
			views.append(c)
	var roofs := {}
	var piece_roofs := {}
	var square := true
	for v in views:
		if v.roof:
			roofs[v.idx] = true
			piece_roofs[v.piece] = piece_roofs.get(v.piece, 0) + 1
		elif not piece_roofs.has(v.piece):
			piece_roofs[v.piece] = 0
		var ratio := maxf(v.part.size.x, v.part.size.y) / minf(v.part.size.x, v.part.size.y)
		if ratio > 1.5:
			square = false
	_expect(roofs.size() == city.buildings.size(), "충돌 건물마다 입체 건물 (%d / %d)" % [roofs.size(), city.buildings.size()])
	_expect(piece_roofs.values().all(func(n): return n == 1), "지붕은 덩어리(본채·나무·카라반 등)마다 한 번")
	_expect(square, "조각은 정사각형에 가깝다")
	# 랜드마크 부지의 소품(벤치·볼라드·지게차 포크)과 산자락 숲의 바위는 낮아도 된다
	_expect(views.all(func(v): return v.visible and (v.height >= IsoView.FLOOR_HEIGHT or city.landmark_indices.values().has(v.idx) \
			or city.kinds[v.idx] == City.FOREST)),
		"입체 건물이 보이고 높이가 있다")
	# 건물 동·남쪽 인도의 사람은 앞, 북·서쪽은 뒤 (긴 건물의 끝 쪽에서도)
	var wrong := 0
	for idx in city.buildings.size():
		var r := city.buildings[idx]
		var parts: Array[BuildingView] = []
		for v in views:
			if v.idx == idx:
				parts.append(v)
		for k in 5:
			var t := (k + 0.5) / 5.0
			var east := Vector2(r.end.x + 14.0, lerpf(r.position.y, r.end.y, t))
			var south := Vector2(lerpf(r.position.x, r.end.x, t), r.end.y + 14.0)
			var north := Vector2(lerpf(r.position.x, r.end.x, t), r.position.y - 14.0)
			var west := Vector2(r.position.x - 14.0, lerpf(r.position.y, r.end.y, t))
			for v in parts:
				if not _overlaps(v, east) and not _overlaps(v, south) and not _overlaps(v, north) and not _overlaps(v, west):
					continue
				if _overlaps(v, east) and IsoView.z_of(east) <= v.z_index:
					wrong += 1
				if _overlaps(v, south) and IsoView.z_of(south) <= v.z_index:
					wrong += 1
				if _overlaps(v, north) and IsoView.z_of(north) >= v.z_index:
					wrong += 1
				if _overlaps(v, west) and IsoView.z_of(west) >= v.z_index:
					wrong += 1
	_expect(wrong == 0, "건물 둘레 인도의 사람이 건물과 맞는 앞뒤로 그려진다 (틀림 %d)" % wrong)
	await _free(main)


## 사람(키 PERSON_HEIGHT)이 그 조각의 벽과 화면에서 겹치는가
func _overlaps(v: BuildingView, p: Vector2) -> bool:
	var wall := BuildingView.silhouette(v.part, v.height)
	for h in [0.0, IsoView.PERSON_HEIGHT * 0.5, IsoView.PERSON_HEIGHT]:
		if Geometry2D.is_point_in_polygon(p + IsoView.lift(h), wall):
			return true
	return false


func _test_fade() -> void:
	var main := _make_main()
	await _frames(2)
	var city: City = main.city
	var player: Player = main.player
	# 블록 하나를 통째로 쓰는 건물의 북쪽 인도 가운데 = 건물 뒤
	var idx := city.buildings.find(city.hq)
	var r := city.hq
	player.global_position = Vector2(r.get_center().x, r.position.y - 14.0)
	main.camera.snap()
	await _frames(40)
	var view: BuildingView = _views_of(city, idx)[0]
	_expect(view.modulate.a < 0.5, "건물 뒤에 가면 흐려진다 (%.2f)" % view.modulate.a)
	player.global_position = Vector2(r.get_center().x, r.end.y + 14.0)
	main.camera.snap()
	await _frames(40)
	_expect(view.modulate.a > 0.99, "앞으로 나오면 다시 진하다 (%.2f)" % view.modulate.a)
	await _free(main)


func _test_toggle() -> void:
	var main := _make_main()
	await _frames(2)
	main.set_iso(false)
	await _frames(2)
	var t: Transform2D = get_viewport().canvas_transform
	_expect(is_zero_approx(t.x.y) and is_zero_approx(t.y.x) and t.x.x > 0.5, "위에서 보기는 기울기 없는 확대 (%s)" % t)
	var hidden := true
	for c in main.city.get_children():
		if c is BuildingView and c.visible:
			hidden = false
	_expect(hidden, "위에서 보기에선 입체 건물을 숨긴다")
	main.player.global_position = LaneGraph.center(Vector2i(3, 3))
	var start: Vector2 = main.player.global_position
	Input.action_press("accelerate")
	await _frames(20)
	Input.action_release("accelerate")
	var moved: Vector2 = main.player.global_position - start
	_expect(moved.y < -20.0 and absf(moved.x) < 1.0, "위에서 보기에선 W가 북쪽 (%s)" % moved)
	main.set_iso(true)
	await _frames(2)
	_expect(absf(get_viewport().canvas_transform.x.y) > 0.01, "다시 2.5D")
	await _free(main)


func _test_bridge_heights() -> void:
	for k in CityMap.BRIDGES:
		var spans := CityMap.bridge_spans(k)
		_expect(not spans.is_empty(), "다리 %d번에 강 위 구간이 있다" % k)
		var cx := City.road_center(k)
		for span in spans:
			_expect(is_equal_approx(CityMap.ground_height(Vector2(cx, (span.x + span.y) * 0.5)), CityMap.DECK_HEIGHT),
				"다리 %d번 가운데는 상판 높이" % k)
			_expect(is_zero_approx(CityMap.ground_height(Vector2(cx, span.x - 1.0))), "다리 %d번 북쪽 끝 밖은 땅" % k)
			_expect(is_zero_approx(CityMap.ground_height(Vector2(cx, span.y + 1.0))), "다리 %d번 남쪽 끝 밖은 땅" % k)
			var prev := 0.0
			var smooth := true
			for i in 41:
				var h := CityMap.ground_height(Vector2(cx, lerpf(span.y, span.x, i / 40.0)))
				smooth = smooth and absf(h - prev) < CityMap.DECK_HEIGHT * 0.3
				prev = h
			_expect(smooth, "다리 %d번 높이가 갑자기 뛰지 않는다" % k)
	# 다리 아닌 곳: 땅 위 교차로와 강가 가로 도로
	_expect(is_zero_approx(CityMap.ground_height(LaneGraph.center(Vector2i(3, 3)))), "강남 교차로는 땅 높이")
	_expect(is_zero_approx(CityMap.ground_height(Vector2(City.road_center(1), CityMap.bridge_spans(2)[0].x + 500.0))),
		"다리 없는 세로 줄(강 위)은 0")


func _test_bridge_vehicle() -> void:
	var main := _make_main()
	await _frames(2)
	var span: Vector2 = CityMap.bridge_spans(2)[-1]
	var v := Vehicle.new()
	v.stats = load("res://data/vehicles/car_sonato.tres")
	main.add_child(v)
	v.place(Vector2(City.road_center(2) + 48.0, (span.x + span.y) * 0.5), 0.0)
	await _frames(3)
	_expect(is_equal_approx(v.ground, CityMap.DECK_HEIGHT), "다리 위 차는 상판 높이로 그린다 (%.1f)" % v.ground)
	main.set_iso(false)
	await _frames(3)
	_expect(is_zero_approx(v.ground), "위에서 보기에선 다리 높이 0 (%.1f)" % v.ground)
	main.set_iso(true)
	await _free(main)


func _test_landmarks() -> void:
	var main := _make_main(CityMap.LAST_CHAPTER)
	await _frames(3)
	var city: City = main.city
	var space := city.get_world_2d().direct_space_state
	# 큰 랜드마크 다섯 곳 (거리 건물 StreetBuilding도 landmark_indices에 같이 든다 — 공터 길은 큰 것만)
	var big := city.landmark_indices.keys().filter(func(k): return (city.looks[city.landmark_indices[k]] as BuildingType).style in LandmarkBuilding.STYLES)
	_expect(big.size() == 5, "랜드마크 다섯 곳 (%d)" % big.size())
	for key in big:
		var idx: int = city.landmark_indices[key]
		var r := city.buildings[idx]
		var t: BuildingType = city.looks[idx]
		var blocked := 0
		var loops := LandmarkBuilding.walk_loops(r, t)
		for loop in loops:
			for k in loop.size():
				for f in [0.0, 0.25, 0.5, 0.75]:
					if _hits(space, loop[k].lerp(loop[(k + 1) % loop.size()], f), Pedestrian.RADIUS):
						blocked += 1
		_expect(not loops.is_empty() and blocked == 0, "%s: 공터 길이 막히지 않는다 (길 %d, 막힘 %d)" % [key, loops.size(), blocked])
		var solid := LandmarkBuilding.collision_rects(r, t, idx)
		var area := 0.0
		for q in solid:
			area += q.get_area()
		_expect(not solid.is_empty() and _hits(space, solid[0].get_center(), 2.0), "%s: 건물은 막는다" % key)
		_expect(area < r.get_area() * 0.75, "%s: 부지의 1/4 넘게 공터 (막힌 곳 %.0f%%)" % [key, area / r.get_area() * 100.0])
		_expect(city.lot_loops.has(city._owners[idx]), "%s: 보행자가 공터 길을 쓴다" % key)
	# 거리 건물(docs/16): 공터 길이 있는 것(학교 운동장·지하철 광장·인쇄 골목·교회 마당)은 막히지 않아야 한다
	var street := 0
	for key in city.landmark_indices:
		var idx: int = city.landmark_indices[key]
		var t: BuildingType = city.looks[idx]
		if not StreetBuilding.owns(t.style):
			continue
		street += 1
		var loops := LandmarkBuilding.walk_loops(city.buildings[idx], t)
		var blocked := 0
		for loop in loops:
			for k in loop.size():
				for f in [0.0, 0.25, 0.5, 0.75]:
					if _hits(space, loop[k].lerp(loop[(k + 1) % loop.size()], f), Pedestrian.RADIUS):
						blocked += 1
		_expect(blocked == 0, "%s: 공터 길이 막히지 않는다 (길 %d, 막힘 %d)" % [key, loops.size(), blocked])
		var solid := LandmarkBuilding.collision_rects(city.buildings[idx], t, idx)
		_expect(not solid.is_empty() and _hits(space, solid[0].get_center(), 2.0), "%s: 건물은 막는다" % key)
	_expect(street == 10, "거리 건물 열 곳 (%d)" % street)
	var trucks := 0
	for v: Vehicle in main.vehicles:
		if v.stats.resource_path == StreetBuilding.FIRE_TRUCK:
			trucks += 1
	_expect(trucks == 2, "소방서 앞 소방차 2대 (%d)" % trucks)
	var terminal := city.buildings[city.landmark_indices["terminal"]]
	var buses := 0
	for v: Vehicle in main.vehicles:
		if v.stats == main.LANDMARK_BUS and terminal.has_point(v.global_position):
			buses += 1
	_expect(buses == 3, "터미널 승강장에 고속버스 3대 (%d)" % buses)
	# 시장 남쪽 인도에서 입구 문 밑을 지나 골목 안으로 걸어 들어간다
	var market := city.buildings[city.landmark_indices["market"]]
	var player: Player = main.player
	player.screen_walk = false
	player.global_position = Vector2(market.get_center().x, market.end.y + 12.0)
	main.camera.snap()
	Input.action_press("accelerate")
	await _frames(90)
	Input.action_release("accelerate")
	_expect(player.global_position.y < market.end.y - 70.0, "시장 골목 안으로 걸어 들어간다 (%.0f, 부지 끝 %.0f)" % [player.global_position.y, market.end.y])
	await _free(main)


func _hits(space: PhysicsDirectSpaceState2D, at: Vector2, radius: float) -> bool:
	var circle := CircleShape2D.new()
	circle.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, at)
	query.collision_mask = Layers.WORLD
	return not space.intersect_shape(query, 1).is_empty()


func _views_of(city: City, idx: int) -> Array[BuildingView]:
	var out: Array[BuildingView] = []
	for c in city.get_children():
		if c is BuildingView and c.idx == idx:
			out.append(c)
	return out


func _free(main: Node2D) -> void:
	main.queue_free()
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
