extends Node2D
## 실제 City 배치를 사용하는 랜드마크 위치 미리보기. 게임 저장 파일은 사용하지 않는다. 밤: -- --night
func _ready() -> void:
	CityMap.set_chapter(4)
	IsoView.enabled=true
	var city := City.new()
	add_child(city)
	await get_tree().process_frame
	# -- --night: 밤 21시 화면 색과 불빛 (city_landmark_night_*.png)
	var night := "--night" in OS.get_cmdline_user_args()
	if night:
		var dark := CanvasModulate.new()
		dark.color = DayNight.tint(21.0)
		add_child(dark)
		BuildingView.set_lights(DayNight.lights_on(21.0), dark.color)
	for key in city.landmark_indices:
		var idx: int = city.landmark_indices[key]
		var lot: Rect2 = city.buildings[idx]
		var center := lot.get_center()+IsoView.lift(city.building_top(idx)*0.3)
		get_viewport().canvas_transform=IsoView.canvas(get_viewport().get_visible_rect().size,center,0.85)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "res://.screenshots/city_landmark_%s%s.png" % ["night_" if night else "", key]
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		print(key," lot=",lot," saved=",path)
	get_tree().quit()
