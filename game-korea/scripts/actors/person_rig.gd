class_name PersonRig
## 관절 있는 사람. 골반·척추·목·머리, 어깨·팔꿈치·손목, 엉덩이·무릎·발목을 몸 기준 3차원 점으로 두고,
## 걷기 위상(phase)과 걸음새(gait: 0 서 있기 · 1 걷기 · 2 달리기)로 매번 자세를 계산한다. down이면 바닥에 눕는다.
## 점은 사람이 보는 방향(facing)으로 돌린 뒤 2.5D 화면에 찍는다 — 좌우 뒤집기가 아니라 8방향 모두 제 모습이 나온다.
## 몸 좌표: x 오른쪽, y 앞, z 위 (화면 px). 그리기는 IsoView.screen_frame 안에서 한다.
## 몸통·소지품은 상자(면마다 보이는지 따져 보이는 면만), 팔다리는 굵은 선이다.
## 옷·모자·얼굴·소지품은 NpcType 값을 읽는다 (설계도: 성인 NPC 12종 앞·뒤, docs/17).

const SKIN := PersonDrawer.SKIN
const SHOES := PersonDrawer.SHOES
const EYE := Color(0.1, 0.08, 0.08)
const GLOVE := Color("1d2227")
const SNEAKER := Color("dcdcd2")
const WORLD := 0.9          ## 몸 가로·앞뒤 1 → 월드 단위
const HIP_Z := 14.0
const HIP_W := 1.8
const THIGH := 7.0
const SHIN := 6.7
const WAIST_Z := 16.4
const SHOULDER_Z := 23.0
const SHOULDER_W := 4.3
const UPPER_ARM := 5.5
const FOREARM := 5.0
const HEAD_Z := 27.2
const HEAD_R := 2.9
## 보는 사람 쪽: 월드 (1, 1) 방향과 위로 0.78 (IsoView.BASIS로 같은 화면 점에 겹치는 방향)
const VIEW_Z := 0.78


## facing: 보는 방향(라디안, Vector2.UP 기준), phase: 걷기 위상, gait: 0 서 있기 ~ 1 걷기 ~ 2 달리기
## weapon: 손에 든 무기 (주인공), down: 쓰러짐(바닥에 누운 자세)
static func draw(ci: CanvasItem, facing: float, phase: float, gait: float, shirt: Color, pants: Color, hair: Color,
		size := 1.0, look: NpcType = null, seed := 0, weapon: WeaponType = null, down := false) -> void:
	if draw_parts(ci, facing, phase, gait, size, look, weapon, down):
		return
	if draw_sheet_frame(ci, facing, phase, gait, size, look, down):
		return
	var w := Wear.new(look, seed, shirt, pants, hair)
	var b := Body.new()
	b.setup(facing, size)
	b.pose(phase, gait, w.arms, w.slim, down)
	ci.draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, PersonDrawer._ground(ci)))
	_shadow(ci, b, down)
	var near := 1 if b.sees(b.rt) else -1            # 화면 쪽 옆 (오른쪽 +1)
	var front := b.sees(b.fw)                        # 앞섶·얼굴이 보인다
	if front:
		_carry_back(ci, b, w)
		_hair_behind(ci, b, w)
	_leg(ci, b, -near, w, true)
	_leg(ci, b, near, w, false)
	_arm(ci, b, -near, w, true, false)
	_carry_side(ci, b, w, -near, front)
	if not front:
		_arm(ci, b, -near, w, true, true)
		_arm(ci, b, near, w, false, true)
		_carry_front(ci, b, w)
	_torso(ci, b, w, front)
	if not front:
		_carry_back(ci, b, w)
	_carry_side(ci, b, w, near, front)
	_head(ci, b, w)
	if not front:
		_hair_behind(ci, b, w)
	_arm(ci, b, near, w, false, false)
	if front:
		_arm(ci, b, -near, w, true, true)
		_arm(ci, b, near, w, false, true)
		_carry_front(ci, b, w)
	if weapon and not weapon.melee:
		var hand := b.at("wrist_r")
		var tip := b.p(b.j["wrist_r"] + b.fw * (3.0 + weapon.slot))
		ci.draw_line(hand, tip, Color(0.1, 0.1, 0.12), 1.6 * size)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 옷차림: NpcType에서 한 번 읽어 둔다 (모자·소지품 유무는 seed로 — 보행자 rng를 더 뽑지 않는다)
class Wear:
	var shirt: Color
	var pants: Color
	var hair: Color
	var outfit: StringName = &"plain"
	var trim := Color.WHITE
	var hat: StringName = &""
	var hat_c: Color
	var face: StringName = &""
	var prop: StringName = &""
	var prop_c := Color.BLACK
	var long_hair := false
	var arms: StringName = &""       ## 팔 자세: carry 앞으로 들기 · rifle 총 · 비우면 흔들기
	var slim := false
	var sleeve: Color                ## 윗팔
	var fore: Color                  ## 아래팔 (걷어붙이면 살)
	var hand := SKIN
	var shoe := SHOES
	var boots := false
	var hem := 13.6                  ## 윗옷 아랫단 높이 (낮을수록 길다)

	func _init(look: NpcType, seed: int, p_shirt: Color, p_pants: Color, p_hair: Color) -> void:
		shirt = p_shirt
		pants = p_pants
		hair = p_hair
		hat_c = p_hair
		if look:
			outfit = look.outfit
			trim = look.trim_color
			hat = look.hat if PersonDrawer._has(seed, 0, look.hat_chance) else &""
			hat_c = look.hat_color
			face = look.face
			prop = look.prop if PersonDrawer._has(seed, 1, look.prop_chance) else &""
			prop_c = look.prop_color
			long_hair = look.long_hair
		slim = long_hair or hat == &"ponytail"
		sleeve = SKIN if outfit == &"tank" else shirt
		fore = SKIN if outfit in [&"tank", &"vest", &"apron"] else shirt.darkened(0.06)
		if outfit in [&"armor", &"tank", &"stripes"]:
			hand = GLOVE
		if prop in [&"delivery", &"box"]:
			arms = &"carry"
		elif prop == &"rifle":
			arms = &"rifle"
		boots = outfit in [&"armor", &"tank", &"stripes", &"camo"]
		if prop == &"delivery" or (outfit == &"jacket" and long_hair):
			shoe = SNEAKER
		elif boots:
			shoe = GLOVE
		match outfit:
			&"suit", &"pinstripe", &"jacket", &"stripes":
				hem = 12.8
			&"coat", &"rags":
				hem = 8.5
			&"plain", &"tank", &"tracksuit", &"camo", &"vest", &"armor", &"apron":
				hem = WAIST_Z


## 한 사람의 자세: 관절 점(몸 좌표)과 화면 찍기
class Body:
	var f := Vector2.UP            ## 앞 (월드)
	var r := Vector2.RIGHT         ## 오른쪽 (월드)
	var size := 1.0
	var j := {}                    ## 관절 이름 → Vector3 (몸 좌표)
	var up := Vector3(0, 0, 1)     ## 몸통 방향 (누우면 바뀐다)
	var rt := Vector3(1, 0, 0)
	var fw := Vector3(0, 1, 0)
	var view := Vector3.ZERO       ## 몸 좌표에서 보는 사람 쪽 — 면의 바깥 방향과 곱해 양수면 그 면이 보인다
	var down := false
	## 몸통 상자: 위·아래 가운데, 반폭, 반두께
	var t_top: Vector3
	var t_bot: Vector3
	var wt := 3.9
	var wb := 3.3
	var dt := 1.9
	var db := 1.7

	func setup(facing: float, s: float) -> void:
		f = Vector2.UP.rotated(facing)
		r = Vector2(-f.y, f.x)
		size = s
		view = Vector3(r.dot(Vector2.ONE) / PersonRig.WORLD, f.dot(Vector2.ONE) / PersonRig.WORLD, PersonRig.VIEW_Z)

	## 몸 좌표 → screen_frame 안 화면 좌표
	func p(v: Vector3) -> Vector2:
		var w := (r * v.x + f * v.y) * PersonRig.WORLD
		return (IsoView.BASIS.basis_xform(w) + Vector2(0, -v.z)) * size

	func at(name: String) -> Vector2:
		return p(j[name])

	func sees(n: Vector3) -> bool:
		return n.dot(view) > 0.0

	## 몸통 면 위의 점. face: 0 앞 · 1 뒤 · 2 오른쪽 · 3 왼쪽, u -1~1 (가로), v 0~1 (위→아래)
	func fp(face: int, u: float, v: float) -> Vector2:
		var a: Vector3
		var c: Vector3
		match face:
			0, 1:
				var s := 1.0 if face == 0 else -1.0
				a = t_top + rt * u * wt + fw * s * dt
				c = t_bot + rt * u * wb + fw * s * db
			_:
				var s := 1.0 if face == 2 else -1.0
				a = t_top + rt * s * wt + fw * u * dt
				c = t_bot + rt * s * wb + fw * u * db
		return p(a.lerp(c, v))

	func pose(phase: float, gait: float, arms: StringName, slim: bool, p_down: bool) -> void:
		down = p_down
		var walk := 0.0 if down else clampf(gait, 0.0, 1.0)
		var run := 0.0 if down else clampf(gait - 1.0, 0.0, 1.0)
		var amp := 0.42 * walk + 0.3 * run            # 허벅지 흔들림 (라디안)
		var flex := 0.55 * walk + 0.8 * run           # 앞으로 내딛을 때 무릎 굽힘
		var lean := 0.8 * walk + 1.8 * run            # 상체 앞으로 숙임 (몸 y)
		var breathe := 0.0 if down else sin(phase * 0.5) * 0.2 * (1.0 - walk)
		var sw := PersonRig.SHOULDER_W * (0.88 if slim else 1.0)
		for side in [-1, 1]:
			var ph: float = phase + (0.0 if side < 0 else PI)
			var a := amp * sin(ph)
			var k := flex * maxf(0.0, cos(ph))
			var tag := "l" if side < 0 else "r"
			var spread := 0.0 if not down else 0.9
			var hip := Vector3(side * PersonRig.HIP_W, 0.0, PersonRig.HIP_Z)
			var knee := hip + Vector3(side * spread, sin(a) * PersonRig.THIGH, -cos(a) * PersonRig.THIGH)
			var ankle := knee + Vector3(side * spread, sin(a - k) * PersonRig.SHIN, -cos(a - k) * PersonRig.SHIN)
			j["hip_" + tag] = hip
			j["knee_" + tag] = knee
			j["ankle_" + tag] = ankle
			j["toe_" + tag] = ankle + Vector3(side * 0.2, 2.1, 0.3 * sin(k))
			var shoulder := Vector3(side * sw, lean * 0.5, PersonRig.SHOULDER_Z + breathe)
			var elbow: Vector3
			var wrist: Vector3
			if down:
				# 쓰러지면 팔이 옆으로 벌어진다
				elbow = shoulder + Vector3(side * 3.6, 0.6, -4.1)
				wrist = elbow + Vector3(side * 3.0, 2.2, -2.9)
			elif arms == &"carry":
				# 상자를 배 앞에 받쳐 든다
				elbow = shoulder + Vector3(side * 0.4, 1.2, -5.3)
				wrist = elbow + Vector3(-side * 0.9, 4.4, 0.9)
			elif arms == &"rifle":
				# 총을 비스듬히 낮춰 든다: 오른손은 손잡이, 왼손은 앞 총열
				if side > 0:
					elbow = shoulder + Vector3(0.6, 0.4, -5.3)
					wrist = elbow + Vector3(-1.4, 3.4, 1.5)
				else:
					elbow = shoulder + Vector3(0.6, 2.6, -4.6)
					wrist = elbow + Vector3(2.6, 3.4, 0.9)
			else:
				# 팔은 같은 쪽 다리와 반대로 흔든다. 달릴수록 팔꿈치를 굽힌다
				var sw_a := -amp * 0.9 * sin(ph)
				var e := 0.2 + 0.35 * walk + 0.9 * run
				elbow = shoulder + Vector3(side * 0.5, sin(sw_a) * PersonRig.UPPER_ARM, -cos(sw_a) * PersonRig.UPPER_ARM)
				wrist = elbow + Vector3(side * 0.2, sin(sw_a + e) * PersonRig.FOREARM, -cos(sw_a + e) * PersonRig.FOREARM)
			j["shoulder_" + tag] = shoulder
			j["elbow_" + tag] = elbow
			j["wrist_" + tag] = wrist
		j["chest"] = Vector3(0.0, lean * 0.5, PersonRig.SHOULDER_Z + 0.6 + breathe)
		j["pelvis"] = Vector3(0.0, 0.0, PersonRig.HIP_Z + 0.4)
		j["neck"] = Vector3(0.0, lean * 0.6, PersonRig.SHOULDER_Z + 1.4 + breathe)
		j["head"] = Vector3(0.0, lean * 0.75, PersonRig.HEAD_Z + breathe)
		if down:
			# 누운 자세: 뒤로 눕히고(앞이 하늘) 머리를 보는 방향으로 — (x, y, z) → (-x, z - 골반, y + 등 두께)
			for key in j:
				var v: Vector3 = j[key]
				j[key] = Vector3(-v.x, v.z - PersonRig.HIP_Z, v.y + 1.9)
		else:
			# 디딘 발이 땅에 닿게 몸 전체를 올리고 내린다 (걸을 때 저절로 오르내림)
			var low := minf(j["ankle_l"].z, j["ankle_r"].z)
			var lift := 0.7 - low
			for key in j:
				j[key] += Vector3(0, 0, lift)
		up = (j["chest"] - j["pelvis"]).normalized()
		rt = j["shoulder_r"] - j["shoulder_l"]
		rt = (rt - up * rt.dot(up)).normalized()
		fw = up.cross(rt)
		wt = sw - 0.4
		wb = 3.0 if slim else 3.3
		dt = 1.7 if slim else 1.9
		t_top = j["chest"] + up * 0.2
		t_bot = j["pelvis"] + up * (PersonRig.WAIST_Z - PersonRig.HIP_Z - 0.4)

	## 몸 좌표 높이 h(서 있을 때 z)에 해당하는 몸통 축 위의 점
	func axis_at(h: float) -> Vector3:
		return j["pelvis"] + up * (h - PersonRig.HIP_Z - 0.4)


static func _shadow(ci: CanvasItem, b: Body, down: bool) -> void:
	var c := b.p(Vector3.ZERO) if not down else b.p(Vector3(0, 2.0, 0))
	var pts := PackedVector2Array()
	for k in 14:
		var a := k * TAU / 14.0
		if down:
			pts.append(b.p(Vector3(cos(a) * 6.5, 2.0 + sin(a) * 15.0, 0)))
		else:
			pts.append(c + Vector2(cos(a) * 6.5, sin(a) * 2.7) * b.size)
	ci.draw_colored_polygon(pts, Color(0, 0, 0, 0.3))


## 빛은 화면 왼쪽 위에서: 윗면은 밝게, 화면 오른쪽을 향한 면은 어둡게
static func _shade(b: Body, n: Vector3, c: Color) -> Color:
	if n.z > 0.7 and not b.down:
		return c.lightened(0.12)
	var d := b.p(n) - b.p(Vector3.ZERO)
	return c.darkened(0.2) if d.x > 0.3 * b.size else c


## 위·아래 단면이 사각형인 덩어리 (몸통·치마·조끼). 축은 몸통 방향을 따른다
static func _prism(ci: CanvasItem, b: Body, top: Vector3, bot: Vector3, wt: float, wb: float, dt: float, db: float,
		col: Color) -> void:
	var rt := b.rt
	var fw := b.fw
	var c := [top + rt * wt + fw * dt, top - rt * wt + fw * dt, top - rt * wt - fw * dt, top + rt * wt - fw * dt,
		bot + rt * wb + fw * db, bot - rt * wb + fw * db, bot - rt * wb - fw * db, bot + rt * wb - fw * db]
	var faces := [[fw, [0, 1, 5, 4]], [-fw, [2, 3, 7, 6]], [rt, [3, 0, 4, 7]], [-rt, [1, 2, 6, 5]], [b.up, [0, 1, 2, 3]]]
	for fc in faces:
		var n: Vector3 = fc[0]
		if not b.sees(n):
			continue
		var q := PackedVector2Array()
		for i: int in fc[1]:
			q.append(b.p(c[i]))
		ci.draw_primitive(q, PackedColorArray([_shade(b, n, col)]), PackedVector2Array())


## 상자 (소지품): 가운데 c, 반길이 축 ax·ay·az (몸 좌표)
static func _box(ci: CanvasItem, b: Body, c: Vector3, ax: Vector3, ay: Vector3, az: Vector3, col: Color) -> void:
	for axis in [ax, ay, az]:
		for s in [1.0, -1.0]:
			var n: Vector3 = axis * s
			if not b.sees(n):
				continue
			var u: Vector3 = ay if axis == ax else ax
			var v: Vector3 = az if axis != az else ay
			var o: Vector3 = c + n
			var q := PackedVector2Array([b.p(o - u - v), b.p(o + u - v), b.p(o + u + v), b.p(o - u + v)])
			ci.draw_primitive(q, PackedColorArray([_shade(b, n.normalized(), col)]), PackedVector2Array())


static func _quad(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	ci.draw_primitive(PackedVector2Array([a, b, c, d]), PackedColorArray([col]), PackedVector2Array())


## 몸통 면 위 작은 사각형 (u0~u1, v0~v1)
static func _patch(ci: CanvasItem, b: Body, face: int, u0: float, u1: float, v0: float, v1: float, col: Color) -> void:
	_quad(ci, b.fp(face, u0, v0), b.fp(face, u1, v0), b.fp(face, u1, v1), b.fp(face, u0, v1), col)


static func _leg(ci: CanvasItem, b: Body, side: int, w: Wear, far: bool) -> void:
	var t := "l" if side < 0 else "r"
	var s := b.size
	var col := w.pants.darkened(0.2) if far else w.pants
	var hip := b.at("hip_" + t)
	var knee := b.at("knee_" + t)
	var ankle := b.at("ankle_" + t)
	var thick := 2.7 if w.slim else 3.1
	ci.draw_line(hip, knee, col, thick * s)
	ci.draw_circle(knee, thick * 0.48 * s, col)
	ci.draw_line(knee, ankle, col.darkened(0.06), (thick - 0.4) * s)
	match w.outfit:
		&"stripes":
			# 방화복 바지 반사띠
			ci.draw_line(knee.lerp(ankle, 0.45), knee.lerp(ankle, 0.62), w.trim, (thick + 0.2) * s)
		&"armor":
			if w.hat == &"helmet":
				ci.draw_circle(knee, 1.5 * s, col.darkened(0.35))          # 무릎 보호대
			ci.draw_line(hip.lerp(knee, 0.35), hip.lerp(knee, 0.62), col.darkened(0.25), (thick + 0.3) * s)
		&"tank", &"camo":
			ci.draw_line(hip.lerp(knee, 0.4), hip.lerp(knee, 0.68), col.lightened(0.1), (thick + 0.3) * s)   # 건빵 주머니
	var shoe := w.shoe.darkened(0.15) if far else w.shoe
	if w.boots:
		ci.draw_line(knee.lerp(ankle, 0.6), ankle, shoe, (thick + 0.1) * s)
	ci.draw_line(ankle, b.at("toe_" + t), shoe, 2.3 * s)
	ci.draw_circle(ankle, 1.2 * s, shoe)


## 팔: 윗팔과 아래팔. 손이 몸 앞으로 나와 있으면 아래팔은 몸통 다음에 따로 그린다 (fore_pass)
static func _arm(ci: CanvasItem, b: Body, side: int, w: Wear, far: bool, fore_pass: bool) -> void:
	var t := "l" if side < 0 else "r"
	var s := b.size
	var wrist3: Vector3 = b.j["wrist_" + t]
	var chest: Vector3 = b.j["chest"]
	var forward: bool = (wrist3 - chest).dot(b.fw) > 1.6 and not b.down
	var sleeve := w.sleeve.darkened(0.2) if far else w.sleeve
	var fore := w.fore.darkened(0.2) if far else w.fore
	var shoulder := b.at("shoulder_" + t)
	var elbow := b.at("elbow_" + t)
	var wrist := b.at("wrist_" + t)
	var thick := 2.3 if w.slim else 2.6
	if not fore_pass:
		ci.draw_circle(shoulder, thick * 0.6 * s, sleeve)
		ci.draw_line(shoulder, elbow, sleeve, thick * s)
		if w.outfit == &"tank":
			# 문신
			ci.draw_line(shoulder.lerp(elbow, 0.25), shoulder.lerp(elbow, 0.8), Color(0.2, 0.28, 0.38, 0.8), 1.2 * s)
		elif w.outfit == &"vest" or w.outfit == &"apron":
			ci.draw_line(shoulder.lerp(elbow, 0.7), elbow, sleeve.lightened(0.12), (thick + 0.4) * s)   # 걷은 소매
		elif w.outfit == &"stripes":
			ci.draw_line(shoulder.lerp(elbow, 0.5), shoulder.lerp(elbow, 0.68), w.trim, (thick + 0.2) * s)
	if forward != fore_pass:
		return
	ci.draw_circle(elbow, thick * 0.5 * s, fore)
	ci.draw_line(elbow, wrist, fore, (thick - 0.4) * s)
	if w.outfit == &"stripes":
		ci.draw_line(elbow.lerp(wrist, 0.4), elbow.lerp(wrist, 0.6), w.trim, (thick - 0.2) * s)
	ci.draw_circle(wrist, 1.25 * s, w.hand.darkened(0.15) if far else w.hand)
	_carry_hand(ci, b, w, side)


## 몸통: 윗옷 상자 + 골반(바지) + 옷 모양별 앞·뒤 무늬
static func _torso(ci: CanvasItem, b: Body, w: Wear, front: bool) -> void:
	var s := b.size
	# 목
	ci.draw_line(b.p(b.j["chest"]), b.p(b.j["neck"] + b.up * 0.8), SKIN.darkened(0.12), 2.0 * s)
	# 골반 (바지)
	_prism(ci, b, b.axis_at(PersonRig.WAIST_Z), b.axis_at(PersonRig.HIP_Z - 1.4), b.wb, b.wb - 0.3, b.db, b.db, w.pants)
	if w.outfit == &"dress" or w.outfit == &"hanbok":
		var skirt := w.shirt.darkened(0.08) if w.outfit == &"dress" else w.pants
		var low := 8.0 if w.outfit == &"dress" else 1.2
		_prism(ci, b, b.axis_at(PersonRig.WAIST_Z), b.axis_at(low), b.wb, b.wb + 1.4, b.db + 0.2, b.db + 1.2, skirt)
	if w.outfit == &"apron":
		# 앞치마 아랫단: 허리에서 무릎까지 다리 앞에 늘어진다
		var top := b.axis_at(PersonRig.WAIST_Z)
		var bot := b.axis_at(8.0)
		var d := b.fw * (b.db + 0.25)
		var q := [top - b.rt * b.wb + d, top + b.rt * b.wb + d, bot + b.rt * (b.wb + 0.2) + d * 1.5, bot - b.rt * (b.wb + 0.2) + d * 1.5]
		if b.sees(b.fw):
			_quad(ci, b.p(q[0]), b.p(q[1]), b.p(q[2]), b.p(q[3]), w.trim)
	var hem_bot := b.axis_at(w.hem)
	var widen := 0.0 if w.hem >= PersonRig.WAIST_Z else (0.4 if w.hem > 10.0 else 1.0)
	b.t_bot = hem_bot
	var wb := b.wb + widen
	var db := b.db + widen * 0.5
	_prism(ci, b, b.t_top, hem_bot, b.wt, wb, b.dt, db, w.shirt)
	b.wb = wb
	b.db = db
	var back := b.sees(-b.fw)
	match w.outfit:
		&"jacket":
			if front:
				_patch(ci, b, 0, -0.26, 0.26, 0.04, 0.96, w.trim)                     # 안에 받친 옷
				ci.draw_line(b.fp(0, -0.3, 0.0), b.fp(0, -0.3, 1.0), w.shirt.darkened(0.3), 0.5 * s)
				ci.draw_line(b.fp(0, 0.3, 0.0), b.fp(0, 0.3, 1.0), w.shirt.darkened(0.3), 0.5 * s)
				_patch(ci, b, 0, -0.85, -0.5, 0.62, 0.74, w.shirt.darkened(0.18))       # 주머니
				_patch(ci, b, 0, 0.5, 0.85, 0.62, 0.74, w.shirt.darkened(0.18))
			if back:
				ci.draw_line(b.fp(1, -0.9, 0.26), b.fp(1, 0.9, 0.26), w.shirt.darkened(0.25), 0.5 * s)
				if w.hat == &"hood":
					_patch(ci, b, 1, -0.6, 0.6, 0.0, 0.3, w.hat_c.lightened(0.06))    # 등에 늘어진 후드
		&"suit", &"pinstripe":
			if w.outfit == &"pinstripe":
				for face in [0, 1, 2, 3]:
					if (face == 0 and front) or (face == 1 and back) or (face == 2 and b.sees(b.rt)) or (face == 3 and b.sees(-b.rt)):
						for u in [-0.62, -0.2, 0.2, 0.62]:
							ci.draw_line(b.fp(face, u, 0.05), b.fp(face, u, 0.98), w.shirt.lightened(0.14), 0.3 * s)
			if front:
				var inner := Color(0.94, 0.94, 0.93) if not w.long_hair else Color(0.08, 0.08, 0.09)
				ci.draw_primitive(PackedVector2Array([b.fp(0, -0.36, 0.0), b.fp(0, 0.36, 0.0), b.fp(0, 0.0, 0.5)]),
					PackedColorArray([inner]), PackedVector2Array())
				if not w.long_hair:
					_quad(ci, b.fp(0, -0.07, 0.04), b.fp(0, 0.07, 0.04), b.fp(0, 0.09, 0.44), b.fp(0, -0.09, 0.44), w.trim)
					ci.draw_primitive(PackedVector2Array([b.fp(0, -0.09, 0.44), b.fp(0, 0.09, 0.44), b.fp(0, 0.0, 0.52)]),
						PackedColorArray([w.trim]), PackedVector2Array())
				ci.draw_line(b.fp(0, -0.42, 0.0), b.fp(0, -0.02, 0.56), w.shirt.darkened(0.35), 0.55 * s)   # 깃
				ci.draw_line(b.fp(0, 0.42, 0.0), b.fp(0, 0.02, 0.56), w.shirt.darkened(0.35), 0.55 * s)
				var btn := Color("ad9973") if w.outfit == &"pinstripe" else w.shirt.darkened(0.45)
				for v in [0.64, 0.78]:
					if w.outfit == &"pinstripe":
						ci.draw_circle(b.fp(0, -0.22, v), 0.35 * s, btn)
						ci.draw_circle(b.fp(0, 0.22, v), 0.35 * s, btn)
					else:
						ci.draw_circle(b.fp(0, 0.06, v), 0.35 * s, btn)
			if back:
				ci.draw_line(b.fp(1, 0.0, 0.72), b.fp(1, 0.0, 1.0), w.shirt.darkened(0.35), 0.5 * s)      # 뒤 트임
		&"tank":
			for face in [0, 1]:
				if (face == 0 and front) or (face == 1 and back):
					_patch(ci, b, face, -1.0, -0.55, 0.0, 0.2, SKIN)
					_patch(ci, b, face, 0.55, 1.0, 0.0, 0.2, SKIN)
					if face == 0:
						ci.draw_primitive(PackedVector2Array([b.fp(0, -0.3, 0.0), b.fp(0, 0.3, 0.0), b.fp(0, 0.0, 0.14)]),
							PackedColorArray([SKIN]), PackedVector2Array())
		&"vest", &"armor":
			# 조끼·방탄복: 몸통보다 조금 두꺼운 상자를 덧입힌다
			var top := b.t_top - b.up * 0.6
			var bot := b.axis_at(PersonRig.WAIST_Z - 0.3)
			_prism(ci, b, top, bot, b.wt + 0.15, b.wb + 0.25, b.dt + 0.35, b.db + 0.35, w.trim)
			var dark := w.trim.darkened(0.35)
			if front:
				if w.outfit == &"vest":
					ci.draw_circle(b.fp(0, -0.5, 0.25), 0.55 * s, Color("e3b023"))          # 휘장
					_patch(ci, b, 0, 0.2, 0.75, 0.2, 0.36, Color(0.82, 0.85, 0.88))         # 이름표
					_patch(ci, b, 0, -0.8, -0.2, 0.55, 0.8, dark)
					_patch(ci, b, 0, 0.2, 0.8, 0.55, 0.8, dark)
				else:
					for u in [-0.65, -0.05, 0.55]:
						_patch(ci, b, 0, u, u + 0.42, 0.62, 0.86, dark.lightened(0.1))      # 탄입대
					ci.draw_line(b.fp(0, 0.0, 0.05), b.fp(0, 0.0, 0.5), dark, 0.5 * s)
			if back:
				# 등판 표식: 작은 화면에서도 읽히는 밝은 띠와 글자 획
				var tag := Color(0.85, 0.88, 0.9) if w.outfit == &"vest" else Color(0.55, 0.6, 0.66)
				_patch(ci, b, 1, -0.7, 0.7, 0.16, 0.34, tag)
				for i in 5:
					var u := -0.56 + i * 0.28
					ci.draw_line(b.fp(1, u, 0.2), b.fp(1, u, 0.3), w.trim.darkened(0.2), 0.45 * s)
		&"stripes":
			for face in [0, 1, 2, 3]:
				var vis: bool = (face == 0 and front) or (face == 1 and back) or (face == 2 and b.sees(b.rt)) or (face == 3 and b.sees(-b.rt))
				if not vis:
					continue
				for v in [0.5, 0.82]:
					_patch(ci, b, face, -1.0, 1.0, v, v + 0.09, w.trim)
					ci.draw_line(b.fp(face, -1.0, v + 0.045), b.fp(face, 1.0, v + 0.045), Color(0.85, 0.86, 0.85), 0.35 * s)
			if front:
				ci.draw_line(b.fp(0, 0.0, 0.02), b.fp(0, 0.0, 1.0), w.shirt.darkened(0.35), 0.6 * s)
				_patch(ci, b, 0, -0.35, 0.35, 0.0, 0.1, Color("33332c"))
			if back:
				_patch(ci, b, 1, -0.7, 0.7, 0.14, 0.3, w.trim)
				for i in 3:
					var u := -0.4 + i * 0.4
					ci.draw_line(b.fp(1, u, 0.17), b.fp(1, u, 0.27), Color("8a3a1c"), 0.5 * s)
		&"apron":
			if front:
				_patch(ci, b, 0, -0.62, 0.62, 0.28, 1.0, w.trim)                                    # 가슴받이
				ci.draw_line(b.fp(0, -0.5, 0.28), b.fp(0, -0.25, 0.0), w.trim, 0.6 * s)
				ci.draw_line(b.fp(0, 0.5, 0.28), b.fp(0, 0.25, 0.0), w.trim, 0.6 * s)
				_patch(ci, b, 0, -0.3, 0.3, 0.55, 0.72, w.trim.lightened(0.12))                     # 주머니
			if back:
				ci.draw_line(b.fp(1, -1.0, 0.9), b.fp(1, 1.0, 0.9), w.trim, 0.7 * s)               # 허리끈과 매듭
				ci.draw_line(b.fp(1, 0.0, 0.9), b.fp(1, -0.35, 1.25), w.trim, 0.6 * s)
				ci.draw_line(b.fp(1, 0.0, 0.9), b.fp(1, 0.35, 1.2), w.trim, 0.6 * s)
				ci.draw_line(b.fp(1, -0.55, 0.0), b.fp(1, 0.55, 0.9), w.trim, 0.5 * s)
				ci.draw_line(b.fp(1, 0.55, 0.0), b.fp(1, -0.55, 0.9), w.trim, 0.5 * s)
		&"tracksuit":
			for face in [2, 3]:
				if b.sees(b.rt if face == 2 else -b.rt):
					ci.draw_line(b.fp(face, 0.0, 0.0), b.fp(face, 0.0, 1.0), w.trim, 0.7 * s)
			if front:
				ci.draw_line(b.fp(0, 0.0, 0.0), b.fp(0, 0.0, 1.0), w.trim.darkened(0.3), 0.5 * s)
		&"coat":
			if front:
				ci.draw_line(b.fp(0, 0.1, 0.0), b.fp(0, 0.1, 1.0), w.shirt.darkened(0.3), 0.6 * s)
				_patch(ci, b, 0, -0.9, 0.9, 0.42, 0.47, w.shirt.darkened(0.25))
				_patch(ci, b, 0, -0.2, 0.3, 0.0, 0.08, w.trim)
		&"camo", &"rags":
			for face in [0, 1]:
				if (face == 0 and front) or (face == 1 and back):
					_patch(ci, b, face, -0.7, -0.2, 0.15, 0.3, w.shirt.darkened(0.3))
					_patch(ci, b, face, 0.2, 0.7, 0.5, 0.65, w.shirt.lightened(0.15))
		&"hanbok":
			if front:
				ci.draw_line(b.fp(0, -0.3, 0.0), b.fp(0, 0.3, 0.6), Color(0.97, 0.97, 0.95), 0.9 * s)
				ci.draw_line(b.fp(0, 0.2, 0.55), b.fp(0, 0.4, 1.2), w.trim, 0.9 * s)
	# 멜빵·가방끈: 앞모습이면 어깨에서 가슴으로, 크로스백은 오른 어깨에서 왼 엉덩이로
	var strap := w.prop_c.darkened(0.45)
	if w.prop in [&"delivery", &"backpack", &"air_tank"] and front:
		for u in [-0.55, 0.55]:
			ci.draw_line(b.fp(0, u, 0.0), b.fp(0, u * 1.1, 0.62), Color("22252a"), 0.7 * s)
	elif w.prop in [&"handbag", &"satchel"]:
		if front:
			ci.draw_line(b.fp(0, 0.7, 0.0), b.fp(0, -1.0, 0.95), strap, 0.6 * s)
		elif back:
			ci.draw_line(b.fp(1, 0.7, 0.0), b.fp(1, -1.0, 0.95), strap, 0.6 * s)
	# 허리띠 (셔츠를 바지에 넣은 옷)
	if w.hem >= PersonRig.WAIST_Z and w.outfit != &"apron":
		var belt := Color("151b20")
		for face in [0, 1]:
			if (face == 0 and front) or (face == 1 and back):
				_patch(ci, b, face, -1.0, 1.0, 0.96, 1.0, belt)
				if face == 0:
					_patch(ci, b, 0, -0.1, 0.12, 0.95, 1.0, Color("8b939a"))


## 긴 머리·묶은 머리: 머리 뒤로 늘어진다 (앞모습이면 몸통보다 먼저)
static func _hair_behind(ci: CanvasItem, b: Body, w: Wear) -> void:
	var s := b.size
	var head: Vector3 = b.j["head"]
	var R := PersonRig.HEAD_R
	if w.hat == &"hood" or w.face == &"balaclava":
		return
	if w.long_hair:
		var top := b.p(head - b.fw * 1.0 + b.up * 0.6)
		var low := b.p(head - b.fw * 1.5 - b.up * 7.0) if not b.down else b.p(head - b.fw * 1.6 + b.up * 4.0)
		ci.draw_line(top, low, w.hair, (R * 2.0 - 0.2) * s)
		ci.draw_circle(low, R * 0.95 * s, w.hair)
	if w.hat == &"ponytail":
		var root := head - b.fw * (R - 0.1) + b.up * 1.2
		var tip := root - b.fw * 1.4 - b.up * 7.5 if not b.down else root + b.up * 5.0 - b.fw * 0.5
		ci.draw_line(b.p(root), b.p(root.lerp(tip, 0.5) - b.fw * 0.5), w.hair, 2.2 * s)
		ci.draw_line(b.p(root.lerp(tip, 0.5) - b.fw * 0.5), b.p(tip), w.hair, 1.5 * s)
		ci.draw_circle(b.p(root), 0.8 * s, Color("74717e"))


static func _head(ci: CanvasItem, b: Body, w: Wear) -> void:
	var s := b.size
	var R := PersonRig.HEAD_R
	var head: Vector3 = b.j["head"]
	var fw := b.fw
	var up := b.up
	var faces := fw.normalized().dot(b.view.normalized()) > -0.2     # 옆모습까지 얼굴을 보인다
	var c := b.p(head)
	var back_c := b.p(head - fw * 0.7 + up * 0.35)
	var face_c := b.p(head + fw * 0.5 - up * 0.25)
	var dome := not b.down
	if w.face == &"balaclava":
		ci.draw_circle(c, R * 1.02 * s, w.hat_c)
		if faces:
			_eyes(ci, b, Color(0.1, 0.08, 0.08), SKIN)
		return
	if w.hat == &"hood":
		# 후드: 머리 전체를 덮고 얼굴만 내놓는다
		ci.draw_circle(b.p(head - fw * 0.5 + up * 0.3), R * 1.28 * s, w.hat_c)
		if faces:
			ci.draw_circle(b.p(head + fw * 1.0 - up * 0.3), R * 0.8 * s, SKIN)
			if w.face == &"mask":
				ci.draw_circle(b.p(head + fw * 1.3 - up * 1.25), R * 0.48 * s, Color("171c24"))
			_eyes(ci, b, EYE, Color.TRANSPARENT)
		else:
			ci.draw_line(b.p(head + up * R * 1.2), b.p(head - fw * R - up * 1.5), w.hat_c.lightened(0.12), 0.5 * s)
		return
	if faces:
		ci.draw_circle(back_c, R * s, w.hair)
		ci.draw_circle(face_c, R * 0.88 * s, SKIN)
		if dome:
			# 머리 윗부분 (앞머리)
			ci.draw_arc(b.p(head + up * 0.35 - fw * 0.15), R * 0.8 * s, PI * 1.02, TAU * 0.99, 10, w.hair, R * 0.62 * s)
	else:
		ci.draw_circle(face_c, R * 0.88 * s, SKIN)
		ci.draw_circle(back_c, R * s, w.hair)
		ci.draw_line(b.p(head - fw * R * 0.9 + up * 1.2), b.p(head - fw * R * 0.9 - up * 1.4), w.hair.lightened(0.14), 0.5 * s)
	if faces:
		match w.face:
			&"sunglasses":
				_eyes(ci, b, Color(0.04, 0.04, 0.05), Color.TRANSPARENT, 0.8)
			&"goggles":
				_eyes(ci, b, Color(0.35, 0.45, 0.5), Color(0.08, 0.08, 0.1), 0.9)
			&"mask":
				ci.draw_circle(b.p(head + fw * 1.15 - up * 1.1), R * 0.62 * s, Color("1b2027"))
				_eyes(ci, b, EYE, Color.TRANSPARENT)
			_:
				_eyes(ci, b, EYE, Color.TRANSPARENT)
				if w.face == &"glasses":
					_eyes(ci, b, Color.TRANSPARENT, Color(0.12, 0.12, 0.15), 0.85)
				elif w.face == &"beard":
					ci.draw_circle(b.p(head + fw * 1.1 - up * 1.4), R * 0.55 * s, w.hair.lerp(Color(0.45, 0.43, 0.4), 0.3))
	_hat(ci, b, w)
	if w.prop == &"headphones":
		var hc := w.prop_c
		for side in [-1.0, 1.0]:
			ci.draw_circle(b.p(head + b.rt * side * R * 0.95), 1.1 * s, hc)
		ci.draw_line(b.p(head + b.rt * -R * 0.95 + up * 0.6), b.p(head + up * (R + 0.4)), hc, 0.8 * s)
		ci.draw_line(b.p(head + up * (R + 0.4)), b.p(head + b.rt * R * 0.95 + up * 0.6), hc, 0.8 * s)


## 두 눈 (얼굴 앞면의 좌우). rim이 있으면 테두리(안경·고글), k는 크기 배율
static func _eyes(ci: CanvasItem, b: Body, fill: Color, rim: Color, k := 0.5) -> void:
	var head: Vector3 = b.j["head"]
	var pts: Array[Vector2] = []
	for side in [-1.0, 1.0]:
		if (b.fw + b.rt * side * 0.9).dot(b.view) > 0.0:
			pts.append(b.p(head + b.fw * PersonRig.HEAD_R * 0.82 + b.rt * side * 1.05 + b.up * 0.2))
	for e in pts:
		if fill.a > 0.0:
			ci.draw_circle(e, k * b.size, fill)
		if rim.a > 0.0:
			ci.draw_arc(e, k * b.size, 0.0, TAU, 8, rim, 0.35 * b.size)
	if pts.size() == 2:
		if fill.a > 0.0 and k >= 0.8:
			ci.draw_line(pts[0], pts[1], fill, 1.2 * b.size)
		elif rim.a > 0.0:
			ci.draw_line(pts[0], pts[1], rim, 0.3 * b.size)


## 모자: 머리 위 테두리를 모은 볼록 다각형 + 챙
static func _hat(ci: CanvasItem, b: Body, w: Wear) -> void:
	var s := b.size
	var R := PersonRig.HEAD_R
	var head: Vector3 = b.j["head"]
	var fw := b.fw
	var up := b.up
	var hc := w.hat_c
	match w.hat:
		&"police":
			_cap(ci, b, head + up * 0.9, R * 1.02, 1.3, hc.darkened(0.4))
			_cap(ci, b, head + up * 2.1, R * 1.16, 1.1, hc)
			_brim(ci, b, head + up * 0.9 + fw * R * 0.6, R * 0.8, 1.7, hc.darkened(0.55))
			if b.sees(fw):
				ci.draw_circle(b.p(head + up * 2.4 + fw * R * 1.1), 0.6 * s, Color("e3b023"))
		&"cap", &"visor":
			if w.hat == &"cap":
				ci.draw_circle(b.p(head + up * 1.1 - fw * 0.2), R * 0.98 * s, hc)
			_cap(ci, b, head + up * 0.8, R * 1.0, 0.8, hc)
			_brim(ci, b, head + up * 0.8 + fw * R * 0.7, R * 0.75, 2.0, hc.darkened(0.3))
		&"flatcap":
			_cap(ci, b, head + up * 1.0, R * 1.08, 1.0, hc)
			_brim(ci, b, head + up * 1.0 + fw * R * 0.7, R * 0.7, 1.2, hc.darkened(0.3))
		&"beanie":
			ci.draw_circle(b.p(head + up * 1.2 - fw * 0.2), R * 1.0 * s, hc)
			_cap(ci, b, head + up * 0.4, R * 1.04, 1.0, hc.darkened(0.25))
		&"helmet":
			ci.draw_circle(b.p(head + up * 0.9 - fw * 0.15), R * 1.12 * s, hc)
			ci.draw_arc(b.p(head + up * 1.1 - fw * 0.15), R * 0.85 * s, PI * 1.15, PI * 1.6, 6, hc.lightened(0.25), 0.6 * s)
			_cap(ci, b, head + up * 0.1, R * 1.14, 0.5, hc.darkened(0.2))
			if b.sees(fw):
				_brim(ci, b, head + up * 0.4 + fw * R * 0.75, R * 0.85, 0.7, hc.darkened(0.3))
		&"fire_helmet":
			_brim(ci, b, head + up * 0.4 - fw * 0.5, R * 1.55, R * 1.6, hc.darkened(0.25), true)
			ci.draw_circle(b.p(head + up * 1.2 - fw * 0.1), R * 1.08 * s, hc)
			ci.draw_line(b.p(head + up * (R + 1.0) - fw * R * 0.6), b.p(head + up * (R + 1.2) + fw * R * 0.4), hc.lightened(0.2), 0.8 * s)
			if b.sees(fw):
				ci.draw_circle(b.p(head + up * 1.3 + fw * R * 1.05), 0.75 * s, Color(0.95, 0.8, 0.25))
		&"headband":
			# 머리띠: 머리 둘레 중 보이는 쪽 반 바퀴, 뒤에 매듭
			var pts := PackedVector2Array()
			for k in 13:
				var a := k * TAU / 12.0
				var n := b.rt * cos(a) + fw * sin(a)
				if n.dot(b.view) > -0.2:
					pts.append(b.p(head + up * 1.7 + n * R * 0.9))
			if pts.size() > 1:
				ci.draw_polyline(pts, hc, 0.9 * s)
			if b.sees(-fw):
				var knot := head + up * 1.7 - fw * R * 0.9
				ci.draw_line(b.p(knot), b.p(knot - fw * 0.8 - up * 2.4 - b.rt * 0.6), hc, 0.8 * s)
				ci.draw_line(b.p(knot), b.p(knot - fw * 0.8 - up * 2.2 + b.rt * 0.7), hc, 0.8 * s)


## 머리 둘레 띠 (모자 몸통): 위·아래 테두리를 모아 볼록 다각형으로
static func _cap(ci: CanvasItem, b: Body, base: Vector3, radius: float, height: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 12:
		var a := k * TAU / 12.0
		var n := b.rt * cos(a) + b.fw * sin(a)
		pts.append(b.p(base + n * radius))
		pts.append(b.p(base + n * radius + b.up * height))
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() > 3:
		hull.remove_at(hull.size() - 1)
		ci.draw_colored_polygon(hull, col)


## 챙: 앞으로 나온 반원판 (full이면 둘레 전체 — 소방 헬멧)
static func _brim(ci: CanvasItem, b: Body, c: Vector3, radius: float, reach: float, col: Color, full := false) -> void:
	var pts := PackedVector2Array()
	var n := 12
	for k in n + 1:
		var a := (k * TAU / n) if full else (k * PI / n)
		var d := b.rt * cos(a) * radius + b.fw * sin(a) * (reach if not full else radius * 1.0)
		pts.append(b.p(c + d))
	if not full:
		pts.append(b.p(c - b.fw * 0.2))
	else:
		pts.remove_at(pts.size() - 1)
	ci.draw_colored_polygon(pts, col)


## 등에 멘 것 (배달 가방·공기통·배낭·자루·기타)
static func _carry_back(ci: CanvasItem, b: Body, w: Wear) -> void:
	var s := b.size
	var chest: Vector3 = b.j["chest"]
	var fw := b.fw
	var up := b.up
	var rt := b.rt
	match w.prop:
		&"delivery", &"backpack":
			var big := w.prop == &"delivery"
			var hw := 3.7 if big else 2.8
			var hd := 2.5 if big else 1.5
			var hh := 3.6 if big else 3.0
			var c := chest - fw * (b.dt + hd + 0.1) - up * (2.4 if big else 4.0)
			_box(ci, b, c, rt * hw, fw * hd, up * hh, w.prop_c)
			if b.sees(-fw):
				var o := c - fw * hd
				if big:
					# 가방 뒷면 로고 (V자)
					ci.draw_line(b.p(o - rt * 1.4 + up * 1.2), b.p(o - up * 1.0), Color(0.96, 0.96, 0.94), 0.8 * s)
					ci.draw_line(b.p(o - up * 1.0), b.p(o + rt * 1.4 + up * 1.2), Color(0.96, 0.96, 0.94), 0.8 * s)
				else:
					_box(ci, b, o - up * 1.2, rt * hw * 0.7, fw * 0.4, up * 1.2, w.prop_c.darkened(0.2))
		&"air_tank":
			var c := chest - fw * (b.dt + 1.5) - up * 3.6
			_box(ci, b, c, rt * 1.6, fw * 1.4, up * 4.4, w.prop_c)
			for h in [2.6, -2.4]:
				_box(ci, b, c + up * h, rt * 1.7, fw * 1.5, up * 0.35, Color("35372e"))
			_box(ci, b, c + up * 4.9, rt * 0.5, fw * 0.5, up * 0.5, Color("35372e"))
		&"sack":
			ci.draw_circle(b.p(chest - fw * (b.dt + 2.6) - up * 1.0), 3.6 * s, w.prop_c)
			ci.draw_circle(b.p(chest - fw * (b.dt + 1.4) + up * 2.0 + rt * 1.4), 1.0 * s, w.prop_c.darkened(0.3))
		&"guitar":
			_box(ci, b, chest - fw * (b.dt + 0.9) - up * 3.0 + rt * 0.8, rt * 2.2, fw * 0.8, up * 5.5, w.prop_c.darkened(0.4))


## 옆구리에 멘 것 (크로스백·손가방): 몸통 왼쪽 엉덩이. side가 그 옆일 때만 그린다
static func _carry_side(ci: CanvasItem, b: Body, w: Wear, side: int, front: bool) -> void:
	if side != -1 or not w.prop in [&"handbag", &"satchel"]:
		return
	var s := b.size
	var big := w.prop == &"satchel"
	var c := b.axis_at(PersonRig.HIP_Z + 1.4) - b.rt * (b.wb + 0.9) + b.fw * 0.4
	_box(ci, b, c, b.rt * (0.9 if big else 0.7), b.fw * (2.4 if big else 1.9), b.up * (2.0 if big else 1.6), w.prop_c)
	if b.sees(-b.rt):
		ci.draw_line(b.p(c - b.rt * 0.95 + b.up * 0.6), b.p(c - b.rt * 0.95 + b.up * 0.6 + b.fw * 1.6), w.prop_c.lightened(0.18), 0.5 * s)


## 앞으로 든 것: 배 앞 상자 (배달원), 총 (특공대)
static func _carry_front(ci: CanvasItem, b: Body, w: Wear) -> void:
	var s := b.size
	var l: Vector3 = b.j["wrist_l"]
	var r: Vector3 = b.j["wrist_r"]
	match w.arms:
		&"carry":
			var c := (l + r) * 0.5 + b.up * 1.9 - b.fw * 0.3
			var col := Color("b18b5c") if w.prop == &"delivery" else w.prop_c
			_box(ci, b, c, b.rt * 2.5, b.fw * 1.9, b.up * 1.9, col)
			if b.sees(b.up):
				ci.draw_line(b.p(c + b.up * 1.9 - b.fw * 1.9), b.p(c + b.up * 1.9 + b.fw * 1.9), Color(0.85, 0.78, 0.6), 0.6 * s)
			for side in [-1.0, 1.0]:
				ci.draw_circle(b.p((l if side < 0 else r)), 1.2 * s, w.hand)
		&"rifle":
			var col := w.prop_c.lightened(0.15)
			var stock := r - b.fw * 2.6 + b.up * 1.4
			var muzzle := l + b.fw * 4.2 + b.up * 0.3
			ci.draw_line(b.p(stock), b.p(muzzle), col, 1.7 * s)
			ci.draw_line(b.p(muzzle), b.p(muzzle + (muzzle - stock).normalized() * 2.0), col.darkened(0.3), 0.8 * s)
			ci.draw_line(b.p(r.lerp(l, 0.35)), b.p(r.lerp(l, 0.35) - b.up * 2.2), col.darkened(0.2), 1.1 * s)   # 탄창
			ci.draw_circle(b.p(r), 1.2 * s, w.hand)
			ci.draw_circle(b.p(l), 1.2 * s, w.hand)


## 손에 든 것 (그 손 아래팔을 그린 다음): 서류가방·단검·전단·지팡이·경찰봉·휴대폰
static func _carry_hand(ci: CanvasItem, b: Body, w: Wear, side: int) -> void:
	var s := b.size
	var t := "l" if side < 0 else "r"
	var wrist: Vector3 = b.j["wrist_" + t]
	var elbow: Vector3 = b.j["elbow_" + t]
	var fore := (wrist - elbow).normalized()
	match w.prop:
		&"briefcase":
			if side > 0:
				var vert := Vector3(0, 0, 1) if not b.down else b.up
				var thin := b.rt if not b.down else Vector3(0, 0, 1)
				var c := wrist - vert * 2.4 + thin * 0.3
				_box(ci, b, c, thin * 0.7, b.fw * 2.6 if not b.down else b.rt * 2.6, vert * 1.9, w.prop_c)
				ci.draw_line(b.p(wrist + b.fw * 0.6), b.p(wrist - b.fw * 0.6), w.prop_c.darkened(0.4), 0.6 * s)
				if b.sees(b.rt):
					ci.draw_circle(b.p(c + b.rt * 0.75 + b.up * 0.9), 0.35 * s, PersonDrawer.CLASP)
		&"blades":
			var tip := wrist + fore * 1.2 - b.up * 3.6 + b.fw * 1.0
			ci.draw_line(b.p(wrist), b.p(wrist + fore * 0.8), Color("252931"), 1.1 * s)
			ci.draw_line(b.p(wrist + fore * 0.6), b.p(tip), w.prop_c, 0.9 * s)
		&"flyers":
			if side > 0:
				var c := wrist + b.fw * 0.8
				_box(ci, b, c, b.rt * 0.2, b.fw * 1.4, b.up * 1.8, Color(0.97, 0.97, 0.94))
		&"cane":
			if side > 0:
				ci.draw_line(b.p(wrist), b.p(Vector3(wrist.x + 0.8, wrist.y + 1.5, 0.0)), w.prop_c, 1.0 * s)
		&"baton":
			if side > 0:
				ci.draw_line(b.p(wrist), b.p(wrist - b.up * 4.0 + b.fw * 0.8), w.prop_c, 1.1 * s)
		&"phone":
			if side > 0:
				_box(ci, b, wrist + b.fw * 0.5, b.rt * 0.2, b.fw * 0.5, b.up * 0.9, Color(0.1, 0.1, 0.12))


# ── 그림 스프라이트 (assets/characters/<id>.png — tools/prepare_character_sprites.py가 제미나이 원본에서 만든다) ──
## 칸 96×112, 8열(아래 WALK_COLS 위 설명) × 2행(앞모습: 화면 오른쪽 아래를 봄 · 뒷모습: 오른쪽 위).
## 칸마다 발끝이 FOOT, 서 있는 키가 SPRITE_BODY px. 왼쪽을 보면 좌우를 뒤집는다. 그림이 없는 종은 위의 관절 그림으로 그린다.
## 그림 파일 이름 = data/npc 파일 이름(id 소문자), 주인공은 player.png.

const SPRITE_DIR := "res://assets/characters/"
const CELL := Vector2(96, 112)
const FOOT := Vector2(48, 108)
const SPRITE_BODY := 96.0
const SPRITE_HEIGHT := 31.0          ## 화면에서 서 있는 키 (px, size 1)
## 그림 8열: 0 서 있기 · 1 걷기 A · 2 걷기 B · 3 달리기 · 4 걷기 모음 · 5 달리기 A · 6 달리기 B · 7 달리기 모음
const WALK_COLS := [1, 4, 2, 4]      ## 딛기 A · 모음 · 딛기 B · 모음
const RUN_COLS := [5, 7, 6, 7]       ## 달리기 A(몸이 뜬다) · 모음 · 달리기 B · 모음
const CYCLE := 16                    ## 한 바퀴 그림 장 수 (9열부터 걷기 16장, 그다음 달리기 16장 — 있으면)
const CADENCE := 1.4                 ## 걷기 위상(walk_phase) 한 바퀴에 걸음 주기 1.4번
const RUN_CADENCE := 1.2

## false면 그림이 있어도 관절 그림으로 (person_gallery -- --code-rig)
static var use_sprites := not ("--code-rig" in OS.get_cmdline_user_args())
static var _sprites := {}


## 그 종의 스프라이트 시트 (없으면 null). look이 없으면 주인공
static func sprite_for(look: NpcType) -> Texture2D:
	var id := "player" if look == null else String(look.id).to_lower()
	if not _sprites.has(id):
		var path := SPRITE_DIR + id + ".png"
		_sprites[id] = load(path) if ResourceLoader.exists(path) else null
	return _sprites[id]


## 서 있는 그림 한 칸 (PersonDrawer.draw_standing·도감이 부른다). 그림이 없으면 false
static func draw_from_actor(ci: CanvasItem, facing: float, phase: float, size: float, look: NpcType,
		_weapon: WeaponType, down: bool) -> bool:
	return draw_sheet_frame(ci, facing, phase, 0.0, size, look, down)


static func draw_sheet_frame(ci: CanvasItem, facing: float, phase: float, gait: float, size: float,
		look: NpcType, down: bool) -> bool:
	if not use_sprites:
		return false
	if not down and (_draw_dir8(ci, facing, phase, gait, size, look) or _draw_dir4(ci, facing, phase, gait, size, look)):
		return true
	var tex := sprite_for(look)
	if tex == null:
		return false
	var g := PersonDrawer._ground(ci)
	var f := Vector2.UP.rotated(facing)
	var k := SPRITE_HEIGHT * size / SPRITE_BODY
	if down:
		# 쓰러짐: 서 있는 앞모습을 바닥(월드 평면)에 눕힌다 — 머리가 보는 방향, 몸 가운데가 노드 자리
		ci.draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, g))
		ci.draw_colored_polygon(_ellipse_pts(Vector2.ZERO, 14.0 * size, 5.0 * size), Color(0, 0, 0, 0.32))
		var r := Vector2(-f.y, f.x)
		var kw := k * 1.15
		var t := Transform2D(r * kw, -f * kw, Vector2.ZERO)
		t.origin = IsoView.lift(g) - t.basis_xform(Vector2(FOOT.x, FOOT.y - SPRITE_BODY * 0.5))
		ci.draw_set_transform_matrix(t)
		ci.draw_texture_rect_region(tex, Rect2(Vector2.ZERO, CELL), Rect2(Vector2.ZERO, CELL))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return true
	var dir := IsoView.to_screen_dir(f)
	var row := 1 if dir.y < -0.1 else 0
	var flip := -1.0 if dir.x < -0.05 else 1.0
	var col := 0
	var bob := 0.0
	if gait > 0.3:
		# 한 걸음 주기를 4토막으로: [왼발 딛기 · 두 발 모음(몸이 올라옴) · 오른발 딛기 · 두 발 모음].
		# 딛는 순간은 낮게, 사이에는 높게 — 같은 그림 두 장만 번갈아 바꾸던 것보다 걸음이 살아난다.
		# 보폭에 맞게 걸음 박자를 CADENCE배로 빠르게 한다 (발이 땅에서 미끄러지지 않게)
		var run := gait > 1.5
		var t := phase * (RUN_CADENCE if run else CADENCE)
		var q := posmod(int(floor(t * 4.0 / TAU)), 4)
		var cycles := int(tex.get_width() / CELL.x) - 8
		if cycles >= CYCLE * (2 if run else 1):
			# 한 바퀴 그림이 있으면 그것을 차례로 (걷기 8~23열, 달리기 24~39열). 몸 오르내림은 그림에 들어 있다
			var n := posmod(int(floor(t * CYCLE / TAU)), CYCLE)
			col = 8 + (CYCLE if run else 0) + n
		elif tex.get_width() >= CELL.x * 8:
			# 딛기 A → 다리 모음 → 딛기 B → 다리 모음 (모음 칸은 다듬기 도구가 같은 그림에서 만든다)
			col = (RUN_COLS if run else WALK_COLS)[q]
		else:
			# 예전 4열 그림: 서 있기 칸을 모음으로
			col = ([3, 0, 3, 0] if run else [1, 0, 2, 0])[q]
		if col >= 8:
			bob = 0.0
		elif run:
			bob = (1.4 if q % 2 == 0 else 0.0) * size
		else:
			bob = (0.0 if q % 2 == 0 else 0.8) * size
	ci.draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, g))
	ci.draw_colored_polygon(_ellipse_pts(Vector2.ZERO, 6.5 * size, 2.6 * size), Color(0, 0, 0, 0.32))
	ci.draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, g + bob).scaled_local(Vector2(flip * k, k)))
	ci.draw_texture_rect_region(tex, Rect2(-FOOT, CELL), Rect2(Vector2(col, row) * CELL, CELL))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


static func _ellipse_pts(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 14:
		out.append(c + Vector2(cos(i * TAU / 14.0) * rx, sin(i * TAU / 14.0) * ry))
	return out


# ── 몸 조각 그림 (assets/characters/rig/<id>.png + .json — tools/prepare_character_rig.py가 만든다) ──
## 머리·몸통·윗팔·아랫팔·허벅지·정강이 조각(앞·뒤)을 관절 뼈대(Body.pose)에 붙여 그린다.
## 조각은 세워 그린 그림이라, 관절 점(pivot)을 앞 관절에 두고 다음 관절 쪽으로 돌린다. 굵기는 한 사람 안에서 같은 배율,
## 길이는 두 관절 사이 화면 거리에 맞춰 늘이고 줄인다(앞뒤로 흔든 팔다리가 짧아 보이게). 왼쪽을 보면 좌우를 뒤집는다.
## 조각이 있으면 스프라이트보다 먼저 쓴다.

const RIG_DIR := "res://assets/characters/rig/"
const RIG_TORSO := 10.0              ## 뼈대의 목~골반 길이 (SHOULDER_Z + 1.4 − HIP_Z − 0.4)
const FAR_TINT := Color(0.74, 0.74, 0.8)
static var _rigs := {}


## 그 종의 조각판 {tex, parts} (없으면 빈 사전)
static func rig_for(look: NpcType) -> Dictionary:
	var id := "player" if look == null else String(look.id).to_lower()
	if not _rigs.has(id):
		var info := {}
		var png := RIG_DIR + id + ".png"
		var meta := RIG_DIR + id + ".json"
		if ResourceLoader.exists(png) and FileAccess.file_exists(meta):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta))
			if data is Dictionary:
				info = {"tex": load(png), "parts": data["parts"]}
		_rigs[id] = info
	return _rigs[id]


static func draw_parts(ci: CanvasItem, facing: float, phase: float, gait: float, size: float, look: NpcType,
		weapon: WeaponType, down: bool) -> bool:
	var rig := rig_for(look)
	if rig.is_empty():
		return false
	var b := Body.new()
	b.setup(facing, size)
	b.pose(phase, gait, &"", false, down)
	var base := IsoView.screen_frame(Vector2.ZERO, PersonDrawer._ground(ci))
	ci.draw_set_transform_matrix(base)
	_shadow(ci, b, down)
	var dir := IsoView.to_screen_dir(Vector2.UP.rotated(facing))
	var row := 0 if down or dir.y >= -0.1 else 1
	var flip := -1.0 if dir.x < -0.05 else 1.0
	var parts: Dictionary = rig["parts"]
	var tex: Texture2D = rig["tex"]
	var torso: Dictionary = parts["torso"][row]
	var ks := RIG_TORSO * size / float(torso["length"])
	var near := 1 if b.sees(b.rt) else -1
	var t := {"ci": ci, "base": base, "tex": tex, "parts": parts, "row": row, "ks": ks, "flip": flip, "b": b}
	for side in [-near, near]:
		var tag := "l" if side < 0 else "r"
		var tint := FAR_TINT if side == -near else Color.WHITE
		_part(t, "thigh", "hip_" + tag, "knee_" + tag, tint)
		_part(t, "shin", "knee_" + tag, "ankle_" + tag, tint)
	var far := "l" if near > 0 else "r"
	_part(t, "upper_arm", "shoulder_" + far, "elbow_" + far, FAR_TINT)
	_part(t, "forearm", "elbow_" + far, "wrist_" + far, FAR_TINT)
	_part(t, "torso", "neck", "pelvis", Color.WHITE)
	_part(t, "head", "neck", "head", Color.WHITE, true)
	var nr := "r" if near > 0 else "l"
	_part(t, "upper_arm", "shoulder_" + nr, "elbow_" + nr, Color.WHITE)
	_part(t, "forearm", "elbow_" + nr, "wrist_" + nr, Color.WHITE)
	if weapon and not weapon.melee:
		ci.draw_set_transform_matrix(base)
		var hand := b.at("wrist_r")
		ci.draw_line(hand, b.p(b.j["wrist_r"] + b.fw * (3.0 + weapon.slot)), Color(0.1, 0.1, 0.12), 1.6 * size)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## 조각 하나: 관절 a에 조각의 관절 점을 두고 b 쪽으로 돌려 그린다. up이면 조각이 위로 선다(머리)
static func _part(t: Dictionary, name: String, from: String, to: String, tint: Color, up := false) -> void:
	var list: Array = t["parts"].get(name, [])
	if list.size() <= t["row"] or list[t["row"]] == null:
		return
	var info: Dictionary = list[t["row"]]
	var b: Body = t["b"]
	var a := b.at(from)
	var d := b.at(to) - a
	var rect := Rect2(info["rect"][0], info["rect"][1], info["rect"][2], info["rect"][3])
	var pivot := Vector2(info["pivot"][0], info["pivot"][1])
	var ks: float = t["ks"]
	var angle: float
	var kl := ks
	if up:
		angle = Vector2.UP.angle_to(d)
	else:
		angle = Vector2.DOWN.angle_to(d)
		kl = clampf(d.length() / float(info["length"]), ks * 0.45, ks * 1.6)
	var xf := Transform2D(angle, Vector2(ks * float(t["flip"]), kl), 0.0, a)
	var ci: CanvasItem = t["ci"]
	ci.draw_set_transform_matrix(t["base"] * xf)
	ci.draw_texture_rect_region(t["tex"], Rect2(-pivot, rect.size), rect, tint)


# ── 정방향 4방향 그림 (assets/characters/<id>_dir4.png — 다듬기 도구가 NN_<id>_walk_dir4.png에서 만든다) ──
## 3행(0 앞: 화면 쪽으로 · 1 뒤: 화면 안쪽으로 · 2 옆: 오른쪽, 왼쪽은 뒤집어 쓴다) × (0 서 있기 + 1~16 걷기 [+ 17~32 달리기]), 칸 128×112.
## 사선 그림(3/4 시점)과 달리 화면 기준 위·아래·좌·우 그대로다. 이 그림이 있으면 서 있기·걷기·달리기를 모두 이걸로 그린다
## (쓰러짐은 예전 시트). 방향은 화면에서의 진행 각도로 고르고, 경계 근처에서는 직전 방향을 지켜 대각선에서 깜박이지 않게 한다.

const DIR4_FRAMES := 24                ## 걷기·달리기 한 바퀴 장 수 (12장 원본은 두 번씩, 8장 원본은 세 번씩 — 다듬기 도구가 넣는다)
const DIR4_CELL := Vector2(128, 112)   ## 옆으로 달리는 보폭이 넓어 칸이 가로로 크다
const DIR4_FOOT := Vector2(64, 108)
const DIR4_HOLD := deg_to_rad(14.0)   ## 직전 방향을 이만큼 더 넓게 봐 준다 (대각선에서 앞·옆이 번갈아 바뀌지 않게)
static var _dir4 := {}


static func dir4_for(look: NpcType) -> Texture2D:
	var id := "player" if look == null else String(look.id).to_lower()
	if not _dir4.has(id):
		var path := SPRITE_DIR + id + "_dir4.png"
		_dir4[id] = load(path) if ResourceLoader.exists(path) else null
	return _dir4[id]


## 화면 진행 방향 → 0 앞(아래) · 1 뒤(위) · 2 오른쪽 · 3 왼쪽. prev 방향은 DIR4_HOLD만큼 넓게 잡는다
static func dir4_row(dir: Vector2, prev: int) -> int:
	var a := dir.angle()          # 0 = 오른쪽, PI/2 = 아래 (화면 y는 아래로)
	var centers := {2: 0.0, 0: PI * 0.5, 3: PI, 1: -PI * 0.5}
	if prev >= 0 and absf(angle_difference(a, centers[prev])) <= PI * 0.25 + DIR4_HOLD:
		return prev
	var best := 0
	var best_d := INF
	for row: int in centers:
		var d := absf(angle_difference(a, centers[row]))
		if d < best_d:
			best_d = d
			best = row
	return best


## 정방향 4방향 그림에 달리기 칸(걷기 다음 DIR4_FRAMES장)까지 있는가
static func _dir4_has_run(look: NpcType) -> bool:
	var tex := dir4_for(look)
	return tex != null and tex.get_width() >= DIR4_CELL.x * (1 + DIR4_FRAMES * 2)


static func _draw_dir4(ci: CanvasItem, facing: float, phase: float, gait: float, size: float, look: NpcType) -> bool:
	var tex := dir4_for(look)
	if tex == null:
		return false
	var dir := IsoView.to_screen_dir(Vector2.UP.rotated(facing))
	var prev: int = ci.get_meta(&"dir4_row", -1)
	var d := dir4_row(dir, prev)
	ci.set_meta(&"dir4_row", d)
	var row := 2 if d >= 2 else d
	var flip := -1.0 if d == 3 else 1.0
	var col := 0
	if gait > 0.3:
		var run := gait > 1.5
		var has_run := _dir4_has_run(look)
		var t := phase * (RUN_CADENCE if run else CADENCE)
		var n := posmod(int(floor(t * DIR4_FRAMES / TAU)), DIR4_FRAMES)
		col = 1 + n + (DIR4_FRAMES if run and has_run else 0)
	var g := PersonDrawer._ground(ci)
	var k := SPRITE_HEIGHT * size / SPRITE_BODY
	ci.draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, g))
	ci.draw_colored_polygon(_ellipse_pts(Vector2.ZERO, 6.5 * size, 2.6 * size), Color(0, 0, 0, 0.32))
	ci.draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, g).scaled_local(Vector2(flip * k, k)))
	ci.draw_texture_rect_region(tex, Rect2(-DIR4_FOOT, DIR4_CELL), Rect2(Vector2(col, row) * DIR4_CELL, DIR4_CELL))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


# ── 8방향 걷기 그림 (assets/characters/<id>_dir8.png + .json — 다듬기 도구가 NN_<id>_walk8_<방향>.png에서 만든다) ──
## 8행(DIR8 순서: 오른쪽부터 시계 방향 45°씩) × (0 서 있기 + 1~N 걷기). .json의 dirs가 실제로 받은 방향, frames가 N(없으면 16)이다.
## 없는 방향은 좌우 짝(예: ↙ ← ↘ 뒤집기)을, 그것도 없으면(↓·↑) 가장 가까운 방향을 쓴다.
## 경계 근처에서는 직전 방향을 DIR8_HOLD만큼 더 지켜 깜박이지 않게 한다. 달리기 그림은 아직 없어 걷기를 빠르게 넘긴다
## (정방향 4방향 그림에 달리기가 있으면 — 주인공 — 달리기는 그것으로 그린다).

const DIR8 := ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
const DIR8_MIRROR := [4, 3, 2, 1, 0, 7, 6, 5]
const DIR8_FRAMES := 16                ## .json에 frames가 없을 때 걷기 장 수
const DIR8_HOLD := deg_to_rad(12.0)
static var _dir8 := {}


## {tex, frames, ok: 방향마다 [그릴 행, 뒤집기] 또는 null}
static func dir8_for(look: NpcType) -> Dictionary:
	var id := "player" if look == null else String(look.id).to_lower()
	if not _dir8.has(id):
		var info := {}
		var png := SPRITE_DIR + id + "_dir8.png"
		var meta := SPRITE_DIR + id + "_dir8.json"
		if ResourceLoader.exists(png) and FileAccess.file_exists(meta):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta))
			if data is Dictionary:
				var have: Array = data.get("dirs", [])
				var ok := []
				for k in 8:
					if DIR8[k] in have:
						ok.append([k, false])
					elif DIR8[DIR8_MIRROR[k]] in have and DIR8_MIRROR[k] != k:
						ok.append([DIR8_MIRROR[k], true])
					else:
						ok.append(null)
				info = {"tex": load(png), "frames": int(data.get("frames", DIR8_FRAMES)), "ok": ok}
		_dir8[id] = info
	return _dir8[id]


## 화면 진행 방향 → 8방향 번호 (그릴 수 있는 것 중 가장 가까운 것, 직전 방향은 넓게)
static func dir8_pick(dir: Vector2, prev: int, ok: Array) -> int:
	var a := dir.angle()
	if prev >= 0 and ok[prev] != null and absf(angle_difference(a, prev * PI / 4.0)) <= PI / 8.0 + DIR8_HOLD:
		return prev
	var best := -1
	var best_d := INF
	for k in 8:
		if ok[k] == null:
			continue
		var d := absf(angle_difference(a, k * PI / 4.0))
		if d < best_d - 0.001 or (absf(d - best_d) <= 0.001 and k == prev):
			best_d = d
			best = k
	return best


static func _draw_dir8(ci: CanvasItem, facing: float, phase: float, gait: float, size: float, look: NpcType) -> bool:
	var info := dir8_for(look)
	if info.is_empty():
		return false
	if gait > 1.5 and _dir4_has_run(look):
		return false
	var ok: Array = info["ok"]
	var dir := IsoView.to_screen_dir(Vector2.UP.rotated(facing))
	var k := dir8_pick(dir, ci.get_meta(&"dir8", -1), ok)
	if k < 0:
		return false
	ci.set_meta(&"dir8", k)
	var row: int = ok[k][0]
	var flip := -1.0 if ok[k][1] else 1.0
	var col := 0
	if gait > 0.3:
		var t := phase * (RUN_CADENCE if gait > 1.5 else CADENCE)
		var n: int = info["frames"]
		col = 1 + posmod(int(floor(t * n / TAU)), n)
	var g := PersonDrawer._ground(ci)
	var s := SPRITE_HEIGHT * size / SPRITE_BODY
	ci.draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, g))
	ci.draw_colored_polygon(_ellipse_pts(Vector2.ZERO, 6.5 * size, 2.6 * size), Color(0, 0, 0, 0.32))
	ci.draw_set_transform_matrix(IsoView.screen_frame(Vector2.ZERO, g).scaled_local(Vector2(flip * s, s)))
	ci.draw_texture_rect_region(info["tex"], Rect2(-DIR4_FOOT, DIR4_CELL), Rect2(Vector2(col, row) * DIR4_CELL, DIR4_CELL))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true
