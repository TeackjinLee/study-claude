class_name MapView
extends Control
## 일시정지 메뉴의 서울 지도: 위에서 본 도시 전체(북쪽이 위). 미니맵(Minimap)과 같은 모양이다 — 밝은 도로 사이에 어두운 블록과
## 부지(건물), 강·공원, 기능 건물은 동그란 그림 표(Minimap.draw_icon — 병원·경찰·은신처·카센터·아지트·창고), 미션·부업 목표까지
## 도로를 따라 노란 길(Minimap.route)과 핀, 주인공은 흰 화살촉.
## 큰 지도에만 있는 것: 잠긴 구역 그늘과 "N장에 열림", 구역 이름, 산 은신처, 공중전화(조직 색 점, 열린 구역만), 쫓는 범인(빨간 점), 범례.
## 비밀 패키지·광란 아이콘은 지도에 없다 (찾는 재미).
## 바탕(블록·부지·강·이름)은 크기가 바뀔 때만 그리고, 움직이는 표시는 위층(Marks)이 매 프레임 그린다.

const BACK := Color(0.05, 0.06, 0.08)
const CRIMINAL := Color(1.0, 0.3, 0.2)
const PHONE_COLOR := Color(1.0, 0.6, 0.2)    ## 범례의 공중전화 (지도 위 점은 조직 색)
const CONE := 26.0                           ## 주인공 보는 쪽 부채꼴 길이

var main: Node2D
var _t := 0.0
var _route := PackedVector2Array()
var _route_goal: Variant = null


func _ready() -> void:
	var marks := Marks.new()
	marks.map = self
	marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(marks)


## 위층: 주인공·목표·길·그림 표처럼 바뀌거나 깜박이는 것
class Marks:
	extends Control
	var map: MapView

	func _process(delta: float) -> void:
		map._t += delta
		queue_redraw()

	func _draw() -> void:
		map._draw_marks(self)


## 월드 → 이 칸 안 좌표 (비율 유지, 가운데 맞춤)
func _xf() -> Transform2D:
	var w := City.world_rect()
	var k := minf(size.x / w.size.x, size.y / w.size.y)
	var off := (size - w.size * k) * 0.5 - w.position * k
	return Transform2D(0.0, Vector2(k, k), 0.0, off)


## 바탕: 도로(지도 전체) 위에 블록과 부지, 잠긴 구역은 어둡게, 강·공원, 구역 이름
func _draw() -> void:
	var xf := _xf()
	draw_rect(Rect2(Vector2.ZERO, size), BACK)
	draw_set_transform_matrix(xf)
	draw_rect(City.world_rect(), Minimap.ROAD_COLOR)
	var lots := Minimap.lots_by_block(main.city.buildings) if main else {}
	for j in range(CityMap.MIN.y, CityMap.MAX.y + 1):
		for i in range(CityMap.MIN.x, CityMap.MAX.x + 1):
			var b := Vector2i(i, j)
			if CityMap.is_land(b) and not CityMap.is_open_block(b):
				draw_rect(City.block_rect(i, j).grow(City.ROAD * 0.5), Minimap.LOCKED_ROAD)
	for j in range(CityMap.MIN.y, CityMap.MAX.y + 1):
		for i in range(CityMap.MIN.x, CityMap.MAX.x + 1):
			var b := Vector2i(i, j)
			if not CityMap.is_land(b):
				continue
			var r := City.block_rect(i, j)
			if not CityMap.is_open_block(b):
				draw_rect(r, Minimap.LOCKED_COLOR)
				continue
			draw_rect(r, Minimap.BLOCK_COLOR)
			for lot: Rect2 in lots.get(b, []):
				draw_rect(lot, Minimap.LOT_COLOR)
	for r in City.water_rects():
		draw_rect(r, Minimap.WATER_COLOR)
	if main:
		for r in main.city.parks:
			if _open(r.get_center()):
				draw_rect(r, Minimap.PARK_COLOR)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var font := ThemeDB.fallback_font
	for d in CityMap.DISTRICTS:
		var a := City.block_rect(d.blocks.position.x, d.blocks.position.y)
		var e := City.block_rect(d.blocks.end.x - 1, d.blocks.end.y - 1)
		var at := xf * ((a.position + e.end) * 0.5)
		var open := d.chapter <= CityMap.chapter
		var name := Locale.t(d.display_name) if open else Locale.t("%d장에 열림") % d.chapter
		draw_string_outline(font, at + Vector2(-80, 6), name, HORIZONTAL_ALIGNMENT_CENTER, 160, 15, 4, Color(0, 0, 0, 0.8))
		draw_string(font, at + Vector2(-80, 6), name, HORIZONTAL_ALIGNMENT_CENTER, 160, 15,
			Color(1, 1, 1, 0.9 if open else 0.45))


func _draw_marks(ci: CanvasItem) -> void:
	if main == null:
		return
	var xf := _xf()
	var city: City = main.city
	var me: Node2D = main.director.controlled_target()
	# GPS 길 (멈춘 동안 목표가 바뀔 때만 다시 찾는다)
	var goal: Variant = Minimap.goal_of(main.missions, main.jobs)
	if goal != _route_goal:
		_route_goal = goal
		_route.clear()
		if goal is Vector2:
			var car: Vehicle = main.director.current_vehicle
			_route = Minimap.route(me.global_position, car.motor.forward() if car else Vector2.ZERO, goal)
	if _route.size() > 1:
		Minimap.draw_route_line(ci, [xf * _route])
	# 공중전화 (열린 구역만)
	for q: Dictionary in main.missions.phones:
		if _open(q.pos):
			_dot(ci, xf * (q.pos as Vector2), (q.gang as GangType).accent, 3.5)
	# 기능 건물 그림 표 (열린 구역만)
	for r in city.hospitals:
		_icon(ci, xf, r.get_center(), Minimap.Icon.HOSPITAL)
	for r in city.stations:
		_icon(ci, xf, r.get_center(), Minimap.Icon.POLICE)
	_icon(ci, xf, city.hq.get_center(), Minimap.Icon.HQ)
	_icon(ci, xf, city.warehouse.get_center(), Minimap.Icon.WAREHOUSE)
	_icon(ci, xf, City.spray_bay(), Minimap.Icon.SPRAY)
	_icon(ci, xf, City.hideout_door(), Minimap.Icon.HIDEOUT)
	for h: Hideout in main.hideouts:
		if h.owned:
			_icon(ci, xf, h.type.door, Minimap.Icon.HIDEOUT)
	# 쫓는 범인 (거리 이벤트)
	var crook: Vector2 = main.street_events.target_position()
	if crook != Vector2.INF:
		_dot(ci, xf * crook, CRIMINAL, 4.5 + sin(_t * 10.0))
	if goal is Vector2:
		Minimap.draw_pin(ci, xf * (goal as Vector2), 0.5 + 0.5 * sin(_t * 6.0))
	Minimap.draw_player(ci, xf * me.global_position, Minimap.heading_of(main.director), CONE)
	_draw_legend(ci)


## 열린 구역인가 (잠긴 구역의 공원·그림 표·공중전화는 그리지 않는다)
static func _open(world: Vector2) -> bool:
	return CityMap.is_open_block(City.nearest_block(world))


func _icon(ci: CanvasItem, xf: Transform2D, world: Vector2, kind: Minimap.Icon) -> void:
	if world != Vector2.ZERO and _open(world):
		Minimap.draw_icon(ci, xf * world, kind)


func _dot(ci: CanvasItem, p: Vector2, color: Color, r: float) -> void:
	ci.draw_circle(p, r + 1.5, Minimap.OUTLINE)
	ci.draw_circle(p, r, color)


## 범례: 왼쪽 아래에 세로로 (지도 옆 빈 곳)
func _draw_legend(ci: CanvasItem) -> void:
	var font := ThemeDB.fallback_font
	var items := [["나", -1], ["병원", Minimap.Icon.HOSPITAL], ["경찰서", Minimap.Icon.POLICE],
		["은신처", Minimap.Icon.HIDEOUT], ["카센터", Minimap.Icon.SPRAY], ["아지트", Minimap.Icon.HQ],
		["창고", Minimap.Icon.WAREHOUSE], ["공중전화", -2], ["미션 목표", -3]]
	const ROW := 22.0
	var w := 0.0
	for item in items:
		w = maxf(w, font.get_string_size(Locale.t(item[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
	var box := Rect2(Vector2(8, size.y - 8 - items.size() * ROW - 8), Vector2(w + 44, items.size() * ROW + 8))
	ci.draw_rect(box, Color(Minimap.BEZEL, 0.8))
	for k in items.size():
		var c := box.position + Vector2(17, 4 + ROW * (k + 0.5))
		var kind: int = items[k][1]
		match kind:
			-1:
				Minimap.draw_player(ci, c, 0.0, 0.0)
			-2:
				_dot(ci, c, PHONE_COLOR, 3.5)
			-3:
				Minimap.draw_pin(ci, c + Vector2(0, 8), 1.0)
			_:
				Minimap.draw_icon(ci, c, kind as Minimap.Icon)
		ci.draw_string(font, c + Vector2(16, 5), Locale.t(items[k][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.85))
