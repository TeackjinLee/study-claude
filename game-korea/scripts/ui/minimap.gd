class_name Minimap
extends Control
## 원형 미니맵 (docs/06 HUD). 주인공이 가운데. 위에서 보는 화면에서는 위가 북쪽,
## 2.5D 화면에서는 화면과 같은 방향(위가 북서쪽)으로 45° 돌린다 — N 표시가 북쪽을 가리킨다.
## 밝은 도로 사이에 어두운 블록과 부지(건물), 강·공원, 기능 건물은 동그란 그림 표(병원 십자·경찰 별·은신처 집·카센터 붓·
## 아지트 왕관·창고 상자), 공중전화·경찰차·쫓는 범인 점을 찍는다. 미션·부업 목표가 있으면 도로를 따라 노란 길(GPS,
## RoadNav.next_cell)을 긋고 목표에 핀을 꽂는다 — 원 밖이면 테두리에 방향 화살과 남은 거리.
## 달릴수록 넓게 본다 (SCALE_FOOT → SCALE_FAST). 아래 이름표에 구역 이름과 목표까지 거리.
## 수배 중에는 카센터도 테두리에 붙여 방향을 보여 준다.
## 그림 표·노란 길·핀·주인공 화살촉 그리기(draw_*)와 route·lots_by_block은 정적이라 일시정지 큰 지도(MapView)도 같이 쓴다.

const RADIUS := 96.0
const SCALE := 0.085             ## 걸을 때 월드 1px → 미니맵 px
const SCALE_FAST := 0.05         ## 빨리 달릴 때 (넓게 본다)
const FAST_SPEED := 700.0        ## 이 빠르기(px/s)면 SCALE_FAST
const ZOOM_RATE := 2.0
const METERS_PER_PX := 0.061     ## 거리 표시 (Hud.KMH_PER_PX와 같은 비율)
const ROUTE_EVERY := 0.4         ## GPS 길을 이 간격으로 다시 찾는다 (초)
const ROUTE_STEPS := 60
const ROAD_COLOR := Color(0.36, 0.41, 0.52)        ## 바탕 = 도로
const BLOCK_COLOR := Color(0.12, 0.15, 0.22)       ## 블록 (인도 포함)
const LOT_COLOR := Color(0.2, 0.24, 0.33)          ## 부지 (건물)
const LOCKED_COLOR := Color(0.07, 0.07, 0.09)
const LOCKED_ROAD := Color(0.16, 0.17, 0.2)
const WATER_COLOR := Color(0.13, 0.32, 0.58)
const PARK_COLOR := Color(0.17, 0.36, 0.24)
const ROUTE_COLOR := Color(1.0, 0.82, 0.18)
const BEZEL := Color(0.04, 0.05, 0.08, 0.92)      ## 바깥 테
const RIM := Color(0.92, 0.94, 1.0, 0.9)           ## 테 안쪽 흰 선
const BEZEL_WIDTH := 7.0
const OUTLINE := Color(0, 0, 0, 0.85)
const ICON_R := 8.0              ## 그림 표 반지름
const POLICE_BLUE := Color(0.35, 0.55, 1.0)
const POLICE_RED := Color(1, 0.2, 0.25)

enum Icon { HOSPITAL, POLICE, HIDEOUT, SPRAY, HQ, WAREHOUSE }

var director: Director
var police: PoliceDispatcher
var missions: MissionSystem
var city: City
var jobs: SideJobs
var events: StreetEvents
var scale_now := SCALE
var _time := 0.0
var _lots := {}                  ## 블록 → 그 블록의 부지 사각형들 (처음 한 번 나눈다)
var _route := PackedVector2Array()
var _route_goal := Vector2.INF
var _route_wait := 0.0


func _process(delta: float) -> void:
	_time += delta
	var car := director.current_vehicle
	var speed := car.speed() if car else 0.0
	var want := lerpf(SCALE, SCALE_FAST, clampf(speed / FAST_SPEED, 0.0, 1.0))
	scale_now = lerpf(scale_now, want, clampf(delta * ZOOM_RATE, 0.0, 1.0))
	_route_wait -= delta
	var goal: Variant = _goal()
	if goal == null:
		_route.clear()
		_route_goal = Vector2.INF
	elif _route_wait <= 0.0 or goal != _route_goal:
		_route_wait = ROUTE_EVERY
		_route_goal = goal
		var me := director.controlled_target().global_position
		_route = route(me, car.motor.forward() if car else Vector2.ZERO, goal)
	queue_redraw()


func _goal() -> Variant:
	return goal_of(missions, jobs)


## 미션 목표, 없으면 부업 목표 (둘 다 없으면 null) — 큰 지도(MapView)도 쓴다
static func goal_of(missions: MissionSystem, jobs: SideJobs) -> Variant:
	var goal: Variant = missions.objective_position()
	if goal == null and jobs:
		goal = jobs.objective_position()
	return goal


## 도로를 따라 from에서 goal까지 가는 길 (교차로 가운데를 잇는다). 가까우면 곧게.
## forward가 있으면(차) 뒤로 도는 길에 벌점을 준다 (RoadNav.next_cell)
static func route(from: Vector2, forward: Vector2, goal: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array([from])
	var mine := RoadNav.road_ends(from)
	var theirs := RoadNav.road_ends(goal)
	if from.distance_to(goal) < City.PITCH * 0.6 or (mine.has(theirs[0]) and mine.has(theirs[1])):
		pts.append(goal)
		return pts
	pts.append(Geometry2D.get_closest_point_to_segment(from, LaneGraph.center(mine[0]), LaneGraph.center(mine[1])))
	var pos := pts[1]
	var fwd := forward
	for i in ROUTE_STEPS:
		var c := RoadNav.next_cell(pos, fwd, goal)
		var at := LaneGraph.center(c)
		if pts.has(at):
			break
		pts.append(at)
		if theirs.has(c):
			break
		fwd = (at - pos).normalized()
		pos = at
	pts.append(Geometry2D.get_closest_point_to_segment(goal, LaneGraph.center(theirs[0]), LaneGraph.center(theirs[1])))
	pts.append(goal)
	return pts


func _draw() -> void:
	var c := Vector2(RADIUS, RADIUS)
	var me := director.controlled_target().global_position
	draw_circle(c, RADIUS + BEZEL_WIDTH + 1.0, Color(0, 0, 0, 0.35))   # 그림자
	draw_circle(c, RADIUS, ROAD_COLOR)
	var circle := _circle_poly(c, RADIUS - 1.0)
	# 주인공 둘레 블록: 블록(인도) 위에 부지, 잠긴 블록은 어둡게
	var here := CityMap.block_at(me)
	var reach := ceili(RADIUS / scale_now / City.PITCH) + 1
	for j in range(here.y - reach, here.y + reach + 1):
		for i in range(here.x - reach, here.x + reach + 1):
			var b := Vector2i(i, j)
			if not CityMap.is_land(b):
				continue
			var r := City.block_rect(i, j)
			if not CityMap.is_open_block(b):
				_fill(r.grow(City.ROAD * 0.5), me, c, circle, LOCKED_ROAD)
				_fill(r, me, c, circle, LOCKED_COLOR)
				continue
			_fill(r, me, c, circle, BLOCK_COLOR)
			for lot: Rect2 in _lots_of(b):
				_fill(lot, me, c, circle, LOT_COLOR)
	var view := RADIUS / scale_now + City.BLOCK
	for r in city.water:
		if absf(r.get_center().x - me.x) < view + r.size.x and absf(r.get_center().y - me.y) < view + r.size.y:
			_fill(r, me, c, circle, WATER_COLOR)
	for r in city.parks:
		_fill(r, me, c, circle, PARK_COLOR)
	# 안쪽 그늘 (테두리 쪽이 어둡다)
	for k in 4:
		draw_arc(c, RADIUS - 2.0 - k * 3.0, 0.0, TAU, 72, Color(0, 0, 0, 0.22 - k * 0.05), 3.0)
	# GPS 길
	if _route.size() > 1:
		_draw_route(me, c)
	# 기능 건물 그림 표
	for r in city.hospitals:
		_icon(r.get_center(), me, c, Icon.HOSPITAL, false)
	for r in city.stations:
		_icon(r.get_center(), me, c, Icon.POLICE, false)
	_icon(city.hq.get_center(), me, c, Icon.HQ, false)
	_icon(city.warehouse.get_center(), me, c, Icon.WAREHOUSE, false)
	_icon(City.hideout_door(), me, c, Icon.HIDEOUT, false)
	_icon(City.spray_bay(), me, c, Icon.SPRAY, police.wanted.level > 0)
	for p in missions.phones:
		_dot(p.pos, me, c, (p.gang as GangType).accent, 3.5, false)
	for car in police.cars:
		_dot(car.global_position, me, c, police_color(car), 3.5, false)
	var thief := events.target_position() if events else Vector2.INF
	if thief != Vector2.INF:
		_dot(thief, me, c, Color(1.0, 0.3, 0.2), 4.0 + 1.0 * sin(_time * 10.0), true)   # 쫓는 범인 (거리 이벤트)
	var goal: Variant = _goal()
	if goal != null:
		_goal_marker(goal, me, c)
	_draw_player(c)
	_draw_bezel(c)
	_draw_label(me, goal)


## 블록의 부지(건물) 사각형 — city.buildings를 처음 한 번 블록별로 나눈다
func _lots_of(b: Vector2i) -> Array:
	if _lots.is_empty():
		_lots = lots_by_block(city.buildings)
	return _lots.get(b, [])


## 부지 사각형을 블록별로 나눈다 (블록 → 사각형 배열)
static func lots_by_block(buildings: Array[Rect2]) -> Dictionary:
	var lots := {}
	for r in buildings:
		var k := CityMap.block_at(r.get_center())
		if not lots.has(k):
			lots[k] = []
		lots[k].append(r)
	lots[Vector2i(1 << 20, 0)] = []    # 건물이 없는 도시여도 다시 나누지 않게
	return lots


## 노란 길: 검은 테 위에 굵은 노란 줄, 원 밖은 자른다
func _draw_route(me: Vector2, c: Vector2) -> void:
	var pts := PackedVector2Array()
	for p in _route:
		pts.append(_to_map(p, me, c))
	pts[0] = c
	draw_route_line(self, Geometry2D.intersect_polyline_with_polygon(pts, _circle_poly(c, RADIUS - 3.0)))


## 노란 길 그림: 검은 테를 먼저 다 긋고 그 위에 노란 줄 (조각이 이어져 보이게)
static func draw_route_line(ci: CanvasItem, parts: Array) -> void:
	for part: PackedVector2Array in parts:
		ci.draw_polyline(part, Color(0, 0, 0, 0.7), 6.0, true)
	for part: PackedVector2Array in parts:
		ci.draw_polyline(part, ROUTE_COLOR, 3.5, true)


## 목표: 원 안이면 노란 핀, 밖이면 테두리에 바깥을 가리키는 화살
func _goal_marker(goal: Vector2, me: Vector2, c: Vector2) -> void:
	var p := _to_map(goal, me, c)
	var off := p - c
	var pulse := 0.5 + 0.5 * sin(_time * 6.0)
	if off.length() < RADIUS - 10.0:
		draw_pin(self, p, pulse)
		return
	var dir := off.normalized()
	var at := c + dir * (RADIUS - 9.0)
	var side := dir.orthogonal()
	var tri := PackedVector2Array([at + dir * 9.0, at - dir * 4.0 + side * 7.0, at - dir * 1.0, at - dir * 4.0 - side * 7.0])
	draw_colored_polygon(tri, Color(ROUTE_COLOR, 0.75 + 0.25 * pulse))
	tri.append(tri[0])
	draw_polyline(tri, OUTLINE, 1.5, true)


## 목표 핀: 뾰족한 끝이 p에 닿는 노란 핀 + 퍼지는 고리 (pulse 0~1)
static func draw_pin(ci: CanvasItem, p: Vector2, pulse: float) -> void:
	ci.draw_circle(p, 6.0 + pulse * 5.0, Color(ROUTE_COLOR, 0.35 * (1.0 - pulse)))
	var head := p + Vector2(0, -12)
	var pin := PackedVector2Array([p, head + Vector2(-5.5, 2.5), head + Vector2(-6, -3), head + Vector2(0, -7.5),
		head + Vector2(6, -3), head + Vector2(5.5, 2.5)])
	ci.draw_colored_polygon(pin, ROUTE_COLOR)
	pin.append(pin[0])
	ci.draw_polyline(pin, OUTLINE, 1.5, true)
	ci.draw_circle(head + Vector2(0, -1.5), 2.2, Color(0.25, 0.18, 0.02))


func _draw_player(c: Vector2) -> void:
	draw_player(self, c, heading_of(director) + _turn(), 34.0)


## 주인공이 보는 쪽 (차를 몰면 차 방향, 0 = 북쪽)
static func heading_of(director: Director) -> float:
	return director.current_vehicle.motor.heading if director.current_vehicle else director.player.facing


## 주인공: 보는 쪽 부채꼴(cone 길이, 0이면 없음) + 흰 화살촉. angle은 그림 위 방향 (0 = 위)
static func draw_player(ci: CanvasItem, c: Vector2, angle: float, cone: float) -> void:
	if cone > 0.0:
		var fan := PackedVector2Array([c])
		for k in 9:
			fan.append(c + Vector2.from_angle(angle - PI * 0.5 - 0.5 + k * 0.125) * cone)
		ci.draw_colored_polygon(fan, Color(1, 1, 1, 0.12))
	var tri := PackedVector2Array([Vector2(0, -11), Vector2(8, 8), Vector2(0, 3.5), Vector2(-8, 8)])
	for k in tri.size():
		tri[k] = c + tri[k].rotated(angle)
	ci.draw_colored_polygon(tri, Color.WHITE)
	tri.append(tri[0])
	ci.draw_polyline(tri, OUTLINE, 2.0, true)


## 테: 어두운 두꺼운 테 + 흰 안쪽 선 + 45° 눈금 + 북쪽 N 표
func _draw_bezel(c: Vector2) -> void:
	draw_arc(c, RADIUS + BEZEL_WIDTH * 0.5, 0.0, TAU, 96, BEZEL, BEZEL_WIDTH, true)
	draw_arc(c, RADIUS, 0.0, TAU, 96, RIM, 2.0, true)
	draw_arc(c, RADIUS + BEZEL_WIDTH, 0.0, TAU, 96, Color(1, 1, 1, 0.25), 1.0, true)
	for k in 8:
		var a := k * TAU / 8.0 + _turn() - PI * 0.5
		var tick := 5.0 if k % 2 == 0 else 3.0
		draw_line(c + Vector2.from_angle(a) * (RADIUS + 1.5), c + Vector2.from_angle(a) * (RADIUS + 1.5 + tick), Color(1, 1, 1, 0.55), 1.5)
	var north := c + Vector2.UP.rotated(_turn()) * (RADIUS + BEZEL_WIDTH * 0.5)
	draw_circle(north, 11.0, Color(0, 0, 0, 0.9))
	draw_circle(north, 9.5, Color(0.75, 0.15, 0.15))
	draw_arc(north, 9.5, 0.0, TAU, 24, RIM, 1.5, true)
	draw_string(ThemeDB.fallback_font, north + Vector2(-5, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


## 아래 이름표: 구역 이름 (목표가 있으면 · 남은 거리)
func _draw_label(me: Vector2, goal: Variant) -> void:
	var dist := CityMap.district_at(me)
	var where := Locale.t(dist.display_name if dist else "한강")
	var far := ""
	if goal != null:
		far = distance_text(_route_length(me))
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(where, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 22.0
	var fw := font.get_string_size(far, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 14.0 if far != "" else 0.0
	var pill := Rect2(Vector2(RADIUS - (w + fw) * 0.5, RADIUS * 2 + BEZEL_WIDTH + 6.0), Vector2(w + fw, 22))
	var box := StyleBoxFlat.new()
	box.bg_color = BEZEL
	box.set_corner_radius_all(11)
	box.set_border_width_all(1)
	box.border_color = Color(RIM, 0.5)
	draw_style_box(box, pill)
	draw_string(font, Vector2(pill.position.x, pill.end.y - 6), where, HORIZONTAL_ALIGNMENT_CENTER, w, 15, Color(0.88, 0.92, 1.0))
	if far != "":
		var x := pill.position.x + w
		draw_line(Vector2(x - 2, pill.position.y + 5), Vector2(x - 2, pill.end.y - 5), Color(1, 1, 1, 0.3), 1.0)
		draw_string(font, Vector2(x, pill.end.y - 6), far, HORIZONTAL_ALIGNMENT_CENTER, fw - 6.0, 15, ROUTE_COLOR)


## 남은 길 (GPS 길이 있으면 그 길이, 없으면 곧은 거리)
func _route_length(me: Vector2) -> float:
	if _route.size() < 2:
		return me.distance_to(_route_goal) if _route_goal != Vector2.INF else 0.0
	var total := me.distance_to(_route[1])
	for k in range(1, _route.size() - 1):
		total += _route[k].distance_to(_route[k + 1])
	return total


## 경찰차 점 색: 파랑, 사이렌을 켜면 빨강·파랑으로 깜박인다 — 큰 지도(MapView)도 쓴다
static func police_color(car: Vehicle) -> Color:
	var red := (Time.get_ticks_msec() / 250) % 2 == 0
	return POLICE_RED if red and car.siren else POLICE_BLUE


## 350m · 1.2km
static func distance_text(px: float) -> String:
	var m := px * METERS_PER_PX
	return "%dm" % (roundi(m / 10.0) * 10) if m < 1000.0 else "%.1fkm" % (m / 1000.0)


## 미니맵 회전 (2.5D면 화면처럼 북서쪽이 위)
static func _turn() -> float:
	return PI * 0.25 if IsoView.enabled else 0.0


func _to_map(world: Vector2, me: Vector2, c: Vector2) -> Vector2:
	return c + (world - me).rotated(_turn()) * scale_now


## 사각형을 원 안으로 잘라 칠한다
func _fill(r: Rect2, me: Vector2, c: Vector2, circle: PackedVector2Array, color: Color) -> void:
	if r.size == Vector2.ZERO:
		return
	var center := _to_map(r.get_center(), me, c)
	if center.distance_to(c) > RADIUS + r.size.length() * 0.5 * scale_now:
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
	draw_circle(p, r + 1.5, OUTLINE)
	draw_circle(p, r, color)


## 기능 건물 그림 표: 동그란 바탕 + 흰 그림. pin이면 원 밖일 때 테두리에 붙인다
func _icon(world: Vector2, me: Vector2, c: Vector2, kind: Icon, pin: bool) -> void:
	if world == Vector2.ZERO:
		return
	const R := ICON_R
	var p := _to_map(world, me, c)
	var off := p - c
	if off.length() > RADIUS - R:
		if not pin:
			return
		p = c + off.normalized() * (RADIUS - R)
	draw_icon(self, p, kind)


## 그림 표 하나를 p에 그린다 (반지름 ICON_R) — 큰 지도(MapView)도 쓴다
static func draw_icon(ci: CanvasItem, p: Vector2, kind: Icon) -> void:
	const R := ICON_R
	var bg: Color = [Color(0.92, 0.92, 0.94), Color(0.2, 0.38, 0.85), Color(0.2, 0.62, 0.35),
		Color(0.15, 0.62, 0.8), Color(0.85, 0.6, 0.15), Color(0.5, 0.4, 0.28)][kind]
	ci.draw_circle(p, R + 1.5, OUTLINE)
	ci.draw_circle(p, R, bg)
	var w := Color.WHITE
	match kind:
		Icon.HOSPITAL:
			var red := Color(0.88, 0.15, 0.15)
			ci.draw_rect(Rect2(p + Vector2(-1.8, -5.5), Vector2(3.6, 11)), red)
			ci.draw_rect(Rect2(p + Vector2(-5.5, -1.8), Vector2(11, 3.6)), red)
		Icon.POLICE:
			ci.draw_colored_polygon(_star(p, 5.5, 2.3), w)
		Icon.HIDEOUT:
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(6, -0.5), p + Vector2(-6, -0.5)]), w)
			ci.draw_rect(Rect2(p + Vector2(-4, -0.5), Vector2(8, 5.5)), w)
			ci.draw_rect(Rect2(p + Vector2(-1.2, 1.5), Vector2(2.4, 3.5)), bg)
		Icon.SPRAY:
			ci.draw_rect(Rect2(p + Vector2(-2.5, -2), Vector2(5, 7.5)), w)
			ci.draw_rect(Rect2(p + Vector2(-1.2, -4.5), Vector2(2.4, 2.5)), w)
			for k in 3:
				ci.draw_circle(p + Vector2(4.0 + k * 0.6, -5.0 + k * 2.0), 0.9, w)
		Icon.HQ:
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-5.5, 4), p + Vector2(-5.5, -3), p + Vector2(-2.7, 0),
				p + Vector2(0, -5), p + Vector2(2.7, 0), p + Vector2(5.5, -3), p + Vector2(5.5, 4)]), w)
		Icon.WAREHOUSE:
			ci.draw_rect(Rect2(p + Vector2(-5, -4), Vector2(10, 9)), w)
			ci.draw_line(p + Vector2(-5, -1), p + Vector2(5, -1), bg, 1.5)
			ci.draw_line(p + Vector2(0, -4), p + Vector2(0, -1), bg, 1.5)


static func _star(c: Vector2, outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 10:
		pts.append(c + Vector2.UP.rotated(k * TAU / 10.0) * (outer if k % 2 == 0 else inner))
	return pts


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
