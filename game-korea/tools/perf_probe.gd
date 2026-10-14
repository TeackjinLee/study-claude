extends Node
## 성능 측정: 본편을 창으로 켜고 봇이 차를 몰아 도시를 돈 뒤, 근처에서 차를 몇 대 불태워 터뜨린다.
## 매 프레임 시간(실제 간격·스크립트·물리·그리기 CPU/GPU)을 모아 평균·상위 1%·끊김(33ms 넘는 프레임)을 출력한다.
## 실행: godot --path . res://tools/perf_probe.tscn            (-- --seconds=40 으로 길이, --chapter=4 로 장)
## -- --uncapped: 프레임 제한·수직 동기화 없이 일의 양만 잰다 (--ablate와 같이 쓴다).
## -- --profile: 노드의 _process/_physics_process를 대신 불러 스크립트별 시간을 재고, 종류별로 숨겨 보며 그리기(_draw) 몫을 잰다 (--burn: 불난 차와 함께).
## -- --ablate: 제자리에서 하나씩 꺼 보며 몫을 잰다. --burn-ablate: 차를 태우는 동안 불·폭발·차·사람을 꺼 본다.
## -- --census: 노드 종류별 수와 종류별로 숨겼을 때의 그리기 호출·도형 수.
## 끝나면 프레임 구간(물리·_process·그리기 반영과 렌더)별 평균도 찍는다.
## 화면이 바뀌는 큰 작업 뒤에 돌려서 전후를 비교한다. 결과는 기계·창 크기에 따라 다르니 같은 조건끼리만 비교한다.

const HITCH_MS := 33.0
const WARMUP := 90

var main: Node2D
var bot: PursuitAI
var _samples: Array = []      ## [실제 간격 ms, 스크립트 ms, 물리 ms, 그리기 CPU ms, GPU ms, 물리 틱 수, 단계]
var _last := 0
var _last_physics := 0
var _frame := 0
var _phase := "주행"
var _targets: Array[Vector2] = []
var _target := 0
var _profile := false
var _owned_p := {}            ## 물리를 대신 불러 주는 노드
var _owned_i := {}            ## _process를 대신 불러 주는 노드
var _cost := {}               ## "스크립트 이름 (물리|프레임)" → [누적 µs, 호출 수]
var _prof_frames := 0
var _tail: Node                ## 맨 마지막에 도는 노드 (프레임 구간 재기)
var _mark := {}                ## 구간 → 누적 µs
var _p_first := 0
var _q_first := 0
var _q_last := 0
var _phys_in_frame := false


func _ready() -> void:
	process_priority = -100000
	process_physics_priority = -100000
	_tail = Tail.new()
	_tail.probe = self
	_tail.process_priority = 100000
	_tail.process_physics_priority = 100000
	add_child(_tail)
	main = load("res://scenes/main.tscn").instantiate()
	main.save_prefix = "user://perf_save_"
	main.load_on_start = false
	main.chapter = clampi(int(_arg("chapter", "3")), 1, CityMap.LAST_CHAPTER)
	add_child(main)
	main.limit_frame_rate()   # 본편과 같게 (Main이 루트가 아니라 스스로 켜지 않는다)
	if "--uncapped" in OS.get_cmdline_user_args():
		# 일의 양만 재기: 프레임 제한·수직 동기화를 끈다 (16.7ms 밑으로 내려가도 보인다)
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	print("화면 주사율 %.0fHz, 물리 %d틱/초, 창 %s" % [DisplayServer.screen_get_refresh_rate(),
		Engine.physics_ticks_per_second, get_viewport().get_visible_rect().size])
	await get_tree().process_frame
	await get_tree().process_frame
	var car: Vehicle = main.start_vehicle
	main.director.enter_immediately(car)
	bot = PursuitAI.new(car, main.vehicles)
	var here := CityMap.block_at(car.global_position)
	for off in [Vector2i(2, 0), Vector2i(2, 2), Vector2i(-1, 2), Vector2i(-1, -1), Vector2i(2, -1), Vector2i(0, 0)]:
		_targets.append(LaneGraph.center(here + off))
	_last = Time.get_ticks_usec()
	_last_physics = Engine.get_physics_frames()
	var seconds := float(_arg("seconds", "40"))
	_profile = "--profile" in OS.get_cmdline_user_args()
	if "--census" in OS.get_cmdline_user_args():
		await get_tree().create_timer(2.0).timeout
		print("  그리기 호출 %d · 도형 %d · 물체 %d" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
		var groups := {
			"모두 보임": func(n): return false,
			"건물 본 조각 숨김(불빛 포함)": func(n): return n is BuildingView and not n.lights,
			"불빛 조각만 숨김": func(n): return n is BuildingView and n.lights,
			"바닥 청크 숨김": func(n): return n is City.Chunk,
			"다리·잠금층 숨김": func(n): return n.get_parent() is City and n is CanvasItem and not n is City.Chunk and not n is BuildingView,
			"차 숨김": func(n): return n is Vehicle,
			"사람 숨김": func(n): return n is Pedestrian or n is Player,
			"HUD 숨김": func(n): return n is CanvasLayer,
		}
		for g: String in groups:
			_each(groups[g], func(n): n.visible = false)
			await get_tree().create_timer(0.6).timeout
			var w := await _window(1.5)
			print("  %-22s 그리기 호출 %5d · 도형 %6d · 프레임 중간 %.2fms" % [g, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), w[3]])
			_each(groups[g], func(n): n.visible = true)
			await get_tree().create_timer(0.6).timeout
		var count := {}
		var vis := {}
		var stack: Array[Node] = [main]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			var k: String = n.get_class() if n.get_script() == null else (n.get_script() as Script).resource_path.get_file()
			if n.get_script() != null and (n.get_script() as Script).resource_path == "":
				k = "내부:" + n.get_class()
			k += " (부모 %s)" % (n.get_parent().get_script().resource_path.get_file() if n.get_parent() and n.get_parent().get_script() else "-")
			count[k] = count.get(k, 0) + 1
			if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
				vis[k] = vis.get(k, 0) + 1
		var keys := count.keys()
		keys.sort_custom(func(a, b): return count[a] > count[b])
		for k in keys.slice(0, 25):
			print("  %-60s %d개 (보임 %d)" % [k, count[k], vis.get(k, 0)])
		get_tree().quit()
		return
	if "--burn-ablate" in OS.get_cmdline_user_args():
		await get_tree().create_timer(4.0).timeout
		_frame = WARMUP + 1
		_burn_nearby()
		await get_tree().create_timer(2.0).timeout
		var fx_tests := {
			"아무것도 안 함": func(_on: bool): pass,
			"차 불·연기층 숨김": func(on: bool): _each(func(n): return n is Vehicle, func(n): n._fx.visible = on),
			"전투(폭발) 숨김": func(on: bool): main.combat.visible = on,
			"땅 불 숨김": func(on: bool): main.fires.visible = on,
			"보행자 숨김": func(on: bool): _each(func(n): return n is Pedestrian, func(n): n.visible = on),
			"차 숨김": func(on: bool): _each(func(n): return n is Vehicle, func(n): n.visible = on),
			"아무것도 안 함 2": func(_on: bool): pass,
		}
		for name: String in fx_tests:
			var base := await _window(1.0)
			fx_tests[name].call(false)
			await get_tree().create_timer(0.2).timeout
			var off := await _window(1.0)
			fx_tests[name].call(true)
			print("  %-14s 기준 중간 %.2fms → 끄면 %.2fms  차이 %+.2f · 불난 차 %d · 잔해 %d" % [name, base[3], off[3], off[3] - base[3],
				main.vehicles.filter(func(v): return v.on_fire or v.burning >= 0.0).size(), main.vehicles.filter(func(v): return v.wrecked).size()])
		get_tree().quit()
		return
	if "--ablate" in OS.get_cmdline_user_args():
		bot = null
		await get_tree().create_timer(3.0).timeout
		_frame = WARMUP + 1
		await _ablate()
		get_tree().quit()
		return
	if _profile:
		await get_tree().create_timer(3.0).timeout
		_adopt()
		if "--burn" in OS.get_cmdline_user_args():
			_burn_nearby()
		await get_tree().create_timer(15.0).timeout
		_print_costs()
		_release()
		await _draw_ablation()
		get_tree().quit()
		return
	await get_tree().create_timer(seconds * 0.7).timeout
	_phase = "폭발"
	_burn_nearby()
	await get_tree().create_timer(seconds * 0.3).timeout
	_report()
	for a in ["accelerate", "brake", "steer_left", "steer_right", "handbrake"]:
		Input.action_release(a)
	get_tree().quit()


func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.split("=", true, 1)[1]
	return fallback


func _physics_process(delta: float) -> void:
	var tp := Time.get_ticks_usec()
	_tick_start = tp
	if not _phys_in_frame:
		_phys_in_frame = true
		if _q_last > 0:
			_add_mark("그리기 반영·렌더·대기 (프레임 끝→물리)", tp - _q_last)
		_p_first = tp
	if _profile and not _owned_p.is_empty():
		for o in _owned_p.keys():
			if not is_instance_valid(o):
				_owned_p.erase(o)
				continue
			var n: Node = o
			if n.is_physics_processing():
				n.set_physics_process(false)   # 스스로 다시 켰다 (보행자 set_active)
			if n is Pedestrian and not n.active:
				continue
			var t0 := Time.get_ticks_usec()
			n._physics_process(delta)
			_add(n, "물리", Time.get_ticks_usec() - t0)
	if bot == null or _targets.is_empty():
		return
	var v := bot.vehicle
	if v.global_position.distance_to(_targets[_target]) < 120.0:
		_target = (_target + 1) % _targets.size()
	bot.target = _targets[_target]
	bot.drive(1.0 / Engine.physics_ticks_per_second)
	for pair in [["accelerate", maxf(v.throttle_input, 0.0)], ["brake", maxf(-v.throttle_input, 0.0)],
			["steer_right", maxf(v.steer_input, 0.0)], ["steer_left", maxf(-v.steer_input, 0.0)],
			["handbrake", 1.0 if v.handbrake_input else 0.0]]:
		if pair[1] > 0.01:
			Input.action_press(pair[0], pair[1])
		else:
			Input.action_release(pair[0])


func _process(delta: float) -> void:
	var tq := Time.get_ticks_usec()
	if _phys_in_frame:
		_add_mark("물리 구간 (틱 전부)", tq - _p_first)
	elif _q_last > 0:
		_add_mark("그리기 반영·렌더·대기 (물리 없음)", tq - _q_last)
	_phys_in_frame = false
	_q_first = tq
	if _profile and not _owned_i.is_empty():
		_prof_frames += 1
		if _prof_frames % 30 == 0:
			_adopt()
		for o in _owned_i.keys():
			if not is_instance_valid(o):
				_owned_i.erase(o)
				continue
			var n: Node = o
			var t0 := Time.get_ticks_usec()
			n._process(delta)
			_add(n, "프레임", Time.get_ticks_usec() - t0)
	var now := Time.get_ticks_usec()
	var phys := Engine.get_physics_frames()
	_frame += 1
	if _frame > WARMUP:
		var vp := get_viewport().get_viewport_rid()
		_samples.append([(now - _last) / 1000.0,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			RenderingServer.viewport_get_measured_render_time_cpu(vp),
			RenderingServer.viewport_get_measured_render_time_gpu(vp),
			phys - _last_physics, _phase])
	_last = now
	_last_physics = phys


## 주인공 차 앞쪽 가까운 차 셋을 불붙여 터뜨린다 (불·연기·폭발·잔해 그림 부하)
func _burn_nearby() -> void:
	var me: Vector2 = bot.vehicle.global_position
	var near: Array = main.vehicles.filter(func(v: Vehicle): return v != bot.vehicle and not v.wrecked)
	near.sort_custom(func(a: Vehicle, b: Vehicle): return a.global_position.distance_to(me) < b.global_position.distance_to(me))
	for i in mini(3, near.size()):
		var v: Vehicle = near[i]
		v.global_position = me + Vector2(300 + i * 120, 200).rotated(bot.vehicle.rotation)
		v.take_damage(v.health - v.max_health() * 0.1, false)
	main.fires.start(me + Vector2(-200, 150), 30.0, false, 9.0, false)


func _report() -> void:
	for phase in ["주행", "폭발"]:
		var rows := _samples.filter(func(s: Array): return s[6] == phase)
		if rows.is_empty():
			continue
		print("── %s: %d프레임" % [phase, rows.size()])
		var names := ["프레임 간격", "스크립트(_process)", "물리(_physics)", "그리기 CPU", "그리기 GPU"]
		for c in names.size():
			var vals: Array = rows.map(func(s: Array): return s[c])
			vals.sort()
			var avg: float = vals.reduce(func(a: float, b: float): return a + b, 0.0) / vals.size()
			print("  %-14s 평균 %6.2fms  중간 %6.2f  상위1%% %6.2f  최대 %6.2f" % [names[c], avg,
				vals[vals.size() / 2], vals[int(vals.size() * 0.99)], vals[-1]])
		var hitches := rows.filter(func(s: Array): return s[0] > HITCH_MS)
		var ticks := {}
		for s: Array in rows:
			ticks[s[5]] = ticks.get(s[5], 0) + 1
		print("  끊김(%.0fms 넘음) %d번 · 프레임당 물리 틱 분포 %s" % [HITCH_MS, hitches.size(), ticks])
		for s: Array in hitches.slice(0, 8):
			print("    %.1fms (스크립트 %.1f, 물리 %.1f, 그리기 %.1f/%.1f, 틱 %d)" % [s[0], s[1], s[2], s[3], s[4], s[5]])


# ── 스크립트별 시간 (--profile) ─────────────────────────

func _adopt() -> void:
	var stack: Array[Node] = [main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n.get_script() == null:
			continue
		if n.is_physics_processing() and n.has_method("_physics_process") and not _owned_p.has(n):
			n.set_physics_process(false)
			_owned_p[n] = true
		if n.is_processing() and n.has_method("_process") and not _owned_i.has(n):
			n.set_process(false)
			_owned_i[n] = true


func _release() -> void:
	for n in _owned_p:
		if is_instance_valid(n) and not (n is Pedestrian and not n.active):
			n.set_physics_process(true)
	for n in _owned_i:
		if is_instance_valid(n):
			n.set_process(true)
	_owned_p.clear()
	_owned_i.clear()


func _add(n: Node, kind: String, us: int) -> void:
	var key := "%s (%s)" % [(n.get_script() as Script).resource_path.get_file(), kind]
	var c: Array = _cost.get(key, [0, 0])
	c[0] += us
	c[1] += 1
	_cost[key] = c


func _print_costs() -> void:
	var keys := _cost.keys()
	keys.sort_custom(func(a, b): return _cost[a][0] > _cost[b][0])
	var frames := maxi(_prof_frames, 1)
	print("── 스크립트별 시간 (%d프레임, 프레임당 ms)" % frames)
	for k in keys.slice(0, 18):
		print("  %-40s %7.2fms  (호출 %d)" % [k, _cost[k][0] / 1000.0 / frames, _cost[k][1]])


## 종류별로 2초씩 숨겨 _draw 몫을 잰다 (숨긴 동안 줄어든 프레임 시간)
func _draw_ablation() -> void:
	var groups := {
		"차": func(n: Node): return n is Vehicle,
		"보행자": func(n: Node): return n is Pedestrian,
		"건물 조각": func(n: Node): return n is BuildingView,
		"전투·불": func(n: Node): return n is Combat or n is Fires,
		"HUD·미니맵": func(n: Node): return n is CanvasLayer,
	}
	var base := await _window(2.0)
	print("── 그리기 몫 (숨기면 줄어드는 프레임 시간, 기준 %.2fms · 스크립트 %.2fms)" % [base[0], base[1]])
	for g: String in groups:
		var hidden: Array[CanvasItem] = []
		var layers: Array[CanvasLayer] = []
		var stack: Array[Node] = [main]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if groups[g].call(n):
				if n is CanvasItem and (n as CanvasItem).visible:
					(n as CanvasItem).visible = false
					hidden.append(n)
				elif n is CanvasLayer and (n as CanvasLayer).visible:
					(n as CanvasLayer).visible = false
					layers.append(n)
				continue
			for c in n.get_children():
				stack.append(c)
		var r := await _window(2.0)
		print("  %-12s %d개 숨김 → 프레임 %.2fms (%+.2f) · 스크립트 %.2fms (%+.2f)" % [g, hidden.size() + layers.size(),
			r[0], r[0] - base[0], r[1], r[1] - base[1]])
		for n in hidden:
			if is_instance_valid(n):
				n.visible = true
		for l in layers:
			l.visible = true
		await get_tree().process_frame


## seconds 동안 평균 [프레임 간격 ms, 스크립트 ms]
func _window(seconds: float) -> Array:
	var start := _samples.size()
	await get_tree().create_timer(seconds).timeout
	var rows := _samples.slice(start)
	if rows.is_empty():
		return [0.0, 0.0]
	var a := 0.0
	var b := 0.0
	var c := 0.0
	for r: Array in rows:
		a += r[0]
		b += r[1]
		c += r[2]
	var gaps: Array = rows.map(func(r: Array): return r[0])
	gaps.sort()
	return [a / rows.size(), b / rows.size(), c / rows.size(), gaps[gaps.size() / 2]]


## 제자리에서 하나씩 끄며 잰다 (기준 · 끈 것 · 기준 … 번갈아 — 상태가 바뀌어 생기는 차이를 줄인다)
func _ablate() -> void:
	var tests := {
		"아무것도 안 함": func(_on: bool): pass,
		"차 숨김": func(on: bool): _each(func(n): return n is Vehicle, func(n): n.visible = on),
		"보행자 숨김": func(on: bool): _each(func(n): return n is Pedestrian, func(n): n.visible = on),
		"건물 조각 숨김": func(on: bool): _each(func(n): return n is BuildingView, func(n): n.visible = on),
		"도시 바닥 숨김": func(on: bool): _each(func(n): return n is City.Chunk, func(n): n.visible = on),
		"도시 나머지 숨김": func(on: bool): _each(func(n): return n.get_parent() is City and not n is City.Chunk and not n is BuildingView and n is CanvasItem, func(n): n.visible = on),
		"HUD·미니맵 숨김": func(on: bool): _each(func(n): return n is CanvasLayer, func(n): n.visible = on),
		"차 물리 끔": func(on: bool): _each(func(n): return n is Vehicle, func(n): n.set_physics_process(on)),
		"보행자 물리 끔": func(on: bool): _each(func(n): return n is Pedestrian, func(n): n.set_physics_process(on and n.active)),
		"교통 끔": func(on: bool): main.traffic.set_physics_process(on),
		"아무것도 안 함 2": func(_on: bool): pass,
	}
	for name: String in tests:
		var base := await _window(2.0)
		tests[name].call(false)
		await get_tree().create_timer(0.5).timeout
		var off := await _window(2.0)
		tests[name].call(true)
		print("  %-14s 기준 중간 %.2fms → 끄면 %.2fms  차이 %+.2f" % [name, base[3], off[3], off[3] - base[3]])
		await get_tree().create_timer(1.5).timeout   # 다시 켤 때 몰려 그리는 것이 지나가게


func _each(match: Callable, act: Callable) -> void:
	var stack: Array[Node] = [main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if match.call(n):
			act.call(n)
			continue
		for c in n.get_children():
			stack.append(c)


func _add_mark(key: String, us: int) -> void:
	var c: Array = _mark.get(key, [0, 0])
	c[0] += us
	c[1] += 1
	_mark[key] = c


var _tick_start := 0


func tail_physics() -> void:
	_add_mark("물리 _physics_process (틱 하나)", Time.get_ticks_usec() - _tick_start)


func tail_process() -> void:
	var t := Time.get_ticks_usec()
	_add_mark("_process 전부", t - _q_first)
	_q_last = t


func _exit_tree() -> void:
	for k in _mark:
		print("  [구간] %-34s 평균 %.2fms (%d번)" % [k, _mark[k][0] / 1000.0 / maxf(_mark[k][1], 1), _mark[k][1]])


class Tail extends Node:
	var probe: Node
	func _process(_delta: float) -> void:
		probe.tail_process()
	func _physics_process(_delta: float) -> void:
		probe.tail_physics()
