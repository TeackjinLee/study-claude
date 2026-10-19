extends Node
## 헬기 그림 요청용 가이드 (output/imagegen/vehicles/GPT_HELI_PROMPT.md).
## 지금 코드 모형(VehicleModel)을 게임과 똑같은 2:1 사선 투영으로 방향마다 찍어, 생성기에 "이 모양 위에 덧칠하라"고 넘길 시트를 만든다.
## 창 모드로 실행한다 (헤드리스는 그리지 않는다):
##   godot --path . res://tools/vehicle_guide.tscn                 (기본 sp_heli)
##   ... -- --ids=sp_heli,sp_fire_heli --cell=384
##
## 방향: 한 바퀴 32방향(11.25°). 화면 좌우 거울 = 월드 x↔y 교환이고 헬기는 좌우 대칭이라,
## 화면 위(↑) → 오른쪽(→) → 아래(↓) 반 바퀴 17방향만 받고 왼쪽 반은 좌우로 뒤집어 쓴다 (회전 r ↔ −90° − r).
##   A 시트: 짝수 방향 9개 (16방향 한 바퀴 — 이것만 있어도 게임에 붙는다)
##   B 시트: 홀수 방향 8개 (A 사이 각도, 9번째 칸은 비운다)
##   C 시트: 뒷모습 4방향 k0~3 (2×2) — 생성기가 코가 먼 쪽(화면 위)을 보는 칸을 앞모습으로 뒤집어 그리곤 해서 따로 다시 받는다
## 그 사이 각도(±5.6°)는 게임이 그림을 사선 투영에 맞게 비틀어 메운다.
## 주 회전날개는 빼고 찍는다 (게임이 도는 날개·원판을 코드로 그린다). 그림자도 없다 (게임이 땅에 그린다).
## 옆면은 좌우 같은 밝기다 (뒤집어 쓰는 그림이라 빛이 한쪽이면 왼쪽 반에서 빛이 반대로 온다).
## 결과: output/imagegen/vehicles/guides/
##   <id>_A_guide.png · <id>_B_guide.png   밝은 회색 동체 · 흰 띠 · 짙은 유리 · 배경 마젠타 (생성기에 넣는 것)
##   <id>_A_ref.png · <id>_B_ref.png       지금 모형 색 그대로 (색 참고)
##   <id>.json                             칸 배치·방향·칸마다 월드 원점(땅)의 그림 좌표·배율

const OUT := "res://output/imagegen/vehicles/guides"
const MAGENTA := Color(1, 0, 1)
const DIRS := 32
const FILL := 0.84          ## 칸 안에서 모형(모든 방향을 합친 범위)이 차지하는 비율


## 차 노드 대신 모형만 그린다 (그림자·전조등 빛·날개 원판 없이)
class Drawer extends Node2D:
	var car: Vehicle

	func _draw() -> void:
		VehicleModel.draw(self, car)


const GUIDE_BODY := Color(0.74, 0.75, 0.77)
const GUIDE_ACCENT := Color(0.96, 0.96, 0.96)


func _ready() -> void:
	IsoView.enabled = true
	VehicleModel.hide_blades = true
	VehicleModel.even_light = true
	VehicleSprite.enabled = false   # 가이드는 언제나 코드 모형이다 (방향 그림을 붙인 차종도)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var gd := ProjectSettings.globalize_path(OUT + "/.gdignore")
	if not FileAccess.file_exists(gd):
		FileAccess.open(gd, FileAccess.WRITE).store_string("")
	var cell := int(_arg("cell", "384"))
	for id in _arg("ids", "sp_heli").split(","):
		var stats: VehicleType = load("res://data/vehicles/%s.tres" % id)
		if stats == null:
			push_warning("차종 없음: %s" % id)
			continue
		await _guide(id, stats, cell)
	VehicleModel.hide_blades = false
	VehicleModel.even_light = false
	get_tree().quit()


## 반 바퀴 17방향의 회전 (k = 0 화면 ↑, 8 화면 →, 16 화면 ↓)
static func rotation_of(k: int) -> float:
	return -PI * 0.25 + k * TAU / DIRS


func _guide(id: String, stats: VehicleType, cell: int) -> void:
	var parts: Array = VehicleModel.model(stats)
	# 모든 방향을 합친 화면 범위 (월드 원점·땅 기준, 줌 1) → 배율과 칸 안 원점을 정한다. 모든 칸이 같은 원점을 쓴다
	var box := Rect2()
	var first := true
	for k in DIRS / 2 + 1:
		for p: VehicleModel.Part in parts:
			if p.blade:
				continue
			for q in p.pts:
				var s := _screen(q, rotation_of(k))
				if first:
					box = Rect2(s, Vector2.ZERO)
					first = false
				else:
					box = box.expand(s)
	var scale := minf(cell * FILL / box.size.x, cell * FILL / box.size.y)
	var origin := Vector2(cell, cell) * 0.5 - box.get_center() * scale
	var sheets := {"A": [], "B": [], "C": [0, 1, 2, 3]}
	for k in DIRS / 2 + 1:
		sheets["A" if k % 2 == 0 else "B"].append(k)
	var grids := {"A": [3, 3], "B": [3, 3], "C": [2, 2]}
	var cells := []
	for sheet: String in sheets:
		var ks: Array = sheets[sheet]
		var cols: int = grids[sheet][0]
		var px := Vector2i(cols * cell, grids[sheet][1] * cell)
		var at := []
		for i in ks.size():
			var corner := Vector2((i % cols) * cell, (i / cols) * cell)
			at.append(corner + origin)
			var r := rotation_of(ks[i])
			var fwd := IsoView.BASIS.basis_xform(Vector2(0, -1).rotated(r))
			cells.append({
				"sheet": sheet, "index": i, "col": i % cols, "row": i / cols, "k": ks[i],
				"rotation": r, "rotation_deg": rad_to_deg(r),
				# 화면에서 앞(코)이 가리키는 각 (0 = 화면 오른쪽, 90 = 화면 아래)
				"screen_heading_deg": rad_to_deg(fwd.angle()),
				"mirror_rotation": -PI * 0.5 - r,
				"origin": [corner.x + origin.x, corner.y + origin.y],
			})
		var ref := await _shot(stats, ks, at, scale, px, false)
		var guide := await _shot(stats, ks, at, scale, px, true)
		_save_on_magenta(ref, "%s_%s_ref" % [id, sheet])
		_save_on_magenta(guide, "%s_%s_guide" % [id, sheet])
		print("가이드 저장: %s_%s (%d×%d, 칸 %d개)" % [id, sheet, px.x, px.y, ks.size()])
	var info := {
		"id": id, "name": stats.display_name, "dirs": DIRS, "cell": cell, "scale": scale,
		"sheets": grids,   # 시트마다 [열, 줄]
		# 칸 안 그림 좌표 = 칸 원점 + scale × (BASIS × (월드 x, y)를 회전 r로 돌린 것 − (0, 높이))
		"basis": [[IsoView.BASIS.x.x, IsoView.BASIS.x.y], [IsoView.BASIS.y.x, IsoView.BASIS.y.y]],
		"rotor_z": Vehicle.rotor_z(stats), "bank_pivot": Vehicle.BANK_PIVOT,
		"size": [stats.size.x, stats.size.y], "height": stats.height,
		"cells": cells,
	}
	var f := FileAccess.open(ProjectSettings.globalize_path("%s/%s.json" % [OUT, id]), FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "  "))


## 모형 점(차 기준 3D) → 화면 (줌 1, 월드 원점·땅 기준)
static func _screen(q: Vector3, r: float) -> Vector2:
	return IsoView.BASIS.basis_xform(Vector2(q.x, q.y).rotated(r)) - Vector2(0, q.z)


func _shot(stats: VehicleType, ks: Array, at: Array, scale: float, px: Vector2i, gray: bool) -> Image:
	var sub := SubViewport.new()
	sub.size = px
	sub.transparent_bg = true
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub)
	var xf := IsoView.BASIS.scaled(Vector2(scale, scale))
	sub.canvas_transform = xf   # 트리에 넣은 뒤에야 캔버스가 생긴다
	var inv := xf.affine_inverse()
	# 가이드: 동체를 밝은 회색으로 칠해 유리(짙은 남색)·썰매(검정)와 갈라 보이게 한다
	# (복사본은 경로가 없어 모형이 기본 세단이 되므로, 원본 보조색을 찍는 동안만 바꾼다)
	var accent := stats.roof_color
	if gray:
		stats.roof_color = GUIDE_ACCENT
	var cars: Array[Vehicle] = []
	for i in ks.size():
		var car := Vehicle.new()
		car.stats = stats
		add_child(car)
		car.paint = GUIDE_BODY if gray else stats.body_color
		car.set_physics_process(false)
		car.set_process(false)
		car.visible = false
		car.rotation = rotation_of(ks[i])
		cars.append(car)
		var d := Drawer.new()
		d.car = car
		d.rotation = car.rotation
		d.position = inv * at[i]
		sub.add_child(d)
	for f in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	stats.roof_color = accent
	sub.queue_free()
	for car in cars:
		car.queue_free()
	return img


func _save_on_magenta(img: Image, name: String) -> void:
	var bg := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	bg.fill(MAGENTA)
	bg.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	bg.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT, name]))


func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.split("=", true, 1)[1]
	return default
