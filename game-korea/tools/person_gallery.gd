extends Node2D
## 사람 도감: data/npc 전 종을 게임과 같은 2.5D 화면으로 크게 보여 준다 (앞모습·뒷모습 한 쌍).
## 실행: godot --path . res://tools/person_gallery.tscn
## 저장: ... -- --shot  →  .screenshots/person_gallery.png

const TOP := 64.0
const COLS := 8
const ZOOM := 3.0


class Doll:
	extends Node2D
	var npc: NpcType
	var facing := 0.0

	func _draw() -> void:
		PersonDrawer.draw_standing(self, facing, 0.0, npc.shirt_colors[0], npc.pants_colors[0],
				npc.hair_colors[0], npc.body_scale, null, npc, 0)


func _ready() -> void:
	IsoView.enabled = true
	var files: Array = []
	for f in DirAccess.get_files_at("res://data/npc"):
		if f.ends_with(".tres"):
			files.append(f.get_basename())
	files.sort()
	var view := get_viewport().get_visible_rect().size
	var rows := ceili(files.size() / float(COLS))
	var cell := Vector2(view.x / COLS, (view.y - TOP) / rows)
	get_viewport().canvas_transform = IsoView.canvas(view, Vector2.ZERO, ZOOM)
	var inv := get_viewport().canvas_transform.affine_inverse()
	var layer := CanvasLayer.new()
	add_child(layer)
	var title := Label.new()
	title.text = "서울 거리 프로젝트 · 사람 도감 (코드로 그린 %d종, 앞·뒤)" % files.size()
	title.position = Vector2(20, 14)
	title.add_theme_font_size_override("font_size", 22)
	layer.add_child(title)
	# 화면에서 오른쪽 아래(앞모습)·오른쪽 위(뒷모습)를 보는 월드 방향
	var front := Vector2.UP.angle_to(IsoView.BASIS.affine_inverse().basis_xform(Vector2(1, 0.45)))
	var back := Vector2.UP.angle_to(IsoView.BASIS.affine_inverse().basis_xform(Vector2(1, -0.45)))
	for i in files.size():
		var npc: NpcType = load("res://data/npc/%s.tres" % files[i])
		var corner := Vector2((i % COLS) * cell.x, TOP + (i / COLS) * cell.y)
		for k in 2:
			var d := Doll.new()
			d.npc = npc
			d.facing = front if k == 0 else back
			d.z_index = 10
			add_child(d)
			d.global_position = inv * (corner + Vector2(cell.x * (0.32 + k * 0.36), cell.y * 0.78))
		var label := Label.new()
		label.text = "%s  %s" % [npc.display_name, files[i]]
		label.position = corner + Vector2(0, cell.y - 22)
		label.size = Vector2(cell.x, 20)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 12)
		layer.add_child(label)
	if "--shot" in OS.get_cmdline_user_args():
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path("res://.screenshots/person_gallery.png")
		get_viewport().get_texture().get_image().save_png(path)
		print("사람 도감 저장: ", path)
		get_tree().quit()


func _draw() -> void:
	draw_rect(Rect2(-100000, -100000, 200000, 200000), Color(0.42, 0.44, 0.46))
