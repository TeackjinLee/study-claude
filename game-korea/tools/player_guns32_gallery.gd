extends Node
## 실제 게임 그리기로 네 무기의 32방향·반동·총구 위치를 한 화면에서 확인한다.

class Doll extends Node2D:
	var weapon: WeaponType
	var facing := 0.0
	var elapsed := 0.0
	func _process(delta: float) -> void:
		elapsed += delta
		var info := PersonRig.gun32_for(String(weapon.pose))
		var duration: float = info["fire_duration"]
		var phase := fmod(elapsed, duration + 0.6)
		set_meta(&"shot_weapon", weapon.id)
		set_meta(&"shot_at", Time.get_ticks_msec() / 1000.0 - phase)
		queue_redraw()
	func _draw() -> void:
		PersonRig.draw(self, facing, 0.0, 0.0, Color.DIM_GRAY, Color.DIM_GRAY, Color.BLACK, 1.0, null, 0, weapon)
		var point: Variant = PersonRig.gun_muzzle(self, facing, 1.0, 0.0, weapon)
		if point is Vector2:
			draw_circle(to_local(point), 0.7, Color.ORANGE)

func _ready() -> void:
	var board := SubViewport.new()
	board.size = Vector2i(1280, 2304)
	board.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	board.transparent_bg = false
	add_child(board)
	var world := Node2D.new()
	board.add_child(world)
	board.canvas_transform = IsoView.canvas(Vector2(board.size), Vector2.ZERO, 3.0)
	var inv := board.canvas_transform.affine_inverse()
	var overlay := CanvasLayer.new()
	board.add_child(overlay)
	var title := Label.new()
	title.text = "주인공 사격 32방향 · 주황 점은 게임 궤적 시작점"
	title.position = Vector2(16, 12)
	overlay.add_child(title)
	var poses := ["pistol", "smg", "shotgun", "rifle"]
	for wi in 4:
		var weapon: WeaponType = load("res://data/weapons/" + poses[wi] + ".tres")
		for k in 32:
			var screen := Vector2.DOWN.rotated(-k * TAU / 32.0)
			var doll := Doll.new()
			doll.weapon = weapon
			doll.facing = Vector2.UP.angle_to(IsoView.BASIS.affine_inverse().basis_xform(screen))
			doll.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			world.add_child(doll)
			var row := wi * 4 + k / 8
			doll.global_position = inv * Vector2(80 + k % 8 * 160, 54 + row * 140 + 110)
			var label := Label.new()
			label.text = "%s %02d" % [weapon.display_name, k]
			label.position = Vector2(k % 8 * 160 + 12, 46 + row * 140)
			overlay.add_child(label)
	var panel := TextureRect.new()
	panel.texture = board.get_texture()
	panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(panel)
	panel.size = get_viewport().get_visible_rect().size
	if "--shot" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		var path := "res://.screenshots/player_guns32_gallery.png"
		board.get_texture().get_image().save_png(path)
		print("저장: ", path)
		get_tree().quit()
