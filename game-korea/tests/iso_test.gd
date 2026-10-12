extends Node
## 2.5D 화면 검증 (물리는 2D 그대로, 그림만 사선).
##  1. 수식: 높이는 화면 위로 올라가고, 깊이(x+y)가 클수록 앞에 그린다. W는 화면 위(월드 북서)로 걷는다.
##  2. 카메라: 화면 변환이 사선이고, 조종 대상이 화면 가운데 근처에 보인다. 마우스 역변환이 월드 좌표로 돌아온다.
##  3. 건물: 충돌 건물마다 입체 조각이 있고, 조각은 정사각형에 가깝다. 지붕은 한 조각만 그린다.
##     건물 바로 동·남쪽 인도에 선 사람은 그 건물보다 앞에, 북·서쪽은 뒤에 그린다.
##  4. 주인공이 건물 뒤에 가면 그 건물이 흐려지고, 나오면 다시 진해진다.
##  5. F9: 위에서 보는 화면으로 바꾸면 변환이 회전·기울기 없는 확대로 돌아오고 입체 건물이 숨는다.
## 실행: godot --headless --fixed-fps 60 --path . res://tests/iso_test.tscn

var _failures: Array[String] = []


func _ready() -> void:
	IsoView.enabled = true
	_test_math()
	await _test_camera_and_walk()
	await _test_buildings()
	await _test_fade()
	await _test_toggle()
	IsoView.enabled = true
	if _failures.is_empty():
		print("iso_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _make_main() -> Node2D:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
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
	var square := true
	for v in views:
		if v.roof:
			roofs[v.idx] = roofs.get(v.idx, 0) + 1
		var ratio := maxf(v.part.size.x, v.part.size.y) / minf(v.part.size.x, v.part.size.y)
		if ratio > 1.5:
			square = false
	_expect(roofs.size() == city.buildings.size(), "충돌 건물마다 입체 건물 (%d / %d)" % [roofs.size(), city.buildings.size()])
	_expect(roofs.values().all(func(n): return n == 1), "지붕은 건물마다 한 번")
	_expect(square, "조각은 정사각형에 가깝다")
	_expect(views.all(func(v): return v.visible and v.height >= IsoView.FLOOR_HEIGHT), "입체 건물이 보이고 높이가 있다")
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
