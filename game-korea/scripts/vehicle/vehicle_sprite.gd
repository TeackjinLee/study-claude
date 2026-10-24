class_name VehicleSprite
extends RefCounted
## 차량 방향 그림 (코드 모형 가이드 위에 덧칠한 그림). tools/prepare_vehicle_sprites.py가 낸
## assets/vehicles/sprites/<id>.png · .json을 읽는다. 없으면 코드 모형(VehicleModel) 그대로다.
## 그림은 한 바퀴 32방향 중 화면 ↑ → → → ↓ 반 바퀴(k = 0…16, 회전 −45° + k × 11.25°)의 칸이 한 줄로 있고,
## 왼쪽 반은 좌우로 뒤집어 쓴다 (화면 좌우 거울 = 월드 x↔y 교환, 회전 r ↔ −90° − r).
## 지금 회전과 가장 가까운 칸을 고르고, 남는 각도(최대 한 칸 11.25°)와 선회 기울기·숙이기(bank·pitch)는 그림을 비틀어 흉내 낸다:
## 코드 모형의 3D 점들을 "그 칸 방향·수평"과 "지금 방향·기울기"로 각각 화면에 찍어, 둘을 가장 잘 잇는 2D 아핀 변환(최소제곱)을 쓴다.
## (바닥 평면만 비틀면 사선 시점(26.6°)과 기울기가 겹칠 때 그림이 선처럼 납작해진다.)
## 한 칸보다 먼 방향은 그림이 없는 것으로 보고 코드 모형으로 그린다.
## 주 회전날개·그림자는 그림에 없다 — 도는 날개는 Vehicle._draw_rotor, 멈춘 날개는 VehicleModel이 모형 날개로 그린다.
## 땅 차량도 같은 방식이다. 그림은 불빛을 꺼진 채로 그리고, 매 순간 바뀌는 것은 게임이 맞춘다:
## 켜진 전조등·브레이크등·후진등·경광등은 VehicleModel이 그 색 키 면만 지금 방향으로 찍어 덧그리고, 찌그러짐은 팬 자국 그늘을 얹고,
## 깔림(crushed)은 비틀기 변환에 모형 높이를 눌러 넣어 그림을 세로로 누른다. 도색 가게가 칠을 바꾼 차는 코드 모형으로 그린다.
## 포탑 차(자주포)는 차체 그림 <id>(part "hull" — 포탑·포신 없이)과 포탑 그림 <id>_turret(part "turret")을 따로 받는다:
## 포탑 그림은 포탑 축(Part.axis_y)이 원점이고 칸은 포탑이 월드에서 보는 방향(차 회전 + Vehicle.turret)이다.
## 비틀기는 포탑 점을 축 기준으로 그 칸 방향에 찍은 것 → 지금 포탑 각·차 방향·기울기로 찍은 것을 잇는다(축 자리 옮김도 같이 들어간다).
## 포신(Part.turret 2)은 든 각(elevation)·뒤로 밀림이 있어 그림에 없다 — VehicleModel이 코드로 그린다.

const DIR := "res://assets/vehicles/sprites/"
const DIRS := 32
const STEP := TAU / DIRS
const MAX_TWIST := STEP * 1.01

var texture: Texture2D
var cell := 1.0
var scale := 1.0               ## 화면(줌 1) 1px당 그림 px
var origins := {}              ## 칸 k → 그 칸에서 헬기 원점(땅)의 그림 px (포탑 그림은 포탑 축)
var part := VehicleModel.Only.ALL   ## 무엇을 그린 그림인가: ALL 통째 · HULL 포탑 뺀 차체 · TURRET 포탑만
var axis_y := 0.0              ## 포탑 그림: 포탑이 도는 축의 y (차 기준)

static var _cache := {}
## false면 그림을 쓰지 않고 코드 모형으로 (가이드 도구가 모형을 찍을 때)
static var enabled := true


## 그 차종의 방향 그림 (없으면 null)
static func of(stats: VehicleType) -> VehicleSprite:
	if stats == null or not enabled or stats.resource_path == "":
		return null
	return _of(stats.resource_path.get_file().get_basename())


## 그 차종의 포탑 그림 (차체 그림과 따로 받은 포탑 차만, 없으면 null)
static func turret_of(stats: VehicleType) -> VehicleSprite:
	if stats == null or not enabled or stats.resource_path == "":
		return null
	return _of(stats.resource_path.get_file().get_basename() + "_turret")


static func _of(key: String) -> VehicleSprite:
	if _cache.has(key):
		return _cache[key]
	var sp: VehicleSprite = null
	var path := DIR + key + ".json"
	if FileAccess.file_exists(path) and BuildingSkin.has_png(DIR + key + ".png"):
		sp = VehicleSprite.new()
		sp._load(key, JSON.parse_string(FileAccess.get_file_as_string(path)))
		if sp.texture == null or sp.origins.is_empty():
			sp = null
	_cache[key] = sp
	return sp


func _load(key: String, info: Dictionary) -> void:
	texture = BuildingSkin.texture(DIR + key + ".png")
	cell = float(info["cell"])
	scale = float(info["scale"])
	part = {"hull": VehicleModel.Only.HULL, "turret": VehicleModel.Only.TURRET}.get(info.get("part", "all"), VehicleModel.Only.ALL)
	axis_y = float(info.get("turret_axis_y", 0.0))
	for f: Dictionary in info["frames"]:
		origins[int(f["k"])] = Vector2(f["origin"][0], f["origin"][1])


## 칸 k가 보여 주는 회전
static func rotation_of(k: int) -> float:
	return -PI * 0.25 + k * STEP


## 회전 r에 쓸 칸: [k, 뒤집기, 남는 각도]. 한 칸보다 가까운 그림이 없으면 []
func pick(r: float) -> Array:
	var best := []
	var best_d := INF
	for k: int in origins:
		var rk := rotation_of(k)
		var d := angle_difference(rk, r)
		if absf(d) < absf(best_d):
			best_d = d
			best = [k, false]
		# 뒤집은 그림은 회전 −90° − rk를 보여 준다
		var dm := angle_difference(-PI * 0.5 - rk, r)
		if absf(dm) < absf(best_d):
			best_d = dm
			best = [k, true]
	if best.is_empty() or absf(best_d) > MAX_TWIST:
		return []
	return [best[0], best[1], best_d]


## 차 노드(회전한 좌표계) 안에 그림을 그린다. 그릴 칸이 없으면 false (코드 모형으로 그린다)
func draw(ci: CanvasItem, car: Vehicle) -> bool:
	# 그림은 차종 기본색으로 그렸다 — 도색 가게(SprayShop)가 다시 칠한 차는 코드 모형으로
	if car.paint != car.stats.body_color:
		return false
	# 포탑 그림은 포탑이 월드에서 보는 방향의 칸을 고른다
	var r := car.rotation + (car.turret if part == VehicleModel.Only.TURRET else 0.0)
	var p := pick(r)
	if p.is_empty():
		return false
	var k: int = p[0]
	var flip: bool = p[1]
	var origin: Vector2 = origins[k]
	var f := -1.0 if flip else 1.0
	# 그림 px → 화면 (줌 1, 헬기 원점 기준): 원점을 빼고 배율로 나누고, 뒤집을 칸은 원점 세로줄을 축으로 뒤집는다
	var norm := Transform2D(Vector2(f / scale, 0.0), Vector2(0.0, 1.0 / scale), Vector2(-f * origin.x / scale, -origin.y / scale))
	# 그림이 보여 주는 방향(수평) → 지금 방향·기울기
	var shown := -PI * 0.5 - rotation_of(k) if flip else rotation_of(k)
	var bend := _bend(car, shown, part, axis_y)
	var view := IsoView.BASIS * Transform2D(car.rotation, Vector2.ZERO)
	var lift := Transform2D(Vector2.RIGHT, Vector2.DOWN, Vector2(0.0, -(car.ground + car.altitude)))
	ci.draw_set_transform_matrix(view.affine_inverse() * lift * bend * norm)
	if ci.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
		ci.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # 크게 그린 그림을 줄여 그린다
	ci.draw_texture_rect_region(texture, Rect2(0, 0, cell, cell), Rect2(k * cell, 0, cell, cell), _tint(car))
	return true


## 모형 점들을 방향 shown·수평으로 찍은 화면 점 → 지금 방향·기울기·깔림으로 찍은 화면 점을 잇는 아핀 변환 (최소제곱, 화면 px 줌 1).
## 포탑 그림(only TURRET)은 점을 축 (0, axis)에서 찍은 것 → 지금 포탑 각으로 축을 돌려 차 원점에서 찍은 것
static func _bend(car: Vehicle, shown: float, only := VehicleModel.Only.ALL, axis := 0.0) -> Transform2D:
	var r := car.rotation
	var turret := only == VehicleModel.Only.TURRET
	if not turret and is_equal_approx(shown, r) and car.bank == 0.0 and car.pitch == 0.0 and car.crushed == 0.0:
		return Transform2D.IDENTITY
	var squash := 1.0 - VehicleModel.CRUSH_FLAT * car.crushed   # 깔린 차는 높이를 누른다 (VehicleModel._project와 같은 차례: 기울이기 전에)
	var pts := _points(car.stats, only)
	var pivot := Vector3(0, axis, 0) if turret else Vector3.ZERO
	var src := PackedVector2Array()
	var dst := PackedVector2Array()
	src.resize(pts.size())
	dst.resize(pts.size())
	var ms := Vector2.ZERO
	var md := Vector2.ZERO
	for i in pts.size():
		var q := pts[i]
		src[i] = _screen(q - pivot, shown)
		if turret:
			var t := Vector2(q.x, q.y - axis).rotated(car.turret)
			q = Vector3(t.x, t.y + axis, q.z)
		dst[i] = _screen(VehicleModel.tilt(Vector3(q.x, q.y, q.z * squash), Vehicle.BANK_PIVOT, car.bank, car.pitch), r)
		ms += src[i]
		md += dst[i]
	ms /= pts.size()
	md /= pts.size()
	# A = (Σ d·sᵀ)(Σ s·sᵀ)⁻¹ (가운데를 뺀 점)
	var sxx := 0.0
	var sxy := 0.0
	var syy := 0.0
	var dx_sx := 0.0
	var dx_sy := 0.0
	var dy_sx := 0.0
	var dy_sy := 0.0
	for i in pts.size():
		var a := src[i] - ms
		var b := dst[i] - md
		sxx += a.x * a.x
		sxy += a.x * a.y
		syy += a.y * a.y
		dx_sx += b.x * a.x
		dx_sy += b.x * a.y
		dy_sx += b.y * a.x
		dy_sy += b.y * a.y
	var det := sxx * syy - sxy * sxy
	if absf(det) < 1e-6:
		return Transform2D.IDENTITY
	var ix := Vector2(syy, -sxy) / det   # (Σ s·sᵀ)⁻¹ 첫 열
	var iy := Vector2(-sxy, sxx) / det
	# A의 열 = (Σ d·sᵀ) × 역행렬의 열
	var col_x := Vector2(dx_sx * ix.x + dx_sy * ix.y, dy_sx * ix.x + dy_sy * ix.y)
	var col_y := Vector2(dx_sx * iy.x + dx_sy * iy.y, dy_sx * iy.x + dy_sy * iy.y)
	var t := Transform2D(col_x, col_y, Vector2.ZERO)
	t.origin = md - t.basis_xform(ms)
	return t


static var _points_cache := {}


## 모형의 꼭짓점 (주 날개 빼고, only가 고른 부품만) — 그림을 비틀 변환을 구하는 데 쓴다
static func _points(stats: VehicleType, only := VehicleModel.Only.ALL) -> PackedVector3Array:
	var key := "%s:%d" % [stats.resource_path, only]
	if not _points_cache.has(key):
		var out := PackedVector3Array()
		for p: VehicleModel.Part in VehicleModel.model(stats):
			if p.blade or (only == VehicleModel.Only.HULL and p.turret != 0) or (only == VehicleModel.Only.TURRET and p.turret != 1):
				continue
			out.append_array(p.pts)
		_points_cache[key] = out
	return _points_cache[key]


## 모형 점(차 기준 3D) → 화면 (줌 1, 헬기 원점·땅 기준)
static func _screen(q: Vector3, r: float) -> Vector2:
	return IsoView.BASIS.basis_xform(Vector2(q.x, q.y).rotated(r)) - Vector2(0, q.z)


## 잔해·불난 차를 그을린 색으로 (VehicleModel._color와 같은 비율)
static func _tint(car: Vehicle) -> Color:
	var c := Color.WHITE
	if car.wrecked:
		return c.darkened(0.78)
	if car.on_fire or car.burning >= 0.0:
		var fire := car.fire_level()
		return c.darkened(0.55 if fire > 1.0 else 0.08 + 0.3 * fire)
	return c
