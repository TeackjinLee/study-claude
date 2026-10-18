extends Node2D
## 사람 도감: data/npc 전 종을 게임과 같은 2.5D 화면으로 크게 보여 준다 (앞모습·뒷모습 한 쌍).
## 실행: godot --path . res://tools/person_gallery.tscn
## 저장: ... -- --shot  →  .screenshots/person_gallery.png
## 몇 종만 크게: ... -- --shot --ids=office,boss  →  .screenshots/person_gallery_office.png (설계도와 비교할 때)
## 관절 있는 사람(PersonRig) 비교: ... -- --rig [--ids=civ_m,police,office] (주인공은 player). --walk면 8방향 걷기만, --run이면 8방향 달리기만, --fall이면 8방향 넘어짐만(2초마다 다시), --punch면 8방향 주먹 콤보만 크게  — 한 줄에 기존 그림 · 새 뼈대 8방향 걷기 · 달리기 · 서 있기.
##   움직이는 걸 창으로 보거나, --shot이면 .screenshots/person_rig.png
## 설계도(성인 12종 앞·뒤)와 맞춰 보기: ... -- --sheet [--shot]  →  .screenshots/person_sheet.png (--all이면 그림이 있는 종 전부)

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


## 관절 있는 사람 한 명 (걷기 위상을 스스로 돌린다)
class RigDoll:
	extends Node2D
	var npc: NpcType
	var facing := 0.0
	var gait := 1.0
	var phase := 0.0
	var down := false

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	var fall_loop := 0.0      ## 0보다 크면 쓰러짐을 이 초마다 처음부터 다시 (--fall)
	var _fall_t := 0.0
	var punch_loop := false   ## 주먹 콤보를 0.35초마다 이어 지른다 (--punch)
	var _punch_t := 0.0
	var _punch_n := 0

	func _process(delta: float) -> void:
		phase += delta * (0.0 if gait <= 0.0 else 6.5 + 3.5 * maxf(gait - 1.0, 0.0))
		if punch_loop:
			_punch_t -= delta
			if _punch_t <= 0.0:
				_punch_t = 0.35 if _punch_n % 3 != 2 else 0.9   # 훅 다음엔 잠깐 쉰다
				set_meta(&"punch", [_punch_n % 3, Time.get_ticks_msec() / 1000.0])
				_punch_n += 1
		if fall_loop > 0.0:
			_fall_t += delta
			if _fall_t >= fall_loop:
				_fall_t = 0.0
				remove_meta(&"dir8_fall")
		queue_redraw()

	func _draw() -> void:
		if npc == null:
			# 주인공 (--ids=player)
			PersonRig.draw(self, facing, phase, gait, Color(0.2, 0.2, 0.22), Color(0.3, 0.33, 0.4), Color(0.08, 0.08, 0.08),
				1.0, null, 0, null, down)
			return
		PersonRig.draw(self, facing, phase, gait, npc.shirt_colors[0], npc.pants_colors[0], npc.hair_colors[0],
			npc.body_scale, npc, 0, null, down)


func _ready() -> void:
	IsoView.enabled = true
	if "--rig" in OS.get_cmdline_user_args():
		_rig_compare()
		return
	if "--sheet" in OS.get_cmdline_user_args():
		_sheet()
		return
	var files: Array = []
	for f in DirAccess.get_files_at("res://data/npc"):
		if f.ends_with(".tres"):
			files.append(f.get_basename())
	files.sort()
	var ids := _ids()
	if not ids.is_empty():
		files = files.filter(func(f: String) -> bool: return f in ids)
	var cols := COLS if ids.is_empty() else files.size()
	var zoom := ZOOM if ids.is_empty() else minf(12.0, 30.0 / cols)
	var view := get_viewport().get_visible_rect().size
	var rows := ceili(files.size() / float(cols))
	var cell := Vector2(view.x / cols, (view.y - TOP) / rows)
	get_viewport().canvas_transform = IsoView.canvas(view, Vector2.ZERO, zoom)
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
		var corner := Vector2((i % cols) * cell.x, TOP + (i / cols) * cell.y)
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
		var name := "person_gallery" if ids.is_empty() else "person_gallery_" + ids[0]
		var path := ProjectSettings.globalize_path("res://.screenshots/%s.png" % name)
		get_viewport().get_texture().get_image().save_png(path)
		print("사람 도감 저장: ", path)
		get_tree().quit()


## --rig: 종마다 한 줄 — [기존 그림] [새 뼈대 8방향 걷기] [달리기] [서 있기]
func _rig_compare() -> void:
	var ids := _ids()
	if "--all" in OS.get_cmdline_user_args():
		# 그림이 있는 종 전부 (assets/characters, 주인공 제외)
		ids = PackedStringArray()
		for f in DirAccess.get_files_at("res://assets/characters"):
			if f.ends_with(".png") and f != "player.png" and ResourceLoader.exists("res://data/npc/" + f.get_basename() + ".tres"):
				ids.append(f.get_basename())
	if ids.is_empty():
		ids = PackedStringArray(["civ_f", "office", "police", "boss"])
	var run_only := "--run" in OS.get_cmdline_user_args()
	var fall_only := "--fall" in OS.get_cmdline_user_args()
	var punch_only := "--punch" in OS.get_cmdline_user_args()
	var walk_only := "--walk" in OS.get_cmdline_user_args() or run_only or fall_only or punch_only
	var cols := 8 if walk_only else 11
	var view := get_viewport().get_visible_rect().size
	var cell := Vector2(view.x / cols, (view.y - TOP) / ids.size())
	var zoom := minf(6.0 if walk_only else 4.2, cell.y / 40.0)
	get_viewport().canvas_transform = IsoView.canvas(view, Vector2.ZERO, zoom)
	var inv := get_viewport().canvas_transform.affine_inverse()
	var layer := CanvasLayer.new()
	add_child(layer)
	var title := Label.new()
	title.text = "인물 (PersonRig) — 8방향 달리기" if run_only else "인물 (PersonRig) — 기존 · 8방향 걷기 · 달리기 · 쓰러짐"
	if fall_only:
		title.text = "인물 (PersonRig) — 8방향 넘어짐 (2초마다 다시)"
	if punch_only:
		title.text = "인물 (PersonRig) — 8방향 주먹 콤보 (잽 · 스트레이트 · 훅)"
	title.position = Vector2(20, 14)
	title.add_theme_font_size_override("font_size", 22)
	layer.add_child(title)
	var heads := ["기존", "→", "↘", "↓", "↙", "←", "↖", "↑", "↗", "달리기", "쓰러짐"]
	if walk_only:
		heads = heads.slice(1, 9)
	for c in cols:
		var h := Label.new()
		h.text = heads[c]
		h.position = Vector2(c * cell.x, 42)
		h.size = Vector2(cell.x, 20)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_theme_font_size_override("font_size", 14)
		layer.add_child(h)
	var front := Vector2.UP.angle_to(IsoView.BASIS.affine_inverse().basis_xform(Vector2(1, 0.45)))
	for row in ids.size():
		var npc: NpcType = null if ids[row] == "player" else load("res://data/npc/%s.tres" % ids[row])
		for c in cols:
			var at: Vector2 = inv * Vector2((c + 0.5) * cell.x, TOP + (row + 0.86) * cell.y)
			if walk_only:
				# 걷기만: 열 c = 화면 기준 8방향 (→부터 시계 방향)
				var wd := RigDoll.new()
				wd.npc = npc
				wd.facing = Vector2.UP.angle_to(IsoView.BASIS.affine_inverse().basis_xform(Vector2.RIGHT.rotated(c * PI / 4.0)))
				wd.phase = c * 0.8
				wd.gait = 2.0 if run_only else 1.0
				if punch_only:
					wd.gait = 0.0
					wd.punch_loop = true
				if fall_only:
					wd.gait = 0.0
					wd.down = true
					wd.fall_loop = 2.0
				add_child(wd)
				wd.global_position = at
				continue
			if c == 0 and npc == null:
				continue
			if c == 0:
				var d := Doll.new()
				d.npc = npc
				d.facing = front
				add_child(d)
				d.global_position = at
				continue
			var rd := RigDoll.new()
			rd.npc = npc
			if c <= 8:
				# 화면 기준 8방향 (→부터 시계 방향)을 보는 월드 방향
				var screen_dir := Vector2.RIGHT.rotated((c - 1) * PI / 4.0)
				rd.facing = Vector2.UP.angle_to(IsoView.BASIS.affine_inverse().basis_xform(screen_dir))
				rd.phase = c * 0.8
			else:
				rd.facing = front
				rd.gait = 2.0 if c == 9 else 0.0
				rd.down = c == 10
			add_child(rd)
			rd.global_position = at
		var label := Label.new()
		label.text = "%s  %s" % ["주인공" if npc == null else npc.display_name, ids[row]]
		label.position = Vector2(4, TOP + row * cell.y + 2)
		label.add_theme_font_size_override("font_size", 13)
		layer.add_child(label)
	if "--shot" in OS.get_cmdline_user_args():
		for i in 4:
			await get_tree().process_frame
		if fall_only:
			await get_tree().create_timer(PersonRig.DIR8_FALL_FRAME * 9.0).timeout   # 다 누운 뒤
		if punch_only:
			await get_tree().create_timer(0.35 + PersonRig.PUNCH_FRAME * 1.5).timeout   # 스트레이트를 뻗은 때
		await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path("res://.screenshots/person_rig.png")
		get_viewport().get_texture().get_image().save_png(path)
		print("관절 사람 저장: ", path)
		get_tree().quit()


## --sheet: 설계도처럼 성인 12종을 4×3 칸에 앞·뒤로 세운다 (관절 그림). --ids로 바꿀 수 있다
func _sheet() -> void:
	var ids := _ids()
	if "--all" in OS.get_cmdline_user_args():
		# 그림이 있는 종 전부 (assets/characters, 주인공 제외)
		ids = PackedStringArray()
		for f in DirAccess.get_files_at("res://assets/characters"):
			if f.ends_with(".png") and f != "player.png" and ResourceLoader.exists("res://data/npc/" + f.get_basename() + ".tres"):
				ids.append(f.get_basename())
	if ids.is_empty():
		ids = PackedStringArray(["civ_f", "office", "delivery", "merchant", "gang_f", "boss", "thug", "thief",
			"police", "swat", "firefighter", "assassin"])
	var cols := 4 if ids.size() <= 12 else 7
	var rows := ceili(ids.size() / float(cols))
	var view := get_viewport().get_visible_rect().size
	var cell := Vector2(view.x / cols, (view.y - TOP) / rows)
	get_viewport().canvas_transform = IsoView.canvas(view, Vector2.ZERO, minf(5.0, cell.y / 40.0))
	var inv := get_viewport().canvas_transform.affine_inverse()
	var layer := CanvasLayer.new()
	add_child(layer)
	var title := Label.new()
	title.text = "서울 거리 프로젝트 · 인물 %d종 앞·뒤 (그림이 없는 종은 관절 그림)" % ids.size()
	title.position = Vector2(20, 14)
	title.add_theme_font_size_override("font_size", 22)
	layer.add_child(title)
	var front := Vector2.UP.angle_to(IsoView.BASIS.affine_inverse().basis_xform(Vector2(-1, 0.45)))
	var back := Vector2.UP.angle_to(IsoView.BASIS.affine_inverse().basis_xform(Vector2(1, -0.45)))
	for i in ids.size():
		var npc: NpcType = load("res://data/npc/%s.tres" % ids[i])
		var corner := Vector2((i % cols) * cell.x, TOP + (i / cols) * cell.y)
		for k in 2:
			var rd := RigDoll.new()
			rd.npc = npc
			rd.gait = 0.0
			rd.facing = front if k == 0 else back
			add_child(rd)
			rd.global_position = inv * (corner + Vector2(cell.x * (0.32 + k * 0.36), cell.y * 0.8))
		var label := Label.new()
		label.text = "%d. %s (%s)" % [i + 1, npc.display_name, ids[i]]
		label.position = corner + Vector2(0, cell.y - 22)
		label.size = Vector2(cell.x, 20)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 13)
		layer.add_child(label)
	if "--shot" in OS.get_cmdline_user_args():
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path("res://.screenshots/person_sheet.png")
		get_viewport().get_texture().get_image().save_png(path)
		print("성인 관절 도감 저장: ", path)
		get_tree().quit()


## `--ids=a,b` 인자 (없으면 빈 배열 = 전 종)
static func _ids() -> PackedStringArray:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ids="):
			return a.get_slice("=", 1).split(",", false)
	return PackedStringArray()


func _draw() -> void:
	draw_rect(Rect2(-100000, -100000, 200000, 200000), Color(0.42, 0.44, 0.46))
