class_name PersonDrawer
## 사람(플레이어·보행자)을 위에서 본 모습으로 그린다. 위쪽(-y)이 정면.

const SKIN := Color(0.93, 0.78, 0.64)


static func draw(ci: CanvasItem, facing: float, phase: float, shirt: Color, pants: Color,
		hair: Color, knocked := false, size := 1.0) -> void:
	ci.draw_set_transform(Vector2.ZERO, facing, Vector2(size, size))
	if knocked:
		# 바닥에 엎어진 모습: 몸이 진행 방향으로 길게 눕는다
		ci.draw_rect(Rect2(-5, -10, 12, 22), Color(0, 0, 0, 0.3))
		ci.draw_rect(Rect2(-5, -4, 10, 9), shirt)
		ci.draw_rect(Rect2(-4.5, 5, 4, 7), pants)
		ci.draw_rect(Rect2(0.5, 5, 4, 7), pants)
		ci.draw_circle(Vector2(0, -7), 3.6, hair)
		ci.draw_circle(Vector2(-7, -3), 1.6, SKIN)
		ci.draw_circle(Vector2(7, -1), 1.6, SKIN)
	else:
		var swing := sin(phase) * 3.0
		ci.draw_circle(Vector2(2, 3), 7.0, Color(0, 0, 0, 0.3))
		ci.draw_rect(Rect2(-4.5, -2 + swing, 3, 5), pants.darkened(0.3))
		ci.draw_rect(Rect2(1.5, -2 - swing, 3, 5), pants.darkened(0.3))
		ci.draw_rect(Rect2(-5, -3, 10, 6), shirt)
		ci.draw_circle(Vector2(-5, 0), 3.0, shirt)
		ci.draw_circle(Vector2(5, 0), 3.0, shirt)
		ci.draw_circle(Vector2(-7, -swing), 1.6, SKIN)
		ci.draw_circle(Vector2(7, swing), 1.6, SKIN)
		ci.draw_circle(Vector2(0, 0.5), 3.6, hair)
		ci.draw_circle(Vector2(0, -1.8), 2.0, SKIN)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 쓰러진 사람 밑에 번진 핏자국
static func draw_blood(ci: CanvasItem, facing: float) -> void:
	ci.draw_set_transform(Vector2.ZERO, facing, Vector2.ONE)
	ci.draw_circle(Vector2(0, -2), 11.0, Color(0.45, 0.02, 0.04, 0.75))
	ci.draw_circle(Vector2(5, 6), 7.0, Color(0.45, 0.02, 0.04, 0.75))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 2.5D: 서 있는 사람을 화면 기준으로 세워 그린다 (발이 노드 원점). 넘어진 사람은 draw()로 바닥에 눕힌다.
## 화면 왼쪽으로 가면 좌우를 뒤집고, 화면 안쪽으로 가면 뒷모습(머리카락)을 보인다.
static func draw_standing(ci: CanvasItem, facing: float, phase: float, shirt: Color, pants: Color,
		hair: Color, size := 1.0, weapon: WeaponType = null) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_circle(Vector2.ZERO, 6.5 * size, Color(0, 0, 0, 0.32))
	var dir := IsoView.to_screen_dir(Vector2.UP.rotated(facing))
	var flip := -1.0 if dir.x < 0.0 else 1.0
	var back := dir.y < -0.05
	ci.draw_set_transform_matrix(IsoView.screen_frame().scaled_local(Vector2(size * flip, size)))
	var stride := sin(phase) * 3.0
	# 다리
	ci.draw_line(Vector2(-2, -10), Vector2(-2 - stride * 0.7, 0), pants.darkened(0.25), 3.0)
	ci.draw_line(Vector2(2, -10), Vector2(2 + stride * 0.7, 0), pants, 3.0)
	# 몸통과 팔
	ci.draw_line(Vector2(-4.5, -19), Vector2(-5 + stride * 0.6, -11), shirt.darkened(0.3), 2.6)
	ci.draw_rect(Rect2(-4.5, -21, 9, 12), shirt)
	ci.draw_rect(Rect2(-4.5, -21, 9, 2), shirt.lightened(0.15))
	ci.draw_line(Vector2(4.5, -19), Vector2(5 - stride * 0.6, -11), shirt.darkened(0.1), 2.6)
	ci.draw_circle(Vector2(5 - stride * 0.6, -10.5), 1.4, SKIN)
	if weapon and not weapon.melee:
		ci.draw_rect(Rect2(4.5, -13 - weapon.slot * 0.5, 7 + weapon.slot, 2.5), Color(0.1, 0.1, 0.12))
	# 머리
	ci.draw_circle(Vector2(0, -25), 4.2, SKIN)
	if back:
		ci.draw_circle(Vector2(0, -25.4), 4.2, hair)
	else:
		ci.draw_arc(Vector2(0, -25), 4.0, PI * 0.95, TAU * 0.98, 10, hair, 3.0)
		ci.draw_circle(Vector2(2.2, -25), 0.8, Color(0.1, 0.08, 0.08))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 2.5D: 머리 위 말풍선 (화면 기준)
static func draw_speech(ci: CanvasItem, text: String, size := 1.0) -> void:
	var font := ThemeDB.fallback_font
	ci.draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, IsoView.PERSON_HEIGHT * size + 8.0))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12.0
	var box := Rect2(Vector2(-w * 0.5, -24), Vector2(w, 18))
	ci.draw_rect(box, Color(1, 1, 1, 0.92))
	ci.draw_rect(box, Color(0, 0, 0, 0.6), false, 1.0)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-4, -6), Vector2(4, -6), Vector2(0, 0)]), Color(1, 1, 1, 0.92))
	ci.draw_string(font, Vector2(box.position.x, box.end.y - 5), text, HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(0.1, 0.1, 0.12))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
