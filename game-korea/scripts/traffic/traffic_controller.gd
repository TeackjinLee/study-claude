class_name TrafficController
extends RefCounted
## 신호등과 교차로 점유 예약.
##
## 차는 정지선에 다가오면 try_reserve()로 자기 이동(들어온 방향→나갈 방향)을 예약한다.
## - 신호 교차로: 내 방향이 초록불일 때만 받는다.
## - 이미 교차로 안에 있는 이동과 경로가 겹치면 거절한다.
## - 겹치는 이동으로 먼저 기다리던 차가 있으면 그 차가 우선이다(좌회전 차가 굶지 않게).
## 교차로를 빠져나가면 release()로 푼다.

enum Light { GREEN, YELLOW, RED }

const GREEN_TIME := 9.0
const YELLOW_TIME := 2.0
const ALL_RED_TIME := 1.0
const CYCLE := (GREEN_TIME + YELLOW_TIME + ALL_RED_TIME) * 2.0

var graph: LaneGraph
var time := 0.0
var signal_offsets := {}   ## 신호 교차로 cell → 주기 오프셋(초)
var _active := {}          ## cell → { 차 id: 이동 }
var _waiting := {}         ## cell → { 차 id: [이동, 기다리기 시작한 시각] }


func _init(p_graph: LaneGraph) -> void:
	graph = p_graph
	# 4지 교차로는 신호등, 3지·2지(다리 위 포함)와 일부 4지는 무신호
	for j in range(CityMap.MIN.y, CityMap.MAX.y + 2):
		for i in range(CityMap.MIN.x, CityMap.MAX.x + 2):
			var cell := Vector2i(i, j)
			var ways := 0
			for d in 4:
				if CityMap.road(cell, d):
					ways += 1
			if ways == 4 and posmod(i + 2 * j, 5) != 0:
				signal_offsets[cell] = posmod(i + j, 4) * 3.0


func advance(delta: float) -> void:
	time += delta


func is_signalized(cell: Vector2i) -> bool:
	return signal_offsets.has(cell)


## dir_in 방향으로 들어오는 차가 보는 신호. 무신호 교차로는 항상 GREEN.
func light(cell: Vector2i, dir_in: int) -> Light:
	if not signal_offsets.has(cell):
		return Light.GREEN
	var t := fposmod(time + signal_offsets[cell] - (dir_in % 2) * CYCLE * 0.5, CYCLE)
	if t < GREEN_TIME:
		return Light.GREEN
	if t < GREEN_TIME + YELLOW_TIME:
		return Light.YELLOW
	return Light.RED


func try_reserve(cell: Vector2i, dir_in: int, dir_out: int, who: int) -> bool:
	var act: Dictionary = _active.get(cell, {})
	if act.has(who):
		return true
	var wait: Dictionary = _waiting.get(cell, {})
	if light(cell, dir_in) != Light.GREEN:
		wait.erase(who)
		return false
	var m := LaneGraph.movement(dir_in, dir_out)
	for other: int in act:
		if graph.movements_conflict(m, act[other]):
			_wait(cell, who, m)
			return false
	var since: float = wait[who][1] if wait.has(who) else time
	for other: int in wait:
		if other == who:
			continue
		var entry: Array = wait[other]
		var other_m: int = entry[0]
		if entry[1] < since and graph.movements_conflict(m, other_m) \
				and light(cell, other_m / 4) == Light.GREEN:
			_wait(cell, who, m)
			return false
	wait.erase(who)
	act[who] = m
	_active[cell] = act
	return true


func release(cell: Vector2i, who: int) -> void:
	if _active.has(cell):
		_active[cell].erase(who)
	if _waiting.has(cell):
		_waiting[cell].erase(who)


func active_count(cell: Vector2i) -> int:
	return _active.get(cell, {}).size()


func _wait(cell: Vector2i, who: int, m: int) -> void:
	var wait: Dictionary = _waiting.get(cell, {})
	if not wait.has(who):
		wait[who] = [m, time]
	_waiting[cell] = wait
