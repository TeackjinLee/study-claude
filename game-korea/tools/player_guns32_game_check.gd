extends "res://tools/screenshot.gd"
## 본편의 실제 발사 입력으로 네 총을 차례로 확인한다. 임시 검사 저장 경로만 쓴다.

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.load_on_start = false
	main.save_prefix = "user://guns32_check_"
	main.chapter = 3
	add_child(main)
	main.player.invincible = true   # 여러 총을 확인하는 중 피격·기절로 다음 검사가 끊기지 않게 한다.
	await _frames(30)
	for pose: String in ["pistol", "smg", "shotgun", "rifle"]:
		await _rifle_shots(main, pose)
	get_tree().quit()
