extends Node
## 건물 그림 요청용 가이드 (output/imagegen/buildings/GEMINI_BUILDING_PROMPT.md).
## 지금 코드 모형(BuildingModel)을 게임과 똑같은 2:1 사선 투영으로 찍어, 생성기에 "이 모양 위에 덧칠하라"고 넘길 그림을 만든다.
## 창 모드로 실행한다 (헤드리스는 그리지 않는다):
##   godot --path . res://tools/building_guide.tscn -- --ids=VILLA,APT
##   ... -- --set=street            (base 15종 · special 8종 · street 10종 · landmarks 10종, 기본 base)
##   ... -- --lots=all              (그 종이 놓이는 부지 크기 전부. 기본은 첫 부지)
##   ... -- --lots=half_y           (부지 이름을 직접: full·half_x·half_y·quarter, 쉼표로 여럿 — 랜드마크는 구역에 통째 부지가
##                                    없으면 반쪽 부지에 선다. 실제 부지는 landmark_city_preview 출력의 lot=으로 본다)
##   ... -- --scale=2 --seed=7      (그림 배율: 게임 줌 1 화면 px의 몇 배 · 모형 무작위 시드)
##   ... -- --floors=4              (층수를 바꿔 찍는다 — <ID>_<부지>_f4. 도시가 층을 ±1 바꾼 건물에 붙일 그림용)
##   ... -- --facade                (통째 그림 대신 벽면 정면도 템플릿)
##   ... -- --hulls                 (받은 통째 그림이 있는 종류: 게임이 그림을 오려 그리는 조각 윤곽을 흰색으로 —
##                                    <ID>_<부지>_hulls.png. prepare_building_sprites.py --debug가 윤곽 밖에 남아 안 그려지는 곳을 빨갛게 본다)
## 결과: output/imagegen/buildings/guides/
##   <ID>_<부지>_guide.png  지금 모형을 회색으로 (창·장식 자리까지) · 배경 마젠타
##   <ID>_<부지>_mass.png   창·장식을 뺀 덩어리만 회색으로 · 배경 마젠타
##   <ID>_<부지>_ref.png    지금 모형 색 그대로 (색감 참고용, 생성기에 넣을지는 선택)
##   <ID>_<부지>.json       배율·그림 크기·월드 원점의 그림 좌표·덩어리 목록 (받은 그림을 게임에 맞출 때 쓴다)
##   <ID>_facade_template.png / .json   (--facade) 정면·옆벽·옥상 칸 배치

const Gallery := preload("res://tools/building_gallery.gd")
const OUT := "res://output/imagegen/buildings/guides"
const MAGENTA := Color(1, 0, 1)
## 부지 이름 → 크기 (City: 블록 안쪽 520, 반쪽 251). 반쪽은 긴 쪽이 x(half_x)·y(half_y) 두 방향이 있다
const LOTS := {
	"full": Vector2(520, 520), "half_x": Vector2(520, 251), "half_y": Vector2(251, 520), "quarter": Vector2(251, 251)}
const FOOTPRINT_LOTS := {0: ["full"], 1: ["half_x", "half_y"], 2: ["quarter"]}
const PAD := 40.0           ## 그림 가장자리 여유 (화면 px, 처마·나무가 나가는 몫)
const SIDEWALK := 28.0
## 월드 x 방향 1px이 화면에서 차지하는 길이 (= |BASIS.x|). 벽면 텍스처의 가로 텍셀 밀도를 세로와 맞출 때 쓴다
const WALL_PX := 0.8720665
## 창 모양별 창 간격 (월드 px, BuildingView._windows와 같다)과 칸 안에서 창이 차지하는 비율 (가로, 세로: 층 바닥에서 위로)
const BAYS := {
	&"punched": [34.0, Vector2(0.22, 0.78), Vector2(0.3, 0.8)],
	&"brick": [34.0, Vector2(0.24, 0.76), Vector2(0.3, 0.8)],
	&"slit": [15.0, Vector2(0.3, 0.7), Vector2(0.25, 0.82)],
	&"apt": [26.0, Vector2(0.12, 0.88), Vector2(0.28, 0.8)],
	&"glass": [22.0, Vector2(0.06, 0.94), Vector2(0.12, 0.94)],
	&"officetel": [34.0, Vector2(0.22, 0.78), Vector2(0.3, 0.8)],
	&"ribbon": [30.0, Vector2(0.0, 0.87), Vector2(0.4, 0.72)],
	&"metal": [28.0, Vector2(0.0, 0.0), Vector2(0.0, 0.0)],
}
## 정면도 템플릿 캔버스 (제미나이 16:9 기본 크기)
const SHEET := Vector2i(1376, 768)
const SHEET_MARGIN := 24
const FRONT_BAYS := 4
const SIDE_BAYS := 2

var _gray := ShaderMaterial.new()
var _white := ShaderMaterial.new()


func _ready() -> void:
	IsoView.enabled = true
	# 가이드는 언제나 코드 모형이다 (벽면 그림·통째 그림을 붙인 종류도)
	BuildingSkin.enabled = false
	BuildingSprite.enabled = false
	_gray.shader = Shader.new()
	_gray.shader.code = """shader_type canvas_item;
void fragment() {
	float g = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(g), COLOR.a);
}"""
	_white.shader = Shader.new()
	_white.shader.code = """shader_type canvas_item;
void fragment() { COLOR = vec4(1.0); }"""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var gd := ProjectSettings.globalize_path(OUT + "/.gdignore")
	if not FileAccess.file_exists(gd):
		FileAccess.open(gd, FileAccess.WRITE).store_string("")
	var scale := float(_arg("scale", "2"))
	var seed := int(_arg("seed", "7"))
	for id in _ids():
		var t := _type(StringName(id))
		if t == null:
			push_warning("건물 종류 없음: %s" % id)
			continue
		if "--facade" in OS.get_cmdline_user_args():
			_facade(t, seed)
			continue
		var hulls := "--hulls" in OS.get_cmdline_user_args()
		var lots: Array = []
		var want := _arg("lots", "")
		if want != "" and want != "all":
			lots = Array(want.split(","))
		else:
			for f in (t.footprints if want == "all" else [t.footprints[0]]):
				lots.append_array(FOOTPRINT_LOTS[f])
		for lot_name: String in lots:
			if hulls:
				await _hulls(t, lot_name, LOTS[lot_name], seed, scale)
			else:
				await _whole(t, lot_name, LOTS[lot_name], seed, scale)
	get_tree().quit()


func _ids() -> Array:
	if _arg("ids", "") != "":
		return Array(_arg("ids", "").split(","))
	match _arg("set", "base"):
		"special": return Gallery.SPECIAL.duplicate()
		"street": return Gallery.STREET.duplicate()
		"landmarks": return Gallery.LANDMARKS.duplicate()
	return Gallery.ORDER.duplicate()


# ── 통째 그림 가이드 ──────────────────────────────────────

func _whole(t: BuildingType, lot_name: String, size: Vector2, seed: int, scale: float) -> void:
	var lot := Rect2(-size * 0.5, size)
	var h := _floors(t) * IsoView.FLOOR_HEIGHT
	var pieces := BuildingModel.build(lot, t, seed, h)
	# 그림 범위: 인도까지 넣은 부지 바닥 + 덩어리마다 바닥~꼭대기
	var box := Rect2(IsoView.BASIS * lot.position, Vector2.ZERO)
	box = _span(box, lot.grow(SIDEWALK), 0.0, 0.0)
	for p in pieces:
		box = _span(box, p.rect, p.h0, p.top())
	box = box.grow(PAD)
	var px := Vector2i((box.size * scale).ceil())
	var xf := IsoView.BASIS.scaled(Vector2(scale, scale))
	xf.origin = -box.position * scale
	var name := _name(t, lot_name)
	var ground := not ("--no-ground" in OS.get_cmdline_user_args())
	var ref := await _shot(pieces, lot, t, seed, xf, px, false, ground)
	var guide := await _shot(pieces, lot, t, seed, xf, px, true, ground)
	var mass_pieces := BuildingModel.build(lot, t, seed, h)
	for p in mass_pieces:
		_strip(p)
	var mass := await _shot(mass_pieces, lot, t, seed, xf, px, true, ground)
	_save_on_magenta(ref, name + "_ref")
	_save_on_magenta(guide, name + "_guide")
	_save_on_magenta(mass, name + "_mass")
	var info := {
		"id": String(t.id), "name": t.display_name, "style": String(t.style), "lot": lot_name,
		"lot_size": [size.x, size.y], "seed": seed, "scale": scale, "image_size": [px.x, px.y],
		# 월드 (x, y)·높이 h → 그림 좌표 = origin + scale × (0.78(x−y), 0.39(x+y) − h). 월드 원점은 부지 가운데
		"origin": [xf.origin.x, xf.origin.y],
		"basis": [[IsoView.BASIS.x.x, IsoView.BASIS.x.y], [IsoView.BASIS.y.x, IsoView.BASIS.y.y]],
		"floor_height": IsoView.FLOOR_HEIGHT * t.visual_floor_scale, "floors": _floors(t),
		"pieces": _piece_list(pieces, 0),
	}
	_write_json(name, info)
	print("가이드 저장: %s (%d×%d)" % [name, px.x, px.y])


## 통째 그림을 붙였을 때 조각마다 오려 그리는 윤곽(BuildingSprite.outline)을 가이드와 같은 좌표로 흰색으로 찍는다.
## 바닥(부지 사각형)은 빼서, 윤곽에도 바닥에도 안 드는 그림 = 게임에서 잘려 안 보이는 곳을 찾게 한다
func _hulls(t: BuildingType, lot_name: String, size: Vector2, seed: int, scale: float) -> void:
	var name := _name(t, lot_name)
	var path := ProjectSettings.globalize_path("%s/%s.json" % [OUT, name])
	if not FileAccess.file_exists(path):
		push_warning("가이드 없음: %s" % name)
		return
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var lot := Rect2(-size * 0.5, size)
	BuildingSprite.enabled = true
	BuildingSprite.margins = false   # 넓히기 전 모형 그대로의 윤곽 (다듬기 도구가 넓힐 몫을 잰다)
	var pieces := BuildingModel.build(lot, t, seed, _floors(t) * IsoView.FLOOR_HEIGHT)
	BuildingSprite.enabled = false
	if pieces.is_empty() or pieces[0].sprite == null:
		push_warning("통째 그림 없음: %s" % name)
		return
	var xf := IsoView.BASIS.scaled(Vector2(scale, scale))
	xf.origin = Vector2(info["origin"][0], info["origin"][1])
	var px := Vector2i(int(info["image_size"][0]), int(info["image_size"][1]))
	var sub := SubViewport.new()
	sub.size = px
	sub.transparent_bg = true
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub)
	sub.canvas_transform = xf
	var root := Node2D.new()
	sub.add_child(root)
	for p in pieces:
		for v in BuildingView.make(root, null, -1, p):
			v.glow.visible = false
	for c in root.get_children():
		c.material = _white
	for f in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	sub.queue_free()
	img.save_png(ProjectSettings.globalize_path("%s/%s_hulls.png" % [OUT, name]))
	# 덩어리마다 윤곽 다각형 (가이드 px) — 다듬기 도구가 잘리는 곳을 덮을 덩어리를 골라 그 덩어리만 넓힌다
	var polys := []
	for p in pieces:
		for part in BuildingView.split(p.rect):
			polys.append({"index": p.sprite_index, "pts": _px(xf, BuildingSprite.outline(p, part))})
		_hull_tops(p, xf, polys)
	_write_json(name + "_hulls", {"pieces": polys})
	print("윤곽 저장: %s_hulls" % name)


## 찍을 층수 (--floors가 없으면 종류의 층수)
func _floors(t: BuildingType) -> int:
	var f := int(_arg("floors", "0"))
	return f if f > 0 else maxi(t.floors, 1)


## 가이드 이름: <ID>_<부지>, 층수를 바꿔 찍으면 <ID>_<부지>_f<층>
func _name(t: BuildingType, lot_name: String) -> String:
	var name := "%s_%s" % [String(t.id), lot_name]
	return name + ("_f%d" % _floors(t) if int(_arg("floors", "0")) > 0 else "")


func _hull_tops(p: BuildingModel.Piece, xf: Transform2D, polys: Array) -> void:
	for s: BuildingModel.Piece in p.on_top:
		polys.append({"index": s.sprite_index, "pts": _px(xf, BuildingSprite.outline(s, s.rect))})
		_hull_tops(s, xf, polys)


func _px(xf: Transform2D, pts: PackedVector2Array) -> Array:
	var out := []
	for v in pts:
		var q := xf * v
		out.append([snappedf(q.x, 0.1), snappedf(q.y, 0.1)])
	return out


## 화면(줌 1) 범위에 덩어리 r의 바닥(h0)·꼭대기(h1) 여덟 꼭짓점을 넣는다
func _span(box: Rect2, r: Rect2, h0: float, h1: float) -> Rect2:
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		for hh in [h0, h1]:
			box = box.expand(IsoView.BASIS * c - Vector2(0.0, hh))
	return box


## 덩어리만 남긴다: 창·벽 장식·간판·재질 얼룩을 빼고 벽·지붕 색을 회색 하나로
func _strip(p: BuildingModel.Piece) -> void:
	p.windows = &"none"
	p.deco = []
	p.text = ""
	p.signs = PackedStringArray()
	p.surface_detail = false
	if p.roof != &"tree":
		p.wall = Color(0.6, 0.6, 0.6)
		p.roof_color = Color(0.78, 0.78, 0.78)
	for s: BuildingModel.Piece in p.on_top:
		_strip(s)


func _shot(pieces: Array[BuildingModel.Piece], lot: Rect2, t: BuildingType, seed: int, xf: Transform2D,
		px: Vector2i, gray: bool, ground: bool) -> Image:
	var sub := SubViewport.new()
	sub.size = px
	sub.transparent_bg = true
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub)
	sub.canvas_transform = xf   # 트리에 넣은 뒤에야 캔버스가 생긴다
	var root := Node2D.new()
	sub.add_child(root)
	if ground:
		var g := Gallery.Ground.new()
		g.lot = lot
		g.kind = t
		g.seed = seed
		g.z_index = 50
		g.z_as_relative = false
		root.add_child(g)
	for p in pieces:
		for v in BuildingView.make(root, null, -1, p):
			v.glow.visible = false   # 낮 그림: 켜진 창은 불빛 마스크로 따로 받는다
	if gray:
		_paint(root)
	for f in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	sub.queue_free()
	return img


func _paint(n: Node) -> void:
	for c in n.get_children():
		if c is CanvasItem and c.material == null:
			c.material = _gray
		_paint(c)


func _save_on_magenta(img: Image, name: String) -> void:
	var bg := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	bg.fill(MAGENTA)
	bg.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	bg.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT, name]))


func _piece_list(pieces: Array, level: int) -> Array:
	var out := []
	for p: BuildingModel.Piece in pieces:
		var parts := []
		for r in BuildingView.split(p.rect):
			parts.append([r.position.x, r.position.y, r.size.x, r.size.y])
		out.append({
			"rect": [p.rect.position.x, p.rect.position.y, p.rect.size.x, p.rect.size.y],
			"h0": p.h0, "h1": p.h1, "top": p.top(), "roof": String(p.roof), "rise": p.rise,
			"windows": String(p.windows), "floor_height": p.floor_height, "blocks_ground": p.blocks_ground,
			"z_at_end": p.z_at_end, "level": level,
			# 그리는 순서 토막 (BuildingView.split). 통째 그림을 게임에 넣을 때 이 토막대로 세로로 잘라 z를 준다
			"parts": parts,
			"on_top": _piece_list(p.on_top, level + 1),
		})
	return out


# ── 벽면 정면도 템플릿 ────────────────────────────────────

## 정면(창 FRONT_BAYS칸) · 옆벽(SIDE_BAYS칸) · 옥상 정사각형을 한 장에 놓는다.
## 줄은 위에서부터 옥상 난간 · 윗층(반복) · 1층. 칸 크기는 게임 비율(층 높이·창 간격) 그대로이고 캔버스에 맞춰 키운다.
func _facade(t: BuildingType, seed: int) -> void:
	var lot := Rect2(-LOTS[FOOTPRINT_LOTS[t.footprints[0]][0]] * 0.5, LOTS[FOOTPRINT_LOTS[t.footprints[0]][0]])
	var pieces := BuildingModel.build(lot, t, seed, maxf(t.floors, 1) * IsoView.FLOOR_HEIGHT)
	var main: BuildingModel.Piece = null
	for p in _flat(pieces):
		if BAYS.has(p.windows) and (main == null or (p.h1 - p.h0) * p.rect.size.x > (main.h1 - main.h0) * main.rect.size.x):
			main = p
	if main == null:
		print("정면도 템플릿 건너뜀 (반복 벽면이 없는 모양 — 통째 덧칠로 받는다): ", t.id)
		return
	var bay_def: Array = BAYS[main.windows]
	var fl := main.floor_height                  # 층 높이 (화면 px)
	var bay := float(bay_def[0]) * WALL_PX       # 창 한 칸 폭 (화면 px)
	# 1층 모양: 가게층이 따로 떨어진 덩어리(상가주택)도 있어 건물 전체에서 본다
	var shop := false
	var piloti := false
	for p in _flat(pieces):
		shop = shop or p.deco.has(&"shops") or p.deco.has(&"shutter")
		piloti = piloti or p.deco.has(&"piloti")
	var parapet := fl * 0.5
	var col_h := parapet + fl * 2.0
	var gap := fl * 0.35
	var w := bay * (FRONT_BAYS + SIDE_BAYS) + col_h + gap * 2.0
	var k := minf((SHEET.x - SHEET_MARGIN * 2) / w, (SHEET.y - SHEET_MARGIN * 2) / col_h)
	var img := Image.create(SHEET.x, SHEET.y, false, Image.FORMAT_RGBA8)
	img.fill(MAGENTA)
	var x0 := (SHEET.x - w * k) * 0.5
	var y0 := (SHEET.y - col_h * k) * 0.5
	var rows := {"parapet": [0.0, parapet], "upper": [parapet, fl], "ground": [parapet + fl, fl]}
	var cells := {}
	var blocks := {"front": [x0, FRONT_BAYS], "side": [x0 + (bay * FRONT_BAYS + gap) * k, SIDE_BAYS]}
	for b: String in blocks:
		var bx: float = blocks[b][0]
		var n: int = blocks[b][1]
		for r: String in rows:
			var ry: float = y0 + float(rows[r][0]) * k
			var rh: float = float(rows[r][1]) * k
			var rect := Rect2i(roundi(bx), roundi(ry), roundi(bay * n * k), roundi(rh))
			cells["%s_%s" % [b, r]] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
			img.fill_rect(rect, Color(0.62, 0.62, 0.62) if r != "parapet" else Color(0.7, 0.7, 0.7))
			# 창 자리 (옆벽은 가운데 한 칸만, 1층은 가게 유리·필로티)
			for i in n:
				var cx := bx + bay * i * k
				if r == "parapet" or (b == "side" and i != n / 2):
					continue
				var wx: Vector2 = bay_def[1]
				var wz: Vector2 = bay_def[2]
				if r == "ground" and (shop or piloti):
					wx = Vector2(0.06, 0.94)
					wz = Vector2(0.0, 0.78) if shop else Vector2(0.0, 0.9)
				if wx.y <= wx.x:
					continue
				var win := Rect2i(roundi(cx + bay * wx.x * k), roundi(ry + rh * (1.0 - wz.y)),
					roundi(bay * (wx.y - wx.x) * k), roundi(rh * (wz.y - wz.x)))
				img.fill_rect(win, Color(0.3, 0.3, 0.32))
		# 칸 경계선 (위치만 알려 준다)
		for i in n + 1:
			img.fill_rect(Rect2i(roundi(bx + bay * i * k) - 1, roundi(y0), 2, roundi(col_h * k)), Color(0.45, 0.45, 0.45))
		for yy in [parapet, parapet + fl]:
			img.fill_rect(Rect2i(roundi(bx), roundi(y0 + yy * k) - 1, roundi(bay * n * k), 2), Color(0.45, 0.45, 0.45))
	var roof := Rect2i(roundi(x0 + (bay * (FRONT_BAYS + SIDE_BAYS) + gap * 2.0) * k), roundi(y0), roundi(col_h * k), roundi(col_h * k))
	img.fill_rect(roof, Color(0.78, 0.78, 0.78))
	cells["roof"] = [roof.position.x, roof.position.y, roof.size.x, roof.size.y]
	var name := "%s_facade" % String(t.id)
	img.save_png(ProjectSettings.globalize_path("%s/%s_template.png" % [OUT, name]))
	_write_json(name, {
		"id": String(t.id), "name": t.display_name, "style": String(t.style), "windows": String(main.windows),
		"floor_height": fl, "bay_world": bay_def[0], "bay_screen": bay, "parapet": parapet,
		"ground_floor": "shops" if shop else ("piloti" if piloti else "plain"),
		"front_bays": FRONT_BAYS, "side_bays": SIDE_BAYS,
		# 템플릿 1px = 게임 화면(줌 1) 1/k px. 받은 그림이 캔버스 크기와 다르면 같은 비율로 다시 잡는다
		"sheet": [SHEET.x, SHEET.y], "texel_per_screen_px": k, "cells": cells,
		"wall_color": t.wall_color.to_html(false),
	})
	print("정면도 템플릿 저장: %s (층 %.1fpx · 창 간격 %.1fpx · 배율 %.2f)" % [name, fl, bay, k])


func _flat(pieces: Array) -> Array:
	var out := []
	for p: BuildingModel.Piece in pieces:
		out.append(p)
		out.append_array(_flat(p.on_top))
	return out


# ── 공통 ──────────────────────────────────────────────────

func _type(id: StringName) -> BuildingType:
	if String(id) in Gallery.LANDMARKS or String(id) in Gallery.STREET:
		return load("res://data/buildings/landmarks/%s.tres" % String(id).to_lower()) as BuildingType
	var all: Array = City.BUILDING_TYPES + City.SCATTER_LOOKS + [City.LOOK_POLICE, City.LOOK_HOSPITAL, City.LOOK_CAR_CENTER]
	for g in City.GANGS:
		all.append(g.base_look)
	for t in all:
		if t and t.id == id:
			return t
	return null


func _write_json(name: String, data: Dictionary) -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path("%s/%s.json" % [OUT, name]), FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))


func _arg(key: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.split("=", true, 1)[1]
	return default
