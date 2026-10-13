class_name PersonDrawer
## 사람(플레이어·보행자)을 위에서 본 모습으로 그린다. 위쪽(-y)이 정면.

const SKIN := Color(0.93, 0.78, 0.64)


## 다리 위에 선 사람은 그 높이만큼 올려 그린다 (2.5D)
static func _ground(ci: CanvasItem) -> float:
	return IsoView.ground((ci as Node2D).global_position) if ci is Node2D else 0.0


static func _base(ci: CanvasItem) -> Vector2:
	return IsoView.lift(_ground(ci))


static func draw(ci: CanvasItem, facing: float, phase: float, shirt: Color, pants: Color,
		hair: Color, knocked := false, size := 1.0, look: NpcType = null, seed := 0) -> void:
	ci.draw_set_transform(_base(ci), facing, Vector2(size, size))
	# 위에서 보면 머리 꼭대기만 보인다: 모자·복면을 쓰면 그 색
	if look and (look.face == &"balaclava" or (look.hat != &"" and _has(seed, 0, look.hat_chance))):
		hair = look.hat_color
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
	ci.draw_set_transform(_base(ci), facing, Vector2.ONE)
	ci.draw_circle(Vector2(0, -2), 11.0, Color(0.45, 0.02, 0.04, 0.75))
	ci.draw_circle(Vector2(5, 6), 7.0, Color(0.45, 0.02, 0.04, 0.75))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 2.5D: 서 있는 사람을 화면 기준으로 세워 그린다 (발이 노드 원점). 넘어진 사람은 draw()로 바닥에 눕힌다.
## 화면 왼쪽으로 가면 좌우를 뒤집고, 화면 안쪽으로 가면 뒷모습(머리카락)을 보인다.
## look(NpcType)이 있으면 그 종의 옷·모자·얼굴·든 것을 그린다 (docs/02). seed는 사람마다 다른 값 — 모자·소지품 유무를 정한다.
## 앞모습에서 몸의 앞쪽은 +x다 (눈·모자 챙·넥타이가 +x 쪽).
static func draw_standing(ci: CanvasItem, facing: float, phase: float, shirt: Color, pants: Color,
		hair: Color, size := 1.0, weapon: WeaponType = null, look: NpcType = null, seed := 0) -> void:
	var g := _ground(ci)
	ci.draw_set_transform(IsoView.lift(g), 0.0, Vector2.ONE)
	ci.draw_circle(Vector2.ZERO, 6.5 * size, Color(0, 0, 0, 0.32))
	var dir := IsoView.to_screen_dir(Vector2.UP.rotated(facing))
	var flip := -1.0 if dir.x < 0.0 else 1.0
	var back := dir.y < -0.05
	ci.draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, g).scaled_local(Vector2(size * flip, size)))
	var stride := sin(phase) * 3.0
	var outfit: StringName = look.outfit if look else &"plain"
	var trim: Color = look.trim_color if look else Color.WHITE
	var hat: StringName = look.hat if look and _has(seed, 0, look.hat_chance) else &""
	var prop: StringName = look.prop if look and _has(seed, 1, look.prop_chance) else &""
	var prop_color: Color = look.prop_color if look else Color.BLACK
	var sleeve := SKIN if outfit == &"tank" else shirt
	var hand := Vector2(5 - stride * 0.6, -10.5)
	# 등에 멘 것: 앞모습이면 몸 뒤에 먼저 그린다
	if not back:
		_carry_back(ci, prop, prop_color, false)
	# 다리
	var leg_b := Vector2(-2 - stride * 0.7, 0)
	var leg_f := Vector2(2 + stride * 0.7, 0)
	ci.draw_line(Vector2(-2, -10), leg_b, pants.darkened(0.25), 3.0)
	ci.draw_line(Vector2(2, -10), leg_f, pants, 3.0)
	match outfit:
		&"tracksuit":
			ci.draw_line(Vector2(3.3, -10), leg_f + Vector2(1.3, 0), trim, 0.8)
		&"stripes":
			for foot in [leg_b, leg_f]:
				var at: Vector2 = Vector2(foot.x * 0.6 + (-0.8 if foot == leg_b else 0.8), -4)
				ci.draw_line(at - Vector2(1.6, 0), at + Vector2(1.6, 0), trim, 1.4)
		&"camo":
			ci.draw_circle(Vector2(2 + stride * 0.35, -5), 1.0, pants.darkened(0.4))
			ci.draw_circle(Vector2(-2 - stride * 0.5, -3), 0.9, pants.lightened(0.2))
	# 뒤 팔
	ci.draw_line(Vector2(-4.5, -19), Vector2(-5 + stride * 0.6, -11), sleeve.darkened(0.3), 2.6)
	# 몸통
	_torso(ci, outfit, shirt, pants, trim, back)
	if back:
		_carry_back(ci, prop, prop_color, true)
	elif prop == &"handbag":
		ci.draw_line(Vector2(-2.2, -20.5), Vector2(1.5, -13), prop_color.darkened(0.4), 0.8)
		ci.draw_rect(Rect2(0, -14, 5, 4.2), prop_color)
	elif prop == &"guitar":
		ci.draw_line(Vector2(-5, -24), Vector2(2.6, -12), Color(0.25, 0.15, 0.08), 1.3)
		ci.draw_circle(Vector2(1.2, -13.6), 2.6, prop_color)
		ci.draw_circle(Vector2(3, -10.8), 3.4, prop_color)
		ci.draw_circle(Vector2(2.4, -12), 0.9, Color(0.1, 0.07, 0.05))
	# 앞 팔
	var elbow := Vector2(5 - stride * 0.6, -11)
	ci.draw_line(Vector2(4.5, -19), elbow, sleeve.darkened(0.1), 2.6)
	match outfit:
		&"tracksuit":
			ci.draw_line(Vector2(5.4, -19), elbow + Vector2(0.9, 0), trim, 0.7)
		&"stripes":
			ci.draw_circle(Vector2(4.5, -19).lerp(elbow, 0.55), 1.35, trim)
		&"tank":
			# 문신
			ci.draw_line(Vector2(4.5, -18.2).lerp(elbow, 0.15), Vector2(4.5, -19).lerp(elbow, 0.6), Color(0.18, 0.26, 0.36, 0.85), 1.3)
		&"hanbok":
			ci.draw_circle(elbow + Vector2(0, 0.3), 1.5, trim)
	ci.draw_circle(hand, 1.4, SKIN)
	_carry_hand(ci, prop, prop_color, hand, back)
	if weapon and not weapon.melee:
		ci.draw_rect(Rect2(4.5, -13 - weapon.slot * 0.5, 7 + weapon.slot, 2.5), Color(0.1, 0.1, 0.12))
	_head(ci, look, hat, hair, back)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## seed의 slot번째 바이트로 0~1 비율 p를 가른다 (rng를 쓰지 않는다 — 보행자 무작위 순서를 바꾸지 않게)
static func _has(seed: int, slot: int, p: float) -> bool:
	return p >= 1.0 or float((seed >> (slot * 8)) & 255) / 256.0 < p


## 몸통 (어깨 y -21 ~ 허리 y -9). 옷 모양마다 덧그린다
static func _torso(ci: CanvasItem, outfit: StringName, shirt: Color, pants: Color, trim: Color, back: bool) -> void:
	match outfit:
		&"coat", &"rags":
			# 허벅지까지 덮는 긴 겉옷
			ci.draw_rect(Rect2(-4.8, -21, 9.6, 15.5), shirt)
			ci.draw_rect(Rect2(-4.8, -21, 9.6, 2), shirt.lightened(0.12))
			if outfit == &"coat":
				ci.draw_rect(Rect2(-4.8, -14.5, 9.6, 1.2), shirt.darkened(0.3))
				if not back:
					ci.draw_line(Vector2(2.4, -21), Vector2(2.4, -5.5), shirt.darkened(0.25), 0.8)
					ci.draw_rect(Rect2(0.8, -21, 2.6, 2.4), trim)
			else:
				# 기운 자국과 해진 밑단
				ci.draw_rect(Rect2(-3.2, -17.5, 2.6, 2.6), shirt.darkened(0.3))
				ci.draw_rect(Rect2(1.2, -12.5, 2.2, 2.2), shirt.lightened(0.15))
				for i in 4:
					ci.draw_rect(Rect2(-4.8 + i * 2.6, -5.5, 1.4, 1.3 + (i % 2) * 0.8), shirt.darkened(0.1))
			return
		&"tank":
			ci.draw_rect(Rect2(-3.6, -20.5, 7.2, 11.5), shirt)
			ci.draw_rect(Rect2(-4.6, -21.2, 2, 2), SKIN)
			ci.draw_rect(Rect2(2.6, -21.2, 2, 2), SKIN)
			return
		&"dress":
			ci.draw_rect(Rect2(-4.2, -21, 8.4, 10), shirt)
			ci.draw_rect(Rect2(-5.2, -12, 10.4, 6.5), shirt.darkened(0.08))
			ci.draw_rect(Rect2(-4.2, -12.5, 8.4, 0.9), trim)
			return
		&"hanbok":
			# 짧은 저고리와 땅까지 닿는 치마
			ci.draw_rect(Rect2(-5.6, -15, 11.2, 15), pants)
			ci.draw_rect(Rect2(-6.2, -3.5, 12.4, 3.5), pants.darkened(0.12))
			ci.draw_rect(Rect2(-4.5, -21, 9, 6.5), shirt)
			if not back:
				ci.draw_line(Vector2(0.4, -21), Vector2(2.6, -17), Color(0.97, 0.97, 0.95), 1.2)
				ci.draw_line(Vector2(2.2, -16.5), Vector2(3.6, -12.5), trim, 1.3)
			return
	ci.draw_rect(Rect2(-4.5, -21, 9, 12), shirt)
	ci.draw_rect(Rect2(-4.5, -21, 9, 2), shirt.lightened(0.15))
	match outfit:
		&"jacket":
			if not back:
				ci.draw_rect(Rect2(1, -20.5, 2.6, 10.5), trim)
		&"suit":
			if not back:
				ci.draw_rect(Rect2(0.8, -21, 3, 5), Color(0.95, 0.95, 0.94))
				ci.draw_line(Vector2(2.3, -20.2), Vector2(2.3, -13), trim, 1.4)
		&"tracksuit":
			ci.draw_line(Vector2(-4.1, -21), Vector2(-4.1, -9), trim, 0.8)
			if not back:
				ci.draw_line(Vector2(2.2, -21), Vector2(2.2, -9), trim.darkened(0.3), 0.6)
		&"vest":
			ci.draw_rect(Rect2(-4.7, -20.5, 9.4, 10.5), trim)
			if not back:
				ci.draw_line(Vector2(2, -20.5), Vector2(2, -10), trim.darkened(0.3), 0.8)
			if trim.get_luminance() > 0.5:
				ci.draw_rect(Rect2(-4.7, -15.6, 9.4, 1.3), Color(0.92, 0.92, 0.9))
			else:
				ci.draw_rect(Rect2(-3, -18.5, 4, 3), trim.lightened(0.12))
		&"stripes":
			ci.draw_rect(Rect2(-4.5, -16, 9, 1.6), trim)
			ci.draw_rect(Rect2(-4.5, -12.2, 9, 1.2), trim)
		&"camo":
			ci.draw_rect(Rect2(-3, -19, 3, 2), shirt.darkened(0.35))
			ci.draw_rect(Rect2(1, -15.5, 3, 2.5), shirt.lightened(0.18))
			ci.draw_rect(Rect2(-2, -12.5, 2.5, 2), shirt.darkened(0.4))
			ci.draw_rect(Rect2(2, -20.5, 2, 1.5), pants.darkened(0.2))
		&"apron":
			if back:
				ci.draw_rect(Rect2(-4.5, -15, 9, 0.9), trim)
			else:
				ci.draw_rect(Rect2(-2.2, -17.5, 6.8, 11.5), trim)
				ci.draw_line(Vector2(-1.5, -17.5), Vector2(-0.5, -21), trim, 0.8)


## 등에 메는 것 (앞모습이면 몸 뒤, 뒷모습이면 몸 위)
static func _carry_back(ci: CanvasItem, prop: StringName, c: Color, back: bool) -> void:
	match prop:
		&"backpack":
			if back:
				ci.draw_rect(Rect2(-3.8, -20.5, 7.6, 9.5), c)
				ci.draw_rect(Rect2(-2.6, -15, 5.2, 3), c.darkened(0.25))
			else:
				ci.draw_rect(Rect2(-8, -20.5, 4, 9.5), c)
				ci.draw_line(Vector2(-3, -21), Vector2(-1.5, -13), c.darkened(0.3), 0.9)
		&"sack":
			ci.draw_circle(Vector2(-1.5, -20) if back else Vector2(-7, -19), 4.4, c)
			ci.draw_rect(Rect2(-2.5, -24.6, 2, 1.4) if back else Rect2(-6, -23.7, 2, 1.4), c.darkened(0.35))
		&"guitar":
			if back:
				ci.draw_rect(Rect2(-3, -25, 4.2, 15), c.darkened(0.45))
		&"box":
			if back:
				ci.draw_rect(Rect2(-4.5, -25, 9, 7.5), c)
				ci.draw_rect(Rect2(-4.5, -22, 9, 1.2), Color(0.95, 0.95, 0.9))


## 손에 드는 것 (hand = 앞 손 위치)
static func _carry_hand(ci: CanvasItem, prop: StringName, c: Color, hand: Vector2, back: bool) -> void:
	match prop:
		&"briefcase":
			ci.draw_rect(Rect2(hand.x - 2.4, hand.y + 0.6, 5.2, 4), c)
			ci.draw_rect(Rect2(hand.x - 0.8, hand.y - 0.2, 1.8, 0.9), c.darkened(0.4))
		&"cane":
			ci.draw_line(hand, Vector2(hand.x + 2.2, 0), c, 1.2)
		&"flyers":
			ci.draw_rect(Rect2(hand.x - 0.6, hand.y - 5, 3.8, 4.8), Color(0.97, 0.97, 0.94))
			ci.draw_line(Vector2(hand.x - 0.1, hand.y - 3.6), Vector2(hand.x + 2.7, hand.y - 3.6), c, 0.7)
		&"baton":
			ci.draw_line(hand, hand + Vector2(3.4, -7), c, 1.9)
			ci.draw_circle(hand + Vector2(3.4, -7), 1.3, c.lightened(0.4))
		&"box":
			if not back:
				ci.draw_rect(Rect2(hand.x - 4.5, hand.y - 6.5, 7, 6), c)
				ci.draw_rect(Rect2(hand.x - 4.5, hand.y - 4.2, 7, 1.1), Color(0.95, 0.95, 0.9))
		&"phone":
			ci.draw_rect(Rect2(hand.x - 0.6, hand.y - 3.6, 1.8, 3), Color(0.1, 0.1, 0.12))


## 머리·머리카락·얼굴·모자
static func _head(ci: CanvasItem, look: NpcType, hat: StringName, hair: Color, back: bool) -> void:
	var face: StringName = look.face if look else &""
	var hat_c: Color = look.hat_color if look else hair
	var eye := Color(0.1, 0.08, 0.08)
	if face == &"balaclava":
		# 복면: 머리 전체를 덮고 눈만 뚫렸다
		ci.draw_circle(Vector2(0, -25), 4.4, hat_c)
		if not back:
			ci.draw_rect(Rect2(0.6, -26, 3.6, 1.7), SKIN)
			ci.draw_circle(Vector2(2.3, -25.2), 0.7, eye)
		return
	if hat == &"hood":
		ci.draw_circle(Vector2(-0.4, -25.3), 4.9, hat_c)
		if not back:
			ci.draw_circle(Vector2(1.5, -24.7), 2.8, SKIN)
			ci.draw_circle(Vector2(2.4, -25.1), 0.75, eye)
		return
	if look and look.long_hair:
		ci.draw_rect(Rect2(-4.2, -25.5, 8.4, 8.5) if back else Rect2(-4.7, -26, 3.6, 8.5), hair)
	ci.draw_circle(Vector2(0, -25), 4.2, SKIN)
	if back:
		ci.draw_circle(Vector2(0, -25.4), 4.2, hair)
	else:
		ci.draw_arc(Vector2(0, -25), 4.0, PI * 0.95, TAU * 0.98, 10, hair, 3.0)
		ci.draw_circle(Vector2(2.2, -25), 0.8, eye)
		match face:
			&"sunglasses":
				ci.draw_rect(Rect2(0.3, -26, 4.3, 1.8), Color(0.04, 0.04, 0.05))
			&"goggles":
				ci.draw_rect(Rect2(0.1, -26.4, 4.6, 2.3), Color(0.08, 0.08, 0.1))
				ci.draw_rect(Rect2(1.2, -26, 3, 1.3), Color(0.35, 0.45, 0.5))
			&"beard":
				ci.draw_rect(Rect2(-0.6, -23.4, 4.6, 2.5), hair.lerp(Color(0.45, 0.43, 0.4), 0.3))
	var dark := hat_c.darkened(0.3)
	match hat:
		&"cap":
			ci.draw_rect(Rect2(-4.4, -29.8, 8.8, 3.6), hat_c)
			ci.draw_rect(Rect2(-3.4, -30.6, 6.8, 1), hat_c)
			if not back:
				ci.draw_rect(Rect2(2.4, -27, 4.8, 1.4), dark)
		&"flatcap":
			ci.draw_rect(Rect2(-4.7, -29.4, 9.4, 3), hat_c)
			ci.draw_rect(Rect2(-3.6, -30.2, 6.8, 0.9), hat_c)
			if not back:
				ci.draw_rect(Rect2(2.6, -27.2, 4.2, 1.2), dark)
		&"beanie":
			ci.draw_rect(Rect2(-4.4, -30.2, 8.8, 4.2), hat_c)
			ci.draw_rect(Rect2(-3.2, -31, 6.4, 1), hat_c)
			ci.draw_rect(Rect2(-4.6, -27.4, 9.2, 1.5), dark)
		&"police":
			ci.draw_rect(Rect2(-4.6, -31, 9.2, 4), hat_c)
			ci.draw_rect(Rect2(-5.5, -27.5, 11, 1.6), hat_c.darkened(0.45))
			if not back:
				ci.draw_rect(Rect2(1, -30.2, 1.8, 1.8), Color(0.95, 0.78, 0.25))
		&"helmet", &"fire_helmet":
			ci.draw_rect(Rect2(-4.8, -30.4, 9.6, 4.6), hat_c)
			ci.draw_rect(Rect2(-3.7, -31.4, 7.4, 1.1), hat_c)
			ci.draw_rect(Rect2(-4.8, -30.4, 9.6, 1.2), hat_c.lightened(0.2))
			if hat == &"fire_helmet":
				ci.draw_rect(Rect2(-6.2, -26.4, 12.4, 1.3), dark)
				if not back:
					ci.draw_rect(Rect2(0.8, -30, 2.4, 2.6), Color(0.95, 0.8, 0.25))
			else:
				ci.draw_rect(Rect2(-5.2, -27, 2.4, 3), dark)
		&"visor":
			ci.draw_rect(Rect2(-4.4, -28.2, 8.8, 1.7), hat_c)
			if not back:
				ci.draw_rect(Rect2(2.2, -27.4, 4.8, 1.3), dark)
	if look and look.prop == &"headphones":
		var c := look.prop_color
		ci.draw_arc(Vector2(0, -25.6), 4.9, PI, TAU, 10, c, 1.1)
		if back:
			ci.draw_circle(Vector2(-4.4, -25), 1.6, c)
			ci.draw_circle(Vector2(4.4, -25), 1.6, c)
		else:
			ci.draw_circle(Vector2(-0.8, -25), 2.0, c)


## 2.5D: 머리 위 말풍선 (화면 기준)
static func draw_speech(ci: CanvasItem, text: String, size := 1.0) -> void:
	var font := ThemeDB.fallback_font
	ci.draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, IsoView.PERSON_HEIGHT * size + 8.0 + _ground(ci)))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12.0
	var box := Rect2(Vector2(-w * 0.5, -24), Vector2(w, 18))
	ci.draw_rect(box, Color(1, 1, 1, 0.92))
	ci.draw_rect(box, Color(0, 0, 0, 0.6), false, 1.0)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-4, -6), Vector2(4, -6), Vector2(0, 0)]), Color(1, 1, 1, 0.92))
	ci.draw_string(font, Vector2(box.position.x, box.end.y - 5), text, HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(0.1, 0.1, 0.12))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
