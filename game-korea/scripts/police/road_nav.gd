class_name RoadNav
## 도로 격자 길찾기 (경찰 추격용, 차·도보 공용). 노드 없는 정적 함수.
## 강·잠긴 구역 때문에 도로가 끊기므로 교차로 사이 거리는 열린 도로만 따라 다익스트라로 잰다.
## 목표가 있는 도로 구간이 같으면 거리표를 다시 쓴다 (장이 바뀌면 clear_cache).

const UTURN_PENALTY := 500.0          ## 달리던 방향을 거꾸로 도는 경로에 붙이는 벌점
const TURN_PENALTY := 120.0           ## 꺾는 경로에 붙이는 작은 벌점 — 격자에는 같은 거리의 길이 많아서,
                                      ## 이게 없으면 교차로 바로 앞에서 직진·회전이 뒤집힌다
const CACHE_LIMIT := 64

static var _cache := {}               ## 길찾기 상태(_key) → { 상태: 거기까지 도로 칸 수 }


static func clear_cache() -> void:
	_cache.clear()


## pos가 열린 교차로 상자 안이면 그 교차로, 아니면 INVALID
static func cell_at(pos: Vector2) -> Vector2i:
	var i := roundi((pos.x - City.road_center(0)) / City.PITCH)
	var j := roundi((pos.y - City.road_center(0)) / City.PITCH)
	var cell := Vector2i(i, j)
	if not LaneGraph.has_cell(cell):
		return INVALID
	var c := LaneGraph.center(cell)
	if absf(pos.x - c.x) <= LaneGraph.HALF and absf(pos.y - c.y) <= LaneGraph.HALF:
		return cell
	return INVALID


## 교차로가 아님 (지도 좌표에 음수가 있어 (-1, -1)을 쓸 수 없다)
const INVALID := Vector2i(-9999, -9999)


static func is_cell(c: Vector2i) -> bool:
	return c != INVALID


## pos에서 가장 가까운 열린 도로 구간의 양 끝 교차로 (인도·건물 위여도 가장 가까운 도로로 본다)
static func road_ends(pos: Vector2) -> Array[Vector2i]:
	var fx := (pos.x - City.road_center(0)) / City.PITCH
	var fy := (pos.y - City.road_center(0)) / City.PITCH
	var base := Vector2i(floori(fx), floori(fy))
	var best: Array[Vector2i] = []
	var best_d := INF
	for dj in range(-1, 3):
		for di in range(-1, 3):
			var c := base + Vector2i(di, dj)
			for d in [1, 2]:
				if not LaneGraph.connected(c, d):
					continue
				var a := LaneGraph.center(c)
				var b := LaneGraph.center(c + CityMap.STEPS[d])
				var dist := Geometry2D.get_closest_point_to_segment(pos, a, b).distance_to(pos)
				if dist < best_d:
					best_d = dist
					best = [c, c + CityMap.STEPS[d]]
	if best.is_empty():
		return [base, base]
	return best


## pos에서 가장 가까운 도로 구간의 양 끝 길찾기 상태 (고가차도 층 level: 1이면 고가 구간만, 0이면 고가 구간을 빼고, -1이면 아무거나).
## 넘는 교차로 끝은 그 구간의 축으로 지난다
static func _end_keys(pos: Vector2, level: int) -> Array[Vector3i]:
	var fx := (pos.x - City.road_center(0)) / City.PITCH
	var fy := (pos.y - City.road_center(0)) / City.PITCH
	var base := Vector2i(floori(fx), floori(fy))
	for pass_level in [level, -1]:
		var best: Array[Vector3i] = []
		var best_d := INF
		for dj in range(-1, 3):
			for di in range(-1, 3):
				var c := base + Vector2i(di, dj)
				for d in [1, 2]:
					if not LaneGraph.connected(c, d):
						continue
					if pass_level >= 0 and CityMap.over_strip(c, d) != (pass_level == 1):
						continue
					var a := LaneGraph.center(c)
					var b := LaneGraph.center(c + CityMap.STEPS[d])
					var dist := Geometry2D.get_closest_point_to_segment(pos, a, b).distance_to(pos)
					if dist < best_d:
						best_d = dist
						best = [_key(c, d % 2), _key(c + CityMap.STEPS[d], d % 2)]
		if not best.is_empty():
			return best
	return [_key(base, -1), _key(base, -1)]


## 길찾기 상태: 보통 교차로는 (x, y, -1), 고가차도가 넘는 교차로는 (x, y, 지나는 축) — 넘는 교차로는 직진만 되므로
## 위(고가 축)와 밑(다른 축)이 다른 자리다. 축은 진행 방향 d의 d % 2 (0 세로·1 가로)
static func _key(c: Vector2i, axis: int) -> Vector3i:
	return Vector3i(c.x, c.y, axis if CityMap.over_axis(c) >= 0 else -1)


## 상태 key에서 target까지 도로로 가는 거리 (못 가면 INF). target_level은 목표의 고가차도 층
static func _cost(key: Vector3i, target: Vector2, target_level: int) -> float:
	var best := INF
	for e in _end_keys(target, target_level):
		var table := _table(e)
		if table.has(key):
			best = minf(best, table[key] * City.PITCH + LaneGraph.center(Vector2i(e.x, e.y)).distance_to(target))
	return best


## 상태 e에서 열린 도로로 몇 칸인지 (모든 칸 길이가 같아 너비 우선 탐색이면 된다)
static func _table(e: Vector3i) -> Dictionary:
	if _cache.has(e):
		return _cache[e]
	if _cache.size() > CACHE_LIMIT:
		_cache.clear()
	var steps := {}
	if LaneGraph.has_cell(Vector2i(e.x, e.y)):
		steps[e] = 0
		var queue: Array[Vector3i] = [e]
		var head := 0
		while head < queue.size():
			var k := queue[head]
			head += 1
			var c := Vector2i(k.x, k.y)
			for d in 4:
				# 넘는 교차로에서는 지나는 축으로만 이어진다. 양방향 도로라 거꾸로 퍼져도 같다
				if k.z >= 0 and d % 2 != k.z:
					continue
				if LaneGraph.connected(c, d):
					var n := _key(c + CityMap.STEPS[d], d % 2)
					if not steps.has(n):
						steps[n] = steps[k] + 1
						queue.append(n)
	_cache[e] = steps
	return steps


## 다음에 향할 교차로. forward가 0이 아니면 그 반대 방향 경로에 벌점을 준다 (차는 쉽게 못 돈다).
## level은 나의, target_level은 목표의 고가차도 층(-1 모름) — 넘는 교차로에서는 달리던 축으로만 나가고, 서 있으면 층으로 정한다
static func next_cell(pos: Vector2, forward: Vector2, target: Vector2, level := 0, target_level := -1) -> Vector2i:
	var here := cell_at(pos)
	var options: Array[Vector3i] = []
	if is_cell(here):
		var over := CityMap.over_axis(here)
		var axis := -1
		if over >= 0:
			if forward != Vector2.ZERO:
				axis = 1 if absf(forward.x) > absf(forward.y) else 0
			else:
				axis = over if level == 1 else 1 - over
		for d in 4:
			if (axis < 0 or d % 2 == axis) and LaneGraph.connected(here, d):
				options.append(_key(here + CityMap.STEPS[d], d % 2))
	else:
		options = _end_keys(pos, level)
	if options.is_empty():
		var e := _end_keys(pos, level)[0]
		return Vector2i(e.x, e.y)
	var best := options[0]
	var best_cost := INF
	for k in options:
		var to := LaneGraph.center(Vector2i(k.x, k.y)) - pos
		var cost := to.length() + _cost(k, target, target_level)
		if forward != Vector2.ZERO:
			var along := to.normalized().dot(forward)
			if along < -0.3:
				cost += UTURN_PENALTY
			elif along < 0.7:
				cost += TURN_PENALTY
		if cost < best_cost:
			best_cost = cost
			best = k
	return Vector2i(best.x, best.y)


## a에서 b까지 폭 2×half_width의 띠가 건물에 막히지 않았는지 (양옆 두 줄 + 가운데 한 줄 레이캐스트)
## level은 고가차도 층 (고가 위면 난간에 막히는지 본다)
static func clear_path(space: PhysicsDirectSpaceState2D, a: Vector2, b: Vector2, half_width: float, level := 0) -> bool:
	var side := (b - a).normalized().orthogonal() * half_width
	for off in [Vector2.ZERO, side, -side]:
		var q := PhysicsRayQueryParameters2D.create(a + off, b + off, Layers.at(Layers.WORLD, level))
		if not space.intersect_ray(q).is_empty():
			return false
	return true
