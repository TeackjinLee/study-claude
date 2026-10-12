extends Control
## 화면 크기에 맞춘 가벼운 빗줄기. 시각 효과만 있으며 게임 날씨·접지력은 바꾸지 않는다.

var drops := 90
var rain_enabled := true
var elapsed := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()


func _draw() -> void:
	var view := get_viewport_rect().size
	# 외곽만 어둡게 해 화면 가운데 도로와 차량을 읽기 쉽게 한다.
	for k in 16:
		var opacity := 0.018 * (1.0 - k / 16.0)
		draw_rect(Rect2(Vector2(k * 4, k * 3), view - Vector2(k * 8, k * 6)), Color(0.01, 0.02, 0.06, opacity), false, 8)
	if not rain_enabled:
		return
	for k in drops:
		var x := fposmod(k * 139.7 - elapsed * (80 + k % 30), view.x + 40) - 20
		var y := fposmod(k * 73.3 + elapsed * (310 + k % 100), view.y + 50) - 25
		var a := Vector2(x, y)
		draw_line(a, a + Vector2(-3, 10 + k % 6), Color(0.65, 0.79, 0.92, 0.08 + (k % 4) * 0.015), 1)
