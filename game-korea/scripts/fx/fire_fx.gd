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
