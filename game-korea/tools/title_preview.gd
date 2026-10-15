extends Node
## 타이틀 화면을 띄워 .screenshots/에 저장한다 (창이 잠깐 뜬다).
## 실행: godot --path . res://tools/title_preview.tscn            → title.png
##       ... -- --modal=slots  → title_slots.png (슬롯 카드, 저장 칸이 있으면 채워 보인다)
##       ... -- --modal=codex  → title_codex.png
##       ... -- --fake-saves   → 가짜 저장 칸 셋을 만들어 이어 하기·카드를 채운다 (user://title_preview_*)

const PREFIX := "user://title_preview_"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var title := TitleScreen.new()
	title.auto_skip = false
	title._no_change_scene = true
	if "--fake-saves" in args:
		_fake_saves()
		title.save_prefix = PREFIX
	add_child(title)
	var name := "title"
	for a in args:
		if a.begins_with("--modal="):
			name = "title_" + a.split("=")[1]
	await _frames(40)
	if name == "title_slots":
		title.open_slots()
	elif name == "title_codex":
		title.open_codex()
	await _frames(30)
	var path := ProjectSettings.globalize_path("res://.screenshots/%s.png" % name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	get_viewport().get_texture().get_image().save_png(path)
	print("타이틀 저장: ", path)
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _fake_saves() -> void:
	var rows := [[SaveGame.AUTO_SLOT, 500000, 1, 3], [1, 1850000, 2, 7], [2, 250000, 1, 1]]
	for r in rows:
		var s := SaveGame.new()
		s.money = r[1]
		s.chapter = r[2]
		for k in r[3]:
			s.completed.append("fake_%d" % k)
		s.saved_at = "2026-10-15T19:%02d:00" % (10 + int(r[0]) % 40)
		s.write(SaveGame.slot_path(PREFIX, r[0]))
