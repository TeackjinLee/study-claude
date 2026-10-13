class_name SkidMarks
extends Node2D
## 뒷바퀴 스키드 마크. 등록된 모든 차를 본다. 오래된 자국부터 지운다.

const MAX_SEGMENTS := 4000
const MAX_STEP := 60.0   ## 이보다 멀리 점프하면(리셋·순간이동) 자국을 잇지 않는다

var vehicles: Array[Vehicle] = []
var _segments := PackedVector2Array()
var _last := {}          ## Vehicle → 직전 뒷바퀴 위치 [왼쪽, 오른쪽]


func _ready() -> void:
	z_index = -5


func _physics_process(_delta: float) -> void:
	var added := false
	for v in vehicles:
		if not v.is_skidding():
			_last.erase(v)
			continue
		var wheels := v.rear_wheel_positions()
		var prev: Array = _last.get(v, [])
		var up := IsoView.lift(v.ground)   # 2.5D: 다리 위 자국은 상판 높이에 남긴다
		for i in prev.size():
			var d := (prev[i] as Vector2).distance_to(wheels[i])
			if d > 1.0 and d < MAX_STEP:
				_segments.append(prev[i] + up)
				_segments.append(wheels[i] + up)
				added = true
		_last[v] = wheels
	if not added:
		return
	if _segments.size() > MAX_SEGMENTS * 2:
		_segments = _segments.slice(_segments.size() - MAX_SEGMENTS * 2)
	queue_redraw()


func segment_count() -> int:
	return _segments.size() / 2


func _draw() -> void:
	if _segments.size() >= 2:
		draw_multiline(_segments, Color(0.04, 0.04, 0.05, 0.6), 4.0)
