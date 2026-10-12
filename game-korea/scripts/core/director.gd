class_name Director
extends Node
## 조종권 관리자. 지금 플레이어가 사람을 조종하는지 차를 조종하는지는 여기서만 정한다.
## 캐릭터와 차는 서로를 직접 참조하지 않는다.

signal control_changed(target: Node2D)
signal vehicle_stolen(vehicle: Vehicle, driver: Pedestrian)
signal entering_started(vehicle: Vehicle)

const ENTER_RANGE := 90.0        ## 운전석 문에서 이 거리 안이면 탈 수 있다
const ENTER_TIME := 0.25         ## 문까지 가서 타는 시간 (M1 기준: 0.3초 이내)
const MAX_ENTER_SPEED := 200.0   ## 이보다 빠른 차에는 못 탄다
const EJECT_OFFSET := 16.0

var player: Player
var vehicles: Array[Vehicle] = []
var pedestrians: PedestrianManager
var police: PoliceDispatcher   ## 경찰차를 빼앗으면 운전하던 경찰이 내린다 (없으면 null)
var current_vehicle: Vehicle = null

var _entering: Vehicle = null
var _enter_t := 0.0
var _enter_from := Vector2.ZERO


func controlled_target() -> Node2D:
	return current_vehicle if current_vehicle else player


func is_entering() -> bool:
	return _entering != null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("enter_exit"):
		request_enter_exit()


func request_enter_exit() -> void:
	if _entering:
		return
	if current_vehicle:
		exit_vehicle()
	else:
		var v := nearest_enterable()
		if v:
			_begin_enter(v)


func nearest_enterable() -> Vehicle:
	if current_vehicle or not player.visible or not player.input_enabled:
		return null
	var best: Vehicle = null
	var best_d := ENTER_RANGE
	for v in vehicles:
		if v.speed() > MAX_ENTER_SPEED or not v.usable():
			continue
		var d := player.global_position.distance_to(v.door_position(false))
		if d < best_d:
			best_d = d
			best = v
	return best


func _begin_enter(v: Vehicle) -> void:
	_entering = v
	_enter_t = 0.0
	_enter_from = player.global_position
	player.input_enabled = false
	entering_started.emit(v)


func _physics_process(delta: float) -> void:
	if _entering == null:
		return
	_enter_t += delta
	var k := clampf(_enter_t / ENTER_TIME, 0.0, 1.0)
	player.global_position = _enter_from.lerp(_entering.door_position(false), k)
	if k >= 1.0:
		enter_immediately(_entering)


## 걸어가는 연출 없이 바로 태운다 (탑승 완료 시점, 테스트·리셋용)
func enter_immediately(v: Vehicle) -> void:
	_entering = null
	if v.has_driver:
		v.has_driver = false
		var door := v.door_position(false)
		var outward := (door - v.global_position).normalized()
		var driver: Pedestrian = null
		if police and police.owns(v):
			police.eject_crew(v, door + outward * EJECT_OFFSET)
		else:
			driver = pedestrians.spawn_fleeing(door + outward * EJECT_OFFSET, outward, v.stats.driver_npc)
		vehicle_stolen.emit(v, driver)
	current_vehicle = v
	v.controlled = true
	player.set_in_vehicle(true)
	control_changed.emit(v)


## 운전석 쪽으로 내린다. 막혀 있으면 조수석 쪽.
func exit_vehicle() -> void:
	var v := current_vehicle
	if v == null:
		return
	v.controlled = false
	current_vehicle = null
	var spot := v.door_position(false)
	if player.blocked_at(spot):
		spot = v.door_position(true)
	player.global_position = spot
	player.facing = v.motor.heading
	player.set_in_vehicle(false)
	control_changed.emit(player)


func _process(_delta: float) -> void:
	if current_vehicle:
		player.global_position = current_vehicle.global_position
