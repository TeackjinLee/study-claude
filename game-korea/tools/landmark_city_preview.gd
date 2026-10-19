extends Node2D
## 실제 City 배치를 사용하는 랜드마크 위치 미리보기. 게임 저장 파일은 사용하지 않는다. 밤: -- --night
## 한 곳만 크게: -- --only=market --zoom=2 (city_landmark_<키>_z2.png)
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
	var only := ""
	var zoom := 0.85
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))
	for key in city.landmark_indices:
		if only != "" and key != only:
			continue
		var idx: int = city.landmark_indices[key]
		var lot: Rect2 = city.buildings[idx]
		var center := lot.get_center()+IsoView.lift(city.building_top(idx)*0.3)
		get_viewport().canvas_transform=IsoView.canvas(get_viewport().get_visible_rect().size,center,zoom)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "res://.screenshots/city_landmark_%s%s%s.png" % ["night_" if night else "", key,
			"" if zoom == 0.85 else "_z%s" % str(zoom).replace(".", "_")]
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		print(key," lot=",lot," saved=",path)
	get_tree().quit()
