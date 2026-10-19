extends Node2D
## 차량 도감: 28종 입체 모형(VehicleModel)을 게임과 같은 2.5D 화면으로 크게 보여 준다.
## Codex의 tools/isometric_sample/vehicle_gallery처럼 확대해서 세부를 확인하는 용도다.
## 실행: godot --path . res://tools/vehicle_gallery.tscn
##   ←/→ 돌리기 · Space 자동 회전 · B 브레이크등 · S 경광등 · 1 앞모습 · 2 뒷모습
## 저장: ... -- --shot  →  .screenshots/vehicle_gallery_front.png, vehicle_gallery_rear.png
## 몇 대만 크게: ... -- --shot --ids=car_sonato,bus_city --name=vehicle_closeup
## 헬기 선회 기울기: ... -- --shot --ids=sp_heli --bank=0.45 (음수면 왼쪽) --pitch=0.28 (앞으로 숙이기, 음수면 코를 든다)
## 한 바퀴 돌려 보기: ... -- --shot --ids=sp_heli --sweep=24 (한 차종을 N방향으로 늘어놓는다 — 방향 그림(VehicleSprite)이
##   칸 사이 각도·뒤집은 왼쪽 반에서 튀지 않는지 본다. --code면 그림 대신 코드 모형)

const TOP := 64.0
const MAX_SCALE := 7.0
## 참고 그림처럼 앞이 화면 왼쪽 아래를 보는 방향 (차 앞은 -y, 월드 +y는 화면 왼쪽 아래)
const FRONT := PI
const REAR := 0.0

var cars: Array[Vehicle] = []
var labels: Array[Label] = []
var heading := FRONT
var spin := false
var braking := false
var cols := 7
var rows := 4
var fit := Vector2(150, 118)      ## 칸 안에서 차가 차지할 화면 크기
var offsets: Array[float] = []    ## 차마다 더 돌릴 각 (--sweep)


func _ready() -> void:
	IsoView.enabled = true
	var files: Array = []
	for f in DirAccess.get_files_at("res://data/vehicles"):
		if f.ends_with(".tres"):
			files.append(f.get_basename())
	files.sort_custom(_order)
	rows = ceili(files.size() / float(cols))   # 차종이 늘면 줄을 늘린다
	var ids := _arg("ids")
	if ids != "":
		files = Array(ids.split(","))
		cols = mini(4, files.size())
		rows = ceili(files.size() / float(cols))
	var sweep := int(_arg("sweep")) if _arg("sweep") != "" else 0
	if sweep > 0:
		files = []
		for i in sweep:
			files.append(ids.split(",")[0] if ids != "" else "sp_heli")
			offsets.append(i * TAU / sweep)
		cols = ceili(sqrt(sweep * 1.6))
		rows = ceili(sweep / float(cols))
		heading = 0.0
	if "--code" in OS.get_cmdline_user_args():
		VehicleSprite.enabled = false
	var view := get_viewport().get_visible_rect().size
	fit = Vector2(view.x / cols * 0.84, (view.y - TOP) / rows * 0.72)
	var layer := CanvasLayer.new()
	add_child(layer)
	var title := Label.new()
	title.text = "서울 거리 프로젝트 · 2.5D 차량 도감 (코드로 만든 입체 모형, 가상 차종)"
	title.position = Vector2(20, 14)
	title.add_theme_font_size_override("font_size", 22)
	layer.add_child(title)
	var help := Label.new()
	help.text = "←/→ 돌리기 · Space 자동 회전 · B 브레이크등 · S 경광등 · 1 앞 · 2 뒤"
	help.position = Vector2(22, 42)
	help.add_theme_font_size_override("font_size", 13)
	help.modulate = Color(0.6, 0.68, 0.75)
	layer.add_child(help)
	for i in files.size():
		var car := Vehicle.new()
		car.stats = load("res://data/vehicles/%s.tres" % files[i])
		add_child(car)
		car.set_physics_process(false)
		car.has_driver = true          # 전조등·탄 사람
		car.beam = false
		car.siren = car.stats.category in [&"police", &"swat", &"ambulance", &"fire"]
		car.bank = float(_arg("bank")) if _arg("bank") != "" else 0.0
		car.pitch = float(_arg("pitch")) if _arg("pitch") != "" else 0.0
		var s := car.stats
		var extent := Vector2(0.78 * (s.size.x + s.size.y), 0.39 * (s.size.x + s.size.y) + s.height + 12.0)
		var k := minf(MAX_SCALE, minf(fit.x / extent.x, fit.y / extent.y))
		car.scale = Vector2(k, k)
		cars.append(car)
		var label := Label.new()
		label.text = s.display_name if offsets.is_empty() else "%.1f°" % rad_to_deg(offsets[i])
		label.add_theme_font_size_override("font_size", 14)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		layer.add_child(label)
		labels.append(label)
	_layout()
	if "--shot" in OS.get_cmdline_user_args() and not offsets.is_empty():
		await _shot(_arg("name") if _arg("name") != "" else "vehicle_sweep")
		get_tree().quit()
		return
	if "--shot" in OS.get_cmdline_user_args():
		var name := _arg("name") if _arg("name") != "" else "vehicle_gallery"
		await _shot(name + "_front")
		heading = REAR
		_apply()
		await _shot(name + "_rear")
		get_tree().quit()


func _arg(key: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.split("=", true, 1)[1]
	return ""


## 승용 → 상용 → 버스 → 특수 → 기타 (docs/12 순서)
func _order(a: String, b: String) -> bool:
	var rank := func(id: String) -> int:
		for k in ["car_", "trk_", "bus_", "police", "sp_", "etc_"].size():
			if id.begins_with(["car_", "trk_", "bus_", "police", "sp_", "etc_"][k]):
				return k
		return 9
	var ra: int = rank.call(a)
	var rb: int = rank.call(b)
	return a < b if ra == rb else ra < rb


func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	var cell := Vector2(view.x / cols, (view.y - TOP) / rows)
	get_viewport().canvas_transform = IsoView.canvas(view, Vector2.ZERO, 1.0)
	var inv := get_viewport().canvas_transform.affine_inverse()
	for i in cars.size():
		var corner := Vector2((i % cols) * cell.x, TOP + (i / cols) * cell.y)
		# 바닥 가운데를 칸 가운데보다 조금 아래에 둔다 (높이만큼 위로 솟는다)
		cars[i].global_position = inv * (corner + Vector2(cell.x * 0.5, cell.y * 0.52))
		labels[i].position = corner + Vector2(0, cell.y - 22)
		labels[i].size = Vector2(cell.x, 20)
	_apply()


func _apply() -> void:
	for i in cars.size():
		var car := cars[i]
		var h := heading + (offsets[i] if i < offsets.size() else 0.0)
		car.rotation = h
		car.motor.heading = h
		# 브레이크등은 앞으로 가며 감속할 때 켜진다
		car.motor.velocity = Vector2.UP.rotated(h) * 20.0 if braking else Vector2.ZERO
		car.throttle_input = -1.0 if braking else 0.0
		car.queue_redraw()


func _process(delta: float) -> void:
	if spin:
		heading = wrapf(heading + delta * 0.8, -PI, PI)
		_apply()
	elif cars.any(func(c: Vehicle) -> bool: return c.siren):
		for car in cars:
			if car.siren:
				car.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-100000, -100000, 200000, 200000), Color(0.07, 0.09, 0.12))


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_LEFT: heading -= PI / 8.0
		KEY_RIGHT: heading += PI / 8.0
		KEY_SPACE: spin = not spin
		KEY_1: heading = FRONT
		KEY_2: heading = REAR
		KEY_S:
			for car in cars:
				car.siren = not car.siren and car.stats.category in [&"police", &"swat", &"ambulance", &"fire"]
		KEY_B:
			braking = not braking
	_apply()


func _shot(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://.screenshots/%s.png" % name)
	get_viewport().get_texture().get_image().save_png(path)
	print("차량 도감 저장: ", path)
