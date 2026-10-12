class_name LanePiece
extends RefCounted
## 차선 경로 한 조각: 교차로 사이 직선 구간(SEGMENT) 또는 교차로 안 이동(TURN).

enum Kind { SEGMENT, TURN }

var kind: Kind
var points: PackedVector2Array
var cum := PackedFloat32Array()   ## 각 점까지의 누적 길이
var length := 0.0
var dir_in := 0                   ## 들어올 때 진행 방향 (LaneGraph.DIRS 인덱스)
var dir_out := 0                  ## 나갈 때 진행 방향
var from_cell := Vector2i.ZERO    ## SEGMENT: 출발 교차로
var to_cell := Vector2i.ZERO      ## SEGMENT: 도착 교차로 / TURN: 지나는 교차로
var turn := 0                     ## TURN: 0 직진, 1 우회전, -1 좌회전


func _init(p_kind: Kind, p_points: PackedVector2Array) -> void:
	kind = p_kind
	points = p_points
	cum.append(0.0)
	for i in range(1, points.size()):
		length += points[i - 1].distance_to(points[i])
		cum.append(length)


func point_at(s: float) -> Vector2:
	s = clampf(s, 0.0, length)
	for i in range(1, points.size()):
		if s <= cum[i]:
			var seg := cum[i] - cum[i - 1]
			return points[i - 1].lerp(points[i], (s - cum[i - 1]) / seg if seg > 0.0 else 0.0)
	return points[points.size() - 1]


func tangent_at(s: float) -> Vector2:
	s = clampf(s, 0.0, length)
	for i in range(1, points.size()):
		if s <= cum[i]:
			return (points[i] - points[i - 1]).normalized()
	return (points[points.size() - 1] - points[points.size() - 2]).normalized()


## 가장 가까운 점의 (s, 거리)
func project(pos: Vector2) -> Vector2:
	var best_s := 0.0
	var best_d := INF
	for i in range(1, points.size()):
		var a := points[i - 1]
		var ab := points[i] - a
		var t := clampf((pos - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := pos.distance_to(a + ab * t)
		if d < best_d:
			best_d = d
			best_s = cum[i - 1] + t * ab.length()
	return Vector2(best_s, best_d)
