class_name FireFx
## 불·연기·불씨·불빛을 코드로 그리는 공통 그림 (차 화재·폭발·땅 불이 같이 쓴다).
## 참고 그림(불꽃 8단계·연기 기둥·불씨 입자·불탄 바닥)을 따라 층을 겹쳐 그린다: 바깥 빨강 → 주황 → 노랑 → 흰 심지.
## 불꽃·연기·불씨는 화면 기준 좌표(IsoView.screen_frame 안, y가 위로 음수)에서, 불빛·그을음은 바닥 좌표에서 그린다.
## 노드 없는 정적 함수뿐이다. 원은 draw_circle(수십 각형) 대신 작은 원 그림을 네모 한 장으로 붙인다(circle) —
## 큰 반투명 원을 수십 개 겹치면 불난 차 한 대에 2ms가 넘게 든다.

const OUTER := Color(0.86, 0.16, 0.04)
const MID := Color(1.0, 0.45, 0.06)
const INNER := Color(1.0, 0.78, 0.2)
const CORE := Color(1.0, 0.96, 0.72)
const SMOKE := Color(0.17, 0.16, 0.17)
const SMOKE_LIT := Color(0.32, 0.3, 0.31)
const CHAR := Color(0.06, 0.04, 0.035)

static var _disc: Texture2D   ## 흰 원 (가장자리가 딱 떨어지는 픽셀 원)
static var _soft: Texture2D   ## 가운데서 가장자리로 사라지는 원 (불빛)
static var _puff: Texture2D   ## 가운데서 가장자리로 사라지는 흰 원 (연기 한 덩이)

## 넘김 그림(assets/fx/, tools/prepare_fx_sprites.py): 있으면 폭발 불덩이·연기, 불꽃, 그을음을 그림으로 그린다.
## 없으면 아래 코드 그림 그대로. false면 언제나 코드 그림 (도감 비교)
static var sprites := true
const SHEET_DIR := "res://assets/fx/"
const FLAME_FPS := 14.0      ## 불꽃 되풀이 넘김 빠르기
static var _sheets := {}     ## 이름 → 시트 정보 + tex (그림이 없으면 빈 사전)
static var _meta = null


## 넘김 그림 시트 (fx.json의 칸 배치·바닥 점·칸마다 덩어리 + tex). 없거나 sprites가 꺼졌으면 빈 사전
static func sheet(name: String) -> Dictionary:
	if not sprites:
		return {}
	if not _sheets.has(name):
		if _meta == null:
			var f := FileAccess.open(SHEET_DIR + "fx.json", FileAccess.READ)
			_meta = JSON.parse_string(f.get_as_text()) if f else {}
			if not _meta is Dictionary:
				_meta = {}
		var tex := BuildingSkin.texture(SHEET_DIR + name + ".png") if _meta.has(name) else null
		_sheets[name] = {}
		if tex:
			_sheets[name] = (_meta[name] as Dictionary).duplicate()
			_sheets[name].tex = tex
	return _sheets[name]


## 넘김 그림 한 장: 시트의 바닥 점(anchor)이 at에 오게, 칸 px × k 크기로 (화면 기준 좌표에서 부른다).
## flip이면 바닥 점을 축으로 좌우로 뒤집는다 — 같은 그림을 엇갈려 쓴다
static func frame(ci: CanvasItem, s: Dictionary, i: int, at: Vector2, k: float, color := Color.WHITE, flip := false) -> void:
	if k <= 0.0 or color.a <= 0.0:
		return
	if ci.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
		ci.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # 크게 그린 그림을 줄여 그린다
	var cell: float = s.cell
	var cols: int = s.grid[0]
	var tex: Texture2D = s.tex
	var uv0 := Vector2((i % cols) * cell, (i / cols) * cell) / tex.get_size()
	var uv1 := uv0 + Vector2(cell, cell) / tex.get_size()
	var ax: float = s.anchor[0]
	var ay: float = s.anchor[1]
	var x0 := at.x + (-ax if not flip else ax - cell) * k
	var x1 := x0 + cell * k
	var y0 := at.y - ay * k
	var y1 := y0 + cell * k
	var u0 := uv0.x if not flip else uv1.x
	var u1 := uv1.x if not flip else uv0.x
	ci.draw_primitive(PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]),
		PackedColorArray([color, color, color, color]),
		PackedVector2Array([Vector2(u0, uv0.y), Vector2(u1, uv0.y), Vector2(u1, uv1.y), Vector2(u0, uv1.y)]), tex)


## 원 하나 (네모 한 장에 원 그림). draw_circle과 같은 자리·크기
static func circle(ci: CanvasItem, at: Vector2, r: float, color: Color) -> void:
	if r <= 0.0:
		return
	if _disc == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var inside := Vector2(x + 0.5 - 16.0, y + 0.5 - 16.0).length() <= 16.0
				img.set_pixel(x, y, Color(1, 1, 1, 1.0 if inside else 0.0))
		_disc = ImageTexture.create_from_image(img)
	ci.draw_texture_rect(_disc, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false, color)


## 가장자리가 부드럽게 사라지는 연기 한 덩이 (color의 알파가 가운데 진하기). r은 보이는 반지름쯤
static func puff(ci: CanvasItem, at: Vector2, r: float, color: Color) -> void:
	if r <= 0.0 or color.a <= 0.0:
		return
	if _puff == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.55, Color(1, 1, 1, 0.75))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 48
		tex.height = 48
		_puff = tex
	var rr := r * 1.3
	ci.draw_texture_rect(_puff, Rect2(at - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, color)


static func _soft_disc() -> Texture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.85, 0.6, 1.0))
		g.set_color(1, Color(1.0, 0.45, 0.12, 0.0))
		g.add_point(0.45, Color(1.0, 0.6, 0.25, 0.45))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_soft = tex
	return _soft


## 불꽃 하나: 바닥 at에 서서 위로 솟는 물방울 모양. size는 높이(px), seed는 깜박임을 엇갈리게 한다
static func flame(ci: CanvasItem, at: Vector2, size: float, t: float, seed: float, alpha := 1.0) -> void:
	if size < 1.0:
		return
	var loop := sheet("flame_loop")
	if not loop.is_empty():
		# 그림: 8장 되풀이, seed로 장·좌우를 엇갈린다. 그림 불꽃 키 ≈ 코드 불꽃(흔들림 포함) 키
		var f := posmod(int(t * FLAME_FPS + seed * 7.0), int(loop.frames))
		frame(ci, loop, f, at, size * 1.15 / float(loop.height), Color(1, 1, 1, alpha), posmod(int(seed * 3.0), 2) == 1)
		return
	var flick := sin(t * 13.0 + seed * 3.1) * 0.5 + sin(t * 21.0 + seed * 1.7) * 0.25
	var h := size * (1.0 + 0.16 * flick)
	var sway := sin(t * 6.0 + seed * 2.3) * 0.22 * size
	var layers := [[OUTER, 1.0], [MID, 0.78], [INNER, 0.55], [CORE, 0.3]]
	for l: Array in layers:
		var k: float = l[1]
		_drop(ci, at + Vector2(0, -size * 0.04 * (1.0 - k)), size * 0.4 * k, h * k, sway * k, Color(l[0], alpha))
	# 끝에서 떨어져 나가는 불 조각 (두 개)
	for i in 2:
		var life := fmod(t * 2.4 + seed * 0.37 + i * 0.5, 1.0)
		var p := at + Vector2(sway * 1.2 + sin(seed * 5.0 + i * 2.0) * size * 0.18, -h * (0.95 + life * 0.45))
		var s := maxf(size * 0.09 * (1.0 - life), 0.6)
		ci.draw_rect(Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), Color(MID if i == 0 else INNER, alpha * (1.0 - life)))


## 연기 기둥: at에서 피어올라 바람에 조금 밀리며 흩어진다. scale은 크기, dark는 0(회색)~1(검은 연기)
static func smoke(ci: CanvasItem, at: Vector2, t: float, scale: float, dark := 1.0, alpha := 1.0, seed := 0.0, puffs := 5) -> void:
	var base := SMOKE_LIT.lerp(SMOKE, dark)
	var grey := Color(0.5, 0.5, 0.52).lerp(base, dark)
	for i in puffs:
		var k := fmod(t * 0.55 + float(i) / puffs + seed * 0.13, 1.0)
		var p := at + Vector2(k * k * 18.0 * scale + sin(t * 1.3 + i * 2.1 + seed) * 2.5 * scale, -k * 46.0 * scale)
		var r := (2.5 + k * 9.0) * scale
		var a := alpha * minf(k * 6.0, 1.0) * (1.0 - k) * 0.8
		# 뭉게구름: 큰 원 하나에 작은 원 둘, 왼쪽 위만 살짝 밝게
		a = minf(a * 1.25, 0.85)
		circle(ci, p, r, Color(grey, a))
		circle(ci, p + Vector2(-r * 0.55, r * 0.2), r * 0.7, Color(grey, a))
		circle(ci, p + Vector2(-r * 0.25, -r * 0.35), r * 0.5, Color(grey.lightened(0.12), a * 0.8))


## 불씨: 작은 네모 점이 위로 날리며 노랑 → 주황 → 빨강으로 식는다
static func embers(ci: CanvasItem, at: Vector2, t: float, n: int, spread: float, rise: float, seed := 0.0, alpha := 1.0) -> void:
	for i in n:
		var k := fmod(t * 0.8 + i * 0.618 + seed * 0.29, 1.0)
		var x := (fmod(i * 0.377 + seed * 0.11, 1.0) - 0.5) * spread * 2.0 + sin(t * 3.0 + i * 1.7) * 3.0
		var p := at + Vector2(x + k * 6.0, -k * rise)
		var c := INNER.lerp(OUTER, k)
		var s := 1.3 if i % 3 else 1.8
		ci.draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), Color(c, alpha * (1.0 - k * k)))


## 바닥에 번지는 불빛 (바닥 좌표에서 그리면 2.5D에선 납작한 타원이 된다)
static func glow(ci: CanvasItem, at: Vector2, r: float, strength: float, t: float, seed := 0.0) -> void:
	var f := 1.0 + 0.06 * sin(t * 9.0 + seed) + 0.04 * sin(t * 23.0 + seed * 2.0)
	# 가운데로 갈수록 밝은 원 그림 한 장 (테두리가 딱 끊겨 보이지 않게)
	var rr := r * f
	ci.draw_texture_rect(_soft_disc(), Rect2(at - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(1, 1, 1, minf(0.42 * strength, 1.0)))


## 불탄 자국: 울퉁불퉁한 검은 얼룩과 흩어진 잔해 조각 (바닥 좌표). seed가 같으면 모양이 같다
static func char_patch(ci: CanvasItem, at: Vector2, r: float, seed: float, alpha := 1.0) -> void:
	var sc := sheet("scorch")
	if not sc.is_empty():
		# 그림은 화면에서 본 2:1 타원이라 화면 기준으로 세워 그린다 (위에서 보기면 세로로 두 배 늘려 둥글게).
		# 바닥 반지름 r인 원은 화면에서 가로 반 1.1r — 코드 얼룩처럼 조금 넉넉하게 덮는다. 부른 쪽 좌표계는 바닥 기본(없음)이다
		var i := posmod(int(seed * 5.0), int(sc.frames))
		var half: float = maxf(sc.boxes[i][2], 1.0)
		ci.draw_set_transform_matrix(IsoView.screen_frame(at) if IsoView.enabled else Transform2D(0.0, Vector2(1, 2), 0.0, at))
		frame(ci, sc, i, Vector2.ZERO, r * 1.3 / half, Color(1, 1, 1, 0.9 * alpha), posmod(int(seed * 3.0), 2) == 1)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	for i in 7:
		var a := seed * 2.7 + i * 0.9
		var d := r * (0.15 + 0.45 * fmod(seed * 0.31 + i * 0.53, 1.0))
		circle(ci, at + Vector2.RIGHT.rotated(a) * d, r * (0.35 + 0.25 * fmod(i * 0.71 + seed, 1.0)), Color(CHAR, 0.22 * alpha))
	circle(ci, at, r * 0.55, Color(CHAR, 0.35 * alpha))
	for i in 10:
		var a := seed * 1.3 + i * 2.39
		var d := r * (0.5 + 0.7 * fmod(i * 0.61 + seed * 0.17, 1.0))
		var p := at + Vector2.RIGHT.rotated(a) * d
		var s := 1.5 + fmod(i * 0.43, 1.0) * 2.0
		ci.draw_rect(Rect2(p, Vector2(s, s * 0.7)), Color(0.1, 0.08, 0.07, 0.7 * alpha))


## 바닥 불: 그을린 자리 위에 작은 불꽃 여럿 (화면 좌표). r은 퍼진 반지름(화면 px), strength 0~1
static func ground_fire(ci: CanvasItem, at: Vector2, r: float, t: float, seed: float, strength := 1.0) -> void:
	var n := clampi(int(r / 7.0) + 2, 2, 9)
	for i in n:
		var a := float(i) / n * TAU + seed
		var d := r * (0.2 + 0.7 * fmod(i * 0.37 + seed * 0.13, 1.0))
		var p := at + Vector2(cos(a) * d, sin(a) * d * 0.5)   # 바닥에 퍼진 모양 (납작하게)
		var size := (6.0 + r * 0.25) * (0.55 + 0.45 * fmod(i * 0.71 + seed, 1.0)) * strength
		flame(ci, p, size, t, seed + i * 1.3)
	embers(ci, at + Vector2(0, -r * 0.2), t, 4 + n / 2, r * 0.6, 26.0 + r * 0.4, seed, strength)


## 물방울 모양 다각형: 바닥 반원 + 위로 뾰족한 끝 (끝은 sway만큼 옆으로 휜다)
static func _drop(ci: CanvasItem, base: Vector2, half_w: float, h: float, sway: float, c: Color) -> void:
	if half_w < 0.6 or h < 1.2:
		return   # 너무 작으면 삼각형 나누기가 실패한다 (Invalid polygon)
	var pts := PackedVector2Array([
		base + Vector2(sway, -h),
		base + Vector2(half_w * 0.55 + sway * 0.55, -h * 0.55),
		base + Vector2(half_w, -h * 0.22),
		base + Vector2(half_w * 0.7, 0.0),
		base + Vector2(0.0, h * 0.06),
		base + Vector2(-half_w * 0.7, 0.0),
		base + Vector2(-half_w, -h * 0.22),
		base + Vector2(-half_w * 0.55 + sway * 0.55, -h * 0.55),
	])
	ci.draw_colored_polygon(pts, c)
