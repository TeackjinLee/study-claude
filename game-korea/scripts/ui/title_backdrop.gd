class_name TitleBackdrop
extends Node2D
## 타이틀 화면에서 그림(assets/title) 위에 얹는 움직이는 효과. 그림 자체는 TitleScreen이 깐다.
## Mode.GLOW: 그림 바로 위·차 아래 — 왼쪽 어둡게(글자가 읽히게), 네온 간판 깜박임, 길바닥에 번지는 헤드라이트·경광등 불빛
## Mode.RAIN: 차·인물 위 — 경광등 번쩍임(빨강·파랑 0.25초 교차)과 빗줄기
## 배경 그림은 1376×768이고 화면(1280×720)에 꽉 차게(cover) 맞춰 깐다 — 그림 좌표는 image_to_screen()으로 바꾼다.

enum Mode { GLOW, RAIN }

const VIEW := Vector2(1280, 720)
const IMAGE := Vector2(1376, 768)
const RED_LIGHT := Color(1.0, 0.14, 0.22)
const BLUE_LIGHT := Color(0.18, 0.42, 1.0)
const SIREN_MS := 250                  ## 빨강·파랑 교차 주기 (docs/06, Vehicle._siren_phase와 같다)

## 배경 그림 안 네온 간판: [x0, y0, x1, y1, 색] (그림 좌표). 깜박이는 것만 골랐다
const SIGNS := [
	[537, 85, 577, 192, Color(1.0, 0.35, 0.65)], [538, 203, 577, 288, Color(1.0, 0.62, 0.15)], [540, 293, 577, 382, Color(0.3, 0.6, 1.0)],
	[577, 195, 650, 265, Color(0.3, 0.95, 0.95)], [575, 292, 650, 348, Color(1.0, 0.85, 0.3)], [661, 210, 692, 340, Color(1.0, 0.28, 0.3)],
	[662, 330, 692, 402, Color(0.3, 0.95, 0.6)], [719, 338, 750, 418, Color(1.0, 0.55, 0.15)], [667, 408, 722, 440, Color(1.0, 0.3, 0.3)],
	[376, 96, 408, 198, Color(1.0, 0.95, 0.8)], [141, 118, 172, 212, Color(0.3, 0.9, 0.9)], [143, 215, 172, 296, Color(1.0, 0.6, 0.2)],
	[337, 389, 495, 432, Color(0.9, 1.0, 1.0)], [553, 392, 650, 438, Color(0.9, 1.0, 1.0)], [1082, 292, 1108, 350, Color(0.9, 0.95, 1.0)],
	[1124, 235, 1162, 322, Color(0.9, 0.95, 1.0)], [1152, 300, 1214, 376, Color(1.0, 0.5, 0.2)], [1158, 110, 1222, 200, Color(0.4, 0.9, 1.0)],
]

var mode := Mode.GLOW
## TitleScreen이 채운다: [{at: 차 바닥 가운데(화면), k: 번짐 배율, lamps: [왼쪽 등, 오른쪽 등](화면), siren: bool, left: "red"|"blue"}]
var cars: Array = []
var _t := 0.0


func _init(p_mode := Mode.GLOW) -> void:
	mode = p_mode


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if mode == Mode.GLOW:
		_shade()
		_signs()
		_pools()
	else:
		_front()


## 그림 좌표 → 화면 좌표 (꽉 차게 덮고 가운데 맞춤)
static func image_to_screen(p: Vector2) -> Vector2:
	var k := maxf(VIEW.x / IMAGE.x, VIEW.y / IMAGE.y)
	return p * k + (VIEW - IMAGE * k) * 0.5


static func _h(i: int, k: int) -> float:
	return fposmod(sin(float(i) * 12.9898 + float(k) * 78.233) * 43758.5453, 1.0)


static func _ell(c: Vector2, rx: float, ry: float, n := 22) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n:
		out.append(c + Vector2(cos(k * TAU / n) * rx, sin(k * TAU / n) * ry))
	return out


func _blob(c: Vector2, rx: float, ry: float, col: Color) -> void:
	if rx > 0.5 and ry > 0.5:
		draw_colored_polygon(_ell(c, rx, ry), col)


static func siren_phase() -> int:
	return int(Time.get_ticks_msec() / SIREN_MS) % 2


## 왼쪽 메뉴 자리를 어둡게 (그림의 큰 건물 창·간판이 글자를 가리지 않게), 위·아래 가장자리도
func _shade() -> void:
	var dark := Color(0.01, 0.02, 0.05)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(420, 0), Vector2(420, 720), Vector2(0, 720)]),
		PackedColorArray([Color(dark, 0.9), Color(dark, 0.74), Color(dark, 0.74), Color(dark, 0.9)]))
	draw_polygon(PackedVector2Array([Vector2(420, 0), Vector2(580, 0), Vector2(580, 720), Vector2(420, 720)]),
		PackedColorArray([Color(dark, 0.74), Color(dark, 0.0), Color(dark, 0.0), Color(dark, 0.74)]))
	draw_polygon(PackedVector2Array([Vector2(0, 600), Vector2(1280, 600), Vector2(1280, 720), Vector2(0, 720)]),
		PackedColorArray([Color(dark, 0.0), Color(dark, 0.0), Color(dark, 0.78), Color(dark, 0.78)]))


## 네온 간판: 숨 쉬듯 번졌다가 가끔 꺼질 듯 껌뻑인다
func _signs() -> void:
	for i in SIGNS.size():
		var s: Array = SIGNS[i]
		var a := image_to_screen(Vector2(s[0], s[1]))
		var b := image_to_screen(Vector2(s[2], s[3]))
		var r := Rect2(a, b - a)
		var col: Color = s[4]
		var flick := fmod(_t * 0.7 + i * 1.37, 5.3)
		if flick < 0.1 or (flick > 0.22 and flick < 0.3 and i % 3 == 0):
			draw_rect(r.grow(1.0), Color(0.03, 0.02, 0.07, 0.55))     # 꺼질 듯
		else:
			var breathe := 0.5 + 0.5 * sin(_t * 2.3 + i)
			for g in 3:
				draw_rect(r.grow(2.0 + g * 5.0), Color(col, (0.035 + 0.025 * breathe) / (1.0 + g * 0.6)))


## 길바닥에 번지는 불빛: 헤드라이트(모든 차)와 경광등 빨강·파랑 웅덩이
func _pools() -> void:
	var phase := siren_phase()
	for c: Dictionary in cars:
		var s: Vector2 = c.at
		var kk: float = c.k
		_blob(s + Vector2(-100, 30) * kk, 130.0 * kk, 28.0 * kk, Color(1.0, 0.92, 0.7, 0.07))
		_blob(s + Vector2(-80, 24) * kk, 70.0 * kk, 15.0 * kk, Color(1.0, 0.95, 0.8, 0.09))
		if c.siren:
			var col := RED_LIGHT if phase == 0 else BLUE_LIGHT
			var side := -1.0 if phase == 0 else 1.0
			var at := s + Vector2(side * 26.0, 12.0) * kk
			_blob(at, 170.0 * kk, 38.0 * kk, Color(col, 0.13))
			_blob(at, 100.0 * kk, 22.0 * kk, Color(col, 0.17))
			_blob(at, 45.0 * kk, 10.0 * kk, Color(col, 0.22))


## 차·인물 위: 경광등 번쩍임, 빗줄기
func _front() -> void:
	var phase := siren_phase()
	for c: Dictionary in cars:
		if not c.siren:
			continue
		# 두 등이 교대로 번쩍: 켜진 쪽은 크고 밝게, 꺼진 쪽은 희미하게
		for side in 2:
			var red_side: bool = (side == 0) == (c.left == "red")
			var on: bool = (phase == 0) == red_side
			var col := RED_LIGHT if red_side else BLUE_LIGHT
			var at: Vector2 = c.lamps[side]
			var kk: float = c.k
			if on:
				_blob(at, 34.0 * kk, 20.0 * kk, Color(col, 0.2))
				_blob(at, 16.0 * kk, 10.0 * kk, Color(col, 0.42))
				_blob(at, 5.0 * kk, 3.5 * kk, Color(1, 1, 1, 0.85))
	for i in 70:
		var sp := 650.0 + 450.0 * _h(i, 1)
		var x := fposmod(_h(i, 2) * 1500.0 - _t * sp * 0.28, 1500.0) - 100.0
		var y := fposmod(_h(i, 3) * 820.0 + _t * sp, 820.0) - 50.0
		var len := 14.0 + 18.0 * _h(i, 4)
		draw_line(Vector2(x, y), Vector2(x - len * 0.28, y + len), Color(0.78, 0.8, 1.0, 0.08 + 0.16 * _h(i, 5)), 1.0)
