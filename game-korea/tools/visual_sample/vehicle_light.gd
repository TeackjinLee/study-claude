extends Node2D
## 시야 안의 실제 차량 위치·회전을 사용하는 바닥 반사. 차체 그림과 물리는 원래 노드가 그린다.

var game: Node2D
var glow: Texture2D
var elapsed := 0.0


func _ready() -> void:
	z_index = 0
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = blend


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(game.camera.global_position - Vector2(1100, 700), Vector2(2200, 1400))
	for car: Vehicle in game.vehicles:
		if not is_instance_valid(car) or car.wrecked or not rect.has_point(car.global_position):
			continue
		draw_set_transform(car.global_position, car.rotation)
		var w := car.stats.size.x
		var h := car.stats.size.y
		if car.occupied():
			for side in [-1.0, 1.0]:
				var front := Vector2(side * w * 0.3, -h * 0.5 - 32)
				draw_texture_rect(glow, Rect2(front - Vector2(25, 75), Vector2(50, 120)), false, Color(1, 0.88, 0.6, 0.26))
				draw_texture_rect(glow, Rect2(Vector2(side * w * 0.3 - 20, h * 0.5 - 10), Vector2(40, 38)), false, Color(1, 0.13, 0.09, 0.2))
		if car.siren:
			var phase := sin(elapsed * 13.0)
			draw_texture_rect(glow, Rect2(-70, -65, 140, 130), false,
				Color(1, 0.08, 0.13, 0.4) if phase > 0 else Color(0.1, 0.3, 1, 0.4))
	draw_set_transform(Vector2.ZERO)
