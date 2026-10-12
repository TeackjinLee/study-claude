class_name SideJobs
extends Node2D
## 부업 (docs/05 §5.4): 택시·버스·배달·응급 이송·소방·자경단.
## 부업 차를 몰고 B를 누르면 한 교대(shift)가 시작된다. 단계마다 목표가 하나 나오고(손님·정류장·불·수배 차량),
## 제한 시간 안에 끝내면 보상을 받고 다음 단계로. 시간이 다 되거나, 차에서 오래 내려 있거나, 차가 부서지면 교대가 끝난다.
## 한 교대에 10단계를 다 끝내면 그 부업의 영구 보너스를 얻는다 (best·bonuses는 저장된다).

signal shift_started(job: SideJobType)
signal level_done(job: SideJobType, level: int, reward: int)
signal shift_ended(job: SideJobType, levels: int, reason: String)
signal job_mastered(job: SideJobType)

const OUT_OF_CAR := 8.0          ## 차에서 이만큼 내려 있으면 교대가 끝난다
const ARRIVE := 70.0             ## 목표에서 이 안에
const STOP_SPEED := 60.0         ## 이보다 느리게 서면 '섰다'
const NEAR := [700.0, 1600.0]    ## 태울 곳·정류장·불·수배 차량은 이 거리 사이
const FAR := [1500.0, 3200.0]    ## 내려 줄 곳은 이 거리 사이
const SEED := 6060
const CIV: NpcType = preload("res://data/npc/civ_f.tres")
const CRIMINAL_CAR: VehicleType = preload("res://data/vehicles/car_sonato.tres")
## 보너스: 부업 id → 차 체력 배율을 받는 차 category
const DURABILITY_BONUS := {&"taxi": &"taxi", &"bus": &"bus", &"delivery": &"bike"}

var jobs: Array[SideJobType] = []
var director: Director
var player: Player
var wallet: Wallet
var pedestrians: PedestrianManager
var traffic: TrafficSystem
var fires: Fires
var police: PoliceDispatcher
var missions: MissionSystem
var best := {}                   ## 부업 id → 한 교대에 끝낸 가장 많은 단계
var bonuses := {}                ## 부업 id → true (10단계를 끝냈다)
var rng := RandomNumberGenerator.new()

var job: SideJobType = null      ## 지금 하는 부업 (없으면 null)
var level := 0                   ## 이번 교대에 끝낸 단계
var stage := 0                   ## 단계 안의 차례 (태우기 0 → 내려 주기 1, 버스는 정류장 번호)
var goal := Vector2.ZERO
var time_left := 0.0
var vehicle: Vehicle = null      ## 교대를 시작한 차
var passenger: Pedestrian = null ## 태울 손님·환자
var target: Vehicle = null       ## 자경단: 부술 수배 차량
var _out := 0.0
var _time := 0.0


func _ready() -> void:
	rng.seed = SEED
	z_as_relative = false
	z_index = 4


func active() -> bool:
	return job != null


## 지금 탄 차로 할 수 있는 부업 (없으면 null)
func available() -> SideJobType:
	var v := director.current_vehicle
	if v == null or v.wrecked or active() or (missions and missions.active()):
		return null
	for j in jobs:
		if j.vehicles.has(v.stats.id):
			return j
	return null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("side_job"):
		if active():
			end("그만뒀다")
		elif available():
			start(available())


func start(j: SideJobType) -> void:
	job = j
	level = 0
	vehicle = director.current_vehicle
	_out = 0.0
	if j.kind == SideJobType.Kind.VIGILANTE and police:
		police.wanted.clear()      # 자경단 등록 — 수배를 풀어 준다
	shift_started.emit(j)
	_next_level()


func end(reason: String) -> void:
	if job == null:
		return
	var j := job
	var done := level
	best[j.id] = maxi(best.get(j.id, 0), done)
	_cleanup()
	job = null
	shift_ended.emit(j, done, reason)


func _cleanup() -> void:
	if passenger and is_instance_valid(passenger):
		pedestrians.remove(passenger)
	passenger = null
	if target and is_instance_valid(target) and target.ai:
		target.ai.persistent = false
	target = null


func _next_level() -> void:
	_cleanup()
	stage = 0
	time_left = job.time_limit(level)
	var here := director.controlled_target().global_position
	match job.kind:
		SideJobType.Kind.TAXI, SideJobType.Kind.DELIVERY, SideJobType.Kind.AMBULANCE:
			goal = _sidewalk_point(here, NEAR)
			if job.kind != SideJobType.Kind.DELIVERY:
				passenger = _spawn_waiting(goal, job.kind == SideJobType.Kind.AMBULANCE)
		SideJobType.Kind.BUS:
			goal = _road_point(here, NEAR)
		SideJobType.Kind.FIRE:
			goal = _road_point(here, NEAR)
			if fires:
				fires.start(goal, 60.0, false, 999.0, false)
		SideJobType.Kind.VIGILANTE:
			goal = _road_point(here, NEAR)
			var piece := traffic.graph.nearest_segment(goal, Vector2.ZERO)
			target = traffic.spawn_at(CRIMINAL_CAR, piece, clampf(piece.project(goal).x, 0.0, piece.length - 1.0))
			target.ai.persistent = true


func _physics_process(delta: float) -> void:
	_time += delta
	queue_redraw()
	if job == null:
		return
	time_left -= delta
	if time_left <= 0.0:
		end("시간 초과")
		return
	if vehicle == null or not is_instance_valid(vehicle) or vehicle.wrecked:
		end("차가 부서졌다")
		return
	_out = 0.0 if director.current_vehicle == vehicle else _out + delta
	if _out > OUT_OF_CAR:
		end("차에서 내렸다")
		return
	if director.current_vehicle != vehicle:
		return
	var pos := vehicle.global_position
	var stopped := vehicle.speed() < STOP_SPEED
	match job.kind:
		SideJobType.Kind.TAXI, SideJobType.Kind.DELIVERY, SideJobType.Kind.AMBULANCE:
			if pos.distance_to(goal) < ARRIVE and stopped:
				if stage == 0:
					stage = 1
					if passenger and is_instance_valid(passenger):
						pedestrians.remove(passenger)
					passenger = null
					goal = City.nearest_hospital(pos) if job.kind == SideJobType.Kind.AMBULANCE else _sidewalk_point(pos, FAR)
					time_left = maxf(time_left, job.time_limit(level) * 0.6)
				else:
					_level_done()
		SideJobType.Kind.BUS:
			if pos.distance_to(goal) < ARRIVE and stopped:
				stage += 1
				if stage >= job.stops:
					_level_done()
				else:
					goal = _road_point(pos, NEAR)
		SideJobType.Kind.FIRE:
			if fires == null or not fires.burning_at(goal):
				_level_done()
		SideJobType.Kind.VIGILANTE:
			if target == null or not is_instance_valid(target) or target.wrecked or target.burning >= 0.0:
				_level_done()
			else:
				goal = target.global_position


## 단계 하나를 끝냈다 (테스트에서도 부른다)
func _level_done() -> void:
	var reward := job.reward(level)
	wallet.earn(reward)
	level += 1
	level_done.emit(job, level, reward)
	if level >= job.levels:
		var j := job
		var first := not bonuses.has(j.id)
		bonuses[j.id] = true
		end("완료")
		if first:
			job_mastered.emit(j)
		return
	_next_level()


## 이 부업 보너스를 얻었나
func has_bonus(id: StringName) -> bool:
	return bonuses.has(id)


## 차 category가 받는 체력 배율 (택시·버스·배달 보너스)
func durability_mult(category: StringName) -> float:
	for id: StringName in DURABILITY_BONUS:
		if DURABILITY_BONUS[id] == category and bonuses.has(id):
			return 1.5
	return 1.0


# ── 장소 고르기 ───────────────────────────────────────────

## here에서 band 거리 사이의 열린 블록 인도 위 한 점
func _sidewalk_point(here: Vector2, band: Array) -> Vector2:
	var blocks := PedestrianManager.nearby_blocks(here, band[0], band[1])
	if blocks.is_empty():
		blocks = PedestrianManager.nearby_blocks(here, 0.0, band[1] * 2.0)
	var b := blocks[rng.randi() % blocks.size()]
	var loop := City.sidewalk_loop(b)
	var e := rng.randi() % 4
	return loop[e].lerp(loop[(e + 1) % 4], rng.randf_range(0.25, 0.75))


## here에서 band 거리 사이의 열린 도로 갓길 한 점
func _road_point(here: Vector2, band: Array) -> Vector2:
	var pieces := traffic.nearby_segments(band[0], band[1], here)
	if pieces.is_empty():
		pieces = traffic.nearby_segments(0.0, band[1] * 2.0, here)
	var p: LanePiece = pieces[rng.randi() % pieces.size()]
	var s := p.length * rng.randf_range(0.35, 0.65)
	return p.point_at(s) + LaneGraph.right_of(p.tangent_at(s)) * LaneGraph.PASS_OFFSET * 0.6


func _spawn_waiting(pos: Vector2, injured: bool) -> Pedestrian:
	var p := Pedestrian.new()
	p.setup(CIV, rng, City.sidewalk_loop(City.nearest_block(pos)), 0, 0.0, 1)
	p.position = pos
	pedestrians.add(p)
	if injured:
		p.knock_down(Vector2.UP)
		p.state_time = 9999.0
	else:
		p._set_state(Pedestrian.State.IDLE, 9999.0)
		p.say("택시!", 9999.0)
	return p


# ── HUD ───────────────────────────────────────────────────

func title_text() -> String:
	if job == null:
		return ""
	return "%s %d/%d   %d:%02d" % [job.display_name, level + 1, job.levels, int(time_left) / 60, int(time_left) % 60]


func objective_text() -> String:
	if job == null:
		return ""
	if director.current_vehicle != vehicle:
		return "부업 차로 돌아가라 (%d초)" % ceili(OUT_OF_CAR - _out)
	match job.kind:
		SideJobType.Kind.TAXI:
			return "손님을 태워라" if stage == 0 else "목적지에 내려 줘라"
		SideJobType.Kind.DELIVERY:
			return "가게에서 받아라" if stage == 0 else "주소로 배달해라"
		SideJobType.Kind.AMBULANCE:
			return "환자를 태워라" if stage == 0 else "병원으로 옮겨라"
		SideJobType.Kind.BUS:
			return "정류장에 서라 (%d/%d)" % [stage + 1, job.stops]
		SideJobType.Kind.FIRE:
			return "불을 꺼라 (Ctrl·J 물대포)"
		SideJobType.Kind.VIGILANTE:
			return "수배 차량을 부숴라"
	return ""


func objective_position() -> Variant:
	if job == null:
		return null
	if director.current_vehicle != vehicle and vehicle and is_instance_valid(vehicle):
		return vehicle.global_position
	return goal


func _draw() -> void:
	if job == null:
		return
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	var cyan := Color(0.35, 0.95, 1.0)
	if job.kind != SideJobType.Kind.VIGILANTE and job.kind != SideJobType.Kind.FIRE:
		draw_circle(goal, ARRIVE, Color(cyan, 0.1 + 0.08 * pulse))
		draw_arc(goal, ARRIVE, 0.0, TAU, 40, Color(cyan, 0.8), 3.0)
		if job.kind == SideJobType.Kind.BUS:
			draw_string(ThemeDB.fallback_font, goal + Vector2(-30, -ARRIVE - 6), "정류장", HORIZONTAL_ALIGNMENT_CENTER, 60, 14, cyan)
	elif target and is_instance_valid(target):
		MissionSystem._draw_pointer(self, target, Color(1.0, 0.3, 0.3), _time)
