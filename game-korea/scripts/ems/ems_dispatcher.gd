class_name EmsDispatcher
extends Node2D
## 구급대: 사람은 죽지 않고 기절한다. 기절한 사람이 생기면 구급차가 사이렌을 켜고 달려와 길가에 서고,
## 구급대원 둘이 내려 들것으로 한 사람씩 구급차 뒤까지 옮겨 싣는다 (한 대에 CAPACITY명). 다 실으면 대원이 타고 떠난다.
## 한 곳(HELI_RADIUS 안)에 HELI_GROUP명 넘게 쓰러져 있으면 병원 옥상 헬기장에 서 있던 구급헬기가 떠서
## 한 사람씩 위에 멈춰 줄로 끌어올리고, 다 태우면 병원 옥상으로 돌아가 내려앉는다.
## 구급대원을 기절시키면 바로 수배 ★4다 (PoliceDispatcher). 구급차를 빼앗거나 부수면 대원은 일을 그만두고 걷는다.
## 무작위는 자기 rng만 쓴다 (교통 rng를 뽑으면 다른 결과 — ★3 도주 등 — 가 바뀐다).

signal heli_launched(at: Vector2)   ## 구급헬기가 떴다

enum Amb { DRIVE, FETCH, CARRY, BOARD }
enum Air { PARKED, TAKEOFF, FLY, PICK, RETURN, LAND }

const AMBULANCE_TYPE: VehicleType = preload("res://data/vehicles/sp_ambulance.tres")
const MEDIC_NPC: NpcType = preload("res://data/npc/paramedic.tres")
const HELI_TYPE: VehicleType = preload("res://data/vehicles/sp_medic_heli.tres")
const SEED := 20261023
const CHECK := 0.5                  ## 이 간격으로 부를지 본다 (초)
const CALL_DELAY := 3.0             ## 기절하고 이만큼 지나면 구급차를 부른다
const REACH := 1600.0               ## 카메라에서 이 안의 기절한 사람만 부른다
const MAX_AMBULANCES := 2           ## 동시에 출동하는 구급차
const CAPACITY := 2                 ## 구급차 한 대가 싣는 사람
const GROUP := 260.0                ## 첫 사람에게서 이 안의 사람을 같은 구급차가 맡는다
const SPAWN := [900.0, 1700.0]      ## 구급차는 이 거리의 도로에서 나타난다
const PARK := 60.0                  ## 길가 정지점에 이만큼 다가가 서면 대원이 내린다
const DEPLOY_NEAR := 220.0          ## 막혀 섰어도 환자가 이 안이면 내린다
const DRIVE_TIMEOUT := 60.0         ## 이만큼 달려도 못 닿으면 그만둔다
const STRETCHER := 26.0             ## 들것 앞뒤 대원 사이
const CARRY_SPEED := 70.0           ## 들것을 들고 걷는 빠르기
const GRAB := 6.0                   ## 대원이 들것 자리에 이만큼 붙으면 든다
const BOARD_REACH := 8.0
const WORK_TIMEOUT := 40.0          ## 대원이 이만큼 한 사람에게 매여 있으면 (막혔다) 그만둔다
const OFFSCREEN := 950.0            ## 일을 그만둔 대원은 카메라에서 이만큼 멀어지면 치운다
const HELI_GROUP := 10              ## 한 곳에 이만큼 넘게 쓰러지면 구급헬기가 뜬다
const HELI_RADIUS := 380.0
const HELI_CAPACITY := 14
const HELI_HOVER := 60.0            ## 끌어올릴 때 땅에서 이만큼 위에 멈춘다
const HELI_CRUISE := 40.0           ## 병원 옥상보다 이만큼 높이 난다 (차종 fly_height보다 낮으면 그쪽)
const HOIST_TIME := 1.6             ## 한 사람을 끌어올리는 시간
const HELI_REACH := 14.0            ## 이만큼 위에 오면 줄을 내린다

var pedestrians: PedestrianManager
var traffic: TrafficSystem
var vehicles: Array[Vehicle] = []
var enabled := true
var rng := RandomNumberGenerator.new()
var units: Array[Dictionary] = []   ## 출동한 구급차 {car, patients, medics, phase, patient, at, park, time}
var dispatches := 0                 ## 구급차 출동 횟수 (테스트용)
var rescued := 0                    ## 구급차가 실어 간 사람 (테스트용)
var heli: PoliceHeli                ## 병원 구급헬기 (옥상에 서 있다)
var air := Air.PARKED
var pad := Vector2.ZERO             ## 헬리패드 가운데 (월드)
var pad_height := 0.0               ## 헬리패드 높이 (땅 높이 포함)
var heli_calls := 0                 ## 구급헬기 출동 횟수 (테스트용)
var heli_rescued := 0               ## 구급헬기가 끌어올린 사람 (테스트용)
var hoisting: Pedestrian = null     ## 지금 끌어올리는 사람
var _hoist := 0.0
var _trip := 0                      ## 이번 출동에 태운 사람
var _heli_center := Vector2.ZERO
var _strays: Array = []             ## 일을 그만둔 대원 (화면 밖에서 치운다)
var _check := CHECK


func _ready() -> void:
	rng.seed = SEED
	z_as_relative = false
	if vehicles.is_empty() and traffic:
		vehicles = traffic.vehicles
	_setup_heli()


# ── 출동 ──────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	for u: Dictionary in units.duplicate():
		_run(u, delta)
	_heli_step(delta)
	_tidy()
	_check -= delta
	if _check <= 0.0:
		_check = CHECK
		_dispatch()


## 실어 갈 사람: 카메라 가까이에서 기절한 지 CALL_DELAY 지났고, 아무 구급대도 맡지 않았다 (가까운 차례)
func waiting(center: Vector2) -> Array[Pedestrian]:
	var found: Array[Pedestrian] = []
	for p in pedestrians.peds:
		if p.is_dead() and not p.carried and not _claimed(p) and p.dead_time >= CALL_DELAY \
				and p.global_position.distance_to(center) < REACH:
			found.append(p)
	found.sort_custom(func(a: Pedestrian, b: Pedestrian) -> bool:
		return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
	return found


func _claimed(p: Pedestrian) -> bool:
	return p.rescuer != null and is_instance_valid(p.rescuer)


func _dispatch() -> void:
	if not enabled or pedestrians == null:
		return
	var center := _center()
	_launch_heli(center)
	if traffic == null or units.size() >= MAX_AMBULANCES:
		return
	var list := waiting(center)
	if list.is_empty():
		return
	var first := list[0]
	var car := _spawn_ambulance(first.global_position)
	if car == null:
		return
	var u := {"car": car, "patients": [], "medics": [], "phase": Amb.DRIVE, "patient": null,
		"at": Vector2.ZERO, "park": Vector2.ZERO, "time": 0.0}
	for p in list:
		if u.patients.size() < CAPACITY and p.global_position.distance_to(first.global_position) < GROUP:
			p.rescuer = car
			u.patients.append(p)
	units.append(u)
	dispatches += 1


## 환자에게서 SPAWN 거리의 도로에 구급차를 세우고 사이렌을 켠다
func _spawn_ambulance(at: Vector2) -> Vehicle:
	var pieces := traffic.nearby_segments(SPAWN[0], SPAWN[1], at)
	for attempt in 20:
		if pieces.is_empty():
			return null
		var piece: LanePiece = pieces[rng.randi() % pieces.size()]
		var s := piece.length * 0.5
		if not traffic.is_clear(piece.point_at(s)):
			continue
		var v := traffic.spawn_at(AMBULANCE_TYPE, piece, s)
		traffic.remove_ai(v)
		v.pursuit = PursuitAI.new(v, vehicles)
		v.pursuit.stop_at_target = true
		v.pursuit.target = _curb(at)
		v.siren = true
		return v
	return null


## pos에서 가장 가까운 도로 차로 위 점 (구급차가 설 곳)
func _curb(pos: Vector2) -> Vector2:
	var piece := traffic.graph.nearest_segment(pos, Vector2.ZERO)
	if piece == null:
		return pos
	return piece.point_at(clampf(piece.project(pos).x, 0.0, piece.length))


## 구급차 뒷문 앞 (들것을 싣는 곳)
static func rear_of(car: Vehicle) -> Vector2:
	return car.to_global(Vector2(0.0, car.stats.size.y * 0.5 + 10.0))


# ── 구급차 한 대 ──────────────────────────────────────────

func _run(u: Dictionary, delta: float) -> void:
	var car: Vehicle = u.car
	if not is_instance_valid(car) or car.wrecked or car.controlled or not car.has_driver:
		_abort(u)    # 빼앗기거나 부서졌다
		return
	u.patients = u.patients.filter(func(p): return is_instance_valid(p) and p.is_dead() and p.rescuer == car)
	u.time += delta
	if u.phase == Amb.DRIVE:
		if u.patients.is_empty():
			_finish(u)
			return
		var p: Pedestrian = u.patients[0]
		var stop := _curb(p.global_position)
		car.pursuit.target = stop
		var near := car.global_position.distance_to(stop) < PARK or car.global_position.distance_to(p.global_position) < DEPLOY_NEAR
		if near and car.pursuit.is_stopped() and u.time > 1.0:
			_deploy(u)
		elif u.time > DRIVE_TIMEOUT:
			_abort(u)
		return
	car.pursuit.target = u.park    # 대원이 일하는 동안 서 있는다
	_crew(u, delta)


## 길가에 섰다: 뒷문에서 대원 둘이 내린다
func _deploy(u: Dictionary) -> void:
	var car: Vehicle = u.car
	u.park = car.global_position
	for k in 2:
		var m := Paramedic.new()
		var pos := rear_of(car) + car.motor.right() * (8.0 if k == 0 else -8.0)
		m.setup(MEDIC_NPC, rng, City.sidewalk_loop(City.nearest_block(pos)), 0, 0.0, 1)
		m.position = pos
		m.level = car.level
		pedestrians.add(m)
		u.medics.append(m)
	u.phase = Amb.FETCH
	u.time = 0.0


func _crew(u: Dictionary, delta: float) -> void:
	var car: Vehicle = u.car
	for m in u.medics:
		if not is_instance_valid(m) or m.is_dead():
			_abort(u)    # 대원이 기절했다 — 다른 구급차가 대원까지 실어 간다
			return
	if u.time > WORK_TIMEOUT:
		if u.phase == Amb.BOARD:
			for m in u.medics:
				pedestrians.remove(m)    # 길이 막혀 못 돌아왔다 — 탄 것으로 친다
			u.medics.clear()
			_finish(u)
		else:
			_abort(u)
		return
	var a: Paramedic = u.medics[0]
	var b: Paramedic = u.medics[1]
	var rear := rear_of(car)
	var p: Pedestrian = u.patient
	if p != null and (not is_instance_valid(p) or not u.patients.has(p)):
		_drop(u)
		p = null
	match u.phase:
		Amb.FETCH:
			if p == null:
				p = _next_patient(u, rear)
				u.patient = p
			if p == null:
				u.phase = Amb.BOARD
				u.time = 0.0
				return
			# 들것 앞(구급차 쪽)에 a, 뒤에 b
			var dir := (rear - p.global_position).normalized()
			a.goal = p.global_position + dir * STRETCHER * 0.5
			b.goal = p.global_position - dir * STRETCHER * 0.5
			if _at_goal(a) and _at_goal(b):
				u.phase = Amb.CARRY
				u.at = p.global_position
				p.carried = true
				a.steered = true
				b.steered = true
		Amb.CARRY:
			if a.state == Pedestrian.State.KNOCKED or b.state == Pedestrian.State.KNOCKED:
				_drop(u)     # 들던 대원이 넘어졌다 — 내려놓고 다시 든다
				u.patient = p
				return
			var to: Vector2 = rear - u.at
			if to.length() < 4.0:
				pedestrians.remove(p)     # 실었다
				u.patients.erase(p)
				rescued += 1
				u.time = 0.0
				_drop(u)
				return
			var dir: Vector2 = to.normalized()
			u.at += dir * minf(CARRY_SPEED * delta, to.length())
			p.global_position = u.at
			p.facing = Vector2.UP.angle_to(dir)
			for k in 2:
				var m: Paramedic = u.medics[k]
				m.global_position = u.at + dir * STRETCHER * (0.5 if k == 0 else -0.5)
				m.facing = p.facing
				m.velocity = dir * CARRY_SPEED
				m.walk_phase += delta * CARRY_SPEED / 9.0
		Amb.BOARD:
			a.goal = rear
			b.goal = rear
			if a.global_position.distance_to(rear) < BOARD_REACH and b.global_position.distance_to(rear) < BOARD_REACH:
				for m in u.medics:
					pedestrians.remove(m)
				u.medics.clear()
				_finish(u)


func _at_goal(m: Paramedic) -> bool:
	return m.state == Pedestrian.State.WALK and m.global_position.distance_to(m.goal) < GRAB


func _next_patient(u: Dictionary, from: Vector2) -> Pedestrian:
	var best: Pedestrian = null
	for p: Pedestrian in u.patients:
		if best == null or p.global_position.distance_to(from) < best.global_position.distance_to(from):
			best = p
	return best


## 들것을 내려놓는다 (대원은 다시 걷는다)
func _drop(u: Dictionary) -> void:
	var p: Pedestrian = u.patient
	if p != null and is_instance_valid(p):
		p.carried = false
	u.patient = null
	for m in u.medics:
		if is_instance_valid(m):
			m.steered = false
	if u.phase == Amb.CARRY:
		u.phase = Amb.FETCH


## 다 실었다: 구급차는 사이렌을 끄고 일반 차처럼 달리다 멀어지면 사라진다
func _finish(u: Dictionary) -> void:
	units.erase(u)
	_release(u.car)


## 그만둔다: 맡은 사람을 놓고, 대원은 평범하게 걷고, 구급차는 (멀쩡하면) 일반 차가 된다
func _abort(u: Dictionary) -> void:
	units.erase(u)
	_drop(u)
	for p in u.patients:
		if is_instance_valid(p) and p.rescuer == u.car:
			p.rescuer = null
	for m in u.medics:
		if is_instance_valid(m) and not m.is_dead():
			m.off_duty()
			_strays.append(m)
	var car: Vehicle = u.car
	if is_instance_valid(car) and not car.wrecked and not car.controlled and car.has_driver:
		_release(car)


func _release(car: Vehicle) -> void:
	if not is_instance_valid(car):
		return
	car.pursuit = null
	car.siren = false
	if car.has_driver and not car.controlled and not car.wrecked and traffic:
		traffic.adopt(car)


## 일을 그만둔 대원은 화면 밖에서 치운다
func _tidy() -> void:
	if _strays.is_empty():
		return
	var center := _center()
	for m in _strays.duplicate():
		if not is_instance_valid(m):
			_strays.erase(m)
		elif not m.is_dead() and m.global_position.distance_to(center) > OFFSCREEN:
			_strays.erase(m)
			pedestrians.remove(m)


func _center() -> Vector2:
	var cam := ChaseCamera.current_cam() if is_inside_tree() else null
	if cam:
		return cam.global_position
	return pedestrians.player.global_position if pedestrians and pedestrians.player else Vector2.ZERO


# ── 병원 구급헬기 ─────────────────────────────────────────

## 강남 병원 옥상 헬리패드에 날개를 세운 헬기를 둔다
func _setup_heli() -> void:
	var lot := City.block_rect(City.HOSPITAL.x, City.HOSPITAL.y).grow(-City.SIDEWALK)
	pad = SpecialBuilding.hospital_helipad(lot).get_center()
	pad_height = IsoView.ground(pad) + SpecialBuilding.hospital_pad_height(City.HOSPITAL_FLOORS * IsoView.FLOOR_HEIGHT)
	heli = PoliceHeli.new()
	heli.stats = HELI_TYPE
	heli.searchlight = false
	heli.beacons = false
	heli.hover_radius = 0.0
	heli.parked = true
	heli.height = pad_height
	heli.target = pad
	heli.position = pad
	add_child(heli)


func cruise_height() -> float:
	return maxf(HELI_TYPE.fly_height, pad_height + HELI_CRUISE)


## 한 곳에 HELI_GROUP명 넘게 쓰러져 있으면 헬기를 띄운다 (헬기가 옥상에 서 있을 때만)
func _launch_heli(center: Vector2) -> void:
	if heli == null or air != Air.PARKED:
		return
	var down: Array[Pedestrian] = []
	for p in pedestrians.peds:
		if p.is_dead() and not p.carried and p.global_position.distance_to(center) < REACH:
			down.append(p)
	if down.size() < HELI_GROUP:
		return
	for p in down:
		var group: Array[Pedestrian] = []
		for q in down:
			if q.global_position.distance_to(p.global_position) < HELI_RADIUS:
				group.append(q)
		if group.size() < HELI_GROUP:
			continue
		var sum := Vector2.ZERO
		for q in group:
			sum += q.global_position
			if not _claimed(q):
				q.rescuer = heli
		_heli_center = sum / group.size()
		air = Air.TAKEOFF
		heli.parked = false
		heli.height = cruise_height()
		heli_calls += 1
		heli_launched.emit(_heli_center)
		return


func _heli_step(delta: float) -> void:
	if heli == null or not is_instance_valid(heli):
		return
	var at := heli.global_position
	match air:
		Air.TAKEOFF:
			heli.target = pad
			if heli.altitude() >= cruise_height() - 1.0:
				air = Air.FLY
		Air.FLY:
			heli.target = _heli_center
			if at.distance_to(_heli_center) < 40.0:
				air = Air.PICK
		Air.PICK:
			_pick(delta)
		Air.RETURN:
			heli.target = pad
			heli.height = cruise_height()
			if at.distance_to(pad) < 10.0:
				air = Air.LAND
				heli.height = pad_height
		Air.LAND:
			heli.target = pad
			if heli.altitude() <= pad_height + 0.5 and at.distance_to(pad) < 6.0:
				heli.parked = true
				heli.global_position = pad
				air = Air.PARKED


## 쓰러진 사람 위에 차례로 멈춰 줄로 끌어올린다. 다 태우면(또는 가득 차면) 돌아간다
func _pick(delta: float) -> void:
	if hoisting != null:
		if not is_instance_valid(hoisting):
			hoisting = null
			return
		_hoist += delta
		queue_redraw()
		if _hoist >= HOIST_TIME:
			pedestrians.remove(hoisting)
			hoisting = null
			heli_rescued += 1
			queue_redraw()
		return
	var next: Pedestrian = null
	if _trip < HELI_CAPACITY:
		for p in pedestrians.peds:
			if not p.is_dead() or p.carried or p.global_position.distance_to(_heli_center) > HELI_RADIUS:
				continue
			if _claimed(p) and p.rescuer != heli:
				continue    # 구급차가 맡았다
			if next == null or p.global_position.distance_to(heli.global_position) < next.global_position.distance_to(heli.global_position):
				next = p
	if next == null:
		air = Air.RETURN
		_trip = 0
		return
	next.rescuer = heli
	heli.target = next.global_position
	var hover := IsoView.ground(next.global_position, next.level) + HELI_HOVER
	heli.height = hover
	if heli.global_position.distance_to(next.global_position) < HELI_REACH and heli.altitude() <= hover + 2.0:
		hoisting = next
		_hoist = 0.0
		_trip += 1
		next.carried = true
		next.visible = false   # 들것 바구니에 실려 줄을 타고 오른다 (_draw)


## 2.5D: 헬기에서 내려온 줄과 오르는 들것 바구니
func _process(_delta: float) -> void:
	z_index = IsoView.Z_AIR - 1 if IsoView.enabled else 19


func _draw() -> void:
	if hoisting == null or not is_instance_valid(hoisting) or heli == null:
		return
	var k := clampf(_hoist / HOIST_TIME, 0.0, 1.0)
	var foot := hoisting.global_position
	var ground := IsoView.ground(foot, hoisting.level)
	var top := heli.global_position + (IsoView.lift(heli.altitude()) if IsoView.enabled else Vector2.ZERO)
	var basket := foot + (IsoView.lift(lerpf(ground, heli.altitude() - 6.0, k)) if IsoView.enabled else Vector2.ZERO)
	draw_line(top, basket, Color(0.15, 0.15, 0.17, 0.9), 1.2)
	draw_set_transform(basket, hoisting.facing, Vector2.ONE)
	draw_rect(Rect2(-6, -15, 12, 30), Color(0.95, 0.5, 0.12))
	draw_rect(Rect2(-4, -12, 8, 24), Color(0.94, 0.95, 0.97))
	draw_rect(Rect2(-3, -9, 6, 14), hoisting.shirt)            # 실린 사람 (몸·머리)
	draw_circle(Vector2(0, -11), 3.0, Color(0.93, 0.78, 0.65))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
