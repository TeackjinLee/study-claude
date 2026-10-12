extends "res://tools/isometric_sample/renderer.gd"
## 게임에 쓰는 같은 렌더러로 대표 차종을 크게 보여주는 외형 도감.

var cars: Array[Vehicle] = []

func _ready() -> void:
	font = ThemeDB.fallback_font
	vehicle_height_scale = 3.0
	basis = Transform2D(Vector2(2.4,1.2),Vector2(-2.4,1.2),Vector2.ZERO)
	for file in ["car_sonato", "car_taxi", "police_patrol", "car_avela_r", "car_sorea", "trk_porta", "bus_city", "sp_ambulance"]:
		var car := Vehicle.new()
		car.stats = load("res://data/vehicles/" + file + ".tres")
		add_child(car)
		car.hide()
		car.set_physics_process(false)
		cars.append(car)
	queue_redraw()
	if "--preview-shot" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.screenshots/m7_vehicle_lineup.png"))
		print("차량 도감 저장: ", error)
		get_tree().quit()

func _draw() -> void:
	draw_rect(get_viewport_rect(),Color("101a27"))
	draw_string(font,Vector2(35,46),"서울 거리 프로젝트 / 2.5D 차량 외형",HORIZONTAL_ALIGNMENT_LEFT,-1,26,Color("e0e7eb"))
	draw_string(font,Vector2(35,75),"게임 렌더러 확대 보기 · 가상 차종 · 코드 기반 아트 초안",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("8fabbc"))
	for idx in cars.size():
		var corner := Vector2(24 + (idx%4)*310,110 + (idx/4)*288)
		draw_rect(Rect2(corner,Vector2(296,270)),Color("1c2b3b"))
		origin = corner + Vector2(148,151)
		preload("res://tools/isometric_sample/vehicle_drawer.gd").draw(self,cars[idx])
		draw_string(font,corner+Vector2(18,242),cars[idx].stats.display_name,HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("dce8eb"))
