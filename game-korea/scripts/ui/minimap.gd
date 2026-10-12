class_name Minimap
extends Control
## 원형 미니맵 (docs/06 HUD). 주인공이 가운데. 위에서 보는 화면에서는 위가 북쪽,
## 2.5D 화면에서는 화면과 같은 방향(위가 북서쪽)으로 45° 돌린다 — N 표시가 북쪽을 가리킨다. 블록·강·특수 건물·미션 목표·공중전화·은신처·카센터·경찰차를 찍는다.
## 아래에 지금 있는 구역 이름을 적는다.
## 수배 중에는 카센터도 테두리에 붙여 방향을 보여 준다.
## 화면 밖 목표는 테두리에 붙여 방향만 보여 준다.

const RADIUS := 86.0
const SCALE := 0.07              ## 월드 1px → 미니맵 px
const BG := Color(0.1, 0.11, 0.15, 0.85)
const BLOCK_COLOR := Color(0.3, 0.32, 0.38)
const LOCKED_COLOR := Color(0.16, 0.16, 0.18)
const WATER_COLOR := Color(0.1, 0.22, 0.4)
const PARK_COLOR := Color(0.2, 0.38, 0.22)

var director: Director
var police: PoliceDispatcher
var missions: MissionSystem
var city: City
var jobs: SideJobs
var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var c := Vector2(RADIUS, RADIUS)
	var me := director.controlled_target().global_position
	draw_circle(c, RADIUS + 3.0, Color(0, 0, 0, 0.8))
	draw_circle(c, RADIUS, BG)
	var circle := _circle_poly(c, RADIUS - 1.0)
	# 주인공 둘레 블록만: 땅·잠긴 땅, 그리고 강물
	var here := CityMap.block_at(me)
	var reach := ceili(RADIUS / SCALE / City.PITCH) + 1
	for j in range(here.y - reach, here.y + reach + 1):
		for i in range(here.x - reach, here.x + reach + 1):
			var b := Vector2i(i, j)
			if CityMap.is_land(b):
				_fill(City.block_rect(i, j), me, c, circle, BLOCK_COLOR if CityMap.is_open_block(b) else LOCKED_COLOR)
	var view := RADIUS / SCALE + City.BLOCK
	for r in city.water:
		if absf(r.get_center().x - me.x) < view and absf(r.get_center().y - me.y) < view:
			_fill(r, me, c, circle, WATER_COLOR)
	for r in city.parks:
		_fill(r, me, c, circle, PARK_COLOR)
	_fill(city.hq, me, c, circle, Color(0.75, 0.6, 0.2))
	_fill(city.hideout, me, c, circle, Color(0.25, 0.6, 0.35))
	for r in city.hospitals:
		_fill(r, me, c, circle, Color(0.85, 0.85, 0.85))
	for r in city.stations:
		_fill(r, me, c, circle, Color(0.3, 0.45, 0.85))
	_fill(city.warehouse, me, c, circle, Color(0.55, 0.5, 0.35))
	_fill(city.spray, me, c, circle, Color(0.3, 0.65, 0.85))
	for p in missions.phones:
		_dot(p.pos, me, c, (p.gang as GangType).accent, 3.0, false)
	_dot(City.hideout_door(), me, c, Color(0.4, 1.0, 0.6), 3.5, false)
	_dot(City.spray_bay(), me, c, Color(0.4, 0.85, 1.0), 3.5, police.wanted.level > 0)
	for car in police.cars:
		var red := (Time.get_ticks_msec() / 250) % 2 == 0
		_dot(car.global_position, me, c, Color(1, 0.2, 0.25) if red and car.siren else Color(0.35, 0.55, 1.0), 3.0, false)
	var goal: Variant = missions.objective_position()
	if goal == null and jobs:
		goal = jobs.objective_position()
	if goal != null:
		var r := 5.0 + 1.5 * sin(_time * 6.0)
		_dot(goal, me, c, Color(1.0, 0.85, 0.2), r, true)
	# 주인공: 진행 방향을 가리키는 흰 삼각형
	var heading := director.current_vehicle.motor.heading if director.current_vehicle else director.player.facing
	var tri := PackedVector2Array([Vector2(0, -7), Vector2(5, 5), Vector2(-5, 5)])
	for k in tri.size():
		tri[k] = c + tri[k].rotated(heading + _turn())
	draw_colored_polygon(tri, Color.WHITE)
	draw_arc(c, RADIUS, 0.0, TAU, 64, Color(0.45, 1.0, 0.55, 0.8), 2.0)
	var dist := CityMap.district_at(me)
	draw_string(ThemeDB.fallback_font, Vector2(0, RADIUS * 2 + 22), dist.display_name if dist else "한강",
		HORIZONTAL_ALIGNMENT_CENTER, RADIUS * 2, 16, Color(0.85, 0.9, 1.0, 0.9))
	var north := c + Vector2.UP.rotated(_turn()) * (RADIUS - 12.0)
	draw_string(ThemeDB.fallback_font, north + Vector2(-4, 5), "N",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))


## 미니맵 회전 (2.5D면 화면처럼 북서쪽이 위)
static func _turn() -> float:
	return PI * 0.25 if IsoView.enabled else 0.0


func _to_map(world: Vector2, me: Vector2, c: Vector2) -> Vector2:
	return c + (world - me).rotated(_turn()) * SCALE


## 사각형을 원 안으로 잘라 칠한다
func _fill(r: Rect2, me: Vector2, c: Vector2, circle: PackedVector2Array, color: Color) -> void:
	if r.size == Vector2.ZERO:
		return
	var center := _to_map(r.get_center(), me, c)
	if center.distance_to(c) > RADIUS + r.size.length() * 0.5 * SCALE:
		return
	var corners := PackedVector2Array([_to_map(r.position, me, c), _to_map(Vector2(r.end.x, r.position.y), me, c),
		_to_map(r.end, me, c), _to_map(Vector2(r.position.x, r.end.y), me, c)])
	var inside := 0
	for p: Vector2 in corners:
		if p.distance_to(c) < RADIUS - 1.0:
			inside += 1
	if inside == 4:
		draw_colored_polygon(corners, color)
		return
	for part in Geometry2D.intersect_polygons(PackedVector2Array(corners), circle):
		# 원 테두리에 걸친 아주 가는 조각은 삼각분할이 실패하므로 건너뛴다
		if absf(_area(part)) > 2.0:
			draw_colored_polygon(part, color)


## 점 하나. pin이면 원 밖일 때 테두리에 붙인다 (아니면 안 그린다)
func _dot(world: Vector2, me: Vector2, c: Vector2, color: Color, r: float, pin: bool) -> void:
	var p := _to_map(world, me, c)
	var off := p - c
	if off.length() > RADIUS - r:
		if not pin:
			return
		p = c + off.normalized() * (RADIUS - r)
	draw_circle(p, r + 1.5, Color(0, 0, 0, 0.8))
	draw_circle(p, r, color)


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for k in poly.size():
		a += poly[k].cross(poly[(k + 1) % poly.size()])
	return a * 0.5


static func _circle_poly(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 40:
		pts.append(c + Vector2.RIGHT.rotated(k * TAU / 40.0) * r)
	return pts
