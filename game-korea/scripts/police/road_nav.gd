class_name RoadNav
## 도로 격자 길찾기 (경찰 추격용, 차·도보 공용). 노드 없는 정적 함수.
## 강·잠긴 구역 때문에 도로가 끊기므로 교차로 사이 거리는 열린 도로만 따라 다익스트라로 잰다.
## 목표가 있는 도로 구간이 같으면 거리표를 다시 쓴다 (장이 바뀌면 clear_cache).

const UTURN_PENALTY := 500.0          ## 달리던 방향을 거꾸로 도는 경로에 붙이는 벌점
const TURN_PENALTY := 120.0           ## 꺾는 경로에 붙이는 작은 벌점 — 격자에는 같은 거리의 길이 많아서,
                                      ## 이게 없으면 교차로 바로 앞에서 직진·회전이 뒤집힌다
const CACHE_LIMIT := 64

static var _cache := {}               ## 교차로 → { 교차로: 거기까지 도로 칸 수 }


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


## 교차로 cell에서 target까지 도로로 가는 거리 (못 가면 INF)
static func cost_to(cell: Vector2i, target: Vector2) -> float:
	var best := INF
	for e in road_ends(target):
		var table := _table(e)
		if table.has(cell):
			best = minf(best, table[cell] * City.PITCH + LaneGraph.center(e).distance_to(target))
	return best


## 교차로 e에서 열린 도로로 몇 칸인지 (모든 칸 길이가 같아 너비 우선 탐색이면 된다)
static func _table(e: Vector2i) -> Dictionary:
	if _cache.has(e):
		return _cache[e]
	if _cache.size() > CACHE_LIMIT:
		_cache.clear()
	var steps := {}
	if LaneGraph.has_cell(e):
		steps[e] = 0
		var queue: Array[Vector2i] = [e]
		var head := 0
		while head < queue.size():
			var c := queue[head]
			head += 1
			for d in 4:
				# 거꾸로 퍼지므로 n → c 방향 도로가 열려 있어야 한다 (양방향 도로라 같다)
				if LaneGraph.connected(c, d):
					var n := c + CityMap.STEPS[d]
					if not steps.has(n):
						steps[n] = steps[c] + 1
						queue.append(n)
	_cache[e] = steps
	return steps


## 다음에 향할 교차로. forward가 0이 아니면 그 반대 방향 경로에 벌점을 준다 (차는 쉽게 못 돈다).
static func next_cell(pos: Vector2, forward: Vector2, target: Vector2) -> Vector2i:
	var here := cell_at(pos)
	var options: Array[Vector2i] = []
	if is_cell(here):
		for d in 4:
			if LaneGraph.connected(here, d):
				options.append(here + CityMap.STEPS[d])
	else:
		options = road_ends(pos)
	if options.is_empty():
		return road_ends(pos)[0]
	var best := options[0]
	var best_cost := INF
	for c in options:
		var to := LaneGraph.center(c) - pos
		var cost := to.length() + cost_to(c, target)
		if forward != Vector2.ZERO:
			var along := to.normalized().dot(forward)
			if along < -0.3:
				cost += UTURN_PENALTY
			elif along < 0.7:
				cost += TURN_PENALTY
		if cost < best_cost:
			best_cost = cost
			best = c
	return best


## a에서 b까지 폭 2×half_width의 띠가 건물에 막히지 않았는지 (양옆 두 줄 + 가운데 한 줄 레이캐스트)
static func clear_path(space: PhysicsDirectSpaceState2D, a: Vector2, b: Vector2, half_width: float) -> bool:
	var side := (b - a).normalized().orthogonal() * half_width
	for off in [Vector2.ZERO, side, -side]:
		var q := PhysicsRayQueryParameters2D.create(a + off, b + off, Layers.WORLD)
		if not space.intersect_ray(q).is_empty():
			return false
	return true
