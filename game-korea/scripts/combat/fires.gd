class_name Fires
extends Node2D
## 땅에 붙은 불 (화염병·화염방사기·헬기 추락). 안에 있는 사람·차가 타고, 시간이 지나면 꺼진다.
## 불이 FIRE_CALL초 넘게 타면 소방차가 출동한다 — 도로로 달려와 불 앞에 서서 물을 뿌려 끈다 (docs/05 §3).
## 소방차는 빼앗을 수 있다 (탈취하면 소방관이 내리고, 그 뒤로는 그냥 차다).

signal fire_started(pos: Vector2)

const DURATION := 9.0
const MAX_FIRES := 24
const PERSON_DPS := 10.0
const VEHICLE_DPS := 14.0
const PLAYER_DPS := 9.0
const DOUSED := 4.0                 ## 물을 맞으면 남은 수명이 이만큼으로 줄어든다
const MERGE := 24.0                 ## 이보다 가까운 불은 하나로 합친다 (화염방사기는 매 틱 불을 놓는다)
const FIRE_CALL := 3.0              ## 이만큼 타면 소방차를 부른다
const TRUCK_SPAWN := [900.0, 1700.0]
const SPRAY_RANGE := 260.0          ## 소방차가 이 안의 불을 끈다
const SPRAY_RATE := 3.5             ## 초당 줄이는 불 수명
const TRUCK_TYPE: VehicleType = preload("res://data/vehicles/sp_fire.tres")

var pedestrians: PedestrianManager
var player: Player
var director: Director
var combat: Combat
var traffic: TrafficSystem
var vehicles: Array[Vehicle] = []
var fires: Array[Dictionary] = []   ## {pos, radius, left, age, by_player, dispatch}
var player_scale := 1.0             ## 주인공이 받는 불 피해 배율 (소방 부업 보너스 0.5)
var truck: Vehicle = null           ## 출동한 소방차
var dispatches := 0                 ## 소방차가 출동한 횟수 (테스트용)
var _time := 0.0


func _ready() -> void:
	z_as_relative = false
	z_index = 3


## pos에 반경 radius 불을 놓는다 (이미 가까이 불이 있으면 그 불을 키운다).
## dispatch가 false면 소방차를 부르지 않는다 (소방 부업 — 주인공이 끄러 간다)
func start(pos: Vector2, radius: float, by_player: bool, duration := DURATION, dispatch := true) -> void:
	for f in fires:
		if (f.pos as Vector2).distance_to(pos) < MERGE:
			f.left = maxf(f.left, duration)
			f.radius = maxf(f.radius, radius)
			return
	if fires.size() >= MAX_FIRES:
		fires.remove_at(0)
	fires.append({"pos": pos, "radius": radius, "left": duration, "age": 0.0, "by_player": by_player, "dispatch": dispatch})
	fire_started.emit(pos)
	if pedestrians:
		pedestrians.scare(pos, radius * 4.0)


## pos 주변 radius 안의 불을 amount초만큼 줄인다 (물대포·소방차). 물을 맞은 불은 아무리 커도 몇 초 안에 꺼진다
func extinguish(pos: Vector2, radius: float, amount: float) -> void:
	for f in fires:
		if (f.pos as Vector2).distance_to(pos) < radius + f.radius:
			f.left = minf(f.left, DOUSED) - amount


func burning_at(pos: Vector2) -> bool:
	for f in fires:
		if (f.pos as Vector2).distance_to(pos) < f.radius:
			return true
	return false


func _physics_process(delta: float) -> void:
	_time += delta
	for f: Dictionary in fires.duplicate():
		f.left -= delta
		f.age += delta
		if f.left <= 0.0:
			fires.erase(f)
			continue
		_burn(f, delta)
	_fire_department(delta)


## 그림은 화면 프레임마다 한 번 (물리 틱마다 부르면 느릴수록 한 프레임에 여러 번 그린다)
func _process(_delta: float) -> void:
	queue_redraw()


func _burn(f: Dictionary, delta: float) -> void:
	var pos: Vector2 = f.pos
	var r: float = f.radius
	if pedestrians:
		for p: Pedestrian in pedestrians.peds.duplicate():
			if not p.is_dead() and p.active and p.global_position.distance_to(pos) < r + Pedestrian.RADIUS:
				pedestrians.damage(p, PERSON_DPS * delta, p.global_position - pos, f.by_player, false)
	for v in vehicles:
		if not v.wrecked and v.global_position.distance_to(pos) < r + v.stats.size.x * 0.5:
			v.take_damage(VEHICLE_DPS * delta, f.by_player)
	if player and player.visible and not player.is_dead() and player.global_position.distance_to(pos) < r + Player.RADIUS:
		player.take_damage(PLAYER_DPS * player_scale * delta)


# ── 소방차 ────────────────────────────────────────────────

func _fire_department(delta: float) -> void:
	if truck and (not is_instance_valid(truck) or truck.wrecked or truck.controlled or not truck.has_driver):
		_release_truck()   # 빼앗기거나 부서졌다
	var target: Variant = null
	for f in fires:
		if f.dispatch and f.age >= FIRE_CALL and (target == null or (f.pos as Vector2).distance_to(_truck_pos()) < (target as Vector2).distance_to(_truck_pos())):
			target = f.pos
	if target == null:
		# 다 껐다: 소방차는 다시 일반 차처럼 달린다
		if truck:
			if truck.pursuit:
				truck.pursuit = null
				truck.siren = false
				traffic.adopt(truck)
			if truck.ai:
				truck.ai.persistent = false
			truck = null
		return
	if truck == null:
		truck = _dispatch(target)
		return
	if truck.pursuit == null:
		traffic.remove_ai(truck)
		truck.pursuit = PursuitAI.new(truck, vehicles)
		truck.siren = true
	truck.pursuit.target = target
	truck.pursuit.target_velocity = Vector2.ZERO
	truck.pursuit.stop_at_target = true
	# 불 앞에 서면 물을 뿌린다
	if truck.global_position.distance_to(target) < SPRAY_RANGE:
		extinguish(truck.global_position, SPRAY_RANGE, SPRAY_RATE * delta)


func _truck_pos() -> Vector2:
	return truck.global_position if truck and is_instance_valid(truck) else Vector2.ZERO


func _dispatch(at: Vector2) -> Vehicle:
	if traffic == null:
		return null
	var pieces := traffic.nearby_segments(TRUCK_SPAWN[0], TRUCK_SPAWN[1], at)
	for attempt in 20:
		if pieces.is_empty():
			return null
		var piece: LanePiece = pieces[traffic.rng.randi() % pieces.size()]
		var s := piece.length * 0.5
		if not traffic.is_clear(piece.point_at(s)):
			continue
		var v := traffic.spawn_at(TRUCK_TYPE, piece, s)
		v.ai.persistent = true
		dispatches += 1
		return v
	return null


func _release_truck() -> void:
	if truck and is_instance_valid(truck):
		truck.pursuit = null
		truck.siren = false
	truck = null


func _draw() -> void:
	# 땅 불 (참고 그림 4행): 그을린 자리와 불빛 위로 작은 불꽃 여럿, 불씨와 연기
	for f in fires:
		var pos: Vector2 = f.pos + IsoView.lift(IsoView.ground(f.pos))   # 다리 위 불은 상판에서 탄다
		var r: float = f.radius
		var fade := clampf(f.left / 1.5, 0.0, 1.0)
		var grow := clampf(f.age / 0.6, 0.3, 1.0)
		var seed := fmod(absf(pos.x * 0.013 + pos.y * 0.007), 10.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		FireFx.char_patch(self, pos, r * 1.1, seed, 0.6 + 0.4 * fade)
		FireFx.glow(self, pos, r * 2.0, 1.4 * fade, _time, seed)
		if IsoView.enabled:
			draw_set_transform_matrix(IsoView.screen_frame(pos))
		else:
			draw_set_transform(pos, 0.0, Vector2.ONE)
		FireFx.smoke(self, Vector2(0, -r * 0.4 - 6.0), _time, 0.45 + r / 50.0, 0.85, 0.55 * fade, seed, 4)
		FireFx.ground_fire(self, Vector2.ZERO, r * grow, _time, seed, fade * (0.6 + 0.4 * grow))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if truck and is_instance_valid(truck) and not fires.is_empty() and truck.pursuit:
		var target: Vector2 = fires[0].pos
		for f in fires:
			if (f.pos as Vector2).distance_to(truck.global_position) < target.distance_to(truck.global_position):
				target = f.pos
		if truck.global_position.distance_to(target) < SPRAY_RANGE:
			_draw_spray(truck.global_position, target)


func _draw_spray(from: Vector2, to: Vector2) -> void:
	for i in 6:
		var k := fmod(_time * 3.0 + i / 6.0, 1.0)
		var p := from.lerp(to, k) + (to - from).orthogonal().normalized() * sin(_time * 9.0 + i) * 8.0
		draw_circle(p, 4.0 + k * 6.0, Color(0.6, 0.85, 1.0, 0.6 * (1.0 - k * 0.5)))
