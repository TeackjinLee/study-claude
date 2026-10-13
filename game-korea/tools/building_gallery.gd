extends Node2D
## 건물 도감: 15종 2.5D 건물(BuildingModel)을 참고 그림 '서울의 다양한 집들'처럼 5×3으로 늘어놓는다.
## 실행: godot --path . res://tools/building_gallery.tscn
## 저장: ... -- --shot  →  .screenshots/building_gallery.png
## 한 종만 크게: ... -- --shot --ids=HANOK,APT --name=building_closeup
## 기능 건물 8종: ... -- --shot --set=special  →  .screenshots/building_special.png

const LANDMARKS := ["LANDMARK_TOWER", "TERMINAL", "MARKET", "DOCK_CRANE", "BROADCAST", "CHECKPOINT", "CONTAINER", "DOCK_WAREHOUSE", "BARRIER", "INDUSTRIAL_DOCK"]

const STREET := ["CHURCH", "MOTEL", "GAS_STATION", "NIGHTLIFE", "PARKING_TOWER", "SCHOOL", "SUBWAY", "FIRE_STATION", "FINANCE_TOWER", "PRINT_ALLEY"]

const TOP := 64.0
const ORDER := [&"HOUSE", &"VILLA", &"OFFICETEL", &"APT", &"ROWHOUSE",
	&"GOSIWON", &"ONEROOM", &"MIXED", &"COMMERCIAL", &"OFFICE",
	&"WAREHOUSE", &"FACTORY", &"HANOK", &"JJOKBANG", &"CAMPSITE"]
## 기능 건물 (참고 시안 4×2 순서)
const SPECIAL := [&"POLICE", &"HOSPITAL", &"GANG_TOWER", &"GANG_OFFICE",
	&"GANG_DOCK", &"CAR_CENTER", &"SAUNA", &"CONVENIENCE"]
## 부지 크기 (City: 블록 안쪽 520, 반쪽 251)
const LOTS := {0: Vector2(520, 520), 1: Vector2(520, 251), 2: Vector2(251, 251)}

var cols := 5
var rows := 3


## 부지 바닥 (인도 테두리 + 마당·화단·담장)
class Ground extends Node2D:
	var lot: Rect2
	var kind: BuildingType
	var seed := 0

	func _draw() -> void:
		draw_rect(lot.grow(28.0), Color(0.33, 0.34, 0.4))
		draw_rect(lot.grow(28.0), Color(0.48, 0.49, 0.55), false, 3.0)
		BuildingModel.draw_ground(self, lot, kind, seed)


func _ready() -> void:
	IsoView.enabled = true
	var ids: Array = ORDER.duplicate()
	if _arg("set") == "special":
		ids = SPECIAL.duplicate()
		cols = 4
		rows = 2
	if _arg("set") == "landmarks":
		ids = LANDMARKS.duplicate()
		cols = 5
		rows = 2
	if _arg("set") == "street":
		ids = STREET.duplicate()
		cols = 5
		rows = 2
	if _arg("ids") != "":
		ids = Array(_arg("ids").split(","))
		cols = mini(3, ids.size())
		rows = ceili(ids.size() / float(cols))
	var view := get_viewport().get_visible_rect().size
	var cell := Vector2(view.x / cols, (view.y - TOP) / rows)
	get_viewport().canvas_transform = IsoView.canvas(view, Vector2.ZERO, 1.0)
	var inv := get_viewport().canvas_transform.affine_inverse()
	var layer := CanvasLayer.new()
	add_child(layer)
	var title := Label.new()
	title.text = "서울 거리 프로젝트 · 2.5D 건물 도감 (코드로 만든 입체 모형)"
	title.position = Vector2(20, 14)
	title.add_theme_font_size_override("font_size", 22)
	layer.add_child(title)
	for i in ids.size():
		var t := _type(StringName(ids[i]))
		if t == null:
			continue
		var size: Vector2 = LOTS[t.footprints[0]]
		var lot := Rect2(-size * 0.5, size)
		var floors := t.floors
		var h := maxf(floors, 1) * IsoView.FLOOR_HEIGHT
		var pieces := BuildingModel.build(lot, t, 7 + i, h)
		var top := 0.0
		for p in pieces:
			top = maxf(top, p.top())
		# 칸에 맞는 배율: 화면 폭 0.78(w+h), 높이 0.39(w+h)+꼭대기
		var extent := Vector2(0.78 * (size.x + size.y + 56.0), 0.39 * (size.x + size.y + 56.0) + top)
		var k := minf(cell.x * 0.92 / extent.x, cell.y * 0.86 / extent.y)
		var holder := Node2D.new()
		var corner := Vector2((i % cols) * cell.x, TOP + (i / cols) * cell.y)
		var screen := corner + Vector2(cell.x * 0.5, cell.y * 0.5 + (top * k) * 0.5 - 8.0)
		holder.position = inv * screen
		holder.scale = Vector2(k, k)
		add_child(holder)
		var ground := Ground.new()
		ground.lot = lot
		ground.kind = t
		ground.seed = 7 + i
		ground.z_index = 50
		ground.z_as_relative = false
		holder.add_child(ground)
		for p in pieces:
			BuildingView.make(holder, null, -1, p)
		var label := Label.new()
		label.text = t.display_name
		label.add_theme_font_size_override("font_size", 15)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = corner + Vector2(0, cell.y - 24)
		label.size = Vector2(cell.x, 20)
		layer.add_child(label)
	if "--shot" in OS.get_cmdline_user_args():
		var name := _arg("name") if _arg("name") != "" else ("building_special" if _arg("set") == "special" else "building_gallery")
		for f in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path("res://.screenshots/%s.png" % name)
		get_viewport().get_texture().get_image().save_png(path)
		print("건물 도감 저장: ", path)
		get_tree().quit()


func _type(id: StringName) -> BuildingType:
	if String(id) in LANDMARKS or String(id) in STREET:
		return load("res://data/buildings/landmarks/%s.tres" % String(id).to_lower()) as BuildingType
	var all: Array = City.BUILDING_TYPES + City.SCATTER_LOOKS + [City.LOOK_POLICE, City.LOOK_HOSPITAL, City.LOOK_CAR_CENTER]
	for g in City.GANGS:
		all.append(g.base_look)
	for t in all:
		if t and t.id == id:
			return t
	return null


func _arg(key: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.split("=", true, 1)[1]
	return ""


func _draw() -> void:
	draw_rect(Rect2(-100000, -100000, 200000, 200000), Color(0.07, 0.09, 0.12))
