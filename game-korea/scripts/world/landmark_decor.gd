class_name LandmarkDecor
## 랜드마크 전용 곡면·철골·천막 그림 (LandmarkBuilding의 roof 이름). 높이는 기존 IsoView 좌표계를 따른다.
## BARE(SpecialDecor.BARE)에 든 것은 벽 없이 여기서 통째로 그린다.

const RED := Color("c8372c")
const WHITE := Color("f1eee6")
const HAZARD := Color("e3b023")


static func draw(v: BuildingView, p: BuildingModel.Piece) -> void:
	match p.roof:
		&"observation_ring": ring(v, p)
		&"crane_brace": brace(v, p)
		&"satellite_dish": dish(v, p)
		&"antenna": antenna(v, p)
		&"lattice": lattice(v, p)
		&"canopy": canopy(v, p)
		&"tarp": tarp(v, p)
		&"produce": produce(v, p)
		&"lanterns": lanterns(v, p)
		&"lamp_pole": lamp_pole(v, p)
		&"hoist": hoist(v, p)
		&"pavilion": pavilion(v, p)


static func _at(w: Vector2, h: float) -> Vector2:
	return w + IsoView.lift(h)


static func ring(v: BuildingView, p: BuildingModel.Piece) -> void:
	var radius := p.rect.size.x * 0.55
	var height := p.h1 - p.h0
	v.draw_set_transform_matrix(IsoView.screen_frame(p.rect.get_center(), p.h1))
	var rim := PackedVector2Array()
	for k in 33:
		var angle := TAU * k / 32.0
		rim.append(Vector2(cos(angle) * radius, sin(angle) * radius * 0.48))
	for k in 16:
		var a := PI * k / 16.0
		var b := PI * (k + 1) / 16.0
		var u := Vector2(cos(a) * radius, sin(a) * radius * 0.48)
		var w := Vector2(cos(b) * radius, sin(b) * radius * 0.48)
		var down := Vector2(0, height)
		v.draw_colored_polygon(PackedVector2Array([u, w, w + down, u + down]), Color("315c72").darkened(k * 0.013))
		v.draw_line(u, w, p.wall, 3)
		v.draw_line(u + down, w + down, p.wall.darkened(0.2), 3)
		v.draw_line(u, u + down, Color("b7af95"), 1.5)
		if k % 3 == 0:
			v.draw_line(u + Vector2(2, 5), u + Vector2(2, height - 4), Color("edc679"), 2)
	v.draw_colored_polygon(rim, p.roof_color)
	v.draw_polyline(rim, p.wall.lightened(0.2), 2)
	v.draw_set_transform_matrix(Transform2D.IDENTITY)


## 크레인 다리 한 쌍(같은 x) 사이: 아래 연결 보, 위 보 밑 무릎 버팀(다리 쪽 사선), 다리 안쪽 트러스
static func brace(v: BuildingView, p: BuildingModel.Piece) -> void:
	var r := p.rect
	var x := r.get_center().x
	var a := Vector2(x, r.position.y - 6.0)
	var b := Vector2(x, r.end.y + 6.0)
	var steel := p.wall.darkened(0.06)
	var length := a.distance_to(b)
	v.draw_line(_at(a, p.h0 + 26.0), _at(b, p.h0 + 26.0), steel.darkened(0.12), 5.0)
	# 다리 한 쌍 위를 잇는 가로보 (옆면과 윗면)
	v.draw_colored_polygon(IsoView.wall(a, b, p.h1 - 10.0, p.h1), steel.darkened(0.18))
	v.draw_line(_at(a, p.h1), _at(b, p.h1), steel.lightened(0.15), 2.0)
	var knee := minf(70.0, length * 0.24)
	for end in [[a, Vector2(0, 1)], [b, Vector2(0, -1)]]:
		var foot: Vector2 = end[0]
		var dir: Vector2 = end[1]
		v.draw_line(_at(foot, p.h1 - 52.0), _at(foot + dir * knee, p.h1), steel, 4.0)
		v.draw_line(_at(foot, p.h1 - 30.0), _at(foot + dir * knee * 0.55, p.h1), steel.lightened(0.08), 2.4)
		# 다리 몸통 트러스 (지그재그)
		var n := 8
		for k in n:
			var z0 := lerpf(p.h0 + 26.0, p.h1, float(k) / n)
			var z1 := lerpf(p.h0 + 26.0, p.h1, float(k + 1) / n)
			var side := 7.0 if k % 2 == 0 else -1.0
			v.draw_line(_at(foot + dir * 7.0, z0), _at(foot + dir * side, z1), steel.darkened(0.25), 1.0)


static func dish(v: BuildingView, p: BuildingModel.Piece) -> void:
	var c := p.rect.get_center()
	var s := p.rect.size.x / 30.0
	v.draw_line(_at(c, p.h0), _at(c, p.h1 - 6 * s), Color("6b747b"), 4 * s)
	v.draw_set_transform_matrix(IsoView.screen_frame(c, p.h1))
	var points := PackedVector2Array()
	for k in 33:
		var a := TAU * k / 32.0
		points.append(Vector2(cos(a) * 17, sin(a) * 23) * s)
	v.draw_colored_polygon(points, Color("d2d1c7"))
	v.draw_polyline(points, Color("737f86"), 2)
	v.draw_line(Vector2(-12, 12) * s, Vector2(7, -12) * s, Color("5f6d79"), 2)
	v.draw_circle(Vector2(7, -12) * s, 3 * s, Color("a4b5ba"))
	v.draw_set_transform_matrix(Transform2D.IDENTITY)


## 타워 꼭대기 송신 안테나: 위로 가늘어지는 빨강·흰 띠, 중간 작은 발판, 끝에 항공등
static func antenna(v: BuildingView, p: BuildingModel.Piece) -> void:
	var c := p.rect.get_center()
	var n := 10
	for k in n:
		var f0 := float(k) / n
		var f1 := float(k + 1) / n
		var w := lerpf(9.0, 2.0, f0)
		var col := RED if k % 2 == 0 else WHITE
		v.draw_line(_at(c, lerpf(p.h0, p.h1, f0)), _at(c, lerpf(p.h0, p.h1, f1)), col, w)
		v.draw_line(_at(c, lerpf(p.h0, p.h1, f0)) + Vector2(w * 0.3, 0), _at(c, lerpf(p.h0, p.h1, f1)) + Vector2(w * 0.3, 0), col.darkened(0.25), w * 0.4)
	for f in [0.22, 0.5]:
		var at := _at(c, lerpf(p.h0, p.h1, f))
		v.draw_colored_polygon(BuildingView._ellipse(at, 9.0, 4.0), Color("8d9296"))
		v.draw_colored_polygon(BuildingView._ellipse(at - Vector2(0, 1.5), 8.0, 3.2), Color("c9ccce"))
	var tip := _at(c, p.h1)
	v.draw_circle(tip, 7.0, Color(1.0, 0.25, 0.15, 0.25))
	v.draw_circle(tip, 2.6, p.roof_color)


## 방송국 철탑: 네 다리가 위로 좁아지고, 칸마다 빨강·흰 번갈아, X 버팀, 중간 접시
static func lattice(v: BuildingView, p: BuildingModel.Piece) -> void:
	var r := p.rect
	var c := r.get_center()
	var legs := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var n := 9
	var prev: Array = []
	for k in n + 1:
		var f := float(k) / n
		var shrink := lerpf(1.0, 0.18, f)
		var ring: Array = []
		for q: Vector2 in legs:
			ring.append(c + (q - c) * shrink + IsoView.lift(lerpf(p.h0, p.h1, f)))
		if k > 0:
			var col := RED if k % 2 == 1 else WHITE
			# 뒤 다리(북서)부터, 앞 다리(남동)는 나중에
			for i in [0, 1, 3, 2]:
				v.draw_line(prev[i], ring[i], col.darkened(0.15 if i != 2 else 0.0), 2.2 if i == 2 else 1.6)
			for pair in [[3, 2], [2, 1]]:
				v.draw_line(prev[pair[0]], ring[pair[1]], col.lightened(0.05), 1.1)
				v.draw_line(prev[pair[1]], ring[pair[0]], col.darkened(0.1), 1.1)
		v.draw_polyline(PackedVector2Array([ring[3], ring[2], ring[1]]), RED.darkened(0.1), 1.2)
		prev = ring
	var tip := c + IsoView.lift(p.h1)
	v.draw_line(tip, tip + IsoView.lift(18.0), WHITE, 1.6)
	for f in [0.5, 1.0]:
		var at := c + IsoView.lift(lerpf(p.h0, p.h1 + 18.0, f))
		v.draw_circle(at, 6.5, Color(1.0, 0.2, 0.15, 0.24))
		v.draw_circle(at, 2.4, p.roof_color)
	for k in 3:
		var f := 0.3 + k * 0.17
		var g: Vector2 = c + (legs[2 if k != 1 else 1] - c) * lerpf(1.0, 0.18, f)
		v.draw_set_transform_matrix(IsoView.screen_frame(g, lerpf(p.h0, p.h1, f)))
		v.draw_line(Vector2.ZERO, Vector2(6, -1), RED, 1.2)
		v.draw_colored_polygon(BuildingView._ellipse(Vector2(8, -1), 4.0, 8.0), Color(0.92, 0.92, 0.9))
		v.draw_colored_polygon(BuildingView._ellipse(Vector2(9, -1), 2.3, 5.6), Color(0.7, 0.72, 0.72))
		v.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 노랑·검정 사선 띠 (바닥 선분 a→b, 높이 h0~h1)
static func _hazard_band(v: BuildingView, a: Vector2, b: Vector2, h0: float, h1: float) -> void:
	var length := a.distance_to(b)
	var t := 0.0
	var k := 0
	while t < length:
		var t1 := minf(t + 8.0, length)
		v.draw_colored_polygon(IsoView.wall(a.lerp(b, t / length), a.lerp(b, t1 / length), h0, h1), HAZARD if k % 2 == 0 else Color("1d1d1f"))
		t = t1
		k += 1


## 승강장 지붕: 골판 지붕면과 앞·옆 가장자리 노랑·검정 띠, 밑면 조명
static func canopy(v: BuildingView, p: BuildingModel.Piece) -> void:
	var r := p.rect
	var top := v._corners(r, p.h1)
	v.draw_colored_polygon(top, p.roof_color)
	var along_y := r.size.y > r.size.x
	var t := 6.0
	var length := r.size.y if along_y else r.size.x
	while t < length:
		var a := Vector2(r.position.x, r.position.y + t) if along_y else Vector2(r.position.x + t, r.position.y)
		var b := Vector2(r.end.x, r.position.y + t) if along_y else Vector2(r.position.x + t, r.end.y)
		v.draw_line(_at(a, p.h1), _at(b, p.h1), p.roof_color.darkened(0.18), 1.0)
		t += 10.0
	_hazard_band(v, Vector2(r.position.x, r.end.y), r.end, p.h0, p.h1)
	_hazard_band(v, Vector2(r.end.x, r.position.y), r.end, p.h0, p.h1)
	top.append(top[0])
	v.draw_polyline(top, p.roof_color.lightened(0.25), 1.5)
	# 밑에 매단 조명 (앞 가장자리 아래)
	for k in 3:
		var at := Vector2(lerpf(r.position.x + 10.0, r.end.x - 10.0, k / 2.0), r.end.y - 4.0)
		v.draw_circle(_at(at, p.h0 - 1.0), 2.0, Color(1.0, 0.92, 0.7))


## 좌판 천막: 네 귀 장대와 줄무늬 천, 앞으로 살짝 숙인다
static func tarp(v: BuildingView, p: BuildingModel.Piece) -> void:
	var r := p.rect
	var nw := r.position
	var ne := Vector2(r.end.x, r.position.y)
	var se := r.end
	var sw := Vector2(r.position.x, r.end.y)
	var pole := Color("4a4038")
	var drop := 5.0
	for q in [nw, ne, sw]:
		v.draw_line(_at(q, 0.0), _at(q, p.h1 - (drop if q.y > nw.y else 0.0)), pole, 1.4)
	var along_x := r.size.x >= r.size.y
	var n := 6
	for k in n:
		var f0 := float(k) / n
		var f1 := float(k + 1) / n
		var quad: PackedVector2Array
		if along_x:
			quad = PackedVector2Array([_at(nw.lerp(ne, f0), p.h1), _at(nw.lerp(ne, f1), p.h1), _at(sw.lerp(se, f1), p.h1 - drop), _at(sw.lerp(se, f0), p.h1 - drop)])
		else:
			quad = PackedVector2Array([_at(nw.lerp(sw, f0), p.h1 - drop * f0), _at(nw.lerp(sw, f1), p.h1 - drop * f1), _at(ne.lerp(se, f1), p.h1 - drop * f1), _at(ne.lerp(se, f0), p.h1 - drop * f0)])
		v.draw_colored_polygon(quad, p.wall if k % 2 == 0 else WHITE.darkened(0.04))
	# 앞 자락
	v.draw_colored_polygon(PackedVector2Array([_at(sw, p.h1 - drop), _at(se, p.h1 - drop), _at(se, p.h1 - drop - 3.0), _at(sw, p.h1 - drop - 3.0)]), p.roof_color)
	v.draw_line(_at(se, 0.0), _at(se, p.h1 - drop), pole, 1.4)


## 좌판 위 물건: 나무 판에 과일·채소 무더기
static func produce(v: BuildingView, p: BuildingModel.Piece) -> void:
	var r := p.rect
	v.draw_colored_polygon(v._corners(r, p.h1), p.wall.lightened(0.15))
	var goods := [Color("e0402e"), Color("f2b33a"), Color("6ea33f"), Color("8a3b8f"), Color("f07a2a"), Color("d9d16a")]
	var y := r.position.y + 3.5
	var row := 0
	while y < r.end.y - 2.0:
		var x := r.position.x + 3.5
		while x < r.end.x - 2.0:
			var col: Color = goods[posmod(p.seed + int((x - r.position.x) / 8.0) + row * 2, goods.size())]
			var at := _at(Vector2(x, y), p.h1 + 1.5)
			v.draw_circle(at, 2.1, col)
			v.draw_circle(at - Vector2(0.6, 0.8), 0.8, col.lightened(0.4))
			x += 4.5
		y += 4.5
		row += 1


## 골목을 가로지르는 전구 줄: 처진 전선에 알전구
static func lanterns(v: BuildingView, p: BuildingModel.Piece) -> void:
	var r := p.rect
	var along_x := r.size.x >= r.size.y
	var a := Vector2(r.position.x, r.get_center().y) if along_x else Vector2(r.get_center().x, r.position.y)
	var b := Vector2(r.end.x, r.get_center().y) if along_x else Vector2(r.get_center().x, r.end.y)
	var n := 12
	var line := PackedVector2Array()
	for k in n + 1:
		var f := float(k) / n
		line.append(_at(a.lerp(b, f), p.h1 - sin(f * PI) * 8.0))
	v.draw_polyline(line, Color("2b2b2b"), 1.0)
	for k in range(1, n):
		var col: Color = [Color(1.0, 0.85, 0.45), Color(1.0, 0.45, 0.35), Color(1.0, 0.95, 0.75)][k % 3]
		v.draw_circle(line[k] + Vector2(0, 2.5), 4.0, Color(col, 0.22))
		v.draw_circle(line[k] + Vector2(0, 2.5), 1.6, col)


## 가로등·투광등: 기둥과 팔, 등 머리와 번짐
static func lamp_pole(v: BuildingView, p: BuildingModel.Piece) -> void:
	var c := p.rect.get_center()
	v.draw_line(_at(c, 0.0), _at(c, p.h1), p.wall, 2.4)
	var head := _at(c, p.h1) + Vector2(7, 1)
	v.draw_line(_at(c, p.h1), head, p.wall, 1.8)
	v.draw_rect(Rect2(head - Vector2(3, 1.5), Vector2(7, 3)), p.wall.lightened(0.15))
	v.draw_circle(head + Vector2(0.5, 2.5), 7.0, Color(1.0, 0.92, 0.65, 0.2))
	v.draw_circle(head + Vector2(0.5, 2.0), 2.0, Color(1.0, 0.95, 0.8))


## 크레인 줄과 스프레더 (매달린 컨테이너는 on_top으로 뒤에 그린다)
static func hoist(v: BuildingView, p: BuildingModel.Piece) -> void:
	var c := p.rect.get_center()
	for dx in [-12.0, 12.0]:
		v.draw_line(_at(c + Vector2(dx, -4), p.h1), _at(c + Vector2(dx * 1.6, -6), p.h0), Color("2a2c2e"), 1.0)
		v.draw_line(_at(c + Vector2(dx, 4), p.h1), _at(c + Vector2(dx * 1.6, 6), p.h0), Color("2a2c2e"), 1.0)
	v.draw_line(_at(c - Vector2(30, 0), p.h0), _at(c + Vector2(30, 0), p.h0), LandmarkBuilding.YELLOW.darkened(0.1), 3.0)


## 팔각정: 붉은 기둥 넷, 낮은 난간(남쪽 가운데 입구), 단청 띠, 한옥 지붕. 밑으로 지나간다
static func pavilion(v: BuildingView, p: BuildingModel.Piece) -> void:
	var r := p.rect
	var posts := [r.position + Vector2(3, 3), Vector2(r.end.x - 3, r.position.y + 3), Vector2(r.position.x + 3, r.end.y - 3), r.end - Vector2(3, 3)]
	for k in 3:
		v.draw_line(_at(posts[k], 0.0), _at(posts[k], p.h1), p.wall.darkened(0.15), 4.0)
	var rail := Color("6b2a20")
	var inner := r.grow(-3.0)
	var corners := [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		if k == 2:
			# 남쪽 난간 가운데는 입구
			v.draw_line(_at(a, 7.0), _at(a.lerp(b, 0.35), 7.0), rail, 1.6)
			v.draw_line(_at(a.lerp(b, 0.65), 7.0), _at(b, 7.0), rail, 1.6)
		else:
			v.draw_line(_at(a, 7.0), _at(b, 7.0), rail, 1.6)
	v.draw_line(_at(posts[3], 0.0), _at(posts[3], p.h1), p.wall, 4.0)
	var top := BuildingModel._box(r, p.h1 - 5.0, p.h1, p.accent, &"hanok", p.roof_color)
	top.rise = p.rise
	top.eave = p.eave
	v.draw_colored_polygon(IsoView.wall(Vector2(r.position.x, r.end.y), r.end, top.h0, top.h1), p.accent)
	v.draw_colored_polygon(IsoView.wall(Vector2(r.end.x, r.position.y), r.end, top.h0, top.h1), p.accent.darkened(0.15))
	for k in 6:
		var at := Vector2(lerpf(r.position.x + 4, r.end.x - 4, k / 5.0), r.end.y)
		v.draw_circle(_at(at, top.h0 + 2.5), 1.2, Color("e0b52a"))
	v._hip(top, true)
