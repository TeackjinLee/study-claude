class_name MissionSystem
extends Node2D
## 갱 미션: 공중전화에서 미션을 받고, 단계마다 표적을 세우고, 성공하면 돈과 존경도를 준다.
## 단계 판정은 MissionRun(노드 없는 계산)이 하고, 여기서는 세상에서 사실을 모아 넘기고 스폰·표시만 한다.
##
## 공중전화는 갱마다 셋(쉬움·보통·어려움)씩 묶음으로 있다 (묶음마다 다른 구역).
## 존경도가 모자라면 잠겨 있고, 받을 미션이 있으면 울린다. 미션에 성공하면 라이벌 갱 존경도가 조금 떨어진다.
## 걸어서 전화기를 밟으면 그 전화의 다음 미션이 시작된다.

signal mission_started(mission: MissionType)
signal mission_finished(mission: MissionType, passed: bool, reason: String)
signal phone_refused(text: String)

## 갱 3파 × 공중전화 묶음 2 × 10 = 60개. 데이터는 tools/gen_missions.py가 만든다
const MISSIONS: Array[MissionType] = [
	preload("res://data/missions/gangnam_01.tres"),
	preload("res://data/missions/gangnam_02.tres"),
	preload("res://data/missions/gangnam_03.tres"),
	preload("res://data/missions/gangnam_04.tres"),
	preload("res://data/missions/gangnam_05.tres"),
	preload("res://data/missions/gangnam_06.tres"),
	preload("res://data/missions/gangnam_07.tres"),
	preload("res://data/missions/gangnam_08.tres"),
	preload("res://data/missions/gangnam_09.tres"),
	preload("res://data/missions/gangnam_10.tres"),
	preload("res://data/missions/gangnam_11.tres"),
	preload("res://data/missions/gangnam_12.tres"),
	preload("res://data/missions/gangnam_13.tres"),
	preload("res://data/missions/gangnam_14.tres"),
	preload("res://data/missions/gangnam_15.tres"),
	preload("res://data/missions/gangnam_16.tres"),
	preload("res://data/missions/gangnam_17.tres"),
	preload("res://data/missions/gangnam_18.tres"),
	preload("res://data/missions/gangnam_19.tres"),
	preload("res://data/missions/gangnam_20.tres"),
	preload("res://data/missions/oldtown_01.tres"),
	preload("res://data/missions/oldtown_02.tres"),
	preload("res://data/missions/oldtown_03.tres"),
	preload("res://data/missions/oldtown_04.tres"),
	preload("res://data/missions/oldtown_05.tres"),
	preload("res://data/missions/oldtown_06.tres"),
	preload("res://data/missions/oldtown_07.tres"),
	preload("res://data/missions/oldtown_08.tres"),
	preload("res://data/missions/oldtown_09.tres"),
	preload("res://data/missions/oldtown_10.tres"),
	preload("res://data/missions/oldtown_11.tres"),
	preload("res://data/missions/oldtown_12.tres"),
	preload("res://data/missions/oldtown_13.tres"),
	preload("res://data/missions/oldtown_14.tres"),
	preload("res://data/missions/oldtown_15.tres"),
	preload("res://data/missions/oldtown_16.tres"),
	preload("res://data/missions/oldtown_17.tres"),
	preload("res://data/missions/oldtown_18.tres"),
	preload("res://data/missions/oldtown_19.tres"),
	preload("res://data/missions/oldtown_20.tres"),
	preload("res://data/missions/smuggler_01.tres"),
	preload("res://data/missions/smuggler_02.tres"),
	preload("res://data/missions/smuggler_03.tres"),
	preload("res://data/missions/smuggler_04.tres"),
	preload("res://data/missions/smuggler_05.tres"),
	preload("res://data/missions/smuggler_06.tres"),
	preload("res://data/missions/smuggler_07.tres"),
	preload("res://data/missions/smuggler_08.tres"),
	preload("res://data/missions/smuggler_09.tres"),
	preload("res://data/missions/smuggler_10.tres"),
	preload("res://data/missions/smuggler_11.tres"),
	preload("res://data/missions/smuggler_12.tres"),
	preload("res://data/missions/smuggler_13.tres"),
	preload("res://data/missions/smuggler_14.tres"),
	preload("res://data/missions/smuggler_15.tres"),
	preload("res://data/missions/smuggler_16.tres"),
	preload("res://data/missions/smuggler_17.tres"),
	preload("res://data/missions/smuggler_18.tres"),
	preload("res://data/missions/smuggler_19.tres"),
	preload("res://data/missions/smuggler_20.tres"),
]
const TIER_NAMES := ["쉬움", "보통", "어려움"]
const PHONE_REACH := 18.0        ## 전화기를 밟는 거리
const PHONE_REARM := 60.0        ## 이만큼 떨어졌다 다시 와야 또 받는다
const PHONE_PROMPT := 80.0       ## 이 안이면 HUD에 전화 안내
const MAINTAIN_INTERVAL := 1.0
const OFFSCREEN := 950.0

var gangs: GangManager
var respect: Respect
var wallet: Wallet
var director: Director
var player: Player
var police: PoliceDispatcher
var traffic: TrafficSystem
var completed := {}               ## 미션 id → true
var run: MissionRun = null
var vehicle: Vehicle = null       ## 미션 차 (ENTER 단계에서 세운 차)
var targets: Array = []           ## 이번 단계 표적 (GangMember 또는 Vehicle)
var phones: Array[Dictionary] = [] ## {gang, tier, pos, armed}

var _world_vehicles: Array[Vehicle] = []
var _guards: Array[GangMember] = []
var _leftovers: Array[Vehicle] = []
var _maintain_timer := MAINTAIN_INTERVAL
var _time := 0.0


func setup(world_vehicles: Array[Vehicle]) -> void:
	_world_vehicles = world_vehicles


func _ready() -> void:
	z_as_relative = false
	z_index = 4
	for g in gangs.gangs:
		for k in g.phones.size():
			phones.append({"gang": g, "tier": k % 3, "set": k / 3, "pos": g.phones[k], "armed": true})


# ── 미션 목록 ─────────────────────────────────────────────

## 그 갱·그 전화의 다음 미션 (다 끝냈으면 null)
func next_mission(g: GangType, tier: int, phone_set := 0) -> MissionType:
	var best: MissionType = null
	for m in MISSIONS:
		if m.gang == g.id and m.tier == tier and m.phone_set == phone_set and not completed.has(m.id):
			if best == null or m.order < best.order:
				best = m
	return best


## 그 갱 공중전화 중 하나라도 열린 구역에 있다 (HUD 존경도 줄에 넣을지)
func gang_reachable(g: GangType) -> bool:
	for pos in g.phones:
		if CityMap.is_open_block(City.nearest_block(pos)):
			return true
	return false


func by_id(id: StringName) -> MissionType:
	for m in MISSIONS:
		if m.id == id:
			return m
	return null


func active() -> bool:
	return run != null and run.running()


func start(m: MissionType) -> void:
	if active():
		return
	run = MissionRun.new(m)
	run.step_started.connect(_begin_step)
	run.finished.connect(_on_finished)
	_begin_step(0)
	mission_started.emit(m)


## 사망·체포 등 바깥 이유로 실패시킨다
func fail(reason: String) -> void:
	if active():
		run.fail(reason)


# ── 매 프레임 ─────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	_time += delta
	_maintain_timer -= delta
	if _maintain_timer <= 0.0:
		_maintain_timer = MAINTAIN_INTERVAL
		_maintain()
	_check_phones()
	if active():
		run.update(delta, facts())
	queue_redraw()


func facts() -> Dictionary:
	var v := director.current_vehicle
	var target := director.controlled_target()
	var f := {
		"pos": target.global_position,
		"speed": v.speed() if v else player.velocity.length(),
		"in_vehicle": vehicle != null and v == vehicle,
		"vehicle_lost": vehicle != null and (not is_instance_valid(vehicle) or vehicle.wrecked or vehicle.burning >= 0.0),
		"vehicle_health": vehicle.health / vehicle.max_health() if vehicle and is_instance_valid(vehicle) else 1.0,
		"targets_left": targets_left(),
		"wanted": police.wanted.level,
	}
	return f


func targets_left() -> int:
	var n := 0
	for t in targets:
		if not is_instance_valid(t):
			continue
		if t is Vehicle and not (t as Vehicle).wrecked:
			n += 1
		elif t is Pedestrian and not (t as Pedestrian).is_dead():
			n += 1
	return n


func _check_phones() -> void:
	var pos := player.global_position
	var on_foot := director.current_vehicle == null and player.visible and not player.is_dead()
	for p in phones:
		var d := pos.distance_to(p.pos)
		if d > PHONE_REARM:
			p.armed = true
		if d > PHONE_REACH:
			continue
		if not on_foot or not p.armed or d > PHONE_REACH:
			continue
		p.armed = false
		if active():
			continue
		var g: GangType = p.gang
		if not respect.tier_open(g, p.tier):
			phone_refused.emit("%s 존경도 %d 이상 필요" % [g.display_name, Respect.required(g, p.tier)])
			continue
		var m := next_mission(g, p.tier, p.set)
		if m == null:
			phone_refused.emit("이 전화의 일은 모두 끝냈다")
			continue
		start(m)


## 가장 가까운 공중전화 앞이면 HUD에 띄울 안내 (없으면 "")
func phone_prompt() -> String:
	if active() or director.current_vehicle:
		return ""
	var p: Dictionary = {}
	var best := PHONE_PROMPT
	for q in phones:
		var d := player.global_position.distance_to(q.pos)
		if d < best:
			best = d
			p = q
	if p.is_empty():
		return ""
	var g: GangType = p.gang
	var label: String = "%s 공중전화 (%s)" % [g.display_name, TIER_NAMES[p.tier]]
	if not respect.tier_open(g, p.tier):
		return "%s — 존경도 %d 필요" % [label, Respect.required(g, p.tier)]
	var m := next_mission(g, p.tier, p.set)
	return "%s — %s" % [label, m.title if m else "일 없음"]


# ── 단계 · 표적 ───────────────────────────────────────────

func _begin_step(index: int) -> void:
	var s := run.mission.steps[index]
	targets.clear()
	match s.kind:
		MissionStep.Kind.ENTER:
			vehicle = _spawn_vehicle(s, 0)
		MissionStep.Kind.KILL:
			for p in s.npc_points:
				targets.append(_spawn_guard(s.npc, p))
		MissionStep.Kind.DESTROY:
			for k in s.points.size():
				targets.append(_spawn_vehicle(s, k))
			for p in s.npc_points:
				_spawn_guard(s.npc, p)
	if s.wanted > 0:
		police.last_known = director.controlled_target().global_position
		police.wanted.raise_to(s.wanted)


func _spawn_guard(npc: NpcType, pos: Vector2) -> GangMember:
	var m := gangs.spawn_guard(npc, pos)
	_guards.append(m)
	return m


func _spawn_vehicle(s: MissionStep, k: int) -> Vehicle:
	var pos := s.points[k]
	var heading := s.headings[k] if k < s.headings.size() else 0.0
	var v: Vehicle
	if s.moving:
		var piece := traffic.graph.nearest_segment(pos, Vector2.UP.rotated(heading))
		v = traffic.spawn_at(s.vehicle, piece, clampf(piece.project(pos).x, 0.0, piece.length - 1.0))
		v.ai.persistent = true
	else:
		v = Vehicle.new()
		v.stats = s.vehicle
		v.has_driver = s.driver
		add_child(v)
		v.place(pos, heading)
		_world_vehicles.append(v)
	_leftovers.append(v)
	return v


func _on_finished(passed: bool, reason: String) -> void:
	var m := run.mission
	if passed:
		completed[m.id] = true
		wallet.earn(m.reward)
		respect.change(m.gang, m.respect)
		# 라이벌 갱은 언짢아한다
		var g := gangs.gang(m.gang)
		if g and g.rival != &"":
			respect.change(g.rival, -roundi(m.respect * g.rival_share))
	for g in _guards:
		gangs.release(g)
	_guards.clear()
	targets.clear()
	vehicle = null
	mission_finished.emit(m, passed, reason)


## 미션이 끝난 뒤 남은 차는 화면 밖에서 치운다 (주인공이 타고 간 차·잔해는 그대로)
func _maintain() -> void:
	if active():
		return
	var camera := ChaseCamera.current_cam()
	if camera == null:
		return
	for v: Vehicle in _leftovers.duplicate():
		if not is_instance_valid(v) or v.wrecked or v.burning >= 0.0 or v == director.current_vehicle:
			_leftovers.erase(v)
			continue
		if v.global_position.distance_to(camera.global_position) > OFFSCREEN:
			_leftovers.erase(v)
			traffic.remove_ai(v)
			_world_vehicles.erase(v)
			v.queue_free()


# ── HUD에 줄 정보 ─────────────────────────────────────────

## 지금 목표 문구 (미션 중이 아니면 "")
func objective_text() -> String:
	if not active():
		return ""
	var s := run.current()
	if run.needs_vehicle() and director.current_vehicle != vehicle:
		return "미션 차로 돌아가라"
	if (s.kind == MissionStep.Kind.KILL or s.kind == MissionStep.Kind.DESTROY) and targets.size() > 1:
		return "%s (%d/%d)" % [s.text, targets.size() - targets_left(), targets.size()]
	return s.text


## 지금 가야 할 곳 (HUD 화살표·미니맵). 없으면 null
func objective_position() -> Variant:
	if not active():
		return null
	var s := run.current()
	if vehicle and is_instance_valid(vehicle) and director.current_vehicle != vehicle \
			and (s.kind == MissionStep.Kind.ENTER or run.needs_vehicle()):
		return vehicle.global_position
	match s.kind:
		MissionStep.Kind.GOTO, MissionStep.Kind.DELIVER:
			return s.points[0]
		MissionStep.Kind.KILL, MissionStep.Kind.DESTROY:
			var from := director.controlled_target().global_position
			var best: Variant = null
			for t in targets:
				if not is_instance_valid(t) or (t is Vehicle and t.wrecked) or (t is Pedestrian and t.is_dead()):
					continue
				var p: Vector2 = t.global_position
				if best == null or from.distance_to(p) < from.distance_to(best):
					best = p
			return best
	return null


# ── 그리기 ────────────────────────────────────────────────

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var view := get_viewport_rect().size / get_viewport().get_canvas_transform().get_scale() if is_inside_tree() else Vector2.ZERO
	var center := director.controlled_target().global_position
	for p in phones:
		# 화면 근처 전화만 그린다 (도시가 넓다)
		if (p.pos as Vector2).distance_to(center) < view.length() + 100.0 and CityMap.is_open_block(City.nearest_block(p.pos)):
			_draw_phone(p, font)
	if not active():
		return
	var s := run.current()
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	var yellow := Color(1.0, 0.85, 0.2)
	if s.kind == MissionStep.Kind.GOTO or s.kind == MissionStep.Kind.DELIVER:
		var at := s.points[0]
		draw_circle(at, s.radius, Color(yellow, 0.12 + 0.1 * pulse))
		draw_arc(at, s.radius, 0.0, TAU, 40, Color(yellow, 0.8), 3.0)
		draw_arc(at, s.radius * (0.4 + 0.5 * pulse), 0.0, TAU, 32, Color(yellow, 0.5), 2.0)
	if vehicle and is_instance_valid(vehicle) and director.current_vehicle != vehicle and not vehicle.wrecked:
		_draw_pointer(self, vehicle, Color(0.3, 0.9, 1.0), _time)
	for t in targets:
		if not is_instance_valid(t) or (t is Vehicle and t.wrecked) or (t is Pedestrian and t.is_dead()):
			continue
		_draw_pointer(self, t, Color(1.0, 0.25, 0.25), _time)


## 표적 위에서 통통 튀는 역삼각형. 2.5D에서는 차 지붕·머리 위 화면 기준으로 세운다
static func _draw_pointer(ci: CanvasItem, target: Node2D, color: Color, time: float) -> void:
	var bounce := 6.0 * absf(sin(time * 4.0))
	var at := target.global_position
	if IsoView.enabled:
		var height := (target as Vehicle).stats.height + 18.0 if target is Vehicle else IsoView.PERSON_HEIGHT + 10.0
		ci.draw_set_transform_matrix(IsoView.screen_frame(at, height + bounce))
		at = Vector2.ZERO
	else:
		at += Vector2(0, -(44.0 if target is Vehicle else 22.0) - bounce)
	var pts := PackedVector2Array([Vector2(at.x - 9, at.y - 14), Vector2(at.x + 9, at.y - 14), at])
	ci.draw_colored_polygon(pts, color)
	pts.append(pts[0])
	ci.draw_polyline(pts, Color(0, 0, 0, 0.8), 2.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 공중전화 부스: 갱 상징색 지붕, 받을 일이 있으면 울린다(파문)
func _draw_phone(p: Dictionary, font: Font) -> void:
	var g: GangType = p.gang
	var pos: Vector2 = p.pos
	var open := respect.tier_open(g, p.tier)
	var ringing := open and not active() and next_mission(g, p.tier, p.set) != null
	var body := Rect2(pos - Vector2(9, 9), Vector2(18, 18))
	draw_rect(Rect2(body.position + Vector2(3, 3), body.size), Color(0, 0, 0, 0.35))
	draw_rect(body, Color(0.15, 0.55, 0.3) if open else Color(0.3, 0.32, 0.35))
	draw_rect(body.grow(-3), g.color)
	draw_rect(body, g.accent if open else Color(0.5, 0.5, 0.55), false, 2.0)
	draw_rect(Rect2(pos - Vector2(4, 2), Vector2(8, 4)), g.accent if open else Color(0.5, 0.5, 0.55))
	if ringing:
		var k := fmod(_time * 1.5 + p.tier * 0.33, 1.0)
		draw_arc(pos, 12.0 + k * 22.0, 0.0, TAU, 24, Color(g.accent, 0.8 * (1.0 - k)), 2.0)
	draw_string(font, pos + Vector2(-20, 24), TIER_NAMES[p.tier], HORIZONTAL_ALIGNMENT_CENTER, 40, 11,
		Color(1, 1, 1, 0.8 if open else 0.4))
