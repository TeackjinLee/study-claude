class_name BuildingSprite
extends RefCounted
## 건물 한 채를 통째로 그린 그림 (회색 가이드 위에 덧칠한 그림). tools/prepare_building_sprites.py가 낸
## assets/buildings/whole/<id>_<부지>.png · _lights.png · .json을 읽는다. 없으면 코드 그림 그대로다.
## 그림은 게임과 같은 2:1 투영이라, 월드 점 하나의 그림 좌표는 origin + scale × BASIS × (점 − 부지 가운데)로 바로 나온다.
## 덩어리(BuildingView 조각)마다 자기 윤곽만큼만 그림을 오려 그리므로 그리는 순서(z)는 코드 모형 그대로다 —
## 사람·차가 건물 앞뒤를 지나도 제자리에서 가려진다. 부지 바닥은 바닥 층(z 100 미만)에 부지 사각형만큼 붙인다.

const DIR := "res://assets/buildings/whole/"

var day: Texture2D
var lights: Texture2D
var origin := Vector2.ZERO     ## 부지 가운데(바닥)의 그림 px
var scale := 1.0               ## 화면(줌 1) 1px당 그림 px
var size := Vector2.ONE
var lot_size := Vector2(520, 520)   ## 가이드를 찍은 부지 크기
var seed := 7                  ## 가이드를 찍은 모형 시드 — 그림과 모양을 맞추려고 이 시드로 짓는다
var floors := 0                ## 가이드를 찍은 층수 (0이면 종류의 층수 그대로)
## 불빛 그림 오른쪽에 창마다 켜지는 차례가 붙어 있다 (불빛 그림이 낮 그림보다 두 배 넘게 넓다 — BuildingView.LIGHT_SHADER)
var window_order := false
## 생성기는 난간·접시·나무 끝을 모형보다 조금 크게 그린다. 조각 윤곽을 화면에서 위로 hull_lift, 좌우로 hull_grow(px)만큼
## 넓혀 그 끝이 잘리지 않게 한다 (다듬기 도구가 잘리는 그림을 재서 정한다)
var hull_lift := 0.0
var hull_grow := 0.0
## 덩어리마다 더 넓힐 몫 (Piece.sprite_index → Vector3(위, 좌우, 아래) 화면 px). 접시·크레인·가로등처럼 한 덩어리만
## 크게(또는 모형보다 낮게) 그려진 곳은 그 덩어리만 넓힌다 — 건물 전체를 넓히면 뒤를 지나는 사람이 일찍 가려진다
var piece_margins := {}

static var _cache := {}
## false면 그림을 쓰지 않고 코드 그림으로 (가이드 도구가 코드 모형을 찍을 때)
static var enabled := true
## false면 윤곽을 넓히지 않는다 (가이드 도구가 모형 그대로의 윤곽을 찍을 때)
static var margins := true


## 그 종류·부지의 그림 (없으면 null). 부지 이름은 building_guide.gd와 같다
## 블록을 합친 부지(CityMap.MERGES)인가 — 그림 이름의 부지는 merge_<가로>x<세로>라 블록 하나 그림을 늘려 쓰지 않는다
static func merged_lot(lot: Rect2) -> bool:
	return lot.size.x > City.BLOCK or lot.size.y > City.BLOCK


static func of(t: BuildingType, lot: Rect2) -> BuildingSprite:
	if t == null or not enabled:
		return null
	var key := "%s_%s" % [String(t.id).to_lower(), lot_name(lot.size)]
	if _cache.has(key):
		return _cache[key]
	var sp: BuildingSprite = null
	var path := DIR + key + ".json"
	if FileAccess.file_exists(path) and BuildingSkin.has_png(DIR + key + ".png"):
		sp = BuildingSprite.new()
		sp._load(key, JSON.parse_string(FileAccess.get_file_as_string(path)))
	_cache[key] = sp
	return sp




## 건물 한 채의 그림: 하나뿐인 그림(<id>_<부지>)이 있으면 그것, 없으면 컨셉 그림들 가운데 seed(건물 번호)로 골라
## 이웃 건물끼리 돌려 쓴다. 컨셉 그림은 모두 같은 가이드(같은 모형 시드) 위에 재질·색만 달리 칠한 것이다.
## floors(도시가 ±1 바꾼 층수)를 주면 그 층수로 그린 컨셉(<id>_<부지>_<컨셉>_f<층>)부터 고르고, 없으면 종류의 층수 그림
static func pick(t: BuildingType, lot: Rect2, seed: int, floors := 0) -> BuildingSprite:
	var one := of(t, lot)
	if one:
		return one
	var list := variants(t, lot)
	if list.is_empty():
		return null
	var base := maxi(t.floors, 1)
	var same := list.filter(func(s: BuildingSprite) -> bool: return s.floors_or(base) == (floors if floors > 0 else base))
	if same.is_empty():
		same = list.filter(func(s: BuildingSprite) -> bool: return s.floors_or(base) == base)
	if same.is_empty():
		same = list
	# 층은 건물 번호 셋마다 돌아가므로(City.building_height) 층이 바뀌는 종류는 번호/3으로 돌려야 같은 층끼리도 컨셉이 바뀐다
	var k := seed / 3 if t.floors >= 3 else seed
	return same[posmod(k, same.size())]


## 이 그림을 지을 층수 (가이드에 적힌 층수, 없으면 base)
func floors_or(base: int) -> int:
	return floors if floors > 0 else base

## 같은 종류·부지에 컨셉을 달리 그린 그림들 (<id>_<부지>_<컨셉>.json — 공원). 이름 순, 없으면 빈 배열.
static func variants(t: BuildingType, lot: Rect2) -> Array:
	if t == null or not enabled:
		return []
	var base := "%s_%s_" % [String(t.id).to_lower(), lot_name(lot.size)]
	if _cache.has(base):
		return _cache[base]
	var out: Array = []
	var names: Array = []
	var dir := DirAccess.open(DIR)
	if dir:
		for f in dir.get_files():
			if f.begins_with(base) and f.ends_with(".json"):
				names.append(f.trim_suffix(".json"))
	names.sort()
	for key in names:
		if not BuildingSkin.has_png(DIR + key + ".png"):
			continue
		var sp := BuildingSprite.new()
		sp._load(key, JSON.parse_string(FileAccess.get_file_as_string(DIR + key + ".json")))
		out.append(sp)
	_cache[base] = out
	return out

static func lot_name(s: Vector2) -> String:
	if merged_lot(Rect2(Vector2.ZERO, s)):   # 합친 블록 부지 (CityMap.MERGES): 가로·세로 블록 수 — merge_1x2
		return "merge_%dx%d" % [roundi((s.x + City.SIDEWALK * 2.0 + City.ROAD) / City.PITCH), roundi((s.y + City.SIDEWALK * 2.0 + City.ROAD) / City.PITCH)]
	if s.x > 400.0 and s.y > 400.0:
		return "full"
	if s.x > 400.0:
		return "half_x"
	if s.y > 400.0:
		return "half_y"
	return "quarter"


func _load(key: String, info: Dictionary) -> void:
	day = BuildingSkin.texture(DIR + key + ".png")
	lights = BuildingSkin.texture(DIR + key + "_lights.png")
	window_order = lights != null and day != null and lights.get_width() > day.get_width() * 1.5
	origin = Vector2(info["origin"][0], info["origin"][1])
	scale = info["scale"]
	size = Vector2(info["size"][0], info["size"][1])
	lot_size = Vector2(info["lot_size"][0], info["lot_size"][1])
	seed = int(info.get("seed", seed))
	floors = int(info.get("floors", 0))
	hull_lift = float(info.get("hull_lift", 0.0))
	hull_grow = float(info.get("hull_grow", 0.0))
	var pm: Dictionary = info.get("hull_pieces", {})
	for k in pm:
		var a: Array = pm[k]
		piece_margins[int(k)] = Vector3(a[0], a[1], a[2] if a.size() > 2 else 0.0)


## 월드 점 v(높이는 IsoView.lift로 이미 더한 점)의 그림 UV. 부지 크기가 가이드와 조금 달라도 부지 비율로 맞춘다
func uv(v: Vector2, lot: Rect2) -> Vector2:
	var w := (v - lot.get_center()) * (lot_size / lot.size)
	return (origin + IsoView.BASIS * w * scale) / size


## 덩어리 p가 화면에서 차지하는 윤곽 (rect는 이 조각의 바닥). 지붕 모양만큼 윗면을 좁힌다
static func outline(p: BuildingModel.Piece, rect: Rect2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var top := p.h1 + p.rise
	match p.roof:
		&"flat", &"none", &"art":
			_box(pts, rect, p.h0)
			_box(pts, rect, p.h1)
		&"gable", &"hip", &"hanok":
			# 처마는 벽 밖으로, 용마루는 덩어리 전체의 긴 쪽을 따라 가운데 — 긴 덩어리는 BuildingView.split으로
			# 정사각형 가까운 토막(rect)으로 나눠 그리므로, 방향·위치는 p.rect로 정하고 길이만 이 토막 구간으로 자른다
			_box(pts, rect, p.h0)
			var e := p.eave
			_box(pts, rect.grow(e), p.h1)
			var whole := p.rect
			if whole.size.x >= whole.size.y:
				var y := whole.get_center().y
				pts.append(Vector2(rect.position.x - e, y) + IsoView.lift(top))
				pts.append(Vector2(rect.end.x + e, y) + IsoView.lift(top))
			else:
				var x := whole.get_center().x
				pts.append(Vector2(x, rect.position.y - e) + IsoView.lift(top))
				pts.append(Vector2(x, rect.end.y + e) + IsoView.lift(top))
		_:
			# 나무·등·소품: 바닥 사각형보다 넓게 퍼지는 것이 많아 둘레를 넉넉히
			var g := clampf(p.rise, 4.0, 16.0)
			_box(pts, rect.grow(g), p.h0)
			_box(pts, rect.grow(g), top)
	var sp := p.sprite
	var m := Vector3.ZERO
	if margins and sp:
		m = Vector3(sp.hull_lift, sp.hull_grow, 0.0).max(sp.piece_margins.get(p.sprite_index, Vector3.ZERO))
	if m != Vector3.ZERO:
		# 화면에서 위·옆·아래로 민 점을 더한다 (볼록 껍질이라 그 사이를 다 덮는다)
		var up := IsoView.lift(m.x)
		var side := IsoView.BASIS.affine_inverse().basis_xform(Vector2(m.y, 0.0))
		var down := -IsoView.lift(m.z)
		var n := pts.size()
		for i in n:
			var v := pts[i]
			for d in [up, side, -side, up + side, up - side, down, down + side, down - side]:
				pts.append(v + d)
	return Geometry2D.convex_hull(pts)


static func _box(pts: PackedVector2Array, r: Rect2, h: float) -> void:
	var l := IsoView.lift(h)
	pts.append(r.position + l)
	pts.append(Vector2(r.end.x, r.position.y) + l)
	pts.append(r.end + l)
	pts.append(Vector2(r.position.x, r.end.y) + l)
