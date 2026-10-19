class_name VehicleModel
## 2.5D 차량 입체 모형 (docs/12_차량_이미지.md의 참고 그림을 보고 코드로 만든다 — 이미지 파일은 쓰지 않는다).
## 차종마다 상자·경사 상자·원통·막대 부품으로 차 모양을 짓고, 2.5D 화면에 비춰 그린다.
## 부품 좌표는 차 기준 3D: x = 오른쪽, y = 뒤(앞이 -y), z = 위 (화면 px, 줌 1).
## 모양은 차종 크기(size·height)에서 한 번 만들어 두고, 그릴 때는 차의 회전만 반영한다 —
## 어느 방향을 보든 같은 모형을 돌려 그리므로 회전 중간 각도도 자연스럽다.
## 확대해서 보려면 tools/vehicle_gallery.tscn (Codex의 차량 도감처럼 크게 비춘다).
##
## 그리는 순서: 부품마다 화면을 향한 면만 그린다 (볼록한 부품이라 면끼리는 순서가 필요 없다).
## 부품끼리는 층(layer: 0 차대 · 1 차체 · 2 위 차체 · 3 지붕 위 · 4 그 위) → 같은 층에서는 깊이 순.
## 바퀴는 차체 옆면이 보이는 쪽이면 차체 다음, 아니면 차체 전에 그린다.
## 면 무늬(창·등·띠·문틈)는 데칼: 부품 면 위의 다각형이고, 그 면이 보일 때 부품 바로 다음에 그린다.
## 차체는 모서리를 깎아(bevel) 둥글게 보이게 한다 — 깎은 면에도 등화·유리를 이어 붙인다.

const F := 0   ## 상자 면 번호: 앞
const R := 1   ## 오른쪽
const B := 2   ## 뒤
const L := 3   ## 왼쪽
const T := 4   ## 위
const FRC := 5 ## 깎은 모서리 면 (bevel이 있을 때만): 앞-오른쪽
const BRC := 6 ## 뒤-오른쪽
const BLC := 7 ## 뒤-왼쪽
const FLC := 8 ## 앞-왼쪽
## 화면 쪽(보는 사람 쪽) 방향 (월드 3D). 화면 x = 0.78(x−y), 화면 y = 0.39(x+y) − z 에 수직
const VIEW := Vector3(0.78, 0.78, 0.608)

const GLASS := Color(0.12, 0.17, 0.25)
const GLINT := Color(0.3, 0.4, 0.5)       ## 유리에 비친 빛 줄기
const TINT := Color(0.06, 0.07, 0.09)     ## 짙은 선팅 유리 (특공대)
const TIRE := Color(0.07, 0.07, 0.08)
const SIDEWALL := Color(0.13, 0.13, 0.14)
const HUB := Color(0.7, 0.72, 0.76)
const STEEL := Color(0.5, 0.52, 0.55)
const DARK := Color(0.13, 0.13, 0.15)
const CHROME := Color(0.8, 0.82, 0.86)
const PLATE := Color(0.92, 0.92, 0.85)
const RIDER := Color(0.15, 0.17, 0.22)
const HELMET := Color(0.95, 0.95, 0.95)
const ORANGE := Color(0.95, 0.5, 0.12)
const CROSS := Color(0.12, 0.65, 0.32)
const HAZARD := Color(0.98, 0.8, 0.1)
const BEACON := Color(1.0, 0.6, 0.1)
const AMBER := Color(1.0, 0.62, 0.18)
const WHITE := Color(0.94, 0.94, 0.95)
const REFLECT := Color(0.85, 0.12, 0.12)  ## 화물차 반사띠 빨강
const POLICE_TRIM := Color(0.72, 0.9, 0.18)  ## 경찰 헬기 연두 띠
const CAMO := Color(0.2, 0.24, 0.14)         ## 군용 얼룩무늬 짙은 녹색
const RECOIL := 6.0                          ## 쏜 순간 포신이 뒤로 밀리는 거리 (px)
const CRUSH_FLAT := 0.62                     ## 다 깔린 차는 높이가 이만큼 줄어든다

## 색 역할: 그릴 때 실제 색으로 바꾼다 (차 도색·브레이크·경광등에 따라)
const BODY := &"body"        ## 차체 색 (카센터에서 바뀐다)
const ACCENT := &"accent"    ## 차종 보조색 (VehicleType.roof_color)
const HEAD := &"head"        ## 전조등
const TAIL := &"tail"        ## 후미등 (브레이크면 밝게)
const REVERSE := &"reverse"  ## 후진등 (후진하면 켠다)
const SIREN_R := &"siren_r"  ## 경광등 빨강
const SIREN_B := &"siren_b"  ## 경광등 파랑


class Part:
	var pts := PackedVector3Array()
	var faces: Array[PackedInt32Array] = []
	var normals: Array[Vector3] = []
	var colors: Array = []          ## 면마다 색 (Color · 역할 · [역할, 어둡게])
	var layer := 1
	var center := Vector3.ZERO
	var wheel := 0                  ## 바퀴면 -1(왼쪽)/1(오른쪽)
	var rider := false              ## 사람이 탔을 때만 그린다 (오토바이·자전거)
	var blade := false              ## 헬기 주 회전날개 (hide_blades면 그리지 않는다)
	var turret := 0                 ## 1: 포탑 (Vehicle.turret만큼 axis_y 축으로 돈다) · 2: 포신 (trunnion에서 들린 뒤 포탑과 같이 돈다)
	var axis_y := 0.0               ## 포탑이 도는 축의 y
	var trunnion := Vector2.ZERO    ## 포신이 들리는 축 (y, z)
	var decals: Array = []          ## [PackedVector3Array, 법선, 색]


static var _cache := {}
static var _dent_height := 1.0   ## 지금 그리는 차의 높이 (찌그러짐: 위쪽 점일수록 덜 밀린다)
static var _bank := 0.0          ## 지금 그리는 차가 옆으로 기운 각 (헬기 선회, Vehicle.bank)
static var _pitch := 0.0         ## 지금 그리는 차가 앞으로 숙인 각 (헬기 가속, Vehicle.pitch)
static var _turret := 0.0        ## 지금 그리는 차의 포탑 각 (차 앞 기준, Vehicle.turret)
static var _elev := 0.0          ## 포신을 든 각 (Vehicle.elevation)
static var _recoil := 0.0        ## 쏜 뒤 포신이 뒤로 밀린 거리 (px)
static var _squash := 1.0        ## 깔려 납작해진 정도 (높이 배율, Vehicle.crushed)
static var _cur: Part = null     ## 지금 그리는 부품 (포탑·포신이면 점을 돌린다)
static var hide_blades := false  ## 주 회전날개를 빼고 그린다 (헬기 그림 가이드 — 날개는 코드가 따로 그린다)
static var even_light := false   ## 옆면을 좌우 같은 밝기로 (헬기 그림 가이드 — 좌우 뒤집어 쓰는 그림이라 빛이 한쪽이면 안 된다)


static func model(stats: VehicleType) -> Array:
	var key: String = stats.resource_path if stats.resource_path != "" else str(stats.get_instance_id())
	if not _cache.has(key):
		_cache[key] = _build(stats)
	return _cache[key]


# ── 그리기 ────────────────────────────────────────────────

## 차 노드(회전한 좌표계) 안에 모형을 그린다
static func draw(ci: CanvasItem, car: Vehicle) -> void:
	var parts: Array = model(car.stats)
	var rot := car.rotation
	var up := IsoView.lift_local(1.0, rot)
	var v2 := Vector2(VIEW.x, VIEW.y).rotated(-rot)
	var view := Vector3(v2.x, v2.y, VIEW.z)
	# 방향 그림이 있는 헬기(VehicleSprite)는 그림으로 — 멈춘 주 날개만 모형으로 얹는다 (돌 때는 Vehicle._draw_rotor)
	var sprite := VehicleSprite.of(car.stats) if IsoView.enabled else null
	if sprite and sprite.draw(ci, car):
		ci.draw_set_transform(IsoView.lift_local(car.ground + car.altitude, rot), 0.0, Vector2.ONE)
		if not car._rotor_spinning() and not hide_blades:
			_bank = car.bank
			_pitch = car.pitch
			for p: Part in parts:
				if p.blade:
					_draw_part(ci, p, view, up, rot, car, [])
		return
	var before: Array[Part] = []
	var middle: Array[Part] = []
	var after: Array[Part] = []
	for p: Part in parts:
		if p.rider and not car.occupied():
			continue
		# 멈춘 주 날개: 날개가 도는 동안엔 도는 원판(Vehicle.draw_rotor)만 보인다
		if p.blade and (hide_blades or car._rotor_spinning()):
			continue
		if p.wheel != 0:
			if Vector3(p.wheel, 0, 0).dot(view) > 0.0:
				after.append(p)
			else:
				before.append(p)
		else:
			middle.append(p)
	_turret = car.turret
	_elev = car.elevation
	_recoil = car.recoil * RECOIL
	_squash = 1.0 - CRUSH_FLAT * car.crushed
	middle.sort_custom(func(a: Part, b: Part) -> bool:
		return a.layer * 100000.0 + _posed(a.center, a).dot(view) < b.layer * 100000.0 + _posed(b.center, b).dot(view))
	var dents: Array = car.dents
	_dent_height = maxf(car.stats.height, 1.0)
	_bank = car.bank
	_pitch = car.pitch
	for list in [before, middle, after]:
		for p: Part in list:
			# 바퀴·사람은 찌그러지지 않는다
			_draw_part(ci, p, view, up, rot, car, [] if p.wheel != 0 or p.rider else dents)
	_draw_dents(ci, dents, view, up, car)


static func _draw_part(ci: CanvasItem, p: Part, view: Vector3, up: Vector2, rot: float, car: Vehicle, dents: Array) -> void:
	_cur = p
	for i in p.faces.size():
		var n := _rolled(_posed(p.normals[i], p, true), 0.0)
		if n.dot(view) <= 0.03:
			continue
		_poly(ci, p.pts, p.faces[i], up, _shade(_color(p.colors[i], car), n, rot), dents)
	for d: Array in p.decals:
		var n := _rolled(_posed(d[1], p, true), 0.0)
		if n.dot(view) <= 0.03:
			continue
		var pts: PackedVector3Array = d[0]
		var idx := PackedInt32Array()
		for k in pts.size():
			idx.append(k)
		_poly(ci, pts, idx, up, _shade(_color(d[2], car), n, rot), dents)
	_cur = null


static func _poly(ci: CanvasItem, pts: PackedVector3Array, idx: PackedInt32Array, up: Vector2, color: Color, dents: Array = []) -> void:
	var out := _project(pts, idx, up, dents)
	# 찌그러뜨려 꼬인 다각형은 펴진 모양으로 그린다 (삼각분할 실패 방지)
	if out.size() > 4 and not dents.is_empty() and Geometry2D.triangulate_polygon(out).is_empty():
		out = _project(pts, idx, up, [])
	if out.size() <= 4:
		ci.draw_primitive(out, PackedColorArray([color]), PackedVector2Array())
	else:
		ci.draw_colored_polygon(out, color)


static func _project(pts: PackedVector3Array, idx: PackedInt32Array, up: Vector2, dents: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(idx.size())
	for k in idx.size():
		var p := pts[idx[k]]
		if not dents.is_empty():
			p = _dented(p, dents)
		if _cur and _cur.turret != 0:
			p = _posed(p, _cur)
		if _squash < 1.0:
			p.z *= _squash
		if _bank != 0.0 or _pitch != 0.0:
			p = _rolled(p, Vehicle.BANK_PIVOT)
		out[k] = Vector2(p.x, p.y) + up * p.z
	return out


## 포탑·포신 부품의 점(normal이면 방향)을 지금 포탑 각·포신 각으로 돌린다. 다른 부품은 그대로
static func _posed(q: Vector3, part: Part, normal := false) -> Vector3:
	if part == null or part.turret == 0:
		return q
	if part.turret == 2:
		# 포신: 쏜 뒤 뒤로 밀리고(+y), 포이 축(trunnion)에서 앞(−y)이 들린다
		var y := q.y if normal else q.y + _recoil - part.trunnion.x
		var z := q.z if normal else q.z - part.trunnion.y
		var c := cos(_elev)
		var sn := sin(_elev)
		q = Vector3(q.x, y * c + z * sn, -y * sn + z * c)
		if not normal:
			q += Vector3(0, part.trunnion.x, part.trunnion.y)
	var r := Vector2(q.x, q.y - (0.0 if normal else part.axis_y)).rotated(_turret)
	return Vector3(r.x, r.y + (0.0 if normal else part.axis_y), q.z)


## 지금 그리는 차의 기울기(_bank)·숙이기(_pitch)로 돌린다. pivot은 축 높이 (방향 벡터면 0)
static func _rolled(p: Vector3, pivot: float) -> Vector3:
	if _bank == 0.0 and _pitch == 0.0:
		return p
	return tilt(p, pivot, _bank, _pitch)


## 앞으로 숙이고(pitch, 좌우 축 x — +면 코(-y)가 내려간다) 옆으로 기울인다(bank, 앞뒤 축 y — +면 오른쪽이 내려간다).
## 축은 높이 pivot에 있다
static func tilt(p: Vector3, pivot: float, bank: float, pitch: float) -> Vector3:
	var z := p.z - pivot
	var cp := cos(pitch)
	var sp := sin(pitch)
	var y := p.y * cp - z * sp
	z = z * cp + p.y * sp
	var cb := cos(bank)
	var sb := sin(bank)
	return Vector3(p.x * cb + z * sb, y, pivot + z * cb - p.x * sb)


## 찌그러진 곳(Vehicle.dents) 가까운 점을 안쪽으로 밀고 위쪽 점은 조금 내린다. 가운데일수록 깊다
static func _dented(p: Vector3, dents: Array) -> Vector3:
	for d: Array in dents:
		var dist := Vector2(p.x, p.y).distance_to(d[0])
		if dist >= DamageModel.DENT_RADIUS:
			continue
		var q := dist / DamageModel.DENT_RADIUS
		var f := 1.0 - q * q
		var depth: float = d[2] * lerpf(1.0, 0.35, clampf(p.z / _dent_height, 0.0, 1.0))
		var push: Vector2 = d[1] * depth * f
		p += Vector3(push.x, push.y, -depth * 0.35 * f if p.z > 2.0 else 0.0)
	return p


## 찌그러진 곳: 보이는 쪽 면에 움푹 팬 자국(그늘진 패임 + 위 테두리 반사)과 구김 줄.
## 모형 꼭짓점은 모서리에만 있어서 면 한가운데가 들어간 모양은 이 자국으로 보인다
static func _draw_dents(ci: CanvasItem, dents: Array, view: Vector3, up: Vector2, car: Vehicle) -> void:
	var height := car.stats.height
	var paint := car.paint
	for d: Array in dents:
		var depth: float = d[2]
		var inward: Vector2 = d[1]
		if depth < 1.0 or Vector3(-inward.x, -inward.y, 0.0).dot(view) <= 0.15:
			continue
		# 모서리는 꼭짓점이 밀려 들어간 모양으로 충분하다 (자국을 그리면 차 밖으로 삐져나온다)
		if absf(inward.x) > 0.35 and absf(inward.y) > 0.35:
			continue
		var along := Vector2(-inward.y, inward.x)
		var base: Vector2 = d[0] + inward * depth * 0.8
		var half_w := clampf(3.0 + depth * 1.2, 3.0, 11.0)
		var half_h := maxf(height * 0.17, 2.5)
		var mid := height * 0.36
		var outline := PackedVector2Array()
		for k in 8:
			var a := TAU * k / 8.0
			outline.append(base + along * cos(a) * half_w + up * (mid + sin(a) * half_h))
		ci.draw_colored_polygon(outline, Color(paint.darkened(0.45), clampf(0.35 + depth * 0.07, 0.0, 0.8)))
		# 위쪽 테두리는 빛을 받아 밝다
		var rim := PackedVector2Array()
		for k in 5:
			var a := PI + PI * k / 4.0
			rim.append(base + along * cos(a) * half_w + up * (mid - sin(a) * half_h))
		ci.draw_polyline(rim, Color(paint.lightened(0.35), 0.7), 0.8)
		var c := Color(0.0, 0.0, 0.0, clampf(0.2 + depth * 0.06, 0.0, 0.5))
		for j in 2:
			var o := base + along * (j - 0.5) * half_w * 0.7 + up * mid
			ci.draw_line(o - along * 1.6 + up * half_h * 0.6, o + along * 1.6 - up * half_h * 0.5, c, 0.7)


## 면 방향에 따른 밝기: 윗면 밝게, 오른쪽 아래를 향한 면 조금, 왼쪽 아래를 향한 면 더 어둡게
static func _shade(c: Color, n: Vector3, rot: float) -> Color:
	if n.z > 0.75:
		return c.lightened(0.05)
	var w := Vector2(n.x, n.y).rotated(rot)
	var dark := 0.2 if w.x > w.y else 0.38
	if even_light:
		dark = 0.29
	if absf(w.x - w.y) < 0.5 * w.length():
		dark = 0.29      # 깎은 모서리 (두 면 사이 밝기)
	if n.z > 0.25:
		dark *= 0.5      # 비스듬한 면 (앞유리·보닛)
	return c.darkened(dark)


static func _color(spec: Variant, car: Vehicle) -> Color:
	var amount := 0.0
	if spec is Array:
		amount = spec[1]
		spec = spec[0]
	var c: Color
	if spec is Color:
		c = spec
	else:
		match spec:
			BODY: c = car.paint
			ACCENT: c = car.stats.roof_color
			HEAD: c = Color(1.0, 0.96, 0.78) if car.occupied() else Color(0.75, 0.75, 0.7)
			TAIL: c = Color(1.0, 0.15, 0.2) if car.is_braking() else Color(0.62, 0.06, 0.09)
			REVERSE: c = Color(1.0, 1.0, 0.95) if car.motor.forward_speed() < -5.0 else Color(0.55, 0.55, 0.56)
			SIREN_R: c = Color(1.0, 0.2, 0.25) if car.siren and car._siren_phase() else Color(0.5, 0.08, 0.1)
			SIREN_B: c = Color(0.3, 0.55, 1.0) if car.siren and not car._siren_phase() else Color(0.1, 0.15, 0.45)
			_: c = Color.MAGENTA
	if amount > 0.0:
		c = c.darkened(amount)
	elif amount < 0.0:
		c = c.lightened(-amount)
	if spec is Color and (spec == TIRE or spec == SIDEWALL):
		return c
	if car.wrecked:
		c = c.darkened(0.78)   # 그을린 잔해
	elif car.on_fire or car.burning >= 0.0:
		var fire := car.fire_level()
		c = c.darkened(0.55 if fire > 1.0 else 0.08 + 0.3 * fire)   # 불길에 그을려 간다
	return c


# ── 부품 만들기 ───────────────────────────────────────────

## 아랫면(z0)과 윗면(z1) 사각형이 다른 볼록 상자. 앞유리·보닛 경사, 좁아지는 지붕에 쓴다.
## bevel > 0이면 세로 모서리 넷을 깎는다 (팔각 기둥) — 앞·옆·뒤 면 번호는 그대로이고 깎은 면은 FRC~FLC
static func hull(xb0: float, xb1: float, yb0: float, yb1: float, z0: float,
		xt0: float, xt1: float, yt0: float, yt1: float, z1: float, color: Variant, layer := 1, bevel := 0.0) -> Part:
	var p := Part.new()
	if bevel <= 0.0:
		p.pts = PackedVector3Array([Vector3(xb0, yb0, z0), Vector3(xb1, yb0, z0), Vector3(xb1, yb1, z0), Vector3(xb0, yb1, z0),
			Vector3(xt0, yt0, z1), Vector3(xt1, yt0, z1), Vector3(xt1, yt1, z1), Vector3(xt0, yt1, z1)])
		# 면 꼭짓점 순서: 왼쪽 아래 → 오른쪽 아래 → 오른쪽 위 → 왼쪽 위 (데칼 u·v 기준)
		p.faces = [PackedInt32Array([0, 1, 5, 4]), PackedInt32Array([1, 2, 6, 5]), PackedInt32Array([2, 3, 7, 6]),
			PackedInt32Array([3, 0, 4, 7]), PackedInt32Array([4, 5, 6, 7])]
	else:
		for q in [[xb0, xb1, yb0, yb1, z0], [xt0, xt1, yt0, yt1, z1]]:
			var x0: float = q[0]
			var x1: float = q[1]
			var y0: float = q[2]
			var y1: float = q[3]
			var z: float = q[4]
			var b := minf(bevel, minf(x1 - x0, y1 - y0) * 0.3)
			p.pts.append_array(PackedVector3Array([Vector3(x0 + b, y0, z), Vector3(x1 - b, y0, z), Vector3(x1, y0 + b, z),
				Vector3(x1, y1 - b, z), Vector3(x1 - b, y1, z), Vector3(x0 + b, y1, z), Vector3(x0, y1 - b, z), Vector3(x0, y0 + b, z)]))
		p.faces = [PackedInt32Array([0, 1, 9, 8]), PackedInt32Array([2, 3, 11, 10]), PackedInt32Array([4, 5, 13, 12]),
			PackedInt32Array([6, 7, 15, 14]), PackedInt32Array([8, 9, 10, 11, 12, 13, 14, 15]),
			PackedInt32Array([1, 2, 10, 9]), PackedInt32Array([3, 4, 12, 11]), PackedInt32Array([5, 6, 14, 13]),
			PackedInt32Array([7, 0, 8, 15])]
	p.layer = layer
	_finish(p, color)
	return p


static func box(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, color: Variant, layer := 1, bevel := 0.0) -> Part:
	return hull(x0, x1, y0, y1, z0, x0, x1, y0, y1, z1, color, layer, bevel)


## 원통 (양 끝 반지름이 달라도 된다). a·b = 양 끝 중심, u·v = 단면 축
static func cyl(a: Vector3, b: Vector3, ra: float, rb: float, u: Vector3, v: Vector3, n: int,
		color: Variant, layer := 1, stripe: Variant = null) -> Part:
	var p := Part.new()
	for k in n:
		var t := TAU * (k + 0.5) / n
		p.pts.append(a + (u * cos(t) + v * sin(t)) * ra)
	for k in n:
		var t := TAU * (k + 0.5) / n
		p.pts.append(b + (u * cos(t) + v * sin(t)) * rb)
	for k in n:
		var k2 := (k + 1) % n
		p.faces.append(PackedInt32Array([k, k2, n + k2, n + k]))
	var cap_a := PackedInt32Array()
	var cap_b := PackedInt32Array()
	for k in n:
		cap_a.append(n - 1 - k)
		cap_b.append(n + k)
	p.faces.append(cap_a)
	p.faces.append(cap_b)
	p.layer = layer
	_finish(p, color)
	if stripe != null:
		for k in range(1, n, 2):
			p.colors[k] = stripe
	p.colors[n] = [color, 0.15] if not (color is Array) else color
	p.colors[n + 1] = [color, 0.15] if not (color is Array) else color
	return p


## 막대: a에서 b까지, 폭(옆)·두께(위아래) — 거울 팔·사다리·회전날개·자전거 틀
static func bar(a: Vector3, b: Vector3, width: float, thick: float, color: Variant, layer := 1) -> Part:
	var p := Part.new()
	var d := (b - a).normalized()
	var s := d.cross(Vector3(0, 0, 1))
	if s.length() < 0.01:
		s = Vector3(1, 0, 0)
	s = s.normalized() * width * 0.5
	var t := s.cross(d).normalized() * thick * 0.5
	p.pts = PackedVector3Array([a - s - t, a + s - t, a + s + t, a - s + t, b - s - t, b + s - t, b + s + t, b - s + t])
	p.faces = [PackedInt32Array([0, 1, 2, 3]), PackedInt32Array([4, 5, 6, 7]), PackedInt32Array([0, 1, 5, 4]),
		PackedInt32Array([1, 2, 6, 5]), PackedInt32Array([2, 3, 7, 6]), PackedInt32Array([3, 0, 4, 7])]
	p.layer = layer
	_finish(p, color)
	return p


## 원통 옆면을 한 바퀴 감는 띠 (v: 원통 a끝 0 → b끝 1). 원통을 겹쳐 그리면 마구리가 비치므로 무늬로 그린다
static func band(p: Part, n: int, v0: float, v1: float, color: Variant) -> void:
	for k in n:
		decal(p, k, 0.0, 1.0, v0, v1, color)


## 바퀴 하나: 12각 타이어 + 옆면에 림·스포크 (spokes 0이면 철제 휠: 림과 너트 판)
static func wheel(x: float, y: float, r: float, half: float, side: int, rim: Variant = HUB, spokes := 5) -> Part:
	var w := cyl(Vector3(x - half, y, r), Vector3(x + half, y, r), r, r, Vector3(0, 1, 0), Vector3(0, 0, 1), 12, TIRE)
	w.colors[12] = SIDEWALL
	w.colors[13] = SIDEWALL
	for cap in [12, 13]:
		var n := w.normals[cap]
		var c := Vector3(x + half * signf(n.x), y, r)
		w.decals.append([_disc(c + n * 0.15, r * 0.7, 10), n, rim])
		if spokes > 0:
			w.decals.append([_disc(c + n * 0.2, r * 0.56, 10), n, DARK])
			w.decals.append([_star(c + n * 0.25, r * 0.6, r * 0.17, spokes), n, rim])
		else:
			w.decals.append([_disc(c + n * 0.2, r * 0.32, 8), n, _darker(rim, 0.35)])
	w.wheel = side
	return w


## 색 지정을 더 어둡게 (이미 [역할, 어둡게]인 것도)
static func _darker(spec: Variant, amount: float) -> Variant:
	if spec is Array:
		return [spec[0], spec[1] + amount]
	return [spec, amount]


## 바퀴 한 쌍씩 (x축 원통). 바깥면이 차체 옆면과 거의 맞닿게 둔다
static func wheels(parts: Array, hw: float, ys: Array, r: float, half := 2.2, rim: Variant = HUB, spokes := 5) -> void:
	for side: int in [-1, 1]:
		for y: float in ys:
			parts.append(wheel(side * (hw - half - 0.1), y, r, half, side, rim, spokes))


## y-z 평면의 원 (바퀴 옆면 무늬)
static func _disc(c: Vector3, r: float, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in n:
		var t := TAU * k / n
		out.append(c + Vector3(0, cos(t), sin(t)) * r)
	return out


## y-z 평면의 별 (휠 스포크)
static func _star(c: Vector3, r: float, r_in: float, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in n * 2:
		var t := PI * k / n + PI * 0.5
		out.append(c + Vector3(0, cos(t), sin(t)) * (r if k % 2 == 0 else r_in))
	return out


## 부품 면 위에 무늬 사각형 (u: 면의 가로 0~1, v: 아래 0 → 위 1)
static func decal(p: Part, face: int, u0: float, u1: float, v0: float, v1: float, color: Variant) -> void:
	decal_uv(p, face, [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)], color)


## 부품 면 위에 아무 모양 (u·v 점들)
static func decal_uv(p: Part, face: int, uvs: Array, color: Variant) -> void:
	var f := p.faces[face]
	var c0 := p.pts[f[0]]
	var c1 := p.pts[f[1]]
	var c2 := p.pts[f[2]]
	var c3 := p.pts[f[3]]
	var n := p.normals[face]
	var pts := PackedVector3Array()
	for uv: Vector2 in uvs:
		pts.append(c0.lerp(c1, uv.x).lerp(c3.lerp(c2, uv.x), uv.y) + n * 0.15)
	p.decals.append([pts, n, color])


## 양 옆면에 같은 무늬 (오른쪽 면 u는 앞→뒤, 왼쪽 면 u는 뒤→앞이므로 뒤집어 맞춘다)
static func sides(p: Part, u0: float, u1: float, v0: float, v1: float, color: Variant) -> void:
	decal(p, R, u0, u1, v0, v1, color)
	decal(p, L, 1.0 - u1, 1.0 - u0, v0, v1, color)


## 면 위에 차 좌표로 다각형: 점은 (가로, 높이) — 옆면이면 가로 = y, 앞뒤면이면 x.
## 면 밖으로 나간 점은 면 가장자리로 당긴다 (바퀴 아치가 차체 위로 삐져나오지 않게)
static func face_pts(p: Part, face: int, pts2: Array, color: Variant) -> void:
	var f := p.faces[face]
	var lo := p.pts[f[0]]
	var lo2 := p.pts[f[1]]
	var hi := p.pts[f[3]]
	var hi2 := p.pts[f[2]]
	var ax := 1 if face == R or face == L else 0
	var n := p.normals[face]
	var out := PackedVector3Array()
	for q: Vector2 in pts2:
		var v := clampf((q.y - lo.z) / (hi.z - lo.z), 0.0, 0.92)
		var a := lo.lerp(hi, v)
		var b := lo2.lerp(hi2, v)
		var da := b[ax] - a[ax]
		var t := clampf((q.x - a[ax]) / da, 0.0, 1.0) if absf(da) > 0.001 else 0.0
		out.append(a.lerp(b, t) + n * 0.15)
	p.decals.append([_unfold(out), n, color])


## 가장자리로 당긴 점이 겹치거나 갔다가 되돌아오면(뾰족 접힘) 뺀다 —
## 그대로 두면 어떤 각도에서 삼각분할이 실패한다 (높은 바퀴 아치: 구급차·특공대)
static func _unfold(pts: PackedVector3Array) -> PackedVector3Array:
	var out := pts.duplicate()
	var changed := true
	while changed and out.size() > 3:
		changed = false
		for i in out.size():
			var a := out[i - 1]
			var b := out[i]
			var c := out[(i + 1) % out.size()]
			if a.distance_to(b) < 0.01:
				out.remove_at(i)
				changed = true
				break
			if a.distance_to(c) < 0.01:
				out.remove_at(i)
				out.remove_at(i % out.size())
				changed = true
				break
	return out


## 양 옆면에 차 좌표 다각형
static func side_pts(p: Part, pts2: Array, color: Variant) -> void:
	face_pts(p, R, pts2, color)
	face_pts(p, L, pts2, color)


## 옆면의 바퀴 아치 (바퀴 뒤로 보이는 어두운 휠하우스)
static func arch(p: Part, y: float, r: float, color: Variant = DARK) -> void:
	var a := r + 0.8
	var pts: Array = [Vector2(y + a, 0.0)]
	for k in 9:
		var t := PI * k / 8.0
		pts.append(Vector2(y + cos(t) * a, r + sin(t) * a))
	pts.append(Vector2(y - a, 0.0))
	side_pts(p, pts, color)


## 옆면 세로 줄 (문틈)
static func seam(p: Part, y: float, z0: float, z1: float, color: Variant = [BODY, 0.38]) -> void:
	side_pts(p, [Vector2(y - 0.3, z0), Vector2(y + 0.3, z0), Vector2(y + 0.3, z1), Vector2(y - 0.3, z1)], color)


## 옆면 사각형 (차 좌표 y0~y1, z0~z1)
static func side_rect(p: Part, y0: float, y1: float, z0: float, z1: float, color: Variant) -> void:
	side_pts(p, [Vector2(y0, z0), Vector2(y1, z0), Vector2(y1, z1), Vector2(y0, z1)], color)


## 윗면 위 사각형 (지붕창·보닛 줄·해치)
static func top_rect(p: Part, x0: float, x1: float, y0: float, y1: float, color: Variant) -> void:
	var z := p.pts[p.faces[T][0]].z + 0.15
	p.decals.append([PackedVector3Array([Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y1, z), Vector3(x0, y1, z)]),
		Vector3(0, 0, 1), color])


static func _finish(p: Part, color: Variant) -> void:
	var sum := Vector3.ZERO
	for q in p.pts:
		sum += q
	p.center = sum / p.pts.size()
	for f in p.faces:
		# 뉴얼 방식 법선, 부품 가운데에서 바깥을 향하게
		var n := Vector3.ZERO
		var fc := Vector3.ZERO
		for k in f.size():
			var a := p.pts[f[k]]
			var b := p.pts[f[(k + 1) % f.size()]]
			n += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
			fc += a
		fc /= f.size()
		n = n.normalized() if n.length() > 0.0001 else Vector3.ZERO
		if n.dot(fc - p.center) < 0.0:
			n = -n
		p.normals.append(n)
		p.colors.append(color)


# ── 차종별 모형 ───────────────────────────────────────────

static func _build(s: VehicleType) -> Array:
	var id := s.resource_path.get_file().get_basename()
	var w := s.size.x
	var l := s.size.y
	var h := s.height
	match id:
		"car_avela": return _car(w, l, h, {})
		"car_sonato": return _car(w, l, h, {"chrome": true, "sunroof": true})
		"car_zenith_g8": return _car(w, l, h, {"chrome": true, "sunroof": true, "cab": [-0.12, 0.31, 0.0, 0.2], "nose": 4.0})
		"car_taxi": return _car(w, l, h, {"taxi": true})
		"police_patrol": return _car(w, l, h, {"police": true})
		"car_striker": return _car(w, l, h, {"sport": true, "cab": [-0.12, 0.42, 0.02, 0.26], "top": 0.68})
		"car_avela_r": return _car(w, l, h, {"sport": true, "cab": [-0.13, 0.36, 0.0, 0.18], "top": 0.68})
		"car_sorea": return _car(w, l, h, {"suv": true})
		"car_rumi": return _car(w, l, h, {"belt": 0.52, "cab": [-0.3, 0.49, -0.21, 0.48], "top": 0.88, "r": 3.7,
			"nose": 2.0, "tail": 0.6, "split": 0.42, "axles": [-0.3, 0.32]})
		"trk_porta": return _flatbed(w, l, h)
		"trk_bongo", "trk_titan", "etc_truck": return _box_truck(w, l, h)
		"trk_tanker": return _tanker(w, l, h)
		"trk_garbage": return _garbage(w, l, h)
		"trk_mixer": return _mixer(w, l, h)
		"sp_fire": return _fire(w, l, h)
		"sp_tow": return _tow(w, l, h)
		"sp_army": return _army(w, l, h)
		"army_spg": return _spg(w, l, h)
		"army_jeep": return _jeep(w, l, h)
		"bus_city", "bus_express", "bus_village": return _bus(w, l, h, id == "bus_express")
		"sp_ambulance": return _van(w, l, h, true)
		"sp_swat": return _van(w, l, h, false)
		"etc_camper": return _camper(w, l, h)
		"sp_heli": return _heli(w, l, h)
		"police_heli": return _heli(w, l, h, {"police": true})
		"sp_fire_heli": return _rescue_heli(w, l, h)
		"army_heli": return _army_heli(w, l, h)
		"etc_bike": return _bike(w, l, false)
		"etc_bicycle": return _bike(w, l, true)
	match s.category:
		&"bus": return _bus(w, l, h, false)
		&"suv": return _car(w, l, h, {"suv": true})
		&"sport": return _car(w, l, h, {"sport": true, "cab": [-0.13, 0.36, 0.0, 0.18], "top": 0.68})
		&"light": return _car(w, l, h, {"belt": 0.52, "cab": [-0.3, 0.49, -0.21, 0.48], "top": 0.88})
		&"ambulance": return _van(w, l, h, true)
		&"swat", &"camper": return _van(w, l, h, false)
		&"bike": return _bike(w, l, false)
		&"bicycle": return _bike(w, l, true)
	if s.category in Vehicle.TRUCKS:
		return _box_truck(w, l, h)
	return _car(w, l, h, {})


## 승용차 앞: 범퍼·흡기구·번호판·전조등(깎은 모서리까지 감싼다)·방향지시등·그릴
static func _car_front(p: Part, chrome: bool) -> void:
	decal(p, F, 0.0, 1.0, 0.0, 0.32, [BODY, 0.14])
	decal(p, F, 0.16, 0.84, 0.05, 0.22, DARK)
	decal(p, F, 0.39, 0.61, 0.08, 0.27, PLATE)
	decal_uv(p, F, [Vector2(0.0, 0.52), Vector2(0.28, 0.62), Vector2(0.28, 0.84), Vector2(0.0, 0.9)], HEAD)
	decal_uv(p, F, [Vector2(0.72, 0.62), Vector2(1.0, 0.52), Vector2(1.0, 0.9), Vector2(0.72, 0.84)], HEAD)
	decal(p, F, 0.32, 0.68, 0.42, 0.9, CHROME if chrome else [DARK, -0.15])
	decal(p, F, 0.34, 0.66, 0.47, 0.85, DARK)
	if chrome:
		for v in [0.58, 0.7]:
			decal(p, F, 0.34, 0.66, v, v + 0.04, CHROME)
	if p.faces.size() > 5:
		for c in [FRC, FLC]:
			decal(p, c, 0.0, 1.0, 0.52, 0.9, HEAD)
			decal(p, c, 0.0, 1.0, 0.34, 0.48, AMBER)


## 승용차 뒤: 범퍼·디퓨저·번호판·후미등(모서리까지)·후진등
static func _car_rear(p: Part) -> void:
	decal(p, B, 0.0, 1.0, 0.0, 0.3, [BODY, 0.14])
	decal(p, B, 0.24, 0.76, 0.03, 0.14, DARK)
	decal(p, B, 0.39, 0.61, 0.38, 0.66, PLATE)
	decal(p, B, 0.0, 0.27, 0.56, 0.88, TAIL)
	decal(p, B, 0.73, 1.0, 0.56, 0.88, TAIL)
	decal(p, B, 0.19, 0.27, 0.6, 0.74, REVERSE)
	decal(p, B, 0.73, 0.81, 0.6, 0.74, REVERSE)
	if p.faces.size() > 5:
		for c in [BRC, BLC]:
			decal(p, c, 0.0, 1.0, 0.56, 0.88, TAIL)


## 캐빈 유리: 앞유리(빛 줄기)·뒷유리·옆창 둘(가운데 기둥). split ≤ 0이면 옆창 하나
static func _glass(c: Part, split: float, glass: Color = GLASS) -> void:
	decal(c, F, 0.02, 0.98, 0.05, 0.93, glass)
	decal_uv(c, F, [Vector2(0.2, 0.1), Vector2(0.31, 0.1), Vector2(0.52, 0.88), Vector2(0.41, 0.88)], GLINT)
	decal_uv(c, F, [Vector2(0.36, 0.1), Vector2(0.4, 0.1), Vector2(0.61, 0.88), Vector2(0.57, 0.88)], GLINT)
	decal(c, B, 0.04, 0.96, 0.08, 0.9, glass)
	if split > 0.0:
		sides(c, 0.05, split - 0.035, 0.1, 0.9, glass)
		sides(c, split + 0.035, 0.94, 0.1, 0.9, glass)
	else:
		sides(c, 0.05, 0.94, 0.1, 0.9, glass)


## 승용차 공통 (세단·택시·경찰·스포츠·SUV·경차)
##  belt 차체 높이 비율 · cab [앞(아래), 뒤(아래), 앞(위), 뒤(위)] 길이 비율 · top 지붕 폭 비율
##  r 바퀴 반지름 · axles 앞뒤 바퀴 위치 · nose/tail 보닛·트렁크 경사 · split 옆창 나누는 곳
##  chrome 크롬 장식 · sunroof · taxi · police · sport · suv
static func _car(w: float, l: float, h: float, o: Dictionary) -> Array:
	var sport: bool = o.get("sport", false)
	var suv: bool = o.get("suv", false)
	if sport:
		o.merge({"belt": 0.64, "r": 3.7, "bevel": 3.6, "nose": 5.0, "tail": 2.0, "split": 0.0})
	if suv:
		o.merge({"belt": 0.56, "cab": [-0.2, 0.47, -0.08, 0.46], "top": 0.84, "r": 4.7, "tail": 0.8, "split": 0.42, "axles": [-0.31, 0.31]})
	var hw := w * 0.5
	var hl := l * 0.5
	var zb := h * float(o.get("belt", 0.64))
	var r: float = o.get("r", 3.9)
	var ax: Array = o.get("axles", [-0.31, 0.3])
	var ys := [l * float(ax[0]), l * float(ax[1])]
	var cab: Array = o.get("cab", [-0.17, 0.3, -0.04, 0.18])
	var top: float = o.get("top", 0.74)
	var chrome: bool = o.get("chrome", false)
	var bv: float = o.get("bevel", 3.0)
	var parts: Array = []
	var body := hull(-hw * 0.95, hw * 0.95, -hl, hl, 1.8,
		-hw, hw, -hl + float(o.get("nose", 3.0)), hl - float(o.get("tail", 2.5)), zb, BODY, 1, bv)
	_car_front(body, chrome or suv)
	_car_rear(body)
	# 옆: 아래 몰딩(SUV는 검은 플라스틱 아치), 바퀴 아치, 문틈·손잡이, 크롬 띠
	sides(body, 0.0, 1.0, 0.0, 0.18, DARK if suv else [BODY, 0.28])
	sides(body, 0.0, 1.0, 0.78, 0.86, [BODY, -0.14])                 # 어깨선 빛 (둥근 옆면처럼)
	for y: float in ys:
		if suv:
			arch(body, y, r + 1.0, [DARK, -0.1])
		arch(body, y, r)
	var y_a := l * float(cab[0]) + 1.0
	var y_b := l * lerpf(cab[0], cab[1], float(o.get("split", 0.5)))
	var y_c: float = ys[1] - r - 1.2
	var doors: Array = [y_a, y_b] if sport else [y_a, y_b, y_c]
	for y: float in doors:
		seam(body, y, 2.5, zb - 0.3)
	for k in doors.size() - 1:
		side_rect(body, doors[k + 1] - 4.2, doors[k + 1] - 1.6, zb - 2.2, zb - 1.4, CHROME if chrome else [BODY, 0.3])
	if chrome:
		sides(body, 0.06, 0.94, 0.9, 0.97, CHROME)
	if o.get("police", false):
		sides(body, 0.0, 1.0, 0.18, 0.56, ACCENT)          # 아래 남색
		sides(body, 0.0, 1.0, 0.56, 0.63, HAZARD)          # 노랑 줄
		decal(body, F, 0.0, 1.0, 0.0, 0.32, ACCENT)
	if sport:
		top_rect(body, -3.4, -1.8, -hl + 5.5, l * float(cab[0]), [BODY, 0.4])   # 보닛 줄
		top_rect(body, 1.8, 3.4, -hl + 5.5, l * float(cab[0]), [BODY, 0.4])
		decal(body, B, 0.3, 0.42, 0.04, 0.16, CHROME)      # 쌍 배기구
		decal(body, B, 0.58, 0.7, 0.04, 0.16, CHROME)
	parts.append(body)
	# 캐빈: 차체색 기둥 + 유리
	var c := hull(-hw * 0.88, hw * 0.88, l * float(cab[0]), l * float(cab[1]), zb,
		-hw * top, hw * top, l * float(cab[2]), l * float(cab[3]), h, BODY, 2, bv * 0.7)
	_glass(c, float(o.get("split", 0.5)))
	if o.get("sunroof", false):
		top_rect(c, -hw * top * 0.6, hw * top * 0.6, l * float(cab[2]) + 2.0, l * lerpf(cab[2], cab[3], 0.5), GLASS)
	parts.append(c)
	# 지붕 위: 상어지느러미 안테나 · SUV 가로대 · 택시 표시등 · 경광등 · 스포츠 날개
	if not o.get("taxi", false) and not o.get("police", false):
		parts.append(hull(-0.6, 0.6, l * float(cab[3]) - 4.0, l * float(cab[3]) - 0.5, h, -0.4, 0.4, l * float(cab[3]) - 1.8, l * float(cab[3]) - 0.8, h + 1.4, DARK, 3))
	if suv:
		for side: int in [-1, 1]:
			parts.append(box(side * hw * top * 0.85 - 0.8, side * hw * top * 0.85 + 0.8, l * float(cab[2]) + 1.0, l * float(cab[3]) - 1.0, h, h + 1.4, CHROME, 3))
		decal(body, F, 0.25, 0.75, 0.0, 0.08, STEEL)       # 아래 보호판
	if o.get("taxi", false):
		var sign := hull(-5.0, 5.0, l * 0.0, l * 0.1, h, -4.2, 4.2, l * 0.01, l * 0.09, h + 4.8, ACCENT, 4, 1.2)
		decal(sign, F, 0.1, 0.9, 0.2, 0.75, DARK)
		decal(sign, B, 0.1, 0.9, 0.2, 0.75, DARK)
		decal(sign, F, 0.2, 0.8, 0.35, 0.6, [ACCENT, -0.3])
		parts.append(sign)
	if o.get("police", false):
		var y0 := l * 0.0
		parts.append(box(-hw * 0.66, hw * 0.66, y0, y0 + 5.0, h, h + 1.0, DARK, 3))
		parts.append(box(-hw * 0.64, -hw * 0.34, y0 + 0.4, y0 + 4.6, h + 1.0, h + 3.2, SIREN_R, 4))
		parts.append(box(-hw * 0.32, -1.0, y0 + 0.4, y0 + 4.6, h + 1.0, h + 3.2, [SIREN_R, 0.25], 4))
		parts.append(box(-1.0, 1.0, y0 + 0.6, y0 + 4.4, h + 1.0, h + 2.6, CHROME, 4))
		parts.append(box(1.0, hw * 0.32, y0 + 0.4, y0 + 4.6, h + 1.0, h + 3.2, [SIREN_B, 0.25], 4))
		parts.append(box(hw * 0.34, hw * 0.64, y0 + 0.4, y0 + 4.6, h + 1.0, h + 3.2, SIREN_B, 4))
	if sport:
		for side: int in [-1, 1]:
			parts.append(box(side * hw * 0.55 - 0.7, side * hw * 0.55 + 0.7, hl - 4.5, hl - 2.5, zb, zb + 2.6, DARK, 3))
		parts.append(hull(-hw * 0.9, hw * 0.9, hl - 5.5, hl - 1.5, zb + 2.6, -hw * 0.92, hw * 0.92, hl - 4.5, hl - 1.0, zb + 3.6, [BODY, 0.3], 4, 1.0))
	for side: int in [-1, 1]:
		var mx: float = hw * 0.86 if side > 0 else -hw - 1.4      # 사이드미러
		var m := box(mx, mx + hw * 0.14 + 1.4, y_a + 0.5, y_a + 2.2, zb - 0.2, zb + 1.8, BODY, 2)
		decal(m, B, 0.1, 0.9, 0.15, 0.85, GLASS)
		parts.append(m)
	wheels(parts, hw, ys, r, 2.3 if suv else 2.1, HUB, 5)
	return parts


## 둥근 지붕: 아래 사각형(z0)에서 inset만큼 안으로 좁아지며 dz 올라가는 낮은 덮개.
## 상자 위에 얹으면 지붕 모서리가 둥글게 꺾여 보인다 (평평한 윗면만 있으면 잘린 상자처럼 보인다)
static func crown(x0: float, x1: float, y0: float, y1: float, z0: float, dz: float, inset: float, color: Variant,
		layer := 1, bevel := 2.0, front_inset := -1.0) -> Part:
	var fi := inset if front_inset < 0.0 else front_inset
	return hull(x0, x1, y0, y1, z0, x0 + inset, x1 - inset, y0 + fi, y1 - inset, z0 + dz, color, layer, bevel)


## 트럭 캡(캡오버): 둘러싼 앞유리·차양·그릴·등화·범퍼, 문 창·문틈·손잡이·발판, 팔 달린 거울, 지붕 표시등. 뒤쪽은 차대
static func _cab(parts: Array, w: float, l: float, cab_len: float, height: float, color: Variant = BODY) -> float:
	var hw := w * 0.5
	var hl := l * 0.5
	var body_top := height - 2.4
	var cab := hull(-hw, hw, -hl, -hl + cab_len, 3.0, -hw * 0.97, hw * 0.97, -hl + 2.5, -hl + cab_len, body_top, color, 1, 2.2)
	decal(cab, F, 0.0, 1.0, 0.0, 0.17, [DARK, -0.12])                 # 범퍼
	decal(cab, F, 0.42, 0.58, 0.03, 0.13, PLATE)
	decal(cab, F, 0.26, 0.74, 0.21, 0.44, DARK)                       # 그릴
	for k in 3:
		decal(cab, F, 0.28, 0.72, 0.25 + k * 0.06, 0.27 + k * 0.06, [DARK, -0.3])
	decal(cab, F, 0.02, 0.22, 0.21, 0.33, HEAD)
	decal(cab, F, 0.78, 0.98, 0.21, 0.33, HEAD)
	decal(cab, F, 0.0, 1.0, 0.5, 0.95, GLASS)                         # 앞유리
	decal(cab, F, 0.49, 0.51, 0.5, 0.95, color)                       # 가운데 기둥
	decal_uv(cab, F, [Vector2(0.14, 0.53), Vector2(0.22, 0.53), Vector2(0.34, 0.92), Vector2(0.26, 0.92)], GLINT)
	decal_uv(cab, F, [Vector2(0.62, 0.53), Vector2(0.66, 0.53), Vector2(0.78, 0.92), Vector2(0.74, 0.92)], GLINT)
	for c in [FRC, FLC]:
		decal(cab, c, 0.0, 1.0, 0.5, 0.95, GLASS)                     # 감싼 앞유리
		decal(cab, c, 0.0, 1.0, 0.21, 0.31, AMBER)
		decal(cab, c, 0.0, 1.0, 0.0, 0.17, [DARK, -0.12])
	sides(cab, 0.1, 0.62, 0.5, 0.93, GLASS)                           # 문 창
	sides(cab, 0.0, 1.0, 0.0, 0.11, DARK)
	sides(cab, 0.7, 0.72, 0.12, 0.92, [color, 0.35])                  # 문틈
	sides(cab, 0.5, 0.62, 0.42, 0.46, CHROME)                         # 손잡이
	sides(cab, 0.12, 0.42, 0.03, 0.1, STEEL)                          # 발판
	parts.append(cab)
	var roof := crown(-hw * 0.97, hw * 0.97, -hl + 2.5, -hl + cab_len, body_top, 2.4, 1.8, color, 2, 2.6, 2.4)
	decal(roof, F, 0.0, 1.0, 0.0, 1.0, [color, 0.3])                  # 차양
	parts.append(roof)
	for side: int in [-1, 1]:
		var x0: float = side * hw
		parts.append(bar(Vector3(x0, -hl + 4.0, height * 0.82), Vector3(x0 + side * 3.0, -hl + 1.5, height * 0.82), 0.7, 0.7, DARK, 2))
		var mx := x0 + side * 3.0
		var m := box(minf(mx, mx + side * 1.4), maxf(mx, mx + side * 1.4), -hl + 1.0, -hl + 2.2, height * 0.45, height * 0.88, DARK, 2)
		decal(m, B, 0.12, 0.88, 0.06, 0.94, GLASS)
		parts.append(m)
	for k in 3:
		var x := (k - 1) * hw * 0.35
		parts.append(box(x - 1.2, x + 1.2, -hl + 3.0, -hl + 4.4, height, height + 0.9, AMBER, 3))
	parts.append(box(-hw * 0.8, hw * 0.8, -hl + cab_len, hl, 2.0, 4.5, DARK, 0))
	return -hl + cab_len


## 짐칸 뒷면 후미등·반사판
static func _rear_lights(p: Part) -> void:
	decal(p, B, 0.03, 0.14, 0.03, 0.12, TAIL)
	decal(p, B, 0.86, 0.97, 0.03, 0.12, TAIL)
	decal(p, B, 0.15, 0.2, 0.04, 0.1, REVERSE)
	decal(p, B, 0.8, 0.85, 0.04, 0.1, REVERSE)


## 바퀴 사이 옆 가드(난간)와 왼쪽 연료통
static func _underside(parts: Array, hw: float, y0: float, y1: float, tank := true) -> void:
	if y1 - y0 < 6.0:
		return
	for side: int in [-1, 1]:
		var x: float = side * (hw - 0.6)
		parts.append(box(x - 0.5, x + 0.5, y0, y1, 3.6, 4.6, STEEL, 1))
		parts.append(box(x - 0.5, x + 0.5, y0, y1, 6.0, 7.0, STEEL, 1))
	if tank and y1 - y0 > 14.0:
		var x := -hw + 3.2
		parts.append(cyl(Vector3(x, y0 + 2.0, 5.2), Vector3(x, y0 + 12.0, 5.2), 2.8, 2.8, Vector3(1, 0, 0), Vector3(0, 0, 1), 8, CHROME, 1))


## 화물 상자 옆 반사띠 (빨강·흰색 번갈아)
static func _reflect(p: Part) -> void:
	for k in 8:
		sides(p, k / 8.0 + 0.005, (k + 1) / 8.0 - 0.005, 0.02, 0.07, REFLECT if k % 2 == 0 else WHITE)


## 1톤 트럭: 캡 + 낮은 적재함(바닥·옆판·앞판·뒷문, 문 경첩)
static func _flatbed(w: float, l: float, h: float) -> Array:
	var hw := w * 0.5
	var hl := l * 0.5
	var parts: Array = []
	var start := _cab(parts, w, l, l * 0.34, h)
	var floor := box(-hw, hw, start + 1.0, hl, 4.5, 6.5, STEEL, 1)
	parts.append(floor)
	var front := box(-hw, hw, start + 1.0, start + 2.5, 6.5, h * 0.78, BODY, 2)
	for k in 4:
		decal(front, B, 0.1, 0.9, 0.2 + k * 0.18, 0.24 + k * 0.18, [BODY, 0.3])   # 망 가드
	parts.append(front)
	for side: int in [-1, 1]:
		var x0: float = hw - 1.4 if side > 0 else -hw
		var gate := box(x0, x0 + 1.4, start + 2.5, hl - 1.4, 6.5, 12.5, BODY, 2)
		sides(gate, 0.0, 1.0, 0.42, 0.5, [BODY, 0.25])
		sides(gate, 0.495, 0.505, 0.0, 1.0, [BODY, 0.35])
		parts.append(gate)
	var tail := box(-hw, hw, hl - 1.4, hl, 6.5, 12.5, BODY, 2)
	decal(tail, B, 0.0, 1.0, 0.42, 0.5, [BODY, 0.25])
	decal(tail, B, 0.4, 0.6, 0.55, 0.85, PLATE)
	parts.append(tail)
	var lights := box(-hw, hw, hl - 1.2, hl, 3.5, 6.5, DARK, 1)
	_rear_lights(lights)
	parts.append(lights)
	var ys := [-hl + l * 0.18, l * 0.3]
	_underside(parts, hw, ys[0] + 6.5, ys[1] - 6.5)
	wheels(parts, hw, ys, 5.0, 2.4, STEEL, 0)
	return parts


## 탑차·화물차: 캡 + 높은 화물 상자 (뒷문 두 짝·잠금 막대, 옆 골, 반사띠, 위 테두리)
static func _box_truck(w: float, l: float, h: float) -> Array:
	var hw := w * 0.5
	var hl := l * 0.5
	var parts: Array = []
	var cab_len := minf(l * 0.3, 24.0)
	var start := _cab(parts, w, l, cab_len, h * 0.8)
	var cargo := box(-hw, hw, start + 1.5, hl, 4.5, h - 1.2, ACCENT)
	decal(cargo, B, 0.03, 0.49, 0.06, 0.95, [ACCENT, 0.1])
	decal(cargo, B, 0.51, 0.97, 0.06, 0.95, [ACCENT, 0.1])
	for u in [0.16, 0.36, 0.64, 0.84]:
		decal(cargo, B, u - 0.012, u + 0.012, 0.08, 0.93, STEEL)          # 잠금 막대
	for v in [0.2, 0.8]:
		decal(cargo, B, 0.0, 0.03, v - 0.04, v + 0.04, STEEL)             # 경첩
		decal(cargo, B, 0.97, 1.0, v - 0.04, v + 0.04, STEEL)
	_rear_lights(cargo)
	var ribs := maxi(5, int(l / 12.0))
	for k in range(1, ribs):
		sides(cargo, float(k) / ribs - 0.006, float(k) / ribs + 0.006, 0.08, 0.95, [ACCENT, 0.18])
	sides(cargo, 0.0, 1.0, 0.95, 1.0, [ACCENT, 0.3])
	_reflect(cargo)
	parts.append(cargo)
	parts.append(crown(-hw, hw, start + 1.5, hl, h - 1.2, 1.2, 0.9, [ACCENT, -0.08], 2, 0.0))
	var ys := [-hl + cab_len * 0.55, l * 0.3]
	if l > 100.0:
		ys.append(l * 0.41)
	_underside(parts, hw, ys[0] + 7.0, ys[1] - 7.0)
	wheels(parts, hw, ys, 5.5, 2.6, STEEL, 0)
	return parts


## 유조차: 캡 + 누운 원통 탱크 (앞 흰색, 뒤 주황, 테 두 줄), 위 통로·맨홀, 뒤 사다리
static func _tanker(w: float, l: float, h: float) -> Array:
	var hw := w * 0.5
	var hl := l * 0.5
	var parts: Array = []
	var start := _cab(parts, w, l, l * 0.24, h)
	var r := hw * 0.92
	var zc := 4.5 + r
	var mid := lerpf(start + 2.0, hl, 0.6)
	var u := Vector3(1, 0, 0)
	var v := Vector3(0, 0, 1)
	var front := cyl(Vector3(0, start + 2.0, zc), Vector3(0, mid, zc), r, r, u, v, 14, ACCENT)
	band(front, 14, 0.48, 0.54, [ACCENT, 0.25])
	parts.append(front)
	var rear := cyl(Vector3(0, mid, zc), Vector3(0, hl - 1.0, zc), r, r, u, v, 14, ORANGE)
	band(rear, 14, 0.46, 0.54, [ORANGE, 0.3])
	parts.append(rear)
	parts.append(box(-2.4, 2.4, start + 4.0, hl - 3.0, zc + r, zc + r + 0.8, STEEL, 3))     # 통로
	for k in 3:
		var y := lerpf(start + 8.0, hl - 8.0, k / 2.0)
		parts.append(cyl(Vector3(0, y, zc + r), Vector3(0, y, zc + r + 1.8), 2.2, 2.2, u, Vector3(0, 1, 0), 8, STEEL, 4))
	for side: int in [-1, 1]:
		parts.append(box(side * 2.0 - 0.4, side * 2.0 + 0.4, hl - 1.0, hl + 0.2, 4.5, zc + r, DARK, 3))   # 사다리
	for k in 4:
		parts.append(box(-2.0, 2.0, hl - 0.6, hl + 0.2, 6.0 + k * 3.5, 6.6 + k * 3.5, DARK, 3))
	var bumper := box(-hw * 0.8, hw * 0.8, hl - 1.5, hl, 2.5, 4.5, DARK, 1)
	_rear_lights(bumper)
	parts.append(bumper)
	var ys := [-hl + l * 0.13, l * 0.25, l * 0.38]
	_underside(parts, hw, ys[0] + 7.0, ys[1] - 7.0)
	wheels(parts, hw, ys, 5.5, 2.6, STEEL, 0)
	return parts


## 청소차: 캡 + 압착 적재함(골) + 뒤 투입구(노랑·검정 경고 띠)
static func _garbage(w: float, l: float, h: float) -> Array:
	var hw := w * 0.5
	var hl := l * 0.5
	var parts: Array = []
	var start := _cab(parts, w, l, l * 0.26, h * 0.82)
	var body := hull(-hw, hw, start + 1.5, hl - 7.0, 4.5, -hw * 0.94, hw * 0.94, start + 2.5, hl - 11.0, h, BODY, 1, 1.6)
	for k in range(1, 6):
		sides(body, k / 6.0 - 0.012, k / 6.0 + 0.012, 0.06, 0.94, [BODY, 0.2])
	sides(body, 0.0, 1.0, 0.0, 0.07, [BODY, 0.35])
	sides(body, 0.04, 0.96, 0.7, 0.76, [BODY, -0.18])
	parts.append(body)
	var hopper := hull(-hw * 0.95, hw * 0.95, hl - 7.0, hl, 3.5, -hw * 0.9, hw * 0.9, hl - 8.0, hl - 2.0, h * 0.78, [BODY, 0.25], 1, 1.2)
	for k in 6:
		decal(hopper, B, k / 6.0, (k + 1) / 6.0, 0.04, 0.2, HAZARD if k % 2 == 0 else DARK)
	decal(hopper, B, 0.14, 0.86, 0.32, 0.86, DARK)
	_rear_lights(hopper)
	parts.append(hopper)
	var ys := [-hl + l * 0.15, l * 0.3]
	_underside(parts, hw, ys[0] + 7.0, ys[1] - 7.0)
	wheels(parts, hw, ys, 5.6, 2.6, STEEL, 0)
	return parts


## 레미콘: 캡 + 뒤로 들린 원뿔 드럼(나선 무늬) + 드럼 받침 + 물탱크 + 뒤 배출 홈통
static func _mixer(w: float, l: float, h: float) -> Array:
	var hw := w * 0.5
	var hl := l * 0.5
	var parts: Array = []
	var start := _cab(parts, w, l, l * 0.25, h)
	var u := Vector3(1, 0, 0)
	var v := Vector3(0, 0, 1)
	parts.append(cyl(Vector3(0, start + 3.0, 6.0 + hw * 0.85), Vector3(0, hl - 4.0, 10.0 + hw * 0.55), hw * 0.88, hw * 0.5,
		u, v, 14, ACCENT, 2, ORANGE))
	parts.append(cyl(Vector3(0, hl - 4.0, 10.0 + hw * 0.55), Vector3(0, hl - 1.5, 11.0 + hw * 0.55), hw * 0.42, hw * 0.3,
		u, v, 10, [ACCENT, 0.2], 2))
	parts.append(cyl(Vector3(0, start + 1.0, 8.0 + hw * 0.6), Vector3(0, start + 3.5, 8.0 + hw * 0.6), hw * 0.55, hw * 0.55,
		u, v, 10, CHROME, 1))                                       # 물탱크
	parts.append(box(-hw * 0.6, hw * 0.6, start + 0.5, start + 3.0, 4.5, 6.0 + hw * 1.3, DARK, 1))
	parts.append(box(-hw * 0.5, hw * 0.5, hl - 6.0, hl - 3.5, 4.5, 9.0 + hw * 0.4, DARK, 1))
	parts.append(bar(Vector3(0, hl - 2.0, 10.0), Vector3(0, hl + 2.5, 6.0), 3.0, 0.8, ORANGE, 3))   # 홈통
	for side: int in [-1, 1]:
		parts.append(box(side * hw * 0.62 - 0.4, side * hw * 0.62 + 0.4, hl - 3.0, hl - 2.2, 4.5, 16.0 + hw * 0.4, DARK, 1))
	var ys := [-hl + l * 0.14, l * 0.24, l * 0.38]
	_underside(parts, hw, ys[0] + 7.0, ys[1] - 7.0)
	wheels(parts, hw, ys, 5.6, 2.6, STEEL, 0)
	return parts


## 소방차: 캡(경광등 막대) + 수납함 차체(은색 셔터, 흰 줄) + 지붕 사다리(난간·발판) + 뒤 호스 릴
static func _fire(w: float, l: float, h: float) -> Array:
	var hw := w * 0.5
	var hl := l * 0.5
	var parts: Array = []
	var start := _cab(parts, w, l, l * 0.24, h)
	parts.append(box(-hw * 0.7, hw * 0.7, -hl + 4.5, -hl + 9.0, h, h + 0.9, DARK, 3))
	for k in 4:
		var x0 := -hw * 0.68 + k * hw * 0.34
		parts.append(box(x0, x0 + hw * 0.32, -hl + 4.9, -hl + 8.6, h + 0.9, h + 3.0, SIREN_R if k % 2 == 0 else [SIREN_R, 0.3], 4))
	var body := box(-hw, hw, start + 1.0, hl, 4.0, h + 2.0, BODY, 1, 1.2)
	for k in 3:
		var u0 := k / 3.0 + 0.03
		var u1 := (k + 1) / 3.0 - 0.03
		sides(body, u0, u1, 0.2, 0.86, ACCENT)
		for s in 4:
			sides(body, u0, u1, 0.3 + s * 0.15, 0.32 + s * 0.15, [ACCENT, 0.22])     # 셔터 줄
		sides(body, lerpf(u0, u1, 0.42), lerpf(u0, u1, 0.58), 0.22, 0.26, DARK)    # 손잡이
	sides(body, 0.0, 1.0, 0.1, 0.17, WHITE)
	sides(body, 0.0, 1.0, 0.0, 0.08, CHROME)
	decal(body, B, 0.2, 0.8, 0.2, 0.86, ACCENT)
	for s in 5:
		decal(body, B, 0.2, 0.8, 0.3 + s * 0.11, 0.32 + s * 0.11, [ACCENT, 0.22])
	_rear_lights(body)
	parts.append(body)
	# 사다리: 두 난간 + 발판, 앞쪽은 받침대
	for side: int in [-1, 1]:
		parts.append(box(side * hw * 0.5 - 1.0, side * hw * 0.5 + 1.0, start - 9.0, hl - 2.0, h + 3.0, h + 5.0, CHROME, 3))
		parts.append(box(side * hw * 0.5 - 0.6, side * hw * 0.5 + 0.6, start + 2.0, start + 4.0, h + 2.0, h + 3.0, DARK, 3))
		parts.append(box(side * hw * 0.5 - 0.6, side * hw * 0.5 + 0.6, hl - 6.0, hl - 4.0, h + 2.0, h + 3.0, DARK, 3))
	var y := start - 7.0
	while y < hl - 3.0:
		parts.append(box(-hw * 0.5, hw * 0.5, y, y + 1.0, h + 3.4, h + 4.4, [CHROME, 0.25], 3))
		y += 5.0
	parts.append(cyl(Vector3(-hw * 0.6, hl - 0.5, h - 4.0), Vector3(hw * 0.6, hl - 0.5, h - 4.0), 3.5, 3.5,
		Vector3(0, 1, 0), Vector3(0, 0, 1), 10, [ACCENT, 0.3], 2))                 # 호스 릴
	var ys := [-hl + l * 0.13, l * 0.3]
	wheels(parts, hw, ys, 6.0, 2.8, CHROME, 0)
	return parts


## 견인차: 캡 + 낮은 데크(공구함) + 뒤로 솟은 붐과 쇠줄·고리 + 바퀴 들어올림 팔 + 주황 경광등
static func _tow(w: float, l: float, h: float) -> Array:
	var hw := w * 0.5
	var hl := l * 0.5
	var parts: Array = []
	var start := _cab(parts, w, l, l * 0.32, h)
	parts.append(box(-hw * 0.7, hw * 0.7, -hl + 6.0, -hl + 10.5, h, h + 0.8, DARK, 3))
	parts.append(box(-hw * 0.66, -0.8, -hl + 6.4, -hl + 10.1, h + 0.8, h + 2.8, BEACON, 4))
	parts.append(box(0.8, hw * 0.66, -hl + 6.4, -hl + 10.1, h + 0.8, h + 2.8, BEACON, 4))
	var deck := box(-hw, hw, start + 1.0, hl - 2.0, 4.5, 8.0, ACCENT, 1, 1.0)
	sides(deck, 0.04, 0.4, 0.15, 0.85, [ACCENT, -0.15])                            # 공구함
	sides(deck, 0.21, 0.23, 0.15, 0.85, DARK)
	sides(deck, 0.0, 1.0, 0.0, 0.1, HAZARD)
	parts.append(deck)
	parts.append(box(-hw * 0.6, hw * 0.6, hl - 18.0, hl - 10.0, 8.0, 12.5, BODY, 2, 1.0))     # 붐 받침
	parts.append(bar(Vector3(0, hl - 14.0, 12.0), Vector3(0, hl - 3.0, h + 10.0), 3.2, 3.2, BODY, 3))
	parts.append(bar(Vector3(0, hl - 2.4, h + 9.0), Vector3(0, hl - 2.4, 9.0), 0.5, 0.5, DARK, 3))   # 쇠줄
	parts.append(box(-1.2, 1.2, hl - 3.4, hl - 1.4, 7.5, 9.5, STEEL, 3))                # 고리
	parts.append(box(-hw * 0.75, hw * 0.75, hl - 2.5, hl + 1.5, 2.5, 4.5, DARK, 1))     # 바퀴 들어올림 팔
	var lights := box(-hw * 0.9, hw * 0.9, hl - 2.5, hl - 2.0, 4.5, 7.0, DARK, 1)
	_rear_lights(lights)
	parts.append(lights)
	wheels(parts, hw, [-hl + l * 0.17, l * 0.3], 5.6, 2.6, STEEL, 0)
	return parts


## 군 트럭: 국방색 캡 + 천막 짐칸 (늑골 줄, 뒤 덮개) + 캡 뒤 예비 타이어
static func _army(w: float, l: float, h: float) -> Array:
	var hw := w * 0.5
	var hl := l * 0.5
	var parts: Array = []
	var start := _cab(parts, w, l, l * 0.28, h * 0.84)
	var bed := box(-hw, hw, start + 1.5, hl, 4.5, 8.0, BODY, 1)
	_rear_lights(bed)
	parts.append(bed)
	var canvas := hull(-hw, hw, start + 1.5, hl, 8.0, -hw * 0.88, hw * 0.88, start + 2.5, hl, h, ACCENT, 1, 2.0)
	for k in range(1, 6):
		sides(canvas, k / 6.0 - 0.012, k / 6.0 + 0.012, 0.0, 1.0, [ACCENT, 0.25])
	sides(canvas, 0.0, 1.0, 0.0, 0.06, [ACCENT, 0.35])
	decal(canvas, B, 0.06, 0.94, 0.05, 0.9, [ACCENT, 0.18])
	for u in [0.25, 0.5, 0.75]:
		decal(canvas, B, u - 0.01, u + 0.01, 0.05, 0.9, [ACCENT, 0.4])
	parts.append(canvas)
	parts.append(cyl(Vector3(-2.0, start + 0.5, h * 0.84 - 3.0), Vector3(2.0, start + 0.5, h * 0.84 - 3.0), 4.0, 4.0,
		Vector3(0, 1, 0), Vector3(0, 0, 1), 10, TIRE, 2))
	var ys := [-hl + l * 0.16, l * 0.25, l * 0.38]
	wheels(parts, hw, ys, 6.0, 2.8, [BODY, 0.1], 0)
	return parts


## 자주포 (K9식 곡사포 장갑차): 무한궤도(궤도 띠·보기륜·구동륜·옆 덮개) + 낮은 차체(경사진 앞판·조종수 해치·전조등·뒤 배기) +
## 큰 포탑(앞이 좁아지는 상자·지휘관 해치·기관총·연막탄 발사기·뒤 짐 바구니, 포탑 = Vehicle.turret으로 돈다) +
## 긴 포신(방패·배연기·포구 제퇴기, Vehicle.elevation만큼 들리고 쏘면 뒤로 밀린다). 국방색 바탕에 짙은 얼룩무늬
static func _spg(w: float, l: float, h: float) -> Array:
	var hw := w * 0.5
	var hl := l * 0.5
	var parts: Array = []
	var u := Vector3(1, 0, 0)
	var v := Vector3(0, 0, 1)
	var tw := 9.0                       # 궤도 폭
	# 무한궤도: 아래가 짧은 띠(앞뒤가 비스듬) + 보기륜 6쌍 + 앞 구동륜·뒤 유도륜 + 위 옆 덮개
	for side: int in [-1, 1]:
		var x0 := side * hw
		var x1 := side * (hw - tw)
		var xa := minf(x0, x1)
		var xb := maxf(x0, x1)
		var belt := hull(xa, xb, -hl + 5.0, hl - 4.0, 0.0, xa, xb, -hl, hl, 8.0, TIRE, 1)
		for k in 14:
			sides(belt, k / 14.0, k / 14.0 + 0.025, 0.0, 1.0, SIDEWALL)    # 궤도 마디
		parts.append(belt)
		for k in 6:
			var y := lerpf(-hl * 0.7, hl * 0.66, k / 5.0)
			parts.append(wheel(side * (hw - 0.9), y, 3.4, 0.5, side, [BODY, 0.25], 0))
		parts.append(wheel(side * (hw - 0.9), -hl + 4.5, 3.8, 0.5, side, DARK, 6))
		parts.append(wheel(side * (hw - 0.9), hl - 4.5, 3.6, 0.5, side, DARK, 0))
		var skirt := box(xa - 0.3, xb + 0.3, -hl + 3.0, hl - 2.0, 7.4, 10.0, BODY, 2, 0.6)
		decal(skirt, R if side > 0 else L, 0.2, 0.42, 0.0, 1.0, CAMO)
		parts.append(skirt)
	# 차체: 궤도 사이 아래 몸통 + 위 갑판 + 경사진 앞판
	parts.append(box(-hw + tw, hw - tw, -hl + 4.0, hl - 2.0, 2.0, 10.0, [BODY, 0.2], 1))
	var deck := box(-hw + 0.5, hw - 0.5, -hl + 12.0, hl, 10.0, 13.0, BODY, 2, 1.0)
	top_rect(deck, -hw + 3.0, hw - 3.0, hl - 9.0, hl - 2.0, DARK)             # 뒤 배기 그릴
	for k in 4:
		top_rect(deck, -hw + 4.0 + k * 3.2, -hw + 5.4 + k * 3.2, hl - 8.0, hl - 3.0, [DARK, -0.15])
	decal(deck, B, 0.1, 0.9, 0.15, 0.85, [BODY, 0.2])
	decal(deck, B, 0.1, 0.2, 0.3, 0.7, TAIL)
	decal(deck, B, 0.8, 0.9, 0.3, 0.7, TAIL)
	parts.append(deck)
	var glacis := hull(-hw + 0.5, hw - 0.5, -hl, -hl + 6.0, 6.0, -hw + 0.5, hw - 0.5, -hl + 9.0, -hl + 12.5, 13.0, BODY, 2)
	decal(glacis, F, 0.08, 0.2, 0.1, 0.35, HEAD)                              # 전조등
	decal(glacis, F, 0.8, 0.92, 0.1, 0.35, HEAD)
	decal(glacis, T, 0.15, 0.4, 0.2, 0.8, CAMO)
	decal(glacis, T, 0.6, 0.85, 0.3, 0.7, CAMO)
	parts.append(glacis)
	var hatch := box(-hw + 4.0, -hw + 11.0, -hl + 13.0, -hl + 19.0, 13.0, 14.0, [BODY, 0.15], 3, 1.0)
	decal(hatch, F, 0.2, 0.8, 0.2, 0.8, GLASS)                                # 조종수 잠망경
	parts.append(hatch)
	# 포탑 (축 axis_y): 큰 상자, 앞이 좁아진다
	var ay := 6.0
	var turret := hull(-hw + 2.5, hw - 2.5, ay - 18.0, ay + 24.0, 13.0, -hw + 4.0, hw - 4.0, ay - 14.0, ay + 23.0, h, BODY, 3, 3.0)
	decal(turret, R, 0.15, 0.4, 0.15, 0.7, CAMO)
	decal(turret, L, 0.55, 0.85, 0.3, 0.85, CAMO)
	decal(turret, T, 0.1, 0.45, 0.55, 0.9, CAMO)
	decal(turret, T, 0.6, 0.9, 0.1, 0.35, CAMO)
	decal(turret, R, 0.55, 0.75, 0.5, 0.75, [BODY, 0.2])                      # 옆 문
	parts.append(turret)
	var cupola := cyl(Vector3(hw - 9.0, ay - 2.0, h), Vector3(hw - 9.0, ay - 2.0, h + 2.2), 3.2, 3.0, u, Vector3(0, 1, 0), 8, [BODY, 0.1], 4)
	parts.append(cupola)
	parts.append(box(-hw + 6.0, -hw + 12.0, ay + 2.0, ay + 8.0, h, h + 1.0, [BODY, 0.15], 4, 1.0))   # 해치
	parts.append(bar(Vector3(hw - 9.0, ay - 2.0, h + 3.0), Vector3(hw - 9.0, ay - 12.0, h + 3.6), 0.9, 0.9, DARK, 4))   # 기관총
	for side: int in [-1, 1]:                                                 # 연막탄 발사기
		parts.append(box(side * (hw - 6.0) - 2.0, side * (hw - 6.0) + 2.0, ay - 16.0, ay - 12.0, h - 5.0, h - 1.5, DARK, 3))
	for k in 3:                                                               # 뒤 짐 바구니
		parts.append(bar(Vector3(-hw + 4.0, ay + 24.0 + k * 1.8, h - 4.0 + k), Vector3(hw - 4.0, ay + 24.0 + k * 1.8, h - 4.0 + k), 0.6, 0.6, DARK, 3))
	parts.append(box(-hw + 5.0, hw - 5.0, ay + 23.5, ay + 28.0, h - 6.0, h - 2.5, [ACCENT, 0.1], 3))
	for p in parts.slice(parts.find(turret)):
		p.turret = 1
		p.axis_y = ay
	# 포신 (포이 축 trunnion): 방패 + 긴 포신 + 배연기 + 포구 제퇴기
	var ty := ay - 16.0
	var tz := h - 4.0
	var gun: Array = []
	gun.append(box(-5.0, 5.0, ty - 5.0, ty + 1.0, tz - 4.5, tz + 4.5, BODY, 3, 1.4))
	var barrel := cyl(Vector3(0, ty - 4.0, tz), Vector3(0, ty - 4.0 - l * 0.62, tz), 2.0, 1.6, u, v, 10, [BODY, 0.08], 3)
	gun.append(barrel)
	gun.append(cyl(Vector3(0, ty - 4.0 - l * 0.26, tz), Vector3(0, ty - 4.0 - l * 0.32, tz), 2.6, 2.6, u, v, 10, [BODY, 0.15], 3))
	gun.append(cyl(Vector3(0, ty - l * 0.62 - 2.0, tz), Vector3(0, ty - l * 0.62 - 7.0, tz), 2.9, 2.9, u, v, 10, DARK, 3))
	for p: Part in gun:
		p.turret = 2
		p.axis_y = ay
		p.trunnion = Vector2(ty, tz)
	parts.append_array(gun)
	return parts


## 군 소형 전술차량: 각진 국방색 차체(보닛·짧은 경사 앞유리·작은 옆 창·문틈) + 지붕 기관총 거치대(포탑 = Vehicle.turret으로 돈다) +
## 앞 범퍼 가드·전조등 + 뒤 예비 타이어·짐칸 + 큰 바퀴 넷. 얼룩무늬
static func _jeep(w: float, l: float, h: float) -> Array:
	var hw := w * 0.5
	var hl := l * 0.5
	var parts: Array = []
	var hood := hull(-hw, hw, -hl + 1.0, -hl + l * 0.32, 4.0, -hw + 1.0, hw - 1.0, -hl + 2.0, -hl + l * 0.32, h * 0.52, BODY, 1, 1.6)
	decal(hood, F, 0.06, 0.94, 0.1, 0.45, DARK)                                # 그릴
	decal(hood, F, 0.08, 0.24, 0.55, 0.85, HEAD)
	decal(hood, F, 0.76, 0.92, 0.55, 0.85, HEAD)
	decal(hood, T, 0.15, 0.55, 0.2, 0.7, CAMO)
	parts.append(hood)
	var cabin := hull(-hw, hw, -hl + l * 0.3, hl, 4.0, -hw + 1.5, hw - 1.5, -hl + l * 0.4, hl - 1.0, h - 2.0, BODY, 1, 1.6)
	decal(cabin, F, 0.08, 0.92, 0.5, 0.95, GLASS)
	sides(cabin, 0.06, 0.28, 0.55, 0.92, GLASS)
	sides(cabin, 0.34, 0.54, 0.55, 0.92, GLASS)
	sides(cabin, 0.31, 0.32, 0.1, 0.95, [BODY, 0.35])                          # 문틈
	sides(cabin, 0.57, 0.58, 0.1, 0.95, [BODY, 0.35])
	sides(cabin, 0.62, 0.9, 0.1, 0.45, CAMO)
	decal(cabin, B, 0.1, 0.3, 0.6, 0.85, TAIL)
	decal(cabin, B, 0.7, 0.9, 0.6, 0.85, TAIL)
	parts.append(cabin)
	parts.append(crown(-hw + 1.5, hw - 1.5, -hl + l * 0.4, hl - 1.0, h - 2.0, 1.6, 1.0, [BODY, 0.1], 2, 1.2))
	parts.append(box(-hw - 0.5, hw + 0.5, -hl - 1.5, -hl + 1.0, 3.0, 6.0, DARK, 1))     # 범퍼 가드
	var spare := cyl(Vector3(0, hl, 9.0), Vector3(0, hl + 2.4, 9.0), 4.6, 4.6, Vector3(1, 0, 0), Vector3(0, 0, 1), 12, TIRE, 2)
	spare.colors[13] = SIDEWALL
	parts.append(spare)
	# 지붕 기관총 거치대 (포탑, 축 y 6)
	var ay := l * 0.1
	var gun: Array = []
	gun.append(cyl(Vector3(0, ay, h - 0.4), Vector3(0, ay, h + 1.0), 5.0, 5.0, Vector3(1, 0, 0), Vector3(0, 1, 0), 10, DARK, 3))
	gun.append(box(-3.4, 3.4, ay - 2.0, ay + 1.0, h + 1.0, h + 5.0, [BODY, 0.1], 3, 0.6))   # 방패
	gun.append(box(-1.2, 1.2, ay - 1.0, ay + 4.0, h + 2.0, h + 3.6, DARK, 3))
	gun.append(bar(Vector3(0, ay - 1.0, h + 3.0), Vector3(0, ay - 14.0, h + 3.2), 0.9, 0.9, DARK, 3))
	for p: Part in gun:
		p.turret = 1
		p.axis_y = ay
	parts.append_array(gun)
	wheels(parts, hw + 0.6, [-hl + l * 0.17, hl - l * 0.18], 6.0, 2.6, [BODY, 0.2], 0)
	return parts


## 버스: 긴 상자(모서리 깎음) + 검은 창 띠·기둥 + 앞문·가운데 문 + 앞 행선지 표시 + 거울 팔 + 지붕 냉방기
static func _bus(w: float, l: float, h: float, express: bool) -> Array:
	var hw := w * 0.5
	var hl := l * 0.5
	var parts: Array = []
	var zt := h - 2.8
	var body := hull(-hw, hw, -hl, hl, 3.0, -hw * 0.98, hw * 0.98, -hl + 2.0, hl, zt, BODY, 1, 2.6)
	# 앞: 큰 유리(가운데 기둥) · 행선지 LED · 등화 · 범퍼 · 번호판
	decal(body, F, 0.0, 1.0, 0.36, 0.84, GLASS)
	decal(body, F, 0.49, 0.51, 0.36, 0.84, BODY)
	decal_uv(body, F, [Vector2(0.12, 0.4), Vector2(0.2, 0.4), Vector2(0.32, 0.8), Vector2(0.24, 0.8)], GLINT)
	decal(body, F, 0.08, 0.92, 0.86, 0.96, DARK)
	decal(body, F, 0.14, 0.62, 0.89, 0.93, ORANGE)
	decal(body, F, 0.7, 0.86, 0.88, 0.94, [ORANGE, -0.2])
	decal(body, F, 0.0, 1.0, 0.0, 0.12, [DARK, -0.1])
	decal(body, F, 0.03, 0.17, 0.14, 0.24, HEAD)
	decal(body, F, 0.83, 0.97, 0.14, 0.24, HEAD)
	decal(body, F, 0.4, 0.6, 0.02, 0.11, PLATE)
	for c in [FRC, FLC]:
		decal(body, c, 0.0, 1.0, 0.36, 0.84, GLASS)
		decal(body, c, 0.0, 1.0, 0.14, 0.24, AMBER)
	# 뒤: 유리 · 엔진 그릴 · 등화
	decal(body, B, 0.1, 0.9, 0.58, 0.86, GLASS)
	decal(body, B, 0.2, 0.8, 0.16, 0.4, DARK)
	for k in 4:
		decal(body, B, 0.22, 0.78, 0.19 + k * 0.05, 0.21 + k * 0.05, [DARK, -0.2])
	decal(body, B, 0.4, 0.6, 0.44, 0.54, PLATE)
	decal(body, B, 0.02, 0.14, 0.08, 0.3, TAIL)
	decal(body, B, 0.86, 0.98, 0.08, 0.3, TAIL)
	for c in [BRC, BLC]:
		decal(body, c, 0.0, 1.0, 0.08, 0.3, TAIL)
	# 옆: 아래 띠 · 검은 창 띠 · 창(기둥 사이) · 문(오른쪽 앞·가운데)
	sides(body, 0.0, 1.0, 0.3, 0.4, ACCENT)
	if express:
		sides(body, 0.0, 1.0, 0.9, 0.97, ACCENT)
	sides(body, 0.0, 1.0, 0.0, 0.08, DARK)
	sides(body, 0.02, 0.98, 0.46, 0.88, DARK)
	var n := maxi(3, int(l / 14.0))
	var door := -1 if l < 80.0 else n / 2
	for k in n:
		var u0 := 0.03 + 0.94 * k / n
		var u1 := 0.03 + 0.94 * (k + 1) / n - 0.018
		if k == 0 or k == door:
			decal(body, R, u0, u1, 0.06, 0.86, DARK)                          # 문 (오른쪽만)
			decal(body, R, u0 + 0.005, (u0 + u1) * 0.5 - 0.004, 0.1, 0.84, GLASS)
			decal(body, R, (u0 + u1) * 0.5 + 0.004, u1 - 0.005, 0.1, 0.84, GLASS)
			decal(body, L, 1.0 - u1, 1.0 - u0, 0.48, 0.86, GLASS)
		else:
			sides(body, u0, u1, 0.48, 0.86, GLASS)
	sides(body, 0.06, 0.12, 0.6, 0.72, [GLINT, 0.2])
	for y in [-l * 0.3, l * 0.3]:
		arch(body, y, 5.8)
	if express:
		arch(body, l * 0.4, 5.8)
	parts.append(body)
	parts.append(crown(-hw * 0.98, hw * 0.98, -hl + 2.0, hl, zt, 2.8, 2.4, BODY, 2, 3.4, 2.0))   # 둥근 지붕
	# 지붕: 냉방기(통풍 줄) · 비상구
	var ac := box(-hw * 0.55, hw * 0.55, -l * 0.12, l * 0.16, h, h + 3.0, ACCENT, 3, 1.5)
	for k in 3:
		top_rect(ac, -hw * 0.4, hw * 0.4, -l * 0.08 + k * l * 0.08, -l * 0.08 + k * l * 0.08 + 1.2, [ACCENT, 0.25])
	parts.append(ac)
	parts.append(box(-hw * 0.3, hw * 0.3, l * 0.27, l * 0.34, h, h + 1.2, [ACCENT, 0.1], 3))
	# 앞으로 뻗은 거울 팔
	for side: int in [-1, 1]:
		var x0: float = side * hw * 0.9
		parts.append(bar(Vector3(x0, -hl + 3.0, h - 3.0), Vector3(x0 + side * 2.5, -hl - 4.0, h - 3.0), 0.8, 0.8, DARK, 2))
		var mx := x0 + side * 2.5
		parts.append(box(minf(mx, mx + side * 1.2), maxf(mx, mx + side * 1.2), -hl - 5.0, -hl - 3.8, h * 0.45, h - 2.5, DARK, 2))
	var ys := [-l * 0.3, l * 0.3]
	if express:
		ys.append(l * 0.4)
	wheels(parts, hw, ys, 5.8, 2.6, STEEL, 0)
	return parts


## 승합(구급차·특공대): 짧은 보닛 + 큰 상자 + 경광등 막대. 구급차는 빨강 띠·초록 십자, 특공대는 선팅·범퍼 가드·지붕 짐대
static func _van(w: float, l: float, h: float, ambulance: bool) -> Array:
	var hw := w * 0.5
	var hl := l * 0.5
	var parts: Array = []
	var hood := hull(-hw, hw, -hl, -hl + l * 0.2, 2.5, -hw * 0.97, hw * 0.97, -hl + 3.0, -hl + l * 0.2, h * 0.46, BODY, 1, 2.6)
	_car_front(hood, ambulance)
	arch(hood, -l * 0.3, 5.4)
	parts.append(hood)
	var glass := GLASS if ambulance else TINT
	var mt := h - 2.0
	var main := hull(-hw, hw, -hl + l * 0.18, hl, 2.5, -hw * 0.95, hw * 0.95, -hl + l * 0.29, hl, mt, BODY, 1, 2.6)
	decal(main, F, 0.02, 0.98, 0.38, 0.93, glass)
	decal_uv(main, F, [Vector2(0.18, 0.42), Vector2(0.28, 0.42), Vector2(0.46, 0.9), Vector2(0.36, 0.9)], GLINT)
	for c in [FRC, FLC]:
		decal(main, c, 0.0, 1.0, 0.38, 0.93, glass)
	decal(main, B, 0.04, 0.49, 0.1, 0.92, [BODY, 0.06])
	decal(main, B, 0.51, 0.96, 0.1, 0.92, [BODY, 0.06])
	decal(main, B, 0.1, 0.43, 0.55, 0.85, glass)
	decal(main, B, 0.57, 0.9, 0.55, 0.85, glass)
	decal(main, B, 0.0, 1.0, 0.0, 0.1, [DARK, -0.1])
	decal(main, B, 0.4, 0.6, 0.12, 0.26, PLATE)
	decal(main, B, 0.02, 0.1, 0.3, 0.6, TAIL)
	decal(main, B, 0.9, 0.98, 0.3, 0.6, TAIL)
	sides(main, 0.04, 0.24, 0.55, 0.86, glass)                         # 운전석 창
	seam(main, -hl + l * 0.42, 3.0, h - 2.0)                           # 앞문 뒤
	seam(main, -hl + l * 0.7, 3.0, h - 2.0)                            # 미닫이문
	arch(main, l * 0.32, 5.4)
	if ambulance:
		sides(main, 0.27, 0.5, 0.6, 0.86, glass)
		sides(main, 0.0, 1.0, 0.3, 0.42, ACCENT)
		for k in 8:
			sides(main, 0.52 + k * 0.06, 0.55 + k * 0.06, 0.24, 0.3, ACCENT)   # 바둑판 무늬
		sides(main, 0.6, 0.84, 0.6, 0.7, CROSS)
		sides(main, 0.68, 0.76, 0.48, 0.84, CROSS)
		var ty := -hl + l * 0.29
		var ly := hl - ty
		top_rect(main, -hw * 0.47, hw * 0.47, ty + ly * 0.55, ty + ly * 0.65, CROSS)    # 지붕 십자
		top_rect(main, -hw * 0.13, hw * 0.13, ty + ly * 0.4, ty + ly * 0.8, CROSS)
	else:
		sides(main, 0.27, 0.6, 0.6, 0.86, glass)
		sides(main, 0.0, 1.0, 0.0, 0.14, [DARK, -0.06])
		sides(main, 0.0, 1.0, 0.45, 0.5, ACCENT)
		for side: int in [-1, 1]:                                          # 지붕 짐대
			parts.append(box(side * hw * 0.75 - 0.6, side * hw * 0.75 + 0.6, -hl + l * 0.45, hl - 3.0, h, h + 1.6, STEEL, 3))
		for k in 3:
			var y := lerpf(-hl + l * 0.45, hl - 3.0, k / 2.0)
			parts.append(box(-hw * 0.75, hw * 0.75, y - 0.5, y + 0.5, h + 1.0, h + 1.8, STEEL, 3))
		for k in 3:                                                   # 범퍼 가드
			parts.append(box(-hw * 0.8, hw * 0.8, -hl - 2.0, -hl - 1.0, 3.0 + k * 2.4, 4.0 + k * 2.4, DARK, 2))
		for side: int in [-1, 1]:
			parts.append(box(side * hw * 0.55 - 0.5, side * hw * 0.55 + 0.5, -hl - 2.0, -hl + 0.5, 2.5, 9.0, DARK, 2))
	parts.append(main)
	parts.append(crown(-hw * 0.95, hw * 0.95, -hl + l * 0.29, hl, mt, 2.0, 1.6, BODY, 2, 2.8, 1.2))
	var y0 := -hl + l * 0.3
	parts.append(box(-hw * 0.72, hw * 0.72, y0, y0 + 5.0, h, h + 0.8, DARK, 3))
	for k in 4:
		var x0 := -hw * 0.7 + k * hw * 0.35
		var col: Variant = SIREN_R if k < 2 else SIREN_B
		parts.append(box(x0, x0 + hw * 0.33, y0 + 0.4, y0 + 4.6, h + 0.8, h + 3.0, col if k % 3 == 0 else [col, 0.25], 4))
	for side: int in [-1, 1]:
		var mx: float = hw - 0.4 if side > 0 else -hw - 1.4
		var m := box(mx, mx + 1.8, -hl + l * 0.2, -hl + l * 0.2 + 1.6, h * 0.5, h * 0.7, DARK, 2)
		parts.append(m)
	wheels(parts, hw, [-l * 0.3, l * 0.32], 5.4, 2.4, HUB if ambulance else DARK, 5 if ambulance else 0)
	return parts


## 캠핑카: 승합 캡 + 운전석 위로 나온 침실 + 거실 상자(창틀·문·띠·차양) + 지붕 냉방기·뒤 사다리
static func _camper(w: float, l: float, h: float) -> Array:
	var hw := w * 0.5
	var hl := l * 0.5
	var parts: Array = []
	var hood := hull(-hw, hw, -hl, -hl + l * 0.2, 2.5, -hw * 0.96, hw * 0.96, -hl + 3.0, -hl + l * 0.2, h * 0.42, ACCENT, 1, 2.6)
	_car_front(hood, false)
	arch(hood, -hl + l * 0.17, 5.4)
	parts.append(hood)
	var cab := hull(-hw, hw, -hl + l * 0.18, -hl + l * 0.3, 2.5, -hw * 0.97, hw * 0.97, -hl + l * 0.26, -hl + l * 0.3, h * 0.7, ACCENT, 1, 2.2)
	decal(cab, F, 0.02, 0.98, 0.3, 0.92, GLASS)
	decal_uv(cab, F, [Vector2(0.2, 0.35), Vector2(0.3, 0.35), Vector2(0.45, 0.88), Vector2(0.35, 0.88)], GLINT)
	for c in [FRC, FLC]:
		decal(cab, c, 0.0, 1.0, 0.3, 0.92, GLASS)
	sides(cab, 0.3, 0.95, 0.45, 0.9, GLASS)
	parts.append(cab)
	var room := box(-hw, hw, -hl + l * 0.3, hl, 3.0, h - 2.0, BODY, 1, 1.6)
	sides(room, 0.0, 1.0, 0.24, 0.29, ACCENT)
	sides(room, 0.0, 1.0, 0.31, 0.34, [ACCENT, -0.3])
	for win in [[0.08, 0.34], [0.6, 0.88]]:
		sides(room, win[0] - 0.015, win[1] + 0.015, 0.47, 0.81, DARK)
		sides(room, win[0], win[1], 0.5, 0.78, GLASS)
	decal(room, R, 0.4, 0.52, 0.05, 0.84, [BODY, 0.12])                   # 출입문
	decal(room, R, 0.425, 0.495, 0.55, 0.78, GLASS)
	decal(room, R, 0.49, 0.51, 0.4, 0.44, CHROME)
	decal(room, B, 0.28, 0.72, 0.5, 0.8, GLASS)
	decal(room, B, 0.0, 1.0, 0.0, 0.1, DARK)
	decal(room, B, 0.4, 0.6, 0.12, 0.25, PLATE)
	_rear_lights(room)
	arch(room, l * 0.3, 5.4)
	parts.append(room)
	var luton := box(-hw, hw, -hl + l * 0.12, -hl + l * 0.3, h * 0.66, h - 2.0, BODY, 2, 1.6)
	decal(luton, F, 0.2, 0.8, 0.3, 0.7, GLASS)
	sides(luton, 0.0, 1.0, 0.0, 0.12, ACCENT)
	parts.append(luton)
	var top := crown(-hw, hw, -hl + l * 0.12, hl, h - 2.0, 2.0, 1.6, BODY, 2, 2.4)
	parts.append(top)
	parts.append(box(hw - 0.2, hw + 1.4, -hl + l * 0.36, hl - 6.0, h - 4.5, h - 2.8, [ACCENT, 0.2], 2))   # 말아 둔 차양
	var ac := box(-hw * 0.45, hw * 0.45, -l * 0.05, l * 0.15, h, h + 2.5, [BODY, 0.1], 3, 1.0)
	top_rect(ac, -hw * 0.3, hw * 0.3, l * 0.0, l * 0.1, [BODY, 0.3])
	parts.append(ac)
	parts.append(box(-hw * 0.3, hw * 0.3, l * 0.25, l * 0.33, h, h + 1.0, GLASS, 3))   # 지붕창
	for x in [-hw * 0.7, 0.0]:                                        # 뒤 사다리
		parts.append(box(x - 0.4, x + 0.4, hl - 0.2, hl + 0.8, 6.0, h, STEEL, 3))
	for k in 5:
		parts.append(box(-hw * 0.7, 0.0, hl + 0.2, hl + 0.8, 8.0 + k * 3.5, 8.6 + k * 3.5, STEEL, 3))
	wheels(parts, hw, [-hl + l * 0.17, l * 0.3], 5.4, 2.4, HUB, 5)
	return parts


## 헬기: 둥근 동체(앞 유리·옆 창·흰 띠) + 꼬리 붐·수직 날개·꼬리 회전날개 + 착륙 썰매 + 주 회전날개 4장.
## o.police: 경찰 헬기 — 연두 띠 하나 더, 엔진 덮개 양옆 경광등(빨강·파랑), 기수 밑 탐조등
static func _heli(w: float, l: float, h: float, o := {}) -> Array:
	var hl := l * 0.5
	var parts: Array = []
	var u := Vector3(1, 0, 0)
	var v := Vector3(0, 0, 1)
	var nose := cyl(Vector3(0, -hl * 0.85, 9.0), Vector3(0, -hl * 0.35, 11.0), 3.0, 9.0, u, v, 12, GLASS, 1)
	for k in 12:
		if k not in [1, 2, 3, 4]:
			nose.colors[k] = BODY   # 위쪽만 유리 지붕, 옆·아래는 동체
	parts.append(nose)
	var cabin := cyl(Vector3(0, -hl * 0.35, 11.0), Vector3(0, hl * 0.12, 12.0), 9.0, 7.0, u, v, 12, BODY, 1)
	# 옆 창: 옆을 보는 면 (11·0번은 오른쪽, 4·5번은 왼쪽)
	for k in [11, 0, 4, 5]:
		cabin.colors[k] = GLASS
	band(cabin, 12, 0.5, 0.62, ACCENT)
	if o.get("police", false):
		band(cabin, 12, 0.66, 0.71, POLICE_TRIM)
	parts.append(cabin)
	parts.append(cyl(Vector3(0, hl * 0.12, 12.0), Vector3(0, hl * 0.3, 13.0), 7.0, 3.0, u, v, 12, BODY, 1))
	parts.append(cyl(Vector3(0, hl * 0.3, 13.0), Vector3(0, hl * 0.95, 15.0), 2.4, 1.4, u, v, 8, BODY, 1))
	parts.append(hull(-0.7, 0.7, hl * 0.78, hl * 0.98, 13.0, -0.6, 0.6, hl * 0.86, hl * 1.0, 24.0, BODY, 2))
	parts.append(box(-4.5, 4.5, hl * 0.84, hl * 0.92, 14.0, 15.0, ACCENT, 2))
	_tail_rotor(parts, Vector3(1.2, hl * 0.93, 21.0), 5.0)
	for side: int in [-1, 1]:
		parts.append(box(side * 8.0 - 0.8, side * 8.0 + 0.8, -hl * 0.65, hl * 0.25, 0.5, 1.8, DARK, 0))
		for y in [-hl * 0.4, hl * 0.05]:
			parts.append(bar(Vector3(side * 8.0, y, 1.6), Vector3(side * 5.0, y, 6.0), 1.0, 1.0, DARK, 0))
	parts.append(box(-2.4, 2.4, -3.0, 4.0, 18.5, 21.0, [BODY, 0.2], 3, 1.0))         # 엔진 덮개
	if o.get("police", false):
		parts.append(box(-3.9, -2.4, -1.0, 2.0, 19.5, 21.2, SIREN_R, 3))            # 경광등
		parts.append(box(2.4, 3.9, -1.0, 2.0, 19.5, 21.2, SIREN_B, 3))
		_searchlight(parts, Vector3(0, -hl * 0.62, 3.6))
	parts.append(cyl(Vector3(0, 0.5, 21.0), Vector3(0, 0.5, 23.0), 1.2, 1.2, u, Vector3(0, 1, 0), 6, DARK, 3))
	_main_rotor(parts, 23.0, l * 0.6, 4, 2.2)
	return parts


## 119 구조헬기: 큰 쌍발 동체(빨강, 흰 아래띠·노란 줄) + 둥근 유리 기수 + 옆 미닫이문·창 + 오른쪽 위 구조 윈치 +
## 흰 엔진 덮개 둘(흡기·배기) + 굵은 꼬리 붐·꼬리날개 + 바퀴 착륙장치(기수 바퀴·옆 스폰슨) + 기수 탐조등 + 빨간 경광등 + 주 날개 4장
static func _rescue_heli(w: float, l: float, h: float) -> Array:
	var hl := l * 0.5
	var parts: Array = []
	var u := Vector3(1, 0, 0)
	var v := Vector3(0, 0, 1)
	var rz := h + Vehicle.ROTOR_ABOVE
	var cy0 := -hl * 0.55
	var cy1 := hl * 0.12
	var cabin := box(-9.5, 9.5, cy0, cy1, 4.0, h - 1.0, BODY, 1, 3.0)
	sides(cabin, 0.0, 1.0, 0.12, 0.26, ACCENT)                                    # 흰 아래띠
	sides(cabin, 0.0, 1.0, 0.28, 0.32, HAZARD)                                    # 노란 줄
	sides(cabin, 0.04, 0.3, 0.5, 0.86, GLASS)                                     # 조종석 옆 창
	decal(cabin, R, 0.38, 0.7, 0.08, 0.9, [BODY, 0.18])                           # 오른쪽 미닫이문
	decal(cabin, R, 0.43, 0.65, 0.5, 0.84, GLASS)
	decal(cabin, R, 0.42, 0.44, 0.34, 0.42, CHROME)                               # 문 손잡이
	decal(cabin, L, 0.3, 0.6, 0.5, 0.84, GLASS)                                   # 왼쪽 창
	decal(cabin, B, 0.2, 0.8, 0.5, 0.85, [BODY, 0.25])
	top_rect(cabin, -7.0, 7.0, cy0 + 2.0, cy0 + 9.0, GLASS)                       # 조종석 천장 유리
	parts.append(cabin)
	var nose := hull(-8.5, 8.5, -hl * 0.84, cy0 + 0.5, 4.0, -7.0, 7.0, -hl * 0.72, cy0 + 0.5, h - 2.0, BODY, 1, 3.0)
	decal(nose, F, 0.05, 0.95, 0.4, 1.0, GLASS)
	decal(nose, T, 0.0, 1.0, 0.0, 1.0, GLASS)
	for c in [FRC, FLC]:
		decal(nose, c, 0.0, 1.0, 0.4, 1.0, GLASS)
	sides(nose, 0.0, 1.0, 0.45, 0.95, GLASS)
	sides(nose, 0.0, 1.0, 0.12, 0.26, ACCENT)
	parts.append(nose)
	var chin := box(-6.5, 6.5, -hl * 0.94, -hl * 0.8, 4.0, 10.0, BODY, 1, 2.5)    # 기수 아래 둥근 턱
	decal(chin, F, 0.15, 0.85, 0.1, 0.45, ACCENT)
	parts.append(chin)
	_searchlight(parts, Vector3(2.5, -hl * 0.86, 2.8))
	# 뒤로 좁아지는 동체 → 꼬리 붐 → 꼬리날개
	var aft := cyl(Vector3(0, cy1, 11.5), Vector3(0, hl * 0.42, 14.0), 8.2, 3.4, u, v, 12, BODY, 1)
	band(aft, 12, 0.0, 1.0, BODY)
	parts.append(aft)
	var boom := cyl(Vector3(0, hl * 0.42, 14.0), Vector3(0, hl * 0.94, 16.0), 3.0, 1.8, u, v, 8, BODY, 1)
	band(boom, 8, 0.3, 0.45, ACCENT)
	parts.append(boom)
	var fin := hull(-0.9, 0.9, hl * 0.8, hl * 0.98, 15.0, -0.7, 0.7, hl * 0.9, hl * 1.02, h + 9.0, BODY, 2)
	sides(fin, 0.0, 1.0, 0.65, 0.85, ACCENT)
	parts.append(fin)
	parts.append(box(-6.5, 6.5, hl * 0.8, hl * 0.88, 15.5, 16.6, ACCENT, 2))      # 수평 안정판
	_tail_rotor(parts, Vector3(1.6, hl * 0.95, h + 5.0), 6.0)
	# 쌍발 엔진 덮개 (흰색)
	var eng := box(-5.5, 5.5, -hl * 0.3, hl * 0.18, h - 1.0, h + 3.5, ACCENT, 3, 1.6)
	top_rect(eng, -0.4, 0.4, -hl * 0.28, hl * 0.16, [ACCENT, 0.25])
	parts.append(eng)
	for side: int in [-1, 1]:
		var intake := cyl(Vector3(side * 3.0, -hl * 0.32, h + 1.2), Vector3(side * 3.0, -hl * 0.26, h + 1.2), 1.4, 1.4,
			u, v, 8, DARK, 3)
		parts.append(intake)
		parts.append(cyl(Vector3(side * 4.8, hl * 0.12, h + 1.6), Vector3(side * 6.2, hl * 0.22, h + 2.0), 1.2, 1.3,
			u, v, 8, DARK, 3))                                                     # 배기구
	parts.append(box(-1.0, 1.0, hl * 0.04, hl * 0.1, h + 3.5, h + 4.6, SIREN_R, 3))  # 경광등
	# 구조 윈치: 오른쪽 문 위로 나온 팔과 감개
	parts.append(bar(Vector3(9.0, -hl * 0.2, h - 2.5), Vector3(14.0, -hl * 0.2, h - 2.0), 1.4, 1.4, STEEL, 2))
	var hoist := box(12.6, 16.0, -hl * 0.26, -hl * 0.14, h - 4.5, h - 1.5, ACCENT, 2, 0.8)
	decal(hoist, R, 0.2, 0.8, 0.2, 0.8, HAZARD)
	parts.append(hoist)
	parts.append(bar(Vector3(14.3, -hl * 0.2, h - 4.5), Vector3(14.3, -hl * 0.2, h - 8.5), 0.4, 0.4, DARK, 2))
	# 바퀴 착륙장치: 기수 바퀴 + 옆 스폰슨 바퀴
	parts.append(bar(Vector3(0, -hl * 0.72, 4.5), Vector3(0, -hl * 0.72, 2.6), 1.0, 1.0, STEEL, 0))
	parts.append(wheel(0.0, -hl * 0.72, 2.2, 0.9, 1, HUB, 0))
	for side: int in [-1, 1]:
		var sponson := box(side * 9.0 - 2.0, side * 9.0 + 2.0, -hl * 0.12, hl * 0.12, 3.0, 7.5, BODY, 1, 1.2)
		if side > 0:
			sponson.colors[R] = [BODY, 0.1]
		parts.append(sponson)
		parts.append(wheel(side * 10.0, -hl * 0.02, 2.6, 1.1, side, HUB, 0))
	parts.append(cyl(Vector3(0, 0.5, h + 3.5), Vector3(0, 0.5, rz), 1.3, 1.3, u, Vector3(0, 1, 0), 6, DARK, 3))
	_main_rotor(parts, rz, l * 0.6, 4, 2.8)
	return parts


## 군용 기동헬기: 국방색 각진 동체 + 짙은 유리 조종석 + 작은 옆 창·문틈 + 양옆 날개와 로켓 포드 + 기수 기관총 +
## 엔진 덮개·배기 + 꼬리 붐·큰 꼬리날개(왼쪽 꼬리 회전날개) + 바퀴 착륙장치 + 주 날개 4장
static func _army_heli(w: float, l: float, h: float) -> Array:
	var hl := l * 0.5
	var parts: Array = []
	var u := Vector3(1, 0, 0)
	var v := Vector3(0, 0, 1)
	var rz := h + Vehicle.ROTOR_ABOVE
	var cy0 := -hl * 0.46
	var cy1 := hl * 0.18
	var cabin := box(-10.0, 10.0, cy0, cy1, 3.0, h - 1.0, BODY, 1, 2.0)
	sides(cabin, 0.06, 0.24, 0.55, 0.85, TINT)                                    # 조종석 뒤 작은 창
	sides(cabin, 0.32, 0.4, 0.58, 0.82, TINT)
	sides(cabin, 0.3, 0.72, 0.06, 0.92, [BODY, 0.12])                             # 큰 미닫이문
	sides(cabin, 0.46, 0.58, 0.58, 0.82, TINT)
	sides(cabin, 0.0, 1.0, 0.0, 0.06, ACCENT)
	decal(cabin, B, 0.15, 0.85, 0.2, 0.8, [BODY, 0.2])
	top_rect(cabin, -8.0, 8.0, cy0 + 2.0, cy0 + 6.0, [BODY, 0.15])
	parts.append(cabin)
	var cockpit := hull(-9.0, 9.0, -hl * 0.78, cy0 + 0.5, 3.0, -7.0, 7.0, -hl * 0.64, cy0 + 0.5, h - 2.0, BODY, 1, 2.0)
	decal(cockpit, F, 0.05, 0.95, 0.42, 1.0, TINT)
	decal(cockpit, T, 0.0, 1.0, 0.0, 1.0, TINT)
	for c in [FRC, FLC]:
		decal(cockpit, c, 0.0, 1.0, 0.42, 1.0, TINT)
	sides(cockpit, 0.0, 1.0, 0.45, 0.95, TINT)
	parts.append(cockpit)
	parts.append(box(-6.0, 6.0, -hl * 0.9, -hl * 0.74, 3.0, 10.5, BODY, 1, 2.5))  # 기수
	# 기수 기관총: 포탑 + 앞으로 뻗은 총열
	parts.append(cyl(Vector3(0, -hl * 0.8, 3.2), Vector3(0, -hl * 0.8, 1.0), 2.4, 2.0, u, Vector3(0, 1, 0), 8, DARK, 0))
	parts.append(bar(Vector3(0, -hl * 0.82, 1.4), Vector3(0, -hl * 0.98, 1.6), 0.9, 0.9, DARK, 0))
	# 양옆 날개와 로켓 포드
	for side: int in [-1, 1]:
		parts.append(box(side * 10.0 - (12.0 if side < 0 else 0.0), side * 10.0 + (12.0 if side > 0 else 0.0),
			-hl * 0.14, hl * 0.02, h - 7.0, h - 5.8, BODY, 1))
		for x in [15.0, 20.0]:
			parts.append(bar(Vector3(side * x, -hl * 0.06, h - 7.0), Vector3(side * x, -hl * 0.06, h - 9.0), 0.8, 0.8, DARK, 1))
			var pod := cyl(Vector3(side * x, -hl * 0.22, h - 10.0), Vector3(side * x, hl * 0.08, h - 10.0), 1.9, 1.9,
				u, v, 8, [BODY, 0.2], 1)
			pod.colors[8] = DARK   # 앞 마구리 (로켓 구멍)
			parts.append(pod)
	# 엔진 덮개 · 배기
	var eng := box(-6.5, 6.5, -hl * 0.3, hl * 0.24, h - 1.0, h + 4.0, [BODY, 0.08], 3, 1.5)
	top_rect(eng, -5.0, 5.0, -hl * 0.1, hl * 0.04, ACCENT)
	parts.append(eng)
	for side: int in [-1, 1]:
		parts.append(cyl(Vector3(side * 6.0, hl * 0.12, h + 1.5), Vector3(side * 8.0, hl * 0.26, h + 1.2), 1.5, 1.7,
			u, v, 8, DARK, 3))
	# 뒤로 좁아지는 동체 → 꼬리 붐 → 큰 꼬리날개
	parts.append(cyl(Vector3(0, cy1, 11.0), Vector3(0, hl * 0.46, 14.0), 8.5, 3.2, u, v, 12, BODY, 1))
	parts.append(cyl(Vector3(0, hl * 0.46, 14.0), Vector3(0, hl * 0.94, 16.0), 3.0, 2.0, u, v, 8, BODY, 1))
	parts.append(hull(-1.0, 1.0, hl * 0.8, hl * 0.96, 15.0, -0.8, 0.8, hl * 0.92, hl * 1.04, h + 11.0, BODY, 2))
	parts.append(box(-7.5, 7.5, hl * 0.86, hl * 0.95, 14.5, 15.6, BODY, 2))       # 수평 안정판
	_tail_rotor(parts, Vector3(-1.8, hl * 0.97, h + 6.0), 6.5)
	# 바퀴 착륙장치: 앞 바퀴 둘 + 꼬리 바퀴
	for side: int in [-1, 1]:
		parts.append(bar(Vector3(side * 9.5, -hl * 0.3, 4.0), Vector3(side * 10.5, -hl * 0.3, 2.8), 1.0, 1.0, DARK, 0))
		parts.append(wheel(side * 10.8, -hl * 0.3, 2.8, 1.1, side, DARK, 0))
	parts.append(bar(Vector3(0, hl * 0.86, 13.0), Vector3(0, hl * 0.86, 2.0), 0.8, 0.8, DARK, 0))
	parts.append(wheel(0.0, hl * 0.86, 1.8, 0.7, 1, DARK, 0))
	parts.append(cyl(Vector3(0, 0.5, h + 4.0), Vector3(0, 0.5, rz), 1.4, 1.4, u, Vector3(0, 1, 0), 6, DARK, 3))
	_main_rotor(parts, rz, l * 0.6, 4, 3.0)
	return parts


## 주 회전날개 (멈춘 날개 n장, 허브는 y 0.5 — Vehicle.draw_rotor의 도는 원판과 같은 자리). blade로 표시해 그림 헬기는 빼고 그린다
static func _main_rotor(parts: Array, z: float, reach: float, n: int, width: float) -> void:
	for k in n:
		var t := PI * 0.25 + 0.35 + k * TAU / n
		var tip := Vector3(cos(t), sin(t), 0.0) * reach
		var blade := bar(Vector3(0, 0.5, z), tip + Vector3(0, 0.5, z - 0.4), width, 0.4, DARK, 4)
		blade.blade = true
		parts.append(blade)


## 꼬리 회전날개: c를 가운데로 십자 막대 둘 (길이 반경 r)
static func _tail_rotor(parts: Array, c: Vector3, r: float) -> void:
	parts.append(bar(c + Vector3(0, -r, 0), c + Vector3(0, r, 0), 1.0, 0.4, DARK, 3))
	parts.append(bar(c + Vector3(0, 0, -r), c + Vector3(0, 0, r), 1.0, 0.4, DARK, 3))


## 기수 밑 탐조등: 짧은 원통, 앞 마구리가 전조등 색 (켜면 밝다)
static func _searchlight(parts: Array, at: Vector3) -> void:
	var lamp := cyl(at + Vector3(0, -1.2, 0), at + Vector3(0, 1.2, 0), 1.6, 1.8, Vector3(1, 0, 0), Vector3(0, 0, 1), 8, DARK, 0)
	lamp.colors[8] = HEAD
	parts.append(lamp)


## 자전거 바퀴: 속이 비치게 가는 타이어 고리(막대 12개) + 바큇살 + 허브
static func _spoked(parts: Array, y: float, r: float) -> void:
	var c := Vector3(0, y, r)
	for k in 12:
		var a := TAU * k / 12.0
		var b := TAU * (k + 1) / 12.0
		parts.append(bar(c + Vector3(0, cos(a), sin(a)) * r, c + Vector3(0, cos(b), sin(b)) * r, 1.0, 1.0, TIRE, 1))
	for k in 3:
		var a := PI * k / 3.0 + 0.3
		var d := Vector3(0, cos(a), sin(a)) * (r - 0.6)
		parts.append(bar(c - d, c + d, 0.3, 0.3, STEEL, 1))
	parts.append(box(-0.8, 0.8, y - 0.8, y + 0.8, r - 0.8, r + 0.8, STEEL, 1))


## 오토바이·자전거: 두 바퀴 + 틀(막대) + 핸들, 탄 사람
static func _bike(w: float, l: float, bicycle: bool) -> Array:
	var hl := l * 0.5
	var parts: Array = []
	var r := 6.0 if bicycle else 5.4
	var yf := -hl + r
	var yr := hl - r
	for y in [yf, yr]:
		if bicycle:
			_spoked(parts, y, r)
		else:
			parts.append(wheel(0.0, y, r, 1.4, 0, CHROME, 5))
	if bicycle:
		var head := Vector3(0, yf + 3.0, r + 7.0)
		var seat := Vector3(0, 1.5, r + 7.0)
		var crank := Vector3(0, 0.5, r)
		for seg in [[Vector3(0, yf, r), head], [head, seat], [head, crank], [seat, crank], [crank, Vector3(0, yr, r)], [seat, Vector3(0, yr, r)]]:
			parts.append(bar(seg[0], seg[1], 0.9, 0.9, BODY, 2))
		parts.append(box(-1.4, 1.4, 0.5, 4.5, r + 7.5, r + 8.4, DARK, 3))                # 안장
		parts.append(bar(head + Vector3(-4.0, -0.5, 1.0), head + Vector3(4.0, -0.5, 1.0), 0.8, 0.8, DARK, 3))   # 핸들
		parts.append(cyl(crank + Vector3(-1.2, 0, 0), crank + Vector3(1.2, 0, 0), 1.8, 1.8, Vector3(0, 1, 0), Vector3(0, 0, 1), 8, STEEL, 2))
	else:
		parts.append(bar(Vector3(0, yf, r), Vector3(0, yf + 3.0, r + 8.0), 1.0, 1.0, CHROME, 2))     # 앞 포크
		parts.append(box(-1.8, 1.8, yf + 3.0, yr - 2.0, r - 1.5, r + 2.5, DARK, 1))               # 엔진·차대
		parts.append(cyl(Vector3(-1.9, -l * 0.05, r - 0.5), Vector3(-1.9, -l * 0.05 + 4.0, r - 0.5), 2.2, 2.2, Vector3(0, 1, 0), Vector3(0, 0, 1), 8, CHROME, 2))
		parts.append(cyl(Vector3(2.4, l * 0.0, r - 1.5), Vector3(2.4, hl - 1.0, r + 1.0), 1.0, 1.0, Vector3(1, 0, 0), Vector3(0, 0, 1), 6, CHROME, 2))   # 배기관
		parts.append(hull(-3.2, 3.2, -l * 0.2, l * 0.05, r + 3.0, -2.6, 2.6, -l * 0.16, l * 0.02, r + 7.0, BODY, 2, 1.0))   # 연료통
		parts.append(box(-2.6, 2.6, l * 0.05, l * 0.3, r + 3.0, r + 5.5, DARK, 2, 0.8))           # 안장
		var bx := box(-2.4, 2.4, l * 0.26, l * 0.42, r + 3.0, r + 10.0, ACCENT, 3, 0.8)           # 배달통
		decal(bx, B, 0.2, 0.8, 0.5, 0.75, BODY)
		parts.append(bx)
		var front := box(-1.5, 1.5, -hl + 1.0, -hl + r + 2.0, r + 2.0, r + 6.0, BODY, 2, 0.6)
		decal(front, F, 0.2, 0.8, 0.3, 0.8, HEAD)
		parts.append(front)
		var back := box(-1.0, 1.0, hl - 2.0, hl - 0.5, r + 2.0, r + 3.5, DARK, 2)
		decal(back, B, 0.1, 0.9, 0.1, 0.9, TAIL)
		parts.append(back)
		parts.append(bar(Vector3(-5.0, -l * 0.27, r + 8.0), Vector3(5.0, -l * 0.27, r + 8.0), 0.8, 0.8, DARK, 3))   # 핸들
	var torso := box(-2.8, 2.8, -l * 0.08, l * 0.08, r + 6.0, r + 14.0, RIDER, 4, 1.0)
	torso.rider = true
	parts.append(torso)
	var head_part := box(-2.2, 2.2, -l * 0.07, l * 0.06, r + 14.0, r + 18.5, HELMET if not bicycle else Color(0.08, 0.07, 0.07), 4, 1.0)
	if not bicycle:
		decal(head_part, F, 0.15, 0.85, 0.3, 0.7, GLASS)
	head_part.rider = true
	parts.append(head_part)
	for side: int in [-1, 1]:
		var arm := bar(Vector3(side * 2.6, -l * 0.02, r + 12.5), Vector3(side * 3.8, -l * 0.25, r + 8.5), 1.2, 1.2, RIDER, 4)
		arm.rider = true
		parts.append(arm)
	return parts
