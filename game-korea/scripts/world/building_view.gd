class_name BuildingView
extends Node2D
## 2.5D 건물 덩어리(BuildingModel.Piece) 한 조각. 바닥 사각형에서 화면을 향한 두 벽(동·남)을 세우고,
## 맨 앞 조각(roof)이 지붕과 그 위에 얹힌 것(윗층·옥상 소품·굴뚝)을 그린다.
## 긴 덩어리는 정사각형에 가까운 조각으로 나눈다 — 조각 가운데의 깊이(x+y)로 정렬해야
## 옆 인도를 걷는 사람이 벽 뒤로 숨지 않는다.
## 그림은 높이를 월드 오프셋(IsoView.lift)으로 바꿔 그리므로 한 번만 그리면 된다.
## 창 간격은 덩어리 전체 벽을 기준으로 잡는다 — 조각 경계에서 창이 어긋나지 않는다.

## 간판은 코드로 그린 녹슨 금속판(SpecialDecor._metal)에 굵은 글씨다 (M7 전에는 그림 파일을 쓰지 않는다).
## 바탕·글자 색은 글자에 든 낱말로 고른다. 위에서부터 먼저 맞는 낱말을 쓴다
const SIGN_STYLES := [
	["오피스텔", Color(0.1, 0.22, 0.78), Color(0.97, 0.97, 1.0)],
	["고시", Color(0.96, 0.93, 0.86), Color(0.85, 0.1, 0.1)],
	["원룸", Color(0.1, 0.22, 0.78), Color(0.97, 0.97, 1.0)],
	["PC", Color(0.86, 0.1, 0.1), Color(1.0, 0.97, 0.95)],
	["만화", Color(0.12, 0.26, 0.82), Color(0.97, 0.97, 1.0)],
	["뷔페", Color(0.86, 0.1, 0.12), Color(1.0, 0.97, 0.95)],
	["음식", Color(0.86, 0.1, 0.12), Color(1.0, 0.97, 0.95)],
	["부동산", Color(0.96, 0.94, 0.88), Color(0.08, 0.18, 0.7)],
	["임대", Color(0.98, 0.82, 0.1), Color(0.08, 0.07, 0.06)],
	["의원", Color(0.55, 0.12, 0.85), Color(1.0, 0.96, 1.0)],
	["외과", Color(0.55, 0.12, 0.85), Color(1.0, 0.96, 1.0)],
	["노래", Color(0.7, 0.1, 0.6), Color(1.0, 0.92, 0.3)],
	["치킨", Color(0.95, 0.5, 0.08), Color(1.0, 0.98, 0.9)],
	["BAR", Color(0.1, 0.1, 0.12), Color(1.0, 0.82, 0.2)],
	["카페", Color(0.36, 0.22, 0.14), Color(0.98, 0.92, 0.8)],
	["사우나", Color(0.96, 0.94, 0.88), Color(0.85, 0.1, 0.1)],
	["약국", Color(0.12, 0.55, 0.3), Color(0.97, 1.0, 0.97)],
	["분식", Color(0.95, 0.75, 0.1), Color(0.75, 0.08, 0.08)],
	["세탁", Color(0.1, 0.5, 0.75), Color(0.97, 0.99, 1.0)],
	["GO25", Color(0.96, 0.95, 0.9), Color(0.05, 0.52, 0.56)],
	# 재래시장 업종
	["시장", Color(0.1, 0.22, 0.62), Color(1.0, 0.36, 0.3)],
	["청과", Color(0.16, 0.5, 0.22), Color(1.0, 0.95, 0.4)],
	["채소", Color(0.16, 0.5, 0.22), Color(0.97, 1.0, 0.95)],
	["생선", Color(0.1, 0.4, 0.75), Color(0.97, 0.99, 1.0)],
	["건어물", Color(0.96, 0.93, 0.86), Color(0.1, 0.3, 0.65)],
	["정육", Color(0.8, 0.1, 0.12), Color(1.0, 0.97, 0.95)],
	["떡집", Color(0.96, 0.85, 0.9), Color(0.7, 0.1, 0.3)],
	["반찬", Color(0.95, 0.75, 0.1), Color(0.35, 0.18, 0.05)],
	["잡화", Color(0.25, 0.25, 0.27), Color(0.98, 0.9, 0.4)],
	["방앗간", Color(0.96, 0.93, 0.86), Color(0.75, 0.2, 0.1)],
	# 인쇄·공구 골목 (거리 건물)
	["인쇄", Color(0.96, 0.95, 0.9), Color(0.1, 0.25, 0.7)],
	["제본", Color(0.12, 0.3, 0.7), Color(0.97, 0.97, 1.0)],
	["출력", Color(0.2, 0.55, 0.3), Color(0.97, 1.0, 0.95)],
	["공구", Color(0.98, 0.82, 0.1), Color(0.1, 0.08, 0.06)],
	["철물", Color(0.75, 0.12, 0.1), Color(1.0, 0.97, 0.9)],
	["전기", Color(0.1, 0.42, 0.78), Color(1.0, 0.92, 0.3)],
]
## 맞는 낱말이 없는 이름의 색 (번갈아)
const SIGN_PLAIN := [[Color(0.1, 0.22, 0.78), Color(0.97, 0.97, 1.0)], [Color(0.25, 0.25, 0.27), Color(0.97, 0.97, 0.95)]]
## 1층 가게 간판에 쓸 업종이 건물 데이터에 없을 때 (오피스텔·고시원 1층 등)
const SHOP_WORDS := ["PC방", "만화", "뷔페", "외국음식", "부동산"]
## 1층 가게 간판으로 쓰지 않는 낱말 (건물 이름·세로 간판용)
const NOT_SHOP := ["오피스텔", "고시", "원룸", "임대", "의원"]


## [바탕, 글자] — 맞는 낱말이 없으면 -1
func _sign_style(text: String) -> int:
	for i in SIGN_STYLES.size():
		if SIGN_STYLES[i][0] in text:
			return i
	return -1


## 금속 간판 한 장 (가운데 s, 위 z, max_w × max_h 안에). vertical이면 한 글자씩 위에서 아래로
func _board(text: String, s: float, z: float, max_w: float, max_h: float, vertical := false) -> void:
	if text == "" or max_w < 6.0 or max_h < 6.0:
		return
	var font := ThemeDB.fallback_font
	var i := _sign_style(text)
	var colors: Array = SIGN_STYLES[i].slice(1) if i >= 0 else SIGN_PLAIN[posmod(_p.seed, SIGN_PLAIN.size())]
	var bg: Color = colors[0]
	var ink: Color = colors[1]
	var outline := Color(0, 0, 0, 0.35) if bg.get_luminance() < 0.55 else Color(0, 0, 0, 0)
	var w: float
	var hh: float
	if vertical:
		var n := text.length()
		w = max_w
		var cell := minf(w * 0.82, (max_h - 6.0) / n)
		hh = cell * n + 6.0
		draw_set_transform_matrix(_frame(s - w * 0.5, w, z))
		SpecialDecor._metal(self, Rect2(0, 0, w, hh), bg, _p.seed + n)
		var size := int(minf(cell * 0.86, w * 0.72))
		for k in n:
			SpecialDecor._bold(self, font, Vector2(0, 3.0 + (k + 1) * cell - cell * 0.16), text[k], w, size, ink, outline)
	else:
		hh = max_h
		var size := int(hh * 0.62)
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		w = minf(max_w, maxf(tw + hh * 0.7, hh * 1.6))
		if tw > w - 6.0:
			size = maxi(6, int(size * (w - 6.0) / tw))
		draw_set_transform_matrix(_frame(s - w * 0.5, w, z))
		SpecialDecor._metal(self, Rect2(0, 0, w, hh), bg, _p.seed + text.length())
		SpecialDecor._bold(self, font, Vector2(0, hh * 0.5 + size * 0.36), text, w, size, ink, outline)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 1층 가게 간판 글자: 데이터의 업종이면 그대로, 건물 이름 등이면 흔한 업종 하나
func _shop_word(text: String, k: int) -> String:
	if _sign_style(text) >= 0 and not NOT_SHOP.any(func(w): return w in text):
		return text
	return SHOP_WORDS[posmod(_p.seed + k + int(_n.x), SHOP_WORDS.size())]

## 불빛 조각(lights): 본 조각의 자식으로 같은 조각을 한 번 더 세워, 켜질 창과 간판만 다시 그린다.
## 셰이더가 밤에 화면을 어둡게 하는 CanvasModulate를 되돌려(boost) 불 켜진 곳만 밝게 남는다.
## 창 불빛은 UV.x = 2로 표시하고 UV.y - 2에 켜지는 차례를 담는다 — 켜진 비율(lights_on)보다 차례가 빠른 창만 보인다.
## 값은 DayNight가 시각에 맞춰 넣으므로 다시 그리지 않는다 (DayNight 없는 갤러리는 기본값: 다 켜짐, 보정 없음).
## 벽면 그림(BuildingSkin)의 불빛은 UV.x를 4 당겨(−4~−3) 표시하고, 꼭짓점 색 r에 켜지는 차례를 담는다.
const LIGHT_SHADER := """
shader_type canvas_item;
uniform vec3 boost = vec3(1.0);
uniform float lights_on = 1.0;
varying vec4 vcol;
void vertex() {
	vcol = COLOR;
}
void fragment() {
	if (UV.x < -1.5) {
		COLOR = texture(TEXTURE, vec2(UV.x + 4.0, UV.y));
		COLOR.a *= 1.0 - smoothstep(lights_on - 0.04, lights_on, vcol.r);
	} else if (UV.x > 1.5) {
		COLOR.a *= 1.0 - smoothstep(lights_on - 0.04, lights_on, UV.y - 2.0);
	}
	COLOR.rgb *= boost;
}
"""
## 불빛 조각에서 그리는 벽 장식 (간판·가게 앞. 낮에는 본 조각에 그린 것과 똑같이 보인다)
const LIGHT_DECOS: Array[StringName] = [&"shops", &"awning", &"name", &"plate", &"top_sign", &"big_sign",
	&"rental_image", &"vsign", &"band_signs", &"emblem_sign", &"hospital_vsign", &"er_band", &"office_plate",
	&"repair_sign", &"sauna_sign", &"store_front", &"store_band", &"wall_lamps", &"landmark_sign", &"street_sign", &"street_nightlife", &"street_vertical_neon"]
static var _light_material: ShaderMaterial


static func light_material() -> ShaderMaterial:
	if _light_material == null:
		var shader := Shader.new()
		shader.code = LIGHT_SHADER
		_light_material = ShaderMaterial.new()
		_light_material.shader = shader
	return _light_material


## 불 켜진 비율(0~1)과 지금 화면 색(CanvasModulate)을 넣는다. 화면 색을 나눠 되돌리고 조금 더 밝힌다
static func set_lights(on: float, screen: Color) -> void:
	var m := light_material()
	m.set_shader_parameter("lights_on", on)
	m.set_shader_parameter("boost", Vector3(1.0 / screen.r, 1.0 / screen.g, 1.0 / screen.b) * (1.0 + 0.12 * on))


const SHOP_BAND := 0.75        ## 1층 상가 띠 높이 (층 높이 배수)
const BAY := 34.0              ## 창 간격 (월드 px)
const LIT := Color(0.95, 0.78, 0.45)
const UNLIT := Color(0.1, 0.13, 0.18)
const GLASS := Color(0.15, 0.24, 0.34)
const PAPER := Color(0.96, 0.82, 0.52)    ## 한옥 창호지 불빛

var city: City                 ## 특수 건물 지붕 그림(art)에만 쓴다
var idx := -1                  ## city.buildings 번호
var piece: BuildingModel.Piece
var rect: Rect2                ## 덩어리 전체 바닥
var part: Rect2                ## 이 조각
var roof := false              ## 지붕을 그리는 조각 (덩어리마다 하나, 가장 앞)
var height := 72.0             ## 덩어리 꼭대기 (지붕·얹힌 것 포함)
var lights := false            ## 불빛 조각이다 (켜질 창·간판만 그린다)
var glow: BuildingView         ## 이 조각의 불빛 조각 (자식)
var _mute := false             ## 불빛 조각이 창을 훑는 동안: 벽·창틀(_quad·_hline)은 그리지 않는다

# 지금 그리는 벽 한 면 (_face 동안만 쓴다)
var _p: BuildingModel.Piece
var _fa := Vector2.ZERO        ## 벽 전체의 시작 모서리 (바닥)
var _along := Vector2.RIGHT    ## 벽을 따라가는 방향
var _len := 0.0                ## 벽 전체 길이
var _s0 := 0.0                 ## 이 조각이 그리는 구간
var _s1 := 0.0
var _n := Vector2.DOWN         ## 바깥 법선
var _shade := 0.0
var _fh := IsoView.FLOOR_HEIGHT
var _floors := 1


## 덩어리 하나를 조각으로 나눠 parent 밑에 세운다
static func make(parent: Node, c: City, i: int, p: BuildingModel.Piece) -> Array[BuildingView]:
	var out: Array[BuildingView] = []
	var parts := split(p.rect)
	for k in parts.size():
		var v := BuildingView.new()
		v.city = c
		v.idx = i
		v.piece = p
		v.rect = p.rect
		v.part = parts[k]
		v.roof = k == parts.size() - 1
		v.height = p.top()
		if p.skin or p.sprite:
			v.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # 크게 그린 벽면 그림을 줄여 그린다 (불빛 조각도 따른다)
		parent.add_child(v)
		out.append(v)
		# 불빛 조각: 같은 z(상대 0)에서 본 조각 바로 뒤에 그려지고, 흐려짐(modulate)·숨김을 따른다
		var l := BuildingView.new()
		l.city = c
		l.idx = i
		l.piece = p
		l.rect = p.rect
		l.part = parts[k]
		l.roof = v.roof
		l.height = v.height
		l.lights = true
		l.material = light_material()
		v.glow = l
		v.add_child(l)
	return out


func _ready() -> void:
	if lights:
		return
	z_as_relative = false
	z_index = IsoView.z_of(part.end - Vector2(0.5, 0.5) if piece.z_at_end else part.get_center())


func _draw() -> void:
	if piece.sprite:
		_sprite_draw()
		return
	_walls(piece, part)
	if roof:
		_top(piece)
		if piece.skin and not lights:
			_skin_parapet(piece)


# ── 벽 ────────────────────────────────────────────────────

func _walls(p: BuildingModel.Piece, seg: Rect2) -> void:
	if p.roof in [&"tree", &"chimney", &"tank", &"tent"] or p.roof in SpecialDecor.BARE or p.roof in StreetDecor.BARE:
		return   # 벽 없이 지붕 그림에서 통째로 그린다
	var r := p.rect
	if seg.end.x >= r.end.x - 0.5:
		_face(p, Vector2(r.end.x, seg.position.y), Vector2(r.end.x, seg.end.y), Vector2.RIGHT)
	if seg.end.y >= r.end.y - 0.5:
		_face(p, Vector2(seg.position.x, r.end.y), Vector2(seg.end.x, r.end.y), Vector2.DOWN)
		if seg.end.x >= r.end.x - 0.5 and not lights:
			draw_line(r.end + IsoView.lift(p.h0), r.end + IsoView.lift(p.h1), p.wall.lightened(0.12), 1.5)   # 모서리


## 벽 한 면: 이 조각 구간 a→b, 바깥 법선 n
func _face(p: BuildingModel.Piece, a: Vector2, b: Vector2, n: Vector2) -> void:
	_p = p
	_n = n
	_shade = IsoView.face_shade(n)
	var south := n == Vector2.DOWN
	_fa = Vector2(p.rect.position.x, p.rect.end.y) if south else Vector2(p.rect.end.x, p.rect.position.y)
	_along = Vector2.RIGHT if south else Vector2.DOWN
	_len = p.rect.size.x if south else p.rect.size.y
	_s0 = (a - _fa).dot(_along)
	_s1 = (b - _fa).dot(_along)
	_floors = maxi(1, roundi((p.h1 - p.h0) / p.floor_height))
	_fh = (p.h1 - p.h0) / _floors
	if p.skin:
		_skin_wall(p, south)
		return
	var wall := p.wall.darkened(_shade)
	if lights:
		# 불빛 조각: 켜질 창과 간판만
		_mute = true
		_windows(p, south, wall)
		_mute = false
		for d in p.deco:
			if d in LIGHT_DECOS or d in StreetDecor.LIGHT:
				_deco(d, south)
		return
	draw_colored_polygon(IsoView.wall(a, b, p.h0, p.h1), wall)
	if p.surface_detail:
		_material(p, wall)
	_windows(p, south, wall)
	if p.surface_detail:
		# 처마 아래 띠 음영과 층 사이 돌출 수평 테두리.
		var h := p.h1-p.h0
		_quad(0,_len,h-3,h,Color(0.015,0.025,0.035,0.4))
		if p.windows in [&"brick", &"punched"]:
			for f in range(1,_floors):
				_hline(f*_fh-1,Color(0.02,0.025,0.04,0.3),2)
				_hline(f*_fh,wall.lightened(0.2),1.5, -INF, INF, 1.5)
	for d in p.deco:
		if not (d in LIGHT_DECOS or d in StreetDecor.LIGHT) and d != &"number":
			_deco(d, south)
	_service_details(p)
	if p.surface_detail:
		_architecture(p, wall)
	if &"number" in p.deco:
		_deco(&"number", south)   # 동 번호판은 벽 기둥·층 띠 위에 얹는다 (먼저 그리면 기둥이 글자를 가른다)


## 종류별 돌출 구조. 창 위에 겹치는 기둥은 창 사이 경계에만 배치한다.
func _architecture(p: BuildingModel.Piece, wall: Color) -> void:
	var h := p.h1 - p.h0
	if h < 24 or _len < 45:
		return
	if p.windows == &"apt":
		var bays := maxi(1, int(_len / 52.0))
		for k in range(1, bays):
			var s := k * _len / bays
			_quad(s-2,s+2,0,h,wall.lightened(0.24),3)
			_quad(s+2,s+4,0,h,wall.darkened(0.24),1)
		for f in range(1,_floors):
			_hline(f*_fh+2,wall.darkened(0.25),2,-INF,INF,2)
	elif p.windows in [&"glass", &"officetel"]:
		# 각 층의 금속 스팬드럴 및 입구 기단.
		for f in range(1,_floors):
			_quad(0,_len,f*_fh-2,f*_fh,wall.darkened(0.18),1.5)
			_hline(f*_fh,Color("a0aeb6").darkened(_shade),1,-INF,INF,2)
		_quad(0,_len,0,3,Color("3e454b"),1.5)
	elif p.windows in [&"metal", &"ribbon"]:
		# 산업 건물의 구조 기둥과 창 아래 환기구.
		var bays := maxi(1,int(_len/70))
		for k in range(bays+1):
			var s := clampf(k*_len/bays,2,_len-2)
			_quad(s-1.5,s+1.5,0,h,wall.lightened(0.2),2)
		for k in maxi(1,int(_len/100)):
			var s := 22.0+k*100
			_quad(s,s+18,h-13,h-5,Color("303c40"),1)
			for slot in 3:
				_hline(h-11+slot*2,Color("80908e"),1,s+2,s+16,1.5)
	elif p.windows in [&"punched", &"brick", &"slit"]:
		# 기반석·코너 벽돌은 평평한 벽의 모서리를 강조한다.
		_quad(0,_len,0,3,wall.darkened(0.25),1)
		for z in range(4,int(h),8):
			_quad(0,4,z,minf(z+5,h),wall.lightened(0.16),1)
			_quad(_len-4,_len,z,minf(z+5,h),wall.lightened(0.16),1)


## 벽 위 한 점 (s = 벽을 따라 거리, z = 이 덩어리 바닥에서 높이, out = 벽 밖으로 나온 거리)
func _pt(s: float, z: float, out := 0.0) -> Vector2:
	return _fa + _along * s + _n * out + IsoView.lift(_p.h0 + z)


## 벽 위 사각형 (이 조각 구간으로 자른다).
## draw_primitive로 그린다: draw_colored_polygon은 부를 때마다 렌더러에 도형 버퍼를 새로 만들어,
## 도시 전체 벽의 재질 칸(_material)만큼 쌓이면 버퍼 한도를 넘겨 창 모드 실행이 멈췄다. 삼각분할도 하지 않아
## 높이가 거의 0인 칸에서 나던 'Invalid polygon' 오류도 없다.
func _quad(s0: float, s1: float, z0: float, z1: float, color: Color, out := 0.0) -> void:
	if _mute:
		return
	var a := maxf(s0, _s0)
	var b := minf(s1, _s1)
	if b - a < 0.3 or absf(z1 - z0) < 0.05:
		return
	draw_primitive(PackedVector2Array([_pt(a, z0, out), _pt(b, z0, out), _pt(b, z1, out), _pt(a, z1, out)]),
		PackedColorArray([color]), PackedVector2Array())


func _hline(z: float, color: Color, width := 1.0, s0 := -INF, s1 := INF, out := 0.0) -> void:
	if _mute:
		return
	var a := maxf(s0, _s0)
	var b := minf(s1, _s1)
	if b > a:
		draw_line(_pt(a, z, out), _pt(b, z, out), color, width)


## 밤에만 보이는 불빛 (불빛 조각에서만 부른다). turn = 켜지는 차례 0~1 — 0이면 날이 저물자마자 켜진다
func _glow(s0: float, s1: float, z0: float, z1: float, color: Color, turn := 0.0, out := 0.0) -> void:
	var a := maxf(s0, _s0)
	var b := minf(s1, _s1)
	if b - a < 0.3 or absf(z1 - z0) < 0.05:
		return
	var uv := Vector2(2.0, 2.0 + turn)
	draw_primitive(PackedVector2Array([_pt(a, z0, out), _pt(b, z0, out), _pt(b, z1, out), _pt(a, z1, out)]),
		PackedColorArray([color]), PackedVector2Array([uv, uv, uv, uv]))


## _glow를 지금 좌표계(간판 좌표계 등)의 사각형으로
func _glow_rect(r: Rect2, color: Color) -> void:
	var uv := Vector2(2.0, 2.0)
	draw_primitive(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([color]), PackedVector2Array([uv, uv, uv, uv]))


## 불 켜질 수 있는 창. 본 조각은 모든 창을 꺼진 유리로 그리고(낮에는 다 꺼져 보인다),
## 불빛 조각은 켜질 창(lit)에만 불빛과 둘레 번짐을 그린다. key로 켜지는 차례를 섞는다. bars면 가운데 창살을 비운다
func _window(c0: float, c1: float, z0: float, z1: float, lit: bool, key: int, color := LIT, bars := false) -> void:
	if not lights:
		_quad(c0, c1, z0, z1, UNLIT.darkened(_shade * 0.4))
		return
	if not lit:
		return
	var turn := BuildingModel.hash01(_p.seed + key * key * 31, key + int(_n.x) * 977) * 0.95
	var on := color.darkened(_shade * 0.4)
	_glow(c0 - 2.0, c1 + 2.0, z0 - 2.0, z1 + 1.5, Color(on, 0.13 * on.a), turn)
	if bars:
		var m := (c0 + c1) * 0.5
		_glow(c0, m - 0.6, z0, z1, on, turn)
		_glow(m + 0.6, c1, z0, z1, on, turn)
	else:
		_glow(c0, c1, z0, z1, on, turn)


func _in(s: float) -> bool:
	return s >= _s0 and s < _s1


## 벽 평면 좌표계: (x, y) = (화면 왼쪽→오른쪽으로 벽을 따라, 화면 아래로 px). 폭 w 구간의 왼쪽 위가 원점
func _frame(s: float, w: float, z: float) -> Transform2D:
	if IsoView.to_screen_dir(_along).x < 0.0:
		return Transform2D(-_along, -IsoView.LIFT, _pt(s + w, z))
	return Transform2D(_along, -IsoView.LIFT, _pt(s, z))


func _lit(k: int, f: int, rate: int) -> bool:
	return posmod(_p.seed * 7 + k * 13 + f * 29 + int(_n.x) * 5, 11) < rate


func wall_trim() -> Color:
	return _p.wall.lightened(0.12).darkened(_shade)


## 벽 전체 좌표로 재질 색 편차를 정한다. 게임 RNG를 사용하지 않는다.
func _material(p: BuildingModel.Piece, wall: Color) -> void:
	var h := p.h1-p.h0
	if h < 12 or _len < 25:
		return
	var brick := p.windows == &"brick"
	var step_x := 12.0 if brick else 28.0
	var step_z := 5.0 if brick else 18.0
	var first := maxi(0,int(_s0/step_x)-1)
	var last := mini(int(ceil(_len/step_x)),int(ceil(_s1/step_x))+1)
	for row in int(ceil(h/step_z)):
		for col in range(first,last):
			var value := BuildingModel.hash01(p.seed,row*127+col*17+int(_n.x)*431)
			var left := col*step_x+(step_x*0.5 if brick and row%2 else 0.0)
			var tint := wall.lightened(value*0.12) if value > 0.5 else wall.darkened((0.5-value)*0.22)
			_quad(left+0.5,minf(left+step_x-0.5,_len),row*step_z+0.5,minf((row+1)*step_z-0.6,h),tint)
	# 빗물 자국은 창보다 먼저 세로 방향으로 얇게 그린다.
	for k in 8:
		var s := BuildingModel.hash01(p.seed,k+801)*_len
		var top := h*(0.45+BuildingModel.hash01(p.seed,k+901)*0.5)
		_quad(s,s+2, maxf(0,top-18),top,Color(0.02,0.04,0.05,0.12))


## 배관과 하단 물때는 벽 끝에만 배치한다. 별도 RNG나 물리 노드는 만들지 않는다.
func _service_details(p: BuildingModel.Piece) -> void:
	var h := p.h1-p.h0
	if h < 28.0 or p.windows in [&"none", &"hanok", &"glass", &"caravan"]:
		return
	var pipe := _len-5.0
	if _in(pipe):
		draw_line(_pt(pipe+1,2),_pt(pipe+1,h-3),Color(0,0,0,0.22),3)
		draw_line(_pt(pipe,2,1),_pt(pipe,h-3,1),Color("707979").darkened(_shade),2)
		var z := 8.0
		while z < h-3:
			_hline(z,Color("a0a69e").darkened(_shade),1,pipe-2,pipe+2,1)
			z += 20.0
	_hline(1.2,Color(0.08,0.09,0.1,0.35),2)
	# 낮은 전기함과 환기구는 좁은 벽에 생략한다.
	if _len > 65.0:
		_quad(8,16,5,14,UNIT_COLOR.darkened(_shade+0.2),1)
		for slot in 3:
			_hline(7+slot*2,Color("3b4549"),0.8,10,14,1.1)


## 층마다 같은 간격의 창 (bay = 창 간격, wx·wz = 칸 안에서 창이 차지하는 비율)
func _grid(bay: float, wx: Vector2, wz: Vector2, skip_ground: bool, rate: int, frame := Color(0, 0, 0, 0)) -> void:
	var bays := maxi(1, int(_len / bay))
	var w := _len / bays
	for f in _floors:
		if f == 0 and skip_ground:
			continue
		for k in bays:
			var c0 := k * w + w * wx.x
			var c1 := k * w + w * wx.y
			if c1 <= _s0 or c0 >= _s1:
				continue
			var z0 := f * _fh + _fh * wz.x
			var z1 := f * _fh + _fh * wz.y
			if frame.a > 0.0:
				_quad(c0 - 1.5, c1 + 1.5, z0 - 1.5, z1 + 1.0, frame.darkened(_shade))
			_window(c0, c1, z0, z1 - 1.2 if lights else z1, _lit(k, f, rate), k * 41 + f, LIT, c1 - c0 > 9.0)
			# 창틀의 깊이, 가운데 창살, 창턱. 모든 면은 조각 구간으로 잘린다.
			var trim := frame.darkened(_shade + 0.15) if frame.a > 0.0 else wall_trim()
			_quad(c0, c1, z1 - 1.2, z1, Color(0.02, 0.025, 0.04, 0.55))
			if c1 - c0 > 9.0:
				_quad((c0+c1)*0.5-0.6,(c0+c1)*0.5+0.6,z0,z1,trim)
				_quad(c0+1,c0+3,z0+1,z1-2,Color(0.75,0.88,1.0,0.16))
			_hline(z0-1.0,trim.lightened(0.18),1.5,c0-2,c1+2,1.5)


func _windows(p: BuildingModel.Piece, south: bool, wall: Color) -> void:
	var ground := p.deco.has(&"shops") or p.deco.has(&"piloti") or p.deco.has(&"shutter")
	match p.windows:
		&"punched":
			_grid(BAY, Vector2(0.22, 0.78), Vector2(0.3, 0.8), ground, 2, p.wall.lightened(0.25))
		&"brick":
			# 줄눈
			var z := 3.0
			while z < p.h1 - p.h0 and not lights:
				_hline(z, wall.darkened(0.14), 1.0)
				var course := int(z / 4.0)
				var s := floorf(_s0 / 12.0)*12.0 + (6.0 if course%2 == 0 else 0.0)
				while s < _s1:
					if _in(s):
						draw_line(_pt(s,maxf(0,z-4)),_pt(s,z),wall.darkened(0.12),0.65)
					s += 12.0
				z += 4.0
			_grid(BAY, Vector2(0.24, 0.76), Vector2(0.3, 0.8), ground, 2, Color(0.75, 0.72, 0.66))
		&"slit":
			_grid(15.0, Vector2(0.3, 0.7), Vector2(0.25, 0.82), ground, 3)
		&"apt":
			_grid(26.0, Vector2(0.12, 0.88), Vector2(0.28, 0.8), false, 2)
			if south and not lights:
				for f in range(1, _floors):
					_hline(f * _fh + _fh * 0.28, Color(0.9, 0.9, 0.88).darkened(_shade * 0.5), 1.5, -INF, INF, 2.0)
				var bays := maxi(1, int(_len / 52.0))
				for k in range(1, bays):
					var s := k * _len / bays
					if _in(s):
						draw_line(_pt(s, 0.0, 2.0), _pt(s, _p.h1 - _p.h0, 2.0), wall.darkened(0.2), 1.5)
		&"glass", &"officetel":
			var glass_from := 0.0
			if p.windows == &"officetel":
				glass_from = _len * 0.62 if south else _len   # 남쪽 벽 동쪽 끝만 유리 기둥
				_grid(BAY, Vector2(0.22, 0.78), Vector2(0.3, 0.8), ground, 2, p.wall.lightened(0.2))
			for f in _floors:
				if f == 0 and ground:
					continue
				_quad(glass_from + 2.0, _len - 2.0, f * _fh + _fh * 0.12, f * _fh + _fh * 0.94, GLASS.darkened(_shade * 0.5))
				var bays := maxi(1, int((_len - glass_from) / 22.0))
				var w := (_len - glass_from) / bays
				for k in bays:
					if lights:
						if _lit(k, f, 3):
							_window(glass_from + k * w + 2.0, glass_from + (k + 1) * w - 1.0, f * _fh + _fh * 0.2, f * _fh + _fh * 0.86,
								true, k * 41 + f, Color(LIT, 0.85))
					else:
						_quad(glass_from+k*w+3,glass_from+k*w+w*0.35,f*_fh+_fh*0.23,f*_fh+_fh*0.82,
							Color(0.55,0.76,0.9,0.13))
				_hline(f*_fh+_fh*0.94,p.wall.lightened(0.22).darkened(_shade),1,glass_from+2,_len-2)
			var bays := maxi(1, int((_len - glass_from) / 22.0))
			for k in bays + 1:
				var s := glass_from + k * (_len - glass_from) / bays
				if _in(s) and s < _len and not lights:
					draw_line(_pt(s, _fh if ground else 0.0), _pt(s, p.h1 - p.h0), p.wall.lightened(0.1).darkened(_shade), 1.0)
		&"ribbon":
			for f in _floors:
				_quad(6.0, _len - 6.0, f * _fh + _fh * 0.4, f * _fh + _fh * 0.72, Color(0.55, 0.62, 0.6).darkened(_shade * 0.5))
				var k := 0
				var s := 6.0
				while s < _len - 10.0:
					if _lit(k, f, 2) and lights:
						_window(s, s + 26.0, f * _fh + _fh * 0.42, f * _fh + _fh * 0.7, true, k * 41 + f)
					s += 30.0
					k += 1
		&"metal":
			var s := 4.0
			while s < _len and not lights:
				if _in(s):
					draw_line(_pt(s, 0.0), _pt(s, p.h1 - p.h0), wall.darkened(0.16), 1.0)
				s += 7.0
			_hline(p.h1 - p.h0 - 3.0, wall.lightened(0.15), 2.0)
		&"hanok":
			# 기둥 사이 창살 (불 켜진 창호지)
			var posts := maxi(2, int(_len / 24.0))
			var w := _len / posts
			for k in posts:
				if _lit(k, 0, 6):
					# 창호지: 낮에는 흐린 종이, 밤에는 불빛 조각이 켜진 창호지와 창살을 다시 그린다
					var top := p.h1 - p.h0 - 5.0
					var turn := BuildingModel.hash01(p.seed + k * k * 31, k + int(_n.x) * 977) * 0.95
					if lights:
						_glow(k * w + 3.0, (k + 1) * w - 3.0, 6.0, top, PAPER.darkened(_shade * 0.35), turn)
					else:
						_quad(k * w + 3.0, (k + 1) * w - 3.0, 6.0, top, PAPER.darkened(0.3 + _shade * 0.35))
					for g in 3:
						var s := k * w + 3.0 + (g + 1) * (w - 6.0) / 4.0
						if lights:
							_glow(s - 0.5, s + 0.5, 6.0, top, WOOD_DARK, turn)
						elif _in(s):
							draw_line(_pt(s, 6.0), _pt(s, top), WOOD_DARK, 1.0)
					if lights:
						_glow(k * w + 3.0, (k + 1) * w - 3.0, (p.h1 - p.h0) * 0.55 - 0.5, (p.h1 - p.h0) * 0.55 + 0.5, WOOD_DARK, turn)
					_hline((p.h1 - p.h0) * 0.55, WOOD_DARK, 1.0, k * w + 3.0, (k + 1) * w - 3.0)
			for k in posts + 1:
				var s := k * w
				if lights:
					break
				if _in(s) or (k == posts and _s1 >= _len - 0.5):
					draw_line(_pt(minf(s, _len - 1.0), 0.0), _pt(minf(s, _len - 1.0), p.h1 - p.h0), WOOD_DARK, 2.5)
			_hline(p.h1 - p.h0 - 2.0, WOOD_DARK, 3.0)
		&"shack":
			if posmod(p.seed, 3) != 0:
				var c := _len * (0.3 + BuildingModel.hash01(p.seed, int(_n.x)) * 0.4)
				_window(c - 6.0, c + 6.0, 6.0, 12.0, p.seed % 2 == 0, 1)
			if south:
				_quad(_len * 0.12, _len * 0.12 + 10.0, 0.0, 13.0, Color(0.22, 0.17, 0.12))
			_hline(1.0, Color(0, 0, 0, 0.3), 2.0)
		&"caravan":
			_quad(0.0, _len, 9.0, 12.0, _p.accent.darkened(_shade * 0.5))
			var count := 3 if south else 1
			for k in count:
				var c := _len * (k + 0.5) / count
				_window(c - 8.0, c + 8.0, 14.0, 21.0, k == 1, k)
			if south and not lights:
				for c in [_len * 0.25, _len * 0.7]:
					if _in(c):
						draw_set_transform_matrix(IsoView.screen_frame(_pt(c, 3.0 - _p.h0)))
						draw_circle(Vector2.ZERO, 4.5, Color(0.08, 0.08, 0.09))
						draw_circle(Vector2.ZERO, 2.0, Color(0.5, 0.5, 0.52))
						draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

const WOOD_DARK := Color(0.24, 0.14, 0.08)


# ── 벽 장식 ───────────────────────────────────────────────

func _deco(d: StringName, south: bool) -> void:
	if String(d).begins_with("sd_"):
		StreetDecor.deco(self, d, south)   # 거리 건물 10종 (docs/16)
		return
	var font := ThemeDB.fallback_font
	var h := _p.h1 - _p.h0
	match d:
		&"street_services":
			# Service-side equipment; front signage retains the main facade.
			if not south:
				for k in range(1, maxi(2, int(_len / 65))):
					var x := k * _len / maxi(2, int(_len / 65))
					_quad(x, x + 2, 1, h - 4, Color("525b59"), 1)
					for level in range(1, maxi(2, int(h / 36))):
						var z := level * 32.0
						_quad(x + 5, x + 17, z, z + 9, Color("a6aaa0"), 3)
						for slat in 3:
							_quad(x + 7, x + 15, z + 2 + slat * 2, z + 3 + slat * 2, Color("454e4e"), 3.2)
		&"street_mullions":
			for k in range(1, maxi(2, int(_len / 22))):
				var x := k * _len / maxi(2, int(_len / 22))
				_quad(x, x + 2, 0, h, Color("9fb4bd"), .7)
		&"street_clock":
			if south and _in(_len * .5):
				var c := _pt(_len * .5, h - 18, 1)
				draw_circle(c, 11, Color("ded6b7"))
				draw_arc(c, 11, 0, TAU, 24, Color("605b4e"), 2)
				draw_line(c, c + Vector2(0,-7), Color("403f3a"), 2)
				draw_line(c, c + Vector2(5,2), Color("403f3a"), 2)
		&"street_fuel_board":
			if south and _in(_len * .5):
				_plate(font, "한빛", _len*.5, h-2, 12, Color("1b676a"), Color("bdcdc3"), Color.WHITE)
				_plate(font, "휘발유", _len*.5, h-23, 9, Color("1a3237"), Color("72948b"), Color("edd690"))
		&"street_church":
			# Tall warm lancet-shaped bays distinguish the nave from residential windows.
			for k in range(1,maxi(2,int(_len/48))):
				var x := k*_len/maxi(2,int(_len/48))
				_quad(x-7,x+7,18,h-23,Color("e8b45c"),1)
				_quad(x-1,x+1,18,h-17,Color("595145"),1.3)
				_quad(x-7,x+7,38,40,Color("595145"),1.3)
		&"street_sign":
			if south:
				var board_h := minf(32,maxf(10,h*.65))
				StreetDecor.neon(self,_p.text,_len*.5,h-1,minf(_len*.82,210),board_h,_p.accent)
		&"street_vertical_neon":
			if south:
				StreetDecor.neon(self,_p.text,_len*.5,h-2,_len*.9,h-4,_p.accent,true)
		&"street_curtain":
			if not south:
				return
			_quad(8, _len - 8, 0, h - 9, Color("211e29"))
			for j in 16:
				var x := 8 + (_len - 16) * j / 16.0
				_quad(x, x + (_len - 16) / 18.0, 3, h - 10, Color("743440") if j % 2 == 0 else Color("b18e82"))
		&"street_pump":
			var hose_x := _len - 3.0
			if _in(hose_x):
				var hose := PackedVector2Array([_pt(hose_x,h*.8,3),_pt(hose_x+5,h*.65,4),_pt(hose_x+6,h*.25,4),_pt(hose_x+2,h*.18,4),_pt(hose_x,h*.45,3)])
				draw_polyline(hose,Color("222629"),2.5)
			_quad(2, _len - 2, h * .55, h * .85, Color("172e34"))
			_quad(3, _len - 3, h * .2, h * .4, Color("20a88f"))
		&"street_nightlife":
			if south:
				var names := ["별밤 노래방", "CLUB 달", "서울 호프"]
				var colors := [Color("e63fa1"), Color("805aff"), Color("ffad3e")]
				for j in 3:
					StreetDecor.neon(self,names[j],_len*.5,h-14-j*52,minf(_len*.65,200),34,colors[j])
		&"landmark_sign":
			if south and _in(_len*0.5):
				_plate(font, _p.text, _len*0.5, h-4, 16, Color("153b7a"), Color("b7c9df"), Color.WHITE)
		&"shops":
			_shops(font)
		&"awning":
			_awnings()
		&"piloti":
			# 1층은 기둥만 있는 주차장
			_quad(0.0, _len, 0.0, _fh * 0.9, Color(0.07, 0.07, 0.08))
			var s := 3.0
			while s < _len:
				_quad(s, s + 5.0, 0.0, _fh * 0.9, _p.wall.lightened(0.1).darkened(_shade))
				s += 58.0
			_quad(_len - 5.0, _len, 0.0, _fh * 0.9, _p.wall.lightened(0.1).darkened(_shade))
			_hline(_fh * 0.3, Color(0.85, 0.85, 0.8, 0.3), 1.0)
		&"balcony":
			if not south:
				return
			var bays := maxi(1, int(_len / 68.0))
			var w := _len / bays
			for f in range(1, _floors):
				for k in bays:
					var s0 := k * w + 8.0
					var s1 := (k + 1) * w - 8.0
					var z := f * _fh
					_quad(s0, s1, z, z + _fh * 0.38, Color(0.82, 0.82, 0.8).darkened(_shade * 0.6), 5.0)
					_hline(z + _fh * 0.38, Color(0.95, 0.95, 0.92).darkened(_shade * 0.4), 1.5, s0, s1, 5.0)
		&"name":
			if south and _in(_len * 0.5):
				_plate(font, _p.text, _len * 0.5, h - 4.0, 13, Color(0.92, 0.9, 0.84), _p.accent.darkened(0.5), Color(0, 0, 0, 0))
		&"rental_image":
			# 기존 중앙 현관/건물명과 겹치지 않게 벽 끝에 작은 임대 표지를 붙인다.
			var s := _len - minf(18.0, _len * 0.2)
			if south and _in(s):
				var hh := minf(38.0, h * 0.62)
				_board("임대", s, minf(h - 2.0, hh + 5.0), minf(22.0, _len * 0.22), hh, true)
		&"vsign":
			var s := _len - 20.0
			if south and _in(s):
				_vertical_sign(font, s, h - 6.0)
		&"band_signs":
			if _floors < 3:
				return
			# 1층 가게 간판(위 1.5층) 위로 한 층씩. 4층 미만이면 하나만
			for f in [1, 2]:
				if f == 2 and _floors < 4:
					continue
				var w := _len * 0.72
				var s := (_len - w) * (0.2 if f == 1 else 0.7)
				var text := _p.signs[posmod(_p.seed + f * 3 + int(_n.x), _p.signs.size())] if not _p.signs.is_empty() else ""
				if _in(s + w * 0.5):
					if _sign_style(text) < 0:
						text = SHOP_WORDS[posmod(_p.seed + f + int(_n.x), SHOP_WORDS.size())]
					_board(text, s + w * 0.5, f * _fh + _fh * 1.22, w, _fh * 0.62)
		&"top_sign":
			# 건물 이름(데이터의 가칭) 파란 금속판. 이전 간판 이미지 'office'는 실존 상표라 쓰지 않는다 (docs/09)
			var size := 24
			var w := minf(font.get_string_size(_p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 28.0, _len * 0.72)
			var s0 := _len * 0.5 - w * 0.5
			if south and _p.text != "" and SpecialDecor._owns(self, s0 + w):
				draw_set_transform_matrix(_frame(s0, w, h - 3.0))
				SpecialDecor._metal(self, Rect2(0, 0, w, 32.0), SpecialDecor.PLATE_BLUE, _p.seed)
				SpecialDecor._bold(self, font, Vector2(0, 24.5), _p.text, w, size, SpecialDecor.WHITE)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		&"number":
			if not south and _in(_len * 0.5):
				# 측벽 윗부분의 큰 동 번호: 흰 페인트 판에 "101동"
				var w := minf(_len * 0.8, 84.0)
				draw_set_transform_matrix(_frame(_len * 0.5 - w * 0.5, w, h - 5.0))
				draw_rect(Rect2(0, 2, w, 28), Color(0.94, 0.93, 0.89).darkened(_shade * 0.7))
				draw_rect(Rect2(0, 2, w, 28), _p.accent.darkened(_shade * 0.4), false, 1.5)
				draw_string(font, Vector2(0, 24), _p.text + "동", HORIZONTAL_ALIGNMENT_CENTER, w, 22, _p.accent.darkened(0.2 + _shade * 0.3))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		&"plate":
			if south and _in(_len * 0.5):
				var z := minf(h - 6.0, _fh * 2.6)
				_plate(font, _p.text, _len * 0.5, z, 14, Color(0.18, 0.32, 0.72), Color(0.6, 0.75, 1.0), Color(0.95, 0.97, 1.0))
		&"ac":
			if not south:
				return
			var bays := maxi(1, int(_len / BAY))
			var w := _len / bays
			for f in range(1, _floors):
				for k in bays:
					if posmod(_p.seed + k * 3 + f, 3) == 0:
						var s := k * w + w * 0.8
						_quad(s, s + 10.0, f * _fh + 1.0, f * _fh + 7.0, UNIT_COLOR.darkened(_shade * 0.5), 4.0)
		&"entrance":
			if south:
				var c := _len * 0.5
				_quad(c - 16.0, c + 16.0, 0.0, _fh * 0.8, Color(0.85, 0.9, 0.85, 0.85).darkened(_shade * 0.5))
				_quad(c - 22.0, c + 22.0, _fh * 0.8, _fh * 0.95, _p.wall.lightened(0.25).darkened(_shade * 0.5), 8.0)
		&"door":
			if south:
				var c := _len * 0.5
				_quad(c - 6.0, c + 6.0, 0.0, minf(h - 2.0, 13.0), Color(0.3, 0.22, 0.16).darkened(_shade * 0.3))
		&"porches":
			if not south:
				return
			var count := maxi(1, int(_len / 120.0))
			for k in count:
				var c := _len * (k + 0.5) / count
				_quad(c - 7.0, c + 7.0, 0.0, 13.0, Color(0.3, 0.22, 0.16).darkened(_shade * 0.3))
				_quad(c - 14.0, c + 14.0, 14.0, 16.5, Color(0.75, 0.3, 0.25).darkened(_shade * 0.4), 7.0)
		&"shutter":
			if not south:
				return
			var count := maxi(1, int(_len / 110.0))
			for k in count:
				var c := _len * (k + 0.5) / count
				var open := posmod(_p.seed + k, 3) == 0
				var top := minf(h - 6.0, 24.0)
				_quad(c - 26.0, c + 26.0, 0.0, top, (Color(0.95, 0.82, 0.5) if open else Color(0.42, 0.44, 0.46)).darkened(_shade * 0.4))
				if not open:
					var z := 2.0
					while z < top:
						_hline(z, Color(0.25, 0.26, 0.28), 1.0, c - 26.0, c + 26.0)
						z += 3.0
				_hline(top + 1.0, Color(0.85, 0.65, 0.15), 2.0, c - 28.0, c + 28.0)
		&"big_sign":
			# 공장 이름(데이터의 가칭) 흰 금속판에 남색 글씨, 왼쪽에 주황 띠.
			# 이전 간판 이미지 'factory'는 실존 회사명이라 쓰지 않는다 (docs/09)
			var size := 22
			var w := minf(font.get_string_size(_p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 40.0, _len * 0.75)
			var s0 := _len * 0.5 - w * 0.5
			if south and _p.text != "" and SpecialDecor._owns(self, s0 + w):
				draw_set_transform_matrix(_frame(s0, w, h - 3.0))
				SpecialDecor._metal(self, Rect2(0, 0, w, 30.0), SpecialDecor.WHITE.darkened(0.04), _p.seed)
				draw_rect(Rect2(4.0, 4.0, 8.0, 22.0), _p.accent)
				SpecialDecor._bold(self, font, Vector2(14.0, 23.0), _p.text, w - 18.0, size, SpecialDecor.NAVY, Color(0, 0, 0, 0))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		&"stone_base":
			_quad(0.0, _len, 0.0, 5.0, BuildingModel.STONE.darkened(_shade))
		&"fan":
			if south:
				var c := _pt(_len * 0.5, h * 0.5)
				draw_set_transform_matrix(IsoView.screen_frame(c))
				draw_circle(Vector2.ZERO, minf(h * 0.38, 4.0), Color(0.2, 0.2, 0.22))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_:
			SpecialDecor.deco(self, d, south)   # 기능 건물 장식 (경찰서·병원·아지트·정비소·사우나·편의점)

const UNIT_COLOR := Color(0.72, 0.72, 0.7)


## 벽에 붙은 간판판 (가운데 s, 위 z)
func _plate(font: Font, text: String, s: float, z: float, size: int, bg: Color, edge: Color, ink: Color) -> void:
	if text == "":
		return
	if "원룸" in text:
		_board(text, s, z, _len * 0.65, 26.0)
		return
	var w := minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 14.0, _len - 8.0)
	var hh := size + 6.0
	if lights:
		_glow(s - w * 0.5 - 3.0, s + w * 0.5 + 3.0, z - hh - 3.0, z + 3.0, Color(bg.lightened(0.45), 0.2), 0.0, 0.8)
	_quad(s - w * 0.5, s + w * 0.5, z - hh, z, bg.darkened(_shade * 0.3), 1.0)
	draw_set_transform_matrix(_frame(s - w * 0.5, w, z))
	if edge.a > 0.0:
		draw_rect(Rect2(0, 0, w, hh), edge, false, 1.5)
	draw_string(font, Vector2(0, hh - 5.0), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, ink if ink.a > 0.0 else edge)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 세로 간판 (벽에서 튀어나온 네온판, 글자를 위에서 아래로)
func _vertical_sign(font: Font, s: float, z: float) -> void:
	# 짧은 한글 업종·건물 종류는 그대로, 아니면(띄어쓰기·영문·긴 이름) 의원·임대
	var text := _p.text
	for word in ["오피스텔", "고시원", "임대", "의원"]:
		if word in text:
			text = word
	if text.length() > 4 or " " in text or _sign_style(text) < 0 or RegEx.create_from_string("[A-Za-z0-9]").search(text):
		text = "의원" if _p.seed % 2 == 0 else "임대"
	_board(text, s, z, 26.0, minf(z - 6.0, 90.0), true)


## 1층 상가: 불 켜진 쇼윈도와 벽에 붙은 간판
func _shops(font: Font) -> void:
	var shops := maxi(1, int(_len / 90.0))
	var w := _len / shops
	for k in shops:
		var s0 := k * w + 6.0
		var s1 := (k + 1) * w - 6.0
		var neon: Color = City.NEON[posmod(_p.seed + k + int(_n.x) * 3, City.NEON.size())]
		_quad(s0, s1, 2.0, _fh * SHOP_BAND, Color(0.95, 0.88, 0.7, 0.9).darkened(_shade * 0.6))
		_quad(lerpf(s0, s1, 0.4), lerpf(s0, s1, 0.6), 0.0, _fh * 0.55, Color(0.2, 0.18, 0.16))
		# 쇼윈도 안쪽 진열대와 금속 문틀. 간판보다 먼저 그려 글자를 덮지 않는다.
		for shelf in 2:
			_hline(4.0+shelf*4.0,Color(0.3,0.24,0.18,0.55),1,s0+2,lerpf(s0,s1,0.38))
		for divider in [0.2,0.4,0.6,0.8]:
			var post := lerpf(s0,s1,divider)
			_quad(post-0.6,post+0.6,2,_fh*SHOP_BAND,Color("39464c"))
		_hline(2,Color("969d92"),1.5,s0,s1,1)
		if _p.signs.is_empty() or not _in((s0 + s1) * 0.5):
			continue
		var text := _p.signs[posmod(_p.seed + k * 3 + int(_n.x), _p.signs.size())]
		var top := _fh * SHOP_BAND + _fh * 0.75
		_board(_shop_word(text, k), (s0+s1)*0.5, top, s1-s0, _fh * 0.7)


## 가게 위 차양 (벽에서 비스듬히 나온 줄무늬 천)
func _awnings() -> void:
	var shops := maxi(1, int(_len / 90.0))
	var w := _len / shops
	for k in shops:
		var color: Color = AWNINGS[posmod(_p.seed + k + int(_n.x), AWNINGS.size())]
		var a := maxf(k * w + 4.0, _s0)
		var b := minf((k + 1) * w - 4.0, _s1)
		if b - a < 1.0:
			continue
		var z0 := _fh * 0.95
		var z1 := _fh * 0.7
		draw_colored_polygon(PackedVector2Array([_pt(a, z0), _pt(b, z0), _pt(b, z1, 10.0), _pt(a, z1, 10.0)]),
			color.darkened(_shade * 0.3))
		var s := a + 4.0
		while s < b:
			draw_line(_pt(s, z0), _pt(s, z1, 10.0), color.lightened(0.35).darkened(_shade * 0.3), 1.5)
			s += 8.0
		draw_line(_pt(a, z1, 10.0), _pt(b, z1, 10.0), color.darkened(0.4), 1.5)

const AWNINGS := [Color(0.75, 0.2, 0.2), Color(0.15, 0.45, 0.55), Color(0.85, 0.5, 0.15), Color(0.25, 0.5, 0.3)]


# ── 지붕과 얹힌 것 ────────────────────────────────────────

func _top(p: BuildingModel.Piece) -> void:
	if lights:
		# 불빛 조각은 지붕을 그리지 않고, 얹힌 덩어리(윗층)의 벽 불빛만 (랜드마크 가로등·전구는 등 불빛)
		if p.roof in LandmarkDecor.GLOWS:
			LandmarkDecor.glow(self, p)
		elif p.roof in StreetDecor.GLOWS:
			StreetDecor.glow(self, p)
		for s: BuildingModel.Piece in p.on_top:
			_walls(s, s.rect)
			_top(s)
		return
	match p.roof:
		&"flat":
			if p.skin:
				_skin_roof(p)
			else:
				_flat(p)
		&"art": _art(p)
		&"street_canopy": StreetDecor.canopy(self, p)
		&"gable": _gable(p)
		&"hip": _hip(p, false)
		&"hanok": _hip(p, true)
		&"tree": _tree(p)
		&"chimney": _cylinder(p, true)
		&"tank": _cylinder(p, false)
		&"tent": _tent(p)
		_: SpecialDecor.roof(self, p)
	if p.on_top.is_empty():
		return
	var tops := p.on_top.duplicate()
	tops.sort_custom(func(a, b): return a.rect.get_center().x + a.rect.get_center().y < b.rect.get_center().x + b.rect.get_center().y)
	if p.surface_detail and p.roof == &"flat":
		for s: BuildingModel.Piece in tops:
			var cast := Rect2(s.rect.position+Vector2(4,6),s.rect.size+Vector2(5,7)).intersection(p.rect.grow(-3))
			if cast.has_area():
				draw_colored_polygon(_corners(cast,p.h1),Color(0.015,0.025,0.03,0.32))
	for s: BuildingModel.Piece in tops:
		_walls(s, s.rect)
		_top(s)


func _corners(r: Rect2, h: float) -> PackedVector2Array:
	var l := IsoView.lift(h)
	return PackedVector2Array([r.position + l, Vector2(r.end.x, r.position.y) + l, r.end + l, Vector2(r.position.x, r.end.y) + l])


## 평지붕: 바닥 면과 난간
func _flat(p: BuildingModel.Piece) -> void:
	var r := p.rect
	draw_colored_polygon(_corners(r, p.h1), p.roof_color)
	# 방수 시트 이음과 바랜 패치. 옥상 설비보다 먼저 그린다.
	if r.size.x > 65.0 and r.size.y > 65.0:
		var lift := IsoView.lift(p.h1)
		var y := r.position.y+18.0
		while y < r.end.y-6:
			draw_line(Vector2(r.position.x+6,y)+lift,Vector2(r.end.x-6,y)+lift,Color(0.04,0.08,0.09,0.2),0.8)
			y += 26.0
		for k in 9:
			var at := r.position+Vector2(8,8)+(r.size-Vector2(34,26))*Vector2(BuildingModel.hash01(p.seed,k+71),BuildingModel.hash01(p.seed,k+91))
			var patch := Rect2(at,Vector2(12+BuildingModel.hash01(p.seed,k+111)*12,5))
			draw_colored_polygon(_corners(patch,p.h1),Color(p.roof_color.lightened(0.18),0.2))
		# 옥상 배수구는 설비 아래에 가려져도 자연스럽게 남는다.
		var drain := r.end-Vector2(12,12)+lift
		draw_rect(Rect2(drain-Vector2(3,3),Vector2(6,6)),Color("263537"))
	if r.size.x > 24.0 and r.size.y > 24.0:
		var inner := _corners(r.grow(-3.0), p.h1)
		inner.append(inner[0])
		draw_polyline(inner, p.roof_color.darkened(0.3), 1.5)
		if p.surface_detail and r.size.x > 65 and r.size.y > 65:
			var inset := _corners(r.grow(-5),p.h1)
			var raised := _corners(r,p.h1+4)
			for side in [1,2]:
				var next: int = (side+1)%4
				draw_colored_polygon(PackedVector2Array([inset[side],inset[next],raised[next],raised[side]]),p.wall.darkened(0.24))
			raised.append(raised[0])
			draw_polyline(raised,p.wall.lightened(0.25),2)
	var edge := _corners(r, p.h1)
	edge.append(edge[0])
	draw_polyline(edge, p.wall.lightened(0.22), 1.5 if r.size.x < 40.0 else 2.5)
	if p.deco.has(&"fan"):
		var center := r.get_center()+IsoView.lift(p.h1+0.4)
		var radius := minf(r.size.x,r.size.y)*0.32
		draw_circle(center,radius,Color("28363c"))
		draw_arc(center,radius,0,TAU,16,Color("9ba6a4"),0.8)
		for blade in 4:
			var direction := Vector2.from_angle(blade*PI*0.5+0.4)
			draw_line(center+direction,center+direction*radius*0.8,Color("697d81"),1.2)


## 특수 건물: 위에서 본 지붕 그림을 지붕 높이에 올린다 (경찰서 헬기장·병원 십자 등)
func _art(p: BuildingModel.Piece) -> void:
	draw_set_transform(IsoView.lift(p.h1), 0.0, Vector2.ONE)
	BuildingDrawer.shadows = false
	if city:
		city._draw_building(self, p.rect, idx, ThemeDB.fallback_font)
	BuildingDrawer.shadows = true
	var edge := PackedVector2Array([p.rect.position, Vector2(p.rect.end.x, p.rect.position.y), p.rect.end,
		Vector2(p.rect.position.x, p.rect.end.y), p.rect.position])
	draw_polyline(edge, p.wall.lightened(0.25), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 박공지붕: 용마루는 긴 쪽으로. 뒤 경사면 → 앞 경사면 → 박공(벽 끝 삼각형) 순서
func _gable(p: BuildingModel.Piece) -> void:
	var r := p.rect
	var e := p.eave
	var h := p.h1 - 1.0
	var t := p.h1 + p.rise
	var dark := p.roof_color.darkened(0.25)
	var tile := p.roof_color.darkened(0.18)
	# 경사면의 가로 이음은 세로 골과 만나 판넬/기와 크기를 읽게 한다.
	if r.size.x >= r.size.y:
		var y0 := r.position.y - e
		var y1 := r.end.y + e
		var yc := r.get_center().y
		var x0 := r.position.x
		var x1 := r.end.x
		draw_colored_polygon(PackedVector2Array([Vector2(x0, y0) + IsoView.lift(h), Vector2(x1, y0) + IsoView.lift(h),
			Vector2(x1, yc) + IsoView.lift(t), Vector2(x0, yc) + IsoView.lift(t)]), dark)
		draw_colored_polygon(PackedVector2Array([Vector2(x0, yc) + IsoView.lift(t), Vector2(x1, yc) + IsoView.lift(t),
			Vector2(x1, y1) + IsoView.lift(h), Vector2(x0, y1) + IsoView.lift(h)]), p.roof_color)
		if p.surface_detail:
			for row in range(1,7):
				var u := row/7.0
				var yy := lerpf(yc,y1,u)
				var zz := lerpf(t,h,u)
				draw_line(Vector2(x0,yy)+IsoView.lift(zz),Vector2(x1,yy)+IsoView.lift(zz),p.roof_color.darkened(0.3),1)
		var x := x0 + 6.0
		while x < x1 - 2.0:
			draw_line(Vector2(x, yc) + IsoView.lift(t), Vector2(x, y1) + IsoView.lift(h), tile, 1.0)
			x += 7.0
		draw_line(Vector2(x0, y1) + IsoView.lift(h), Vector2(x1, y1) + IsoView.lift(h), p.roof_color.lightened(0.2), 1.5)
		draw_colored_polygon(PackedVector2Array([Vector2(x1, r.position.y) + IsoView.lift(p.h1), Vector2(x1, r.end.y) + IsoView.lift(p.h1),
			Vector2(x1, yc) + IsoView.lift(t)]), p.wall.darkened(IsoView.face_shade(Vector2.RIGHT)))
		draw_line(Vector2(x1, y0) + IsoView.lift(h), Vector2(x1, yc) + IsoView.lift(t), p.roof_color.lightened(0.1), 2.0)
		draw_line(Vector2(x1, yc) + IsoView.lift(t), Vector2(x1, y1) + IsoView.lift(h), p.roof_color.lightened(0.1), 2.0)
		draw_line(Vector2(x0, yc) + IsoView.lift(t), Vector2(x1, yc) + IsoView.lift(t), p.roof_color.darkened(0.45), 2.5)
	else:
		var x0 := r.position.x - e
		var x1 := r.end.x + e
		var xc := r.get_center().x
		var y0 := r.position.y
		var y1 := r.end.y
		draw_colored_polygon(PackedVector2Array([Vector2(x0, y0) + IsoView.lift(h), Vector2(xc, y0) + IsoView.lift(t),
			Vector2(xc, y1) + IsoView.lift(t), Vector2(x0, y1) + IsoView.lift(h)]), dark)
		draw_colored_polygon(PackedVector2Array([Vector2(xc, y0) + IsoView.lift(t), Vector2(x1, y0) + IsoView.lift(h),
			Vector2(x1, y1) + IsoView.lift(h), Vector2(xc, y1) + IsoView.lift(t)]), p.roof_color.darkened(0.08))
		if p.surface_detail:
			for row in range(1,7):
				var u := row/7.0
				var xx := lerpf(xc,x1,u)
				var zz := lerpf(t,h,u)
				draw_line(Vector2(xx,y0)+IsoView.lift(zz),Vector2(xx,y1)+IsoView.lift(zz),p.roof_color.darkened(0.3),1)
		var y := y0 + 6.0
		while y < y1 - 2.0:
			draw_line(Vector2(xc, y) + IsoView.lift(t), Vector2(x1, y) + IsoView.lift(h), tile, 1.0)
			y += 7.0
		draw_line(Vector2(x1, y0) + IsoView.lift(h), Vector2(x1, y1) + IsoView.lift(h), p.roof_color.lightened(0.2), 1.5)
		draw_colored_polygon(PackedVector2Array([Vector2(r.position.x, y1) + IsoView.lift(p.h1), Vector2(r.end.x, y1) + IsoView.lift(p.h1),
			Vector2(xc, y1) + IsoView.lift(t)]), p.wall.darkened(IsoView.face_shade(Vector2.DOWN)))
		draw_line(Vector2(x0, y1) + IsoView.lift(h), Vector2(xc, y1) + IsoView.lift(t), p.roof_color.lightened(0.1), 2.0)
		draw_line(Vector2(xc, y1) + IsoView.lift(t), Vector2(x1, y1) + IsoView.lift(h), p.roof_color.lightened(0.1), 2.0)
		draw_line(Vector2(xc, y0) + IsoView.lift(t), Vector2(xc, y1) + IsoView.lift(t), p.roof_color.darkened(0.45), 2.5)


## 모임지붕 (curved면 한옥: 처마 끝이 들리고 가운데가 처진다). 북·서 → 남·동 순서
func _hip(p: BuildingModel.Piece, curved: bool) -> void:
	var r := p.rect.grow(p.eave)
	var h := p.h1 - (3.0 if curved else 1.0)
	var t := p.h1 + p.rise
	var along_x := r.size.x >= r.size.y
	var short := minf(r.size.x, r.size.y)
	var inset := short * (0.32 if curved else 0.5)
	var c := r.get_center()
	var ra: Vector2
	var rb: Vector2
	if along_x:
		ra = Vector2(r.position.x + inset, c.y)
		rb = Vector2(r.end.x - inset, c.y)
	else:
		ra = Vector2(c.x, r.position.y + inset)
		rb = Vector2(c.x, r.end.y - inset)
	var nw := r.position
	var ne := Vector2(r.end.x, r.position.y)
	var se := r.end
	var sw := Vector2(r.position.x, r.end.y)
	var lift_up := 7.0 if curved else 0.0
	var A := ra + IsoView.lift(t)
	var B := rb + IsoView.lift(t)
	var north := _eave(nw, ne, h, lift_up)
	var east := _eave(ne, se, h, lift_up)
	var south := _eave(se, sw, h, lift_up)
	var west := _eave(sw, nw, h, lift_up)
	var shade := p.roof_color
	if along_x:
		_slope(north, A, B, shade.darkened(0.28))
		_slope(west, A, A, shade.darkened(0.36))
		_slope(south, B, A, shade)
		_slope(east, B, B, shade.darkened(0.14))
	else:
		_slope(north, A, A, shade.darkened(0.28))
		_slope(west, B, A, shade.darkened(0.36))
		_slope(south, B, B, shade)
		_slope(east, A, B, shade.darkened(0.14))
	# 기와골: 처마에서 용마루 쪽으로 (남쪽 면은 se→sw, 동쪽 면은 ne→se 순서)
	var tile := shade.darkened(0.2) if not curved else shade.lightened(0.12)
	for side in 2:
		var edge: PackedVector2Array = south if side == 0 else east
		var count := int(edge[0].distance_to(edge[-1]) / 7.0)
		for k in range(1, count):
			var f := float(k) / count
			var r_pt: Vector2
			if side == 0:
				r_pt = B.lerp(A, f) if along_x else B
			else:
				r_pt = B if along_x else A.lerp(B, f)
			var e_pt := _along_poly(edge, f)
			draw_line(e_pt, e_pt.lerp(r_pt, 0.86), tile, 1.0)
			if p.surface_detail:
				# 기와의 이음과 가는 명암선으로 겹침을 표현한다.
				for course in range(1,7):
					var q := e_pt.lerp(r_pt,course/8.0)
					var tangent := (edge[-1]-edge[0]).normalized()*2.0
					draw_line(q-tangent,q+tangent,shade.darkened(0.4),1)
					draw_line(q-tangent+Vector2(0,-1),q+tangent+Vector2(0,-1),shade.lightened(0.16),0.6)
	# 처마 끝선과 용마루
	var rim := Color(0.72, 0.7, 0.66) if curved else shade.lightened(0.18)
	draw_polyline(_join(east, []), rim, 1.5)
	draw_polyline(_join(south, []), rim, 1.5)
	draw_line(A, B, shade.darkened(0.5), 4.0 if curved else 2.5)
	if curved:
		# 용마루 끝 치미 (살짝 들린 끝)
		for q in [A, B]:
			draw_line(q, q + Vector2(0, -6), shade.darkened(0.5), 3.0)
			draw_circle(q + Vector2(0, -6), 2.0, Color(0.75, 0.73, 0.68))
		draw_line(A + Vector2(0, -1.5), B + Vector2(0, -1.5), Color(0.75, 0.73, 0.68, 0.7), 1.0)


## 경사면 한 장: 처마 선 edge(처음→끝)와 용마루 from→to를 띠로 잇는다 (휜 처마도 삼각분할이 깨지지 않게)
func _slope(edge: PackedVector2Array, from: Vector2, to: Vector2, color: Color) -> void:
	var n := edge.size() - 1
	for k in n:
		var r0 := from.lerp(to, float(k) / n)
		var r1 := from.lerp(to, float(k + 1) / n)
		_tri(edge[k], edge[k + 1], r1, color)
		if r0.distance_squared_to(r1) > 0.01:
			_tri(edge[k], r1, r0, color)


## 삼각형 하나 (넓이가 거의 없으면 건너뛴다 — 삼각분할 오류 방지)
func _tri(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	if absf((b - a).cross(c - a)) > 0.05:
		draw_colored_polygon(PackedVector2Array([a, b, c]), color)


## 처마 한 변 a→b (높이 h, 한옥이면 끝을 들고 바깥으로 뺀다)
func _eave(a: Vector2, b: Vector2, h: float, up: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var steps := 6 if up > 0.0 else 1
	var mid := (a + b) * 0.5
	for k in steps + 1:
		var f := float(k) / steps
		var p := a.lerp(b, f)
		var curve := pow(absf(f - 0.5) * 2.0, 3.0)   # 가운데 0, 끝 1
		var push := Vector2.ZERO
		if up > 0.0:
			push = ((a if f < 0.5 else b) - mid).normalized() * curve * 4.0
		out.append(p + push + IsoView.lift(h + up * curve))
	return out


func _join(a: PackedVector2Array, b: Array) -> PackedVector2Array:
	var out := a.duplicate()
	for q in b:
		out.append(q)
	return out


func _along_poly(pts: PackedVector2Array, f: float) -> Vector2:
	var x := f * (pts.size() - 1)
	var i := mini(int(x), pts.size() - 2)
	return pts[i].lerp(pts[i + 1], x - i)


## 나무: 바닥 그림자, 줄기, 화면을 향한 둥근 수관
func _tree(p: BuildingModel.Piece) -> void:
	var base := p.rect.get_center()
	var r := p.rise
	draw_set_transform_matrix(IsoView.screen_frame(base) * Transform2D(0.0, Vector2(1.0, 0.5), 0.0, Vector2.ZERO))
	draw_circle(Vector2(5, 3), r * 0.9, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_line(base, base + IsoView.lift(p.h1 + r * 0.3), p.wall, 3.0)
	draw_set_transform_matrix(IsoView.screen_frame(base, p.h1 + r * 0.55))
	var leaf := p.roof_color.lerp(Color(0.2, 0.36, 0.14), BuildingModel.hash01(p.seed, 1) * 0.6)
	if p.roof_color.r > p.roof_color.g + 0.15:
		leaf = p.roof_color.darkened(BuildingModel.hash01(p.seed, 1) * 0.15)   # 꽃나무(벚꽃)는 초록에 섞지 않는다
	draw_circle(Vector2(0, 0), r, leaf.darkened(0.25))
	draw_circle(Vector2(-r * 0.32, -r * 0.28), r * 0.66, leaf)
	draw_circle(Vector2(r * 0.34, -r * 0.12), r * 0.6, leaf.lightened(0.05))
	draw_circle(Vector2(-r * 0.05, -r * 0.55), r * 0.48, leaf.lightened(0.16))
	for k in 4:
		var a := BuildingModel.hash01(p.seed, k + 5) * TAU
		draw_circle(Vector2.from_angle(a) * r * 0.5 + Vector2(0, -r * 0.2), 2.0, leaf.lightened(0.32))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 원기둥 (굴뚝·물탱크): 화면 좌표로 몸통과 위 타원
func _cylinder(p: BuildingModel.Piece, chimney: bool) -> void:
	var c := p.rect.get_center()
	var rx := p.rect.size.x * 0.55
	var ry := rx * 0.5
	var body := p.wall
	draw_set_transform_matrix(IsoView.screen_frame(c))
	var y0 := -p.h0
	var y1 := -p.h1
	draw_colored_polygon(_ellipse(Vector2(0, y0), rx, ry), body.darkened(0.35))
	draw_rect(Rect2(-rx, y1, rx * 2.0, y0 - y1), body.darkened(0.12))
	draw_rect(Rect2(rx * 0.25, y1, rx * 0.75, y0 - y1), body.darkened(0.35))
	draw_rect(Rect2(-rx * 0.7, y1, rx * 0.3, y0 - y1), body.lightened(0.08))
	if chimney:
		# 꼭대기 근처 주황 띠 둘
		for k in 2:
			var y := y1 + 8.0 + k * 14.0
			draw_rect(Rect2(-rx, y, rx * 2.0, 6.0), p.roof_color.darkened(0.1))
			draw_rect(Rect2(rx * 0.25, y, rx * 0.75, 6.0), p.roof_color.darkened(0.4))
		draw_colored_polygon(_ellipse(Vector2(0, y1), rx, ry), body.lightened(0.1))
		draw_colored_polygon(_ellipse(Vector2(0, y1), rx * 0.7, ry * 0.7), Color(0.08, 0.07, 0.07))
	else:
		draw_colored_polygon(_ellipse(Vector2(0, y1), rx, ry), body.lightened(0.18))
		draw_line(Vector2(-rx, y1 + 5.0), Vector2(rx, y1 + 5.0), body.darkened(0.4), 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in 16:
		out.append(c + Vector2(cos(k * TAU / 16.0) * rx, sin(k * TAU / 16.0) * ry))
	return out


## 텐트: 네모 바닥의 뾰족 지붕. 북·서 면 → 남·동 면, 남쪽에 입구
func _tent(p: BuildingModel.Piece) -> void:
	var r := p.rect
	var apex := r.get_center() + IsoView.lift(p.h0 + p.rise)
	var l := IsoView.lift(p.h0)
	var nw := r.position + l
	var ne := Vector2(r.end.x, r.position.y) + l
	var se := r.end + l
	var sw := Vector2(r.position.x, r.end.y) + l
	var c := p.roof_color
	draw_colored_polygon(PackedVector2Array([nw, ne, apex]), c.darkened(0.4))
	draw_colored_polygon(PackedVector2Array([sw, nw, apex]), c.darkened(0.3))
	draw_colored_polygon(PackedVector2Array([sw, se, apex]), c)
	draw_colored_polygon(PackedVector2Array([se, ne, apex]), c.darkened(0.15))
	var door := (sw + se) * 0.5
	draw_colored_polygon(PackedVector2Array([door - (se - sw) * 0.14, door + (se - sw) * 0.14, door.lerp(apex, 0.55)]),
		Color(0.12, 0.1, 0.1))
	draw_line(sw, apex, c.lightened(0.25), 1.0)
	draw_line(se, apex, c.lightened(0.25), 1.0)


## 화면에서 이 건물(전체)의 윤곽 — 사각형 바닥과 지붕을 감싼 육각형 (월드 좌표)
static func silhouette(r: Rect2, h: float) -> PackedVector2Array:
	var l := IsoView.lift(h)
	var ne := Vector2(r.end.x, r.position.y)
	var sw := Vector2(r.position.x, r.end.y)
	return PackedVector2Array([r.position + l, ne + l, ne, r.end, sw, sw + l])


## 조각으로 나눈다: 긴 변을 짧은 변 길이에 가깝게 자른다
static func split(r: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if r.size.x >= r.size.y:
		var n := maxi(1, roundi(r.size.x / r.size.y))
		for k in n:
			out.append(Rect2(r.position.x + r.size.x * k / n, r.position.y, r.size.x / n, r.size.y))
	else:
		var n := maxi(1, roundi(r.size.y / r.size.x))
		for k in n:
			out.append(Rect2(r.position.x, r.position.y + r.size.y * k / n, r.size.x, r.size.y / n))
	return out


# ── 벽면 그림 (BuildingSkin) ──────────────────────────────

## 벽면 그림 위에 그대로 얹는 장식 (간판·번호판 — 글자는 코드가 그린다). 나머지(필로티·발코니·실외기·가게 앞)는 그림에 있다
const SKIN_DECOS: Array[StringName] = [&"name", &"plate", &"top_sign", &"big_sign", &"rental_image", &"vsign",
	&"band_signs", &"number", &"office_plate"]


## 벽 한 면을 그림으로: 층마다(맨 아래 1층 띠, 그 위 윗층 띠) 창 칸마다 그림 한 칸.
## 긴 벽은 정면 그림, 짧은 벽은 옆벽 그림. 불빛 조각은 불빛 그림을 칸마다 켜지는 차례를 담아 그린다
func _skin_wall(p: BuildingModel.Piece, south: bool) -> void:
	var skin := p.skin
	var other := p.rect.size.y if south else p.rect.size.x
	var front := _len > other + 0.5 or (absf(_len - other) <= 0.5 and south)
	var blk: Dictionary = skin.blocks["front" if front else "side"]
	var n: int = blk["bays"]
	var bays := maxi(1, roundi(_len / skin.bay_world))
	var w := _len / bays
	var tint := Color.WHITE.darkened(_shade * 0.75)
	for f in _floors:
		var band: Rect2 = blk["ground" if f == 0 else "upper"]
		for k in bays:
			var c := k % n
			var uv := Rect2(band.position + Vector2(band.size.x * c / n, 0.0), Vector2(band.size.x / n, band.size.y))
			if not lights:
				_skin_quad(k * w, (k + 1) * w, f * _fh, (f + 1) * _fh, uv, skin.day, tint, false)
			elif skin.lights and _lit(k, f, 11 if f == 0 else 5):
				var key := k * 41 + f
				var turn := BuildingModel.hash01(_p.seed + key * key * 31, key + int(_n.x) * 977) * (0.3 if f == 0 else 0.95)
				_skin_quad(k * w, (k + 1) * w, f * _fh, (f + 1) * _fh, uv, skin.lights, Color(turn, 1.0, 1.0), true)
	for d in p.deco:
		if d in SKIN_DECOS and (not lights or d in LIGHT_DECOS or d in StreetDecor.LIGHT):
			_deco(d, south)


## 그림 한 칸을 벽 위 x0~x1(화면 왼쪽부터 벽을 따라 거리) · z0~z1에. 이 조각 구간으로 자르고 UV도 같이 자른다.
## glow면 불빛 셰이더의 그림 모드 (UV.x − 4, 꼭짓점 색 r = 켜지는 차례)
func _skin_quad(x0: float, x1: float, z0: float, z1: float, uv: Rect2, tex: Texture2D, color: Color, glow: bool) -> void:
	var flip := IsoView.to_screen_dir(_along).x < 0.0     # 동쪽 벽은 벽을 따라가면 화면 왼쪽으로 간다
	var s0 := _len - x1 if flip else x0
	var s1 := _len - x0 if flip else x1
	var a := maxf(s0, _s0)
	var b := minf(s1, _s1)
	if b - a < 0.3:
		return
	var ta := (a - s0) / (s1 - s0)
	var tb := (b - s0) / (s1 - s0)
	var ua := uv.end.x - uv.size.x * ta if flip else uv.position.x + uv.size.x * ta
	var ub := uv.end.x - uv.size.x * tb if flip else uv.position.x + uv.size.x * tb
	var off := -4.0 if glow else 0.0
	draw_primitive(PackedVector2Array([_pt(a, z0), _pt(b, z0), _pt(b, z1), _pt(a, z1)]),
		PackedColorArray([color, color, color, color]),
		PackedVector2Array([Vector2(ua + off, uv.end.y), Vector2(ub + off, uv.end.y),
			Vector2(ub + off, uv.position.y), Vector2(ua + off, uv.position.y)]), tex)


## 옥상: 위에서 본 옥상 그림을 지붕 면에 편다. 뒤쪽 두 변(북·서)의 난간은 안쪽 면과 윗면을 여기서 —
## 옥상 설비보다 먼저 그려야 설비가 그 앞에 선다
func _skin_roof(p: BuildingModel.Piece) -> void:
	var uv := p.skin.roof
	draw_primitive(_corners(p.rect, p.h1), PackedColorArray([Color(0.86, 0.86, 0.86)]),   # 옥상은 위를 봐 벽보다 밝지만, 그림이 진해 조금 누른다
		PackedVector2Array([uv.position, Vector2(uv.end.x, uv.position.y), uv.end, Vector2(uv.position.x, uv.end.y)]), p.skin.day)
	if p.rect.size.x > PARAPET_T * 4.0 and p.rect.size.y > PARAPET_T * 4.0:
		for south: bool in [false, true]:
			_skin_parapet_face(p, south, true)
		_skin_parapet_cap(p, false)


const PARAPET_T := 4.0   ## 벽면 그림 건물의 옥상 난간 두께 (월드 px) — 띠 한 장이면 납작해 보인다


## 난간 한 변: 바깥 면(앞쪽 두 변) 또는 뒤쪽 변의 안쪽 면(inner — 옥상 쪽을 보고 서 있어 앞에서 보인다).
## south: 남(앞 x축) 변 / 북 변의 안쪽 면, 아니면 동 변 / 서 변의 안쪽 면
func _skin_parapet_face(p: BuildingModel.Piece, south: bool, inner: bool) -> void:
	var r := p.rect
	var floors := maxi(1, roundi((p.h1 - p.h0) / p.floor_height))
	var fh := (p.h1 - p.h0) / floors
	var t := PARAPET_T if inner else 0.0
	var n := Vector2.DOWN if south else Vector2.RIGHT
	_p = p
	_n = n
	_shade = IsoView.face_shade(n)
	if inner:
		_fa = r.position + Vector2(t, t)
	else:
		_fa = Vector2(r.position.x, r.end.y) if south else Vector2(r.end.x, r.position.y)
	_along = Vector2.RIGHT if south else Vector2.DOWN
	_len = (r.size.x if south else r.size.y) - 2.0 * t
	_s0 = 0.0
	_s1 = _len
	var other := r.size.y if south else r.size.x
	var whole := r.size.x if south else r.size.y
	var front := whole > other + 0.5 or (absf(whole - other) <= 0.5 and south)
	var blk: Dictionary = p.skin.blocks["front" if front else "side"]
	var band: Rect2 = blk["parapet"]
	var nb: int = blk["bays"]
	var bays := maxi(1, roundi(whole / p.skin.bay_world))
	var w := whole / bays
	var h := p.h1 - p.h0
	# 안쪽 면은 옥상 쪽이라 바깥 면보다 그늘지게
	var tint := Color.WHITE.darkened(_shade * 0.75 + (0.22 if inner else 0.0))
	for k in bays:
		var c := k % nb
		var uv := Rect2(band.position + Vector2(band.size.x * c / nb, 0.0), Vector2(band.size.x / nb, band.size.y))
		_skin_quad(k * w - t, (k + 1) * w - t, h, h + fh * p.skin.parapet, uv, p.skin.day, tint, false)


## 난간 윗면 (두께 PARAPET_T의 띠): 뒤쪽 두 변(front = false) 또는 앞쪽 두 변
func _skin_parapet_cap(p: BuildingModel.Piece, front: bool) -> void:
	var r := p.rect
	var floors := maxi(1, roundi((p.h1 - p.h0) / p.floor_height))
	var top := p.h1 + (p.h1 - p.h0) / floors * p.skin.parapet
	var t := PARAPET_T
	var cap := Color(0.78, 0.78, 0.76)
	var strips: Array[Rect2] = []
	if front:
		strips = [Rect2(r.position.x, r.end.y - t, r.size.x, t), Rect2(r.end.x - t, r.position.y, t, r.size.y - t)]
	else:
		strips = [Rect2(r.position.x, r.position.y, r.size.x, t), Rect2(r.position.x, r.position.y + t, t, r.size.y - t)]
	for q in strips:
		draw_primitive(_corners(q, top), PackedColorArray([cap, cap, cap, cap]), PackedVector2Array())
	# 바깥 모서리 선: 윗면과 바깥 면 경계를 또렷하게
	var l := IsoView.lift(top)
	var edge := cap.darkened(0.35)
	if front:
		draw_polyline(PackedVector2Array([Vector2(r.position.x, r.end.y) + l, r.end + l, Vector2(r.end.x, r.position.y) + l]), edge, 1.0)
	else:
		draw_polyline(PackedVector2Array([Vector2(r.position.x, r.end.y) + l, r.position + l, Vector2(r.end.x, r.position.y) + l]), edge, 1.0)


## 옥상 난간: 보이는 두 벽 위에 난간 띠를 세운다 (옥상·옥탑보다 나중에 — 앞 가장자리의 난간이 그 앞에 선다).
## 지붕 조각(가장 앞)이 벽 전체 길이를 한 번에 그린다
func _skin_parapet(p: BuildingModel.Piece) -> void:
	for south: bool in [false, true]:
		_skin_parapet_face(p, south, false)
	if p.rect.size.x > PARAPET_T * 4.0 and p.rect.size.y > PARAPET_T * 4.0:
		_skin_parapet_cap(p, true)


# ── 통째 그림 (BuildingSprite) ────────────────────────────

## 이 조각의 윤곽만큼 통째 그림을 오려 그린다. 지붕 조각은 얹힌 덩어리(첨탑·옥탑)도 각자 윤곽대로.
## 불빛 조각은 불빛 그림을 불빛 셰이더의 그림 모드로 (덩어리마다 켜지는 차례 하나)
func _sprite_draw() -> void:
	_sprite_hull(piece, part)
	if roof:
		_sprite_tops(piece)


func _sprite_tops(p: BuildingModel.Piece) -> void:
	for s: BuildingModel.Piece in p.on_top:
		_sprite_hull(s, s.rect)
		_sprite_tops(s)


func _sprite_hull(p: BuildingModel.Piece, r: Rect2) -> void:
	var sp := p.sprite
	var tex := sp.lights if lights else sp.day
	if tex == null:
		return
	var pts := BuildingSprite.outline(p, r)
	if pts.size() < 3:
		return
	var uvs := PackedVector2Array()
	for v in pts:
		uvs.append(sp.uv(v, p.lot) + (Vector2(-4.0, 0.0) if lights else Vector2.ZERO))
	var c := Color.WHITE
	if lights:
		c = Color(BuildingModel.hash01(p.seed, int(p.rect.position.x) * 7 + int(p.rect.position.y)) * 0.6, 1.0, 1.0)
	draw_polygon(pts, PackedColorArray([c]), uvs, tex)
