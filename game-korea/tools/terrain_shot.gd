extends Node
## 서울 지형(Terrain) 화면을 .screenshots/terrain_*.png로 찍는다 (창이 잠깐 뜬다).
## 실행: godot --path . res://tools/terrain_shot.tscn [-- --day] [--chapter=1 (잠긴 구역 그늘)]

const OUT_DIR := "res://.screenshots/"
## [이름, 블록, 블록 안 위치(0~1), 줌]
const SPOTS := [
	["terrain_namsan", Vector2i(2, -6), Vector2(0.5, 0.9), 0.7],
	["terrain_namsan_near", Vector2i(2, -6), Vector2(0.1, 1.2), 1.1],
	["terrain_jongno_slope", Vector2i(3, -6), Vector2(0.6, 0.6), 1.0],
	["terrain_bukak", Vector2i(3, -11), Vector2(0.5, 0.8), 0.7],
	["terrain_riverside", Vector2i(2, -5), Vector2(0.5, 0.6), 0.6],
	["terrain_gangnam_south", Vector2i(2, 4), Vector2(0.5, 0.5), 0.6],
	["terrain_overpass", Vector2i(1, 2), Vector2(0.6, 0.0), 0.7],
	["terrain_wide", Vector2i(1, -7), Vector2(0.5, 0.5), 0.3],
	["terrain_police", Vector2i(3, -7), Vector2(0.5, 0.5), 1.0],   # 비탈 부지의 단과 축대 (통째 그림)
	["terrain_apt", Vector2i(2, -10), Vector2(0.5, 0.5), 1.0],     # 코드 모형 아파트 단
	["terrain_tower", Vector2i(2, -6), Vector2(0.5, 0.5), 1.0],    # 랜드마크 공터 단
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.save_prefix = "user://screenshot_save_"   # 실제 세이브는 건드리지 않는다
	main.chapter = 4
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--chapter="):   # 잠긴 구역 그늘이 단 위에 제대로 앉는지 볼 때 (예: --chapter=1)
			main.chapter = int(a.get_slice("=", 1))
	add_child(main)
	await _frames(30)
	var cam: ChaseCamera = main.camera
	cam.target = null
	if "--day" in OS.get_cmdline_user_args():
		main.sky.paused_clock = true
		main.sky.set_hour(13.0)
	for s in SPOTS:
		var r := City.block_rect(s[1].x, s[1].y)
		cam.global_position = r.position + r.size * (s[2] as Vector2)
		cam.zoom = Vector2(s[3], s[3])
		await _frames(4)
		await _save(s[0])
	get_tree().quit()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + name + ".png"))
	print("saved ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
