extends Node2D
## 불·폭발 도감: 차 화재 단계, 폭발 순서, 땅 불, 차종별 불을 게임과 같은 2.5D 화면으로 크게 본다 (FireFx).
## 실행: godot --path . res://tools/fire_gallery.tscn
## 저장: ... -- --shot  →  .screenshots/fire_gallery.png  (--code면 넘김 그림 대신 코드 그림 → fire_gallery_code.png)

const TOP := 64.0
const ZOOM := 2.0
const BLAST_SCALE := 0.5          ## 폭발은 커서 줄여 보여 준다
const PAINT := Color(0.13, 0.13, 0.15)

## [차 id, 상태, 이름] — 상태: 체력 비율(불 없음/불남), "burn"(곧 터짐), 숫자 문자열은 잔해가 된 지 초
const CARS := [
	["car_sonato", 0.3, "① 많이 부서짐 (연기)"],
	["car_sonato", 0.19, "② 불이 났다 (20% 아래)"],
	["car_sonato", 0.1, "③ 불이 번진다"],
	["car_sonato", 0.01, "④ 거의 다 탔다"],
	["car_sonato", "burn", "⑤ 차 전체가 탄다 (곧 터짐)"],
	["car_sonato", "1", "⑥ 터진 잔해 (1초)"],
	["car_sonato", "15", "⑦ 사그라든 잔해 (15초)"],
]
const BLAST_AGES := [0.04, 0.16, 0.36, 0.7, 1.25]
const KINDS := [["car_taxi", 0.08], ["police_patrol", "burn"], ["trk_porta", 0.05], ["bus_city", "burn"]]

var cars: Array[Vehicle] = []
var combat: Combat
var fires: Fires


func _ready() -> void:
	IsoView.enabled = true
	FireFx.sprites = not "--code" in OS.get_cmdline_user_args()
	RenderingServer.set_default_clear_color(Color(0.09, 0.1, 0.12))
	var view := get_viewport().get_visible_rect().size
	get_viewport().canvas_transform = IsoView.canvas(view, Vector2.ZERO, ZOOM)
	var inv := get_viewport().canvas_transform.affine_inverse()
	var floor := Node2D.new()   # 아스팔트 바닥 (그을음·불빛이 보이게)
	floor.z_as_relative = false
	floor.z_index = -20
	floor.draw.connect(func(): floor.draw_rect(Rect2(-100000, -100000, 200000, 200000), Color(0.2, 0.21, 0.23)))
	add_child(floor)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label(layer, "서울 거리 프로젝트 · 불·폭발 도감 (%s)" % ("넘김 그림 assets/fx" if FireFx.sprites else "코드로 그린 불꽃·연기·불씨"), Vector2(20, 14), 22)
	var row := (view.y - TOP) / 3.0
	# 1행: 차 화재 단계
	var cell := view.x / CARS.size()
	for i in CARS.size():
		var at := Vector2(cell * (i + 0.5), TOP + row * 0.62)
		_car(CARS[i][0], CARS[i][1], inv * at)
		_label(layer, CARS[i][2], Vector2(cell * i, TOP + row - 26), 13, cell)
	# 2행: 폭발 순서 + 땅 불 + 그을린 자국
	combat = Combat.new()
	add_child(combat)
	combat.set_physics_process(false)
	combat.scale = Vector2(BLAST_SCALE, BLAST_SCALE)
	combat._decals.scale = Vector2.ONE
	cell = view.x / (BLAST_AGES.size() + 2)
	for i in BLAST_AGES.size():
		var at := inv * Vector2(cell * (i + 0.5), TOP + row * 1.72)
		combat._blasts.append([at / BLAST_SCALE, 1.0, BLAST_AGES[i]])
		_label(layer, "폭발 %.2f초" % BLAST_AGES[i], Vector2(cell * i, TOP + row * 2 - 26), 13, cell)
	fires = Fires.new()
	add_child(fires)
	fires.set_physics_process(false)
	fires.fires.append({"pos": inv * Vector2(cell * 5.5, TOP + row * 1.72), "radius": 30.0, "left": 9.0, "age": 2.0, "by_player": false, "dispatch": false})
	_label(layer, "땅 불 (화염병)", Vector2(cell * 5, TOP + row * 2 - 26), 13, cell)
	combat._scorch.append(inv * Vector2(cell * 6.5, TOP + row * 1.62) / BLAST_SCALE)
	combat._decals.queue_redraw()
	_label(layer, "폭발 그을음", Vector2(cell * 6, TOP + row * 2 - 26), 13, cell)
	# 3행: 차종별
	cell = view.x / KINDS.size()
	for i in KINDS.size():
		var car := _car(KINDS[i][0], KINDS[i][1], inv * Vector2(cell * (i + 0.5), TOP + row * 2.6))
		_label(layer, car.stats.display_name, Vector2(cell * i, view.y - 24), 13, cell)
	if "--shot" in OS.get_cmdline_user_args():
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path("res://.screenshots/fire_gallery%s.png" % ("" if FireFx.sprites else "_code"))
		get_viewport().get_texture().get_image().save_png(path)
		print("불·폭발 도감 저장: ", path)
		get_tree().quit()


func _car(id: String, state: Variant, at: Vector2) -> Vehicle:
	var car := Vehicle.new()
	car.stats = load("res://data/vehicles/%s.tres" % id)
	add_child(car)
	car.set_physics_process(false)
	car.beam = false
	if id == "car_sonato":
		car.paint = PAINT
	car.global_position = at
	car.rotation = PI
	car.motor.heading = PI
	if state is float:
		car.health = car.max_health() * state
		car.on_fire = state < DamageModel.FIRE_HEALTH
	elif state == "burn":
		car.health = 0.0
		car.burning = 2.0
	else:
		car.wrecked = true
		car.wreck_age = float(state)
	cars.append(car)
	return car


func _label(layer: CanvasLayer, text: String, at: Vector2, size: int, width := 0.0) -> void:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	if width > 0.0:
		l.size = Vector2(width, 20)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(l)


func _process(delta: float) -> void:
	for car in cars:
		car.queue_redraw()
		car._fx.queue_redraw()
	combat.queue_redraw()
	fires._time += delta
	fires.queue_redraw()
