class_name WorkZone
extends Node2D
## 도로 공사 현장 장식 (City.work_site): 라바콘 줄·"공사중" 표지판·흙더미. 그림만 — 충돌은 없다 (막힌 차선은 세워 둔 중장비가 막는다).
## 라바콘·표지판은 서 있는 것이라 하나씩 자기 깊이(IsoView.z_of)로 그린다. 흙더미는 굴삭기가 퍼 갈 수 있는 자리다.

const CONE := Color(0.98, 0.45, 0.1)
const STRIPE := Color(0.95, 0.95, 0.92)
const DIRT := Color(0.47, 0.36, 0.24)

var _sign: Node2D
var _iso := true


## 공사 현장 정보로 장식 노드들을 만든다
static func build(parent: Node, site: Dictionary) -> WorkZone:
	var zone := WorkZone.new()
	parent.add_child(zone)
	for c: Vector2 in site.cones:
		zone._piece(c, _draw_cone)
	zone._sign = zone._piece(site.sign, _draw_sign)
	zone._piece(site.pile, _draw_pile, true)
	return zone


func _piece(at: Vector2, painter: Callable, ground := false) -> Node2D:
	var n := Node2D.new()
	n.position = at
	n.z_as_relative = false
	n.z_index = 60 if ground else IsoView.z_of(at)
	n.draw.connect(func(): painter.call(n))
	add_child(n)
	return n


## 라바콘: 바닥 받침 + 원뿔 + 흰 띠 둘 (화면 기준으로 세워 그린다)
static func _draw_cone(n: Node2D) -> void:
	if IsoView.enabled:
		n.draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, IsoView.ground(n.position)))
	n.draw_rect(Rect2(-6, -2, 12, 3), Color(0.2, 0.2, 0.2))
	n.draw_colored_polygon(PackedVector2Array([Vector2(-5, -1), Vector2(5, -1), Vector2(1.2, -17), Vector2(-1.2, -17)]), CONE)
	n.draw_colored_polygon(PackedVector2Array([Vector2(-3.8, -6), Vector2(3.8, -6), Vector2(3.1, -9), Vector2(-3.1, -9)]), STRIPE)
	n.draw_colored_polygon(PackedVector2Array([Vector2(-2.6, -11), Vector2(2.6, -11), Vector2(2.0, -13.5), Vector2(-2.0, -13.5)]), STRIPE)
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## "공사중" 표지판: 다리 둘 + 노랑·검정 빗금 테두리 판 + 글자 + 깜빡이는 경고등
static func _draw_sign(n: Node2D) -> void:
	if IsoView.enabled:
		n.draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, IsoView.ground(n.position)))
	for x in [-14.0, 14.0]:
		n.draw_rect(Rect2(x - 1.0, -22, 2, 22), Color(0.35, 0.35, 0.36))
	n.draw_rect(Rect2(-22, -40, 44, 20), Color(0.98, 0.78, 0.1))
	for k in 6:
		var x0 := -22.0 + k * 8.0
		n.draw_colored_polygon(PackedVector2Array([Vector2(x0, -20), Vector2(x0 + 4, -20), Vector2(x0 + 8, -24), Vector2(x0 + 4, -24)]), Color(0.1, 0.1, 0.1))
	n.draw_string(ThemeDB.fallback_font, Vector2(-22, -26), "공사중", HORIZONTAL_ALIGNMENT_CENTER, 44, 11, Color(0.1, 0.1, 0.1))
	var on := (Time.get_ticks_msec() / 500) % 2 == 0
	n.draw_circle(Vector2(0, -44), 3.0, Color(1.0, 0.6, 0.1) if on else Color(0.45, 0.25, 0.08))
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 흙더미: 바닥에 겹친 갈색 타원 몇 겹 (높이는 화면 위로 조금씩)
static func _draw_pile(n: Node2D) -> void:
	for k in 4:
		var r := 34.0 - k * 7.0
		var lift := IsoView.lift(k * 3.0) if IsoView.enabled else Vector2.ZERO
		FireFx.circle(n, lift, r, DIRT.lightened(k * 0.06))
	for k in 6:
		var a := k * 1.7
		n.draw_circle(Vector2.RIGHT.rotated(a) * (12.0 + k * 3.0), 2.0, DIRT.darkened(0.3))


func _process(_delta: float) -> void:
	_sign.queue_redraw()   # 경고등 깜빡임
	if _iso != IsoView.enabled:   # 위에서 보기(F9)로 바뀌면 다시 그린다
		_iso = IsoView.enabled
		for c in get_children():
			(c as Node2D).queue_redraw()
