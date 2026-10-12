extends Node2D
## XY 충돌 좌표 → 사선 화면 좌표. Z는 그림에만 쓰며 물리에는 전달하지 않는다.

var game: Node2D
var focus := Vector2.ZERO
var basis := Transform2D(Vector2(0.78, 0.39), Vector2(-0.78, 0.39), Vector2.ZERO)
var origin := Vector2.ZERO
var font: Font
var actors: Array[Node2D] = []
var fade := 1.0
var grain: Texture2D
var glow: Texture2D
var vehicle_height_scale := 1.0
var pin_labels: Array[Rect2] = []
const PROFILE = preload("res://data/visual/gangnam_night.tres")


func _ready() -> void:
	font = ThemeDB.fallback_font


func project(p: Vector2, height := 0.0) -> Vector2:
	return origin + basis * (p - focus) - Vector2(0, height)


func _poly(points: Array, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), Color(color, color.a * fade))


func _quad(r: Rect2, height: float, color: Color) -> void:
	_poly([project(r.position, height), project(Vector2(r.end.x, r.position.y), height), project(r.end, height), project(Vector2(r.position.x, r.end.y), height)], color)


func _collect(node: Node) -> void:
	for child in node.get_children():
		if child is Vehicle or child is Pedestrian:
			actors.append(child)
		else:
			_collect(child)


func _draw() -> void:
	var city: City = game.city
	var viewport_size := get_viewport_rect().size
	origin = viewport_size * Vector2(0.5, 0.59)
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color("141c2a"))
	var cell := CityMap.block_at(focus)
	# 도로 표시는 원본 좌표·교차로 함수를 그대로 투영한다.
	var ground_transform := basis
	ground_transform.origin = origin - basis * focus
	draw_set_transform_matrix(ground_transform)
	for j in range(cell.y - 2, cell.y + 3):
		for i in range(cell.x - 2, cell.x + 3):
			var block := City.block_rect(i, j)
			draw_rect(block, Color("4b505b"))
			draw_rect(block.grow(-4), Color("323c47"), false, 3)
			for x in range(int(block.position.x), int(block.end.x), 24):
				draw_line(Vector2(x, block.position.y), Vector2(x, block.end.y), Color(0.6, 0.65, 0.7, 0.1))
			city._draw_road_segment(self, i, j, true, [])
			city._draw_road_segment(self, j, i, false, [])
	for idx in game.city.parks.size():
		if game.city.parks[idx].get_center().distance_to(focus) < 2200:
			BuildingDrawer.draw(self, game.city.parks[idx], game.city.park_kinds[idx], idx, font)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# 광원 근처 노면에만 색 번짐을 놓는다.
	for j in range(cell.y - 1, cell.y + 2):
		for i in range(cell.x - 1, cell.x + 2):
			var p := project(City.block_rect(i,j).position - Vector2(12,12))
			var color: Color = PROFILE.cyan if (i+j)%2 == 0 else PROFILE.pink
			draw_texture_rect(glow, Rect2(p-Vector2(90,35),Vector2(180,70)),false,Color(color,0.24))
	var items: Array[Dictionary] = []
	var controller: TrafficController = game.traffic.controller
	for signal_cell: Vector2i in controller.signal_offsets:
		var center := LaneGraph.center(signal_cell)
		if center.distance_to(focus) > 1600:
			continue
		for direction in 4:
			if not CityMap.road(signal_cell, (direction + 2) % 4):
				continue
			var dir := LaneGraph.DIRS[direction]
			var pole := center - dir * (LaneGraph.HALF + 10.0) + LaneGraph.right_of(dir) * (LaneGraph.HALF + 10.0)
			items.append({"depth": pole.x + pole.y, "signal_pos": pole, "light": controller.light(signal_cell, direction), "direction": dir})
	for idx in game.city.buildings.size():
		var r: Rect2 = game.city.buildings[idx]
		if r.get_center().distance_to(focus) < 2100:
			items.append({"depth": r.end.x + r.end.y, "building": idx})
	actors.clear()
	_collect(game)
	for actor in actors:
		if actor.global_position.distance_to(focus) < 1700:
			items.append({"depth": actor.global_position.x + actor.global_position.y, "actor": actor})
	if game.player.visible:
		items.append({"depth": game.player.global_position.x + game.player.global_position.y, "actor": game.player})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.depth < b.depth)
	for item in items:
		if item.has("building"):
			_building(item.building)
		elif item.has("signal_pos"):
			_signal(item.signal_pos, item.light, item.direction)
		elif item.actor is Vehicle:
			_vehicle(item.actor)
		else:
			_person(item.actor)
	_facilities()
	# 가려진 경우에도 실제 조종 대상의 위치를 읽을 수 있는 표식.
	var target: Node2D = game.director.controlled_target()
	var mark := project(target.global_position, 37)
	_poly([mark + Vector2(-7, -9), mark + Vector2(7, -9), mark], Color("ffd278"))


func _signal(world: Vector2, light: int, direction: Vector2) -> void:
	var foot := project(world)
	var top := project(world, 40)
	draw_line(foot, top, Color("9baab3"), 3)
	draw_rect(Rect2(top - Vector2(8, 26), Vector2(16, 30)), Color("101720"))
	var colors: Array[Color] = [Color("ff5b67"), Color("ffd166"), Color("5cec9b")]
	var active := 2 - light
	for lamp in 3:
		draw_circle(top + Vector2(0, -20 + lamp * 9), 3, colors[lamp] if lamp == active else Color("303b44"))
	# 차량이 들어오는 방향을 작은 화살표로 표시한다.
	var arrow := basis.basis_xform(direction).normalized() * 10
	draw_line(foot, foot + arrow, Color(colors[active],0.7), 2)
	draw_line(foot + arrow, foot + arrow * 0.6 + arrow.orthogonal() * 0.3, colors[active], 1)
	draw_line(foot + arrow, foot + arrow * 0.6 - arrow.orthogonal() * 0.3, colors[active], 1)


func _facilities() -> void:
	pin_labels.clear()
	var missions: MissionSystem = game.missions
	var destination: Variant = missions.objective_position()
	if destination is Vector2:
		_pin(destination, "미션 목표", Color("ffd166"))
	for hideout: Hideout in game.hideouts:
		if hideout.visible:
			_pin(hideout.global_position, "은신처 · 저장" if hideout.owned else "매물 · ₩" + Hud.won(hideout.type.price), Color("79e7b0"))
	var shop: SprayShop = game.spray_shop
	if CityMap.is_open_block(City.nearest_block(shop.global_position)):
		_pin(shop.global_position, "정비 · ₩" + Hud.won(SprayShop.PRICE), Color("79c8f3"))
	for phone: Dictionary in missions.phones:
		var pos: Vector2 = phone.pos
		if not CityMap.is_open_block(City.nearest_block(pos)):
			continue
		var unlocked := missions.respect.tier_open(phone.gang, phone.tier)
		var available := unlocked and missions.next_mission(phone.gang,phone.tier,phone.set) != null
		var state := "수락 가능" if available else ("완료" if unlocked else "잠김")
		if missions.active():
			state = "진행 중"
		_pin(pos,"전화 · " + MissionSystem.TIER_NAMES[phone.tier] + " · " + state,Color("ffd166") if available and not missions.active() else Color("9aa9b8"))


func _pin(world: Vector2, title: String, color: Color) -> void:
	var foot := project(world)
	var viewport := get_viewport_rect().grow(-24)
	if not viewport.has_point(foot):
		return
	var width := font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x + 16
	var label_pos := foot - Vector2(width * 0.5, 49)
	label_pos.x = clampf(label_pos.x,24,get_viewport_rect().size.x-width-24)
	var label_rect := Rect2(label_pos,Vector2(width,23))
	for attempt in 5:
		var overlaps := false
		for other in pin_labels:
			if label_rect.grow(3).intersects(other):
				overlaps = true
				break
		if not overlaps:
			break
		label_rect.position.y -= 28
	if label_rect.position.y < 24:
		return
	pin_labels.append(label_rect)
	label_pos = label_rect.position
	draw_arc(foot, 9, 0, TAU, 20, color, 2)
	draw_line(foot-Vector2(0,10),label_rect.get_center()+Vector2(0,12),Color(color,0.55),1)
	draw_rect(Rect2(label_pos,Vector2(width,23)),Color(0.025,0.055,0.08,0.94))
	draw_rect(Rect2(label_pos,Vector2(width,23)),Color(color,0.65),false,1)
	draw_string(font,label_pos+Vector2(8,16),title,HORIZONTAL_ALIGNMENT_LEFT,-1,13,color)


func _building(idx: int) -> void:
	var r: Rect2 = game.city.buildings[idx]
	var kind: BuildingType = game.city.kinds[idx]
	var style: StringName = kind.style if kind else &"office"
	var floors := 3 if style in [&"villa", &"house", &"rowhouse"] else 5
	var height := float(floors * 26 + idx % 3 * 12)
	var a := project(r.position, height)
	var b := project(Vector2(r.end.x, r.position.y), height)
	var c := project(r.end, height)
	var d := project(Vector2(r.position.x, r.end.y), height)
	var b0 := project(Vector2(r.end.x, r.position.y))
	var c0 := project(r.end)
	var d0 := project(Vector2(r.position.x, r.end.y))
	# 투영된 벽·지붕과 조종 대상이 겹치면 건물 전체를 반투명하게 한다.
	var outline := PackedVector2Array([a, b, b0, c0, d0, d])
	fade = 0.22 if Geometry2D.is_point_in_polygon(project(game.director.controlled_target().global_position, 12), outline) else 1.0
	_poly([b, c, c0, b0], Color("263747"))
	_poly([d, c, c0, d0], Color("3c3944"))
	_poly([a, b, c, d], Color("34474b") if style in [&"office", &"officetel"] else Color("45414b"))
	var roof_transform := basis
	roof_transform.origin = origin - basis * focus - Vector2(0,height)
	draw_set_transform_matrix(roof_transform)
	draw_texture_rect(grain,r,true,Color(0.8,0.85,0.95,0.4*fade))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# 두 전면을 따라 각 층의 창을 세운다.
	for side in 2:
		var start := Vector2(r.end.x, r.position.y) if side == 0 else Vector2(r.position.x, r.end.y)
		var finish := r.end
		var bays := maxi(2, int(start.distance_to(finish) / 33))
		for floor_idx in floors:
			for bay in bays:
				var p := start.lerp(finish, (bay + 0.18) / bays)
				var q := start.lerp(finish, (bay + 0.7) / bays)
				var z := float(12 + floor_idx * 26)
				var color := Color("c09b65") if (bay * 7 + floor_idx * 3 + idx) % 4 == 0 else Color("1c2837")
				_poly([project(p,z), project(q,z), project(q,z+13), project(p,z+13)], color)
		if style in [&"commercial", &"mixed", &"gosiwon"]:
			for shop in mini(4, bays / 2):
				var anchor := start.lerp(finish, 0.12 + shop * 0.21)
				_wall_sign(anchor, finish-start, 49.0, PROFILE.signs[(idx+shop+side)%PROFILE.signs.size()], PROFILE.pink if shop%2 == 0 else PROFILE.cyan)
	# 난간과 옥상 설비는 지붕 안에 배치한다.
	var roof := r.grow(-8)
	var corners := PackedVector2Array([project(roof.position,height+3), project(Vector2(roof.end.x,roof.position.y),height+3), project(roof.end,height+3), project(Vector2(roof.position.x,roof.end.y),height+3), project(roof.position,height+3)])
	draw_polyline(corners, Color(Color("829093"), fade), 3)
	for k in 4:
		var unit := Rect2(r.position + Vector2(30 + k * 42, 35), Vector2(27, 22))
		if r.encloses(unit):
			_quad(unit, height + 5, Color("7b8990"))
			_quad(unit.grow(-5), height + 6, Color("33434d"))
	var title := kind.signs[idx % kind.signs.size()] if kind and not kind.signs.is_empty() else "서울 빌딩"
	if r == game.city.hq:
		title = "금강개발"
	elif r == game.city.hideout:
		title = "은신처"
	elif style == &"apt":
		title += "01동"
	var sign_pos := project(r.end, height * 0.7)
	var tint := Color("66d7ed") if idx % 2 == 0 else Color("ee6fa6")
	var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 18
	draw_rect(Rect2(sign_pos - Vector2(width / 2, 22), Vector2(width, 28)), Color(0.035, 0.06, 0.1, fade))
	draw_rect(Rect2(sign_pos - Vector2(width / 2, 22), Vector2(width, 28)), Color(tint, fade), false, 1)
	draw_string(font, sign_pos - Vector2(width / 2 - 9, 2), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(tint, fade))
	fade = 1.0


func _wall_sign(anchor: Vector2, direction: Vector2, height: float, text: String, color: Color) -> void:
	var along := basis.basis_xform(direction).normalized()
	var transform := Transform2D(along, Vector2.DOWN, project(anchor,height))
	draw_set_transform_matrix(transform)
	var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x + 12
	draw_rect(Rect2(-3,-3,width+6,26),Color(0.015,0.025,0.04,fade))
	draw_rect(Rect2(0,0,width,20),Color(color.darkened(0.8),fade))
	draw_rect(Rect2(0,0,width,20),Color(color,fade),false,1)
	draw_string(font,Vector2(6,15),text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(color.lightened(0.4),fade))
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _vehicle(car: Vehicle) -> void:
	preload("res://tools/isometric_sample/vehicle_drawer.gd").draw(self, car)


func _person(person: Node2D) -> void:
	var p := project(person.global_position)
	var down: bool = person.is_dead() if person is Player else person.state in [Pedestrian.State.DEAD, Pedestrian.State.KNOCKED]
	draw_set_transform(p,0,Vector2(1,0.4))
	draw_circle(Vector2.ZERO,7,Color(0,0,0,0.35))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if down:
		draw_line(p-Vector2(6,0),p+Vector2(6,0),person.shirt,5)
		return
	var stride := sin(person.walk_phase) * 2.0
	draw_line(p+Vector2(-2,-8),p+Vector2(-3,stride),person.pants,3)
	draw_line(p+Vector2(2,-8),p+Vector2(3,-stride),person.pants,3)
	draw_rect(Rect2(p-Vector2(5,19),Vector2(10,12)),person.shirt.lightened(0.15))
	draw_circle(p-Vector2(0,23),4,Color("c39b7c"))
	draw_arc(p-Vector2(0,24),4,PI,TAU,8,person.hair,3)
