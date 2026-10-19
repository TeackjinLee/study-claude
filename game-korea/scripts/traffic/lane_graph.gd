class_name LaneGraph
extends RefCounted
## 격자 도시의 차선 그래프. 노드 없이 City·CityMap만으로 만든다.
## 도로가 있는 구간마다 차선을 만든다(잠긴 구역 포함). 잠긴 구간은 exits()·is_open()이 빼 준다.
##
## 방향마다 차로가 둘이다. NPC는 중앙선에서 LANE_OFFSET 떨어진 안쪽 차로를 달리고,
## 바깥 차로(PASS_OFFSET만큼 더 오른쪽)는 갓길 주차와 추월에 쓴다. 우측통행.
## 교차로 회전은 원호다 — 정지선(STOP_LINE)부터 돌기 시작해 반경이 차의 최소 회전 반경보다 크다.
## 고가차도가 넘는 교차로(CityMap.over_axis)는 직진만 있다 — 고가 위는 고가 축, 밑은 다른 축으로 곧장 지난다.

const LANE_OFFSET := 24.0
const PASS_OFFSET := 48.0
const HALF := City.ROAD * 0.5             ## 교차로 상자 반폭
const EDGE := HALF + City.STOP_LINE       ## 교차로 중심 → 정지선 거리
const DIRS: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]   ## 북 동 남 서
const STEPS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const ARC_POINTS := 12
const CONFLICT_DISTANCE := 30.0           ## 두 이동 경로가 이보다 가까우면 동시에 못 지나간다

var segments := {}       ## Vector3i(i, j, dir) → LanePiece
var turns := {}          ## Vector4i(i, j, dir_in, dir_out) → LanePiece
var all_segments: Array[LanePiece] = []
var _conflicts := {}     ## Vector2i(movement_a, movement_b) → true


func _init() -> void:
	for j in range(CityMap.MIN.y, CityMap.MAX.y + 2):
		for i in range(CityMap.MIN.x, CityMap.MAX.x + 2):
			var cell := Vector2i(i, j)
			for d in 4:
				if CityMap.road(cell, d):
					var seg := _make_segment(cell, d)
					segments[Vector3i(i, j, d)] = seg
					all_segments.append(seg)
				if not CityMap.road(cell, (d + 2) % 4):
					continue
				for out in 4:
					if out != (d + 2) % 4 and CityMap.road(cell, out) and allowed(cell, d, out):
						turns[Vector4i(i, j, d, out)] = _make_turn(cell, d, out)
	_build_conflicts()


static func right_of(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)


static func center(cell: Vector2i) -> Vector2:
	return Vector2(City.road_center(cell.x), City.road_center(cell.y))


## 열린 교차로인가 (잠긴 구역·강 위 빈자리는 아니다)
static func has_cell(cell: Vector2i) -> bool:
	return CityMap.is_open_node(cell)


## cell에서 d 방향으로 열린 도로가 이어지는가
static func connected(cell: Vector2i, d: int) -> bool:
	return CityMap.open_road(cell, d)


## 열린 구간인가 (생성·합류는 열린 구간에만)
static func is_open(piece: LanePiece) -> bool:
	return CityMap.open_road(piece.from_cell, piece.dir_in)


## cell에서 dir_in으로 들어와 dir_out으로 나갈 수 있는가 — 고가차도가 넘는 교차로는 직진만
static func allowed(cell: Vector2i, dir_in: int, dir_out: int) -> bool:
	return dir_in == dir_out or CityMap.over_axis(cell) < 0


static func dir_index(v: Vector2i) -> int:
	return STEPS.find(Vector2i(signi(v.x), signi(v.y)))


static func movement(dir_in: int, dir_out: int) -> int:
	return dir_in * 4 + dir_out


## dir_in 방향으로 cell에 들어온 차가 나갈 수 있는 방향 (유턴 제외)
func exits(cell: Vector2i, dir_in: int) -> Array[int]:
	var result: Array[int] = []
	if not CityMap.road(cell, (dir_in + 2) % 4):
		return result
	for out in 4:
		if out != (dir_in + 2) % 4 and connected(cell, out) and allowed(cell, dir_in, out):
			result.append(out)
	return result


func segment(cell: Vector2i, dir: int) -> LanePiece:
	return segments.get(Vector3i(cell.x, cell.y, dir))


func turn(cell: Vector2i, dir_in: int, dir_out: int) -> LanePiece:
	return turns.get(Vector4i(cell.x, cell.y, dir_in, dir_out))


func movements_conflict(a: int, b: int) -> bool:
	return _conflicts.has(Vector2i(a, b))


## pos에서 가장 가까운 구간. heading과 반대로 가는 차선은 건너뛴다(가능하면).
func nearest_segment(pos: Vector2, heading: Vector2) -> LanePiece:
	var best: LanePiece = null
	var best_d := INF
	for seg in all_segments:
		if not is_open(seg):
			continue
		var d := seg.project(pos).y
		if heading != Vector2.ZERO and DIRS[seg.dir_in].dot(heading) < 0.3:
			d += 1000.0
		if d < best_d:
			best_d = d
			best = seg
	return best


func _make_segment(cell: Vector2i, d: int) -> LanePiece:
	var dir := DIRS[d]
	var off := right_of(dir) * LANE_OFFSET
	var a := center(cell) + dir * EDGE + off
	var b := center(cell + STEPS[d]) - dir * EDGE + off
	var piece := LanePiece.new(LanePiece.Kind.SEGMENT, PackedVector2Array([a, b]))
	piece.dir_in = d
	piece.dir_out = d
	piece.from_cell = cell
	piece.to_cell = cell + STEPS[d]
	return piece


func _make_turn(cell: Vector2i, d_in: int, d_out: int) -> LanePiece:
	var piece := LanePiece.new(LanePiece.Kind.TURN, _turn_points(center(cell), d_in, d_out))
	piece.dir_in = d_in
	piece.dir_out = d_out
	piece.from_cell = cell
	piece.to_cell = cell
	piece.turn = 0 if d_out == d_in else (1 if d_out == (d_in + 1) % 4 else -1)
	return piece


## 정지선에서 출구 차선까지. 회전은 두 차선의 교점을 꼭짓점으로 하는 사분원.
## (양쪽 다리 길이가 같으므로 원호가 두 끝에서 정확히 접한다)
static func _turn_points(c: Vector2, d_in: int, d_out: int) -> PackedVector2Array:
	var din := DIRS[d_in]
	var dout := DIRS[d_out]
	var p0 := c - din * EDGE + right_of(din) * LANE_OFFSET
	var p1 := c + dout * EDGE + right_of(dout) * LANE_OFFSET
	if d_in == d_out:
		return PackedVector2Array([p0, p1])
	# p0을 지나 din 방향인 직선과 p1을 지나 dout 방향인 직선의 교점
	var corner := p0 + din * (p1 - p0).dot(din)
	var arc_center := p0 + p1 - corner
	var v0 := p0 - arc_center
	var angle := v0.angle_to(p1 - arc_center)
	var pts := PackedVector2Array()
	for k in ARC_POINTS + 1:
		pts.append(arc_center + v0.rotated(angle * k / ARC_POINTS))
	return pts


## 원점 교차로에서 12가지 이동끼리 경로가 겹치는지 미리 계산한다. 같은 방향에서 들어오는 이동끼리는
## 앞뒤로 줄을 서므로 충돌로 보지 않는다.
func _build_conflicts() -> void:
	var paths := {}
	for d_in in 4:
		for d_out in 4:
			if d_out != (d_in + 2) % 4:
				paths[movement(d_in, d_out)] = _densify(_turn_points(Vector2.ZERO, d_in, d_out), 8.0)
	for a: int in paths:
		for b: int in paths:
			if a / 4 == b / 4:
				continue
			if _min_distance(paths[a], paths[b]) < CONFLICT_DISTANCE:
				_conflicts[Vector2i(a, b)] = true


static func _densify(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(1, pts.size()):
		var n := maxi(1, ceili(pts[i - 1].distance_to(pts[i]) / step))
		for k in n:
			out.append(pts[i - 1].lerp(pts[i], float(k) / n))
	out.append(pts[pts.size() - 1])
	return out


static func _min_distance(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var best := INF
	for p in a:
		for q in b:
			best = minf(best, p.distance_to(q))
	return best
