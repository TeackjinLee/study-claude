class_name RainFx
extends RefCounted
## 비 화면 효과: 화면을 덮는 사각형 하나에 거는 셰이더 (그리기 한 번 — 빗줄기를 선으로 하나씩 그리지 않는다).
## 불규칙하게 보이도록:
## - 빗줄기 세 겹(가까이 길고 빠르고 성김 · 멀리 짧고 흐리고 촘촘). 열마다 간격·빠르기·길이·밝기가 다르고 줄도 칸마다 있다 없다 한다
## - 바람: 기울기가 천천히 흔들리고 가끔 돌풍이 분다
## - 빗발: 화면 곳곳이 굵어졌다 가늘어졌다 하며 흘러간다 (큰 얼룩 노이즈)
## - 땅에 튀는 물방울: 땅에 붙어 있다(카메라가 움직이면 같이 밀린다), 칸마다 다른 때·크기로 튄다
## 빗줄기 겹도 카메라 이동만큼(가까운 겹일수록 덜) 밀려 땅 위 공중에 있는 것처럼 보인다.
## 세기·카메라는 DayNight가 프레임마다 `update`로 넣는다.

static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SHADER
		_material.shader = sh
	return _material


## rain 빗발 세기 0..1, view 월드 → 화면 변환 (카메라)
static func update(rain: float, view: Transform2D) -> void:
	var m := material()
	m.set_shader_parameter("rain", rain)
	m.set_shader_parameter("ground", view.origin)
	m.set_shader_parameter("zoom", view.x.length())


const SHADER := """
shader_type canvas_item;

uniform float rain = 0.0;
uniform vec2 ground = vec2(0.0);   // 월드 원점의 화면 위치 (카메라가 움직이면 바뀐다)
uniform float zoom = 1.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// 빗줄기 한 겹. px 화면 점(픽셀), lean 기울기(x/y), colw 열 폭, len 줄 길이, speed 떨어지는 빠르기(px/s), fill 열·칸에 줄이 있을 몫
float streaks(vec2 px, float lean, float colw, float len, float speed, float fill, float seed) {
	// 떨어지는 쪽이 +y가 되게 돌린다
	vec2 dir = normalize(vec2(lean, 1.0));
	vec2 q = vec2(px.x * dir.y - px.y * dir.x, px.x * dir.x + px.y * dir.y);
	float col = floor(q.x / colw);
	float c1 = hash(vec2(col, seed));
	float c2 = hash(vec2(col, seed + 1.7));
	float gap = len * (2.5 + 6.0 * c1);                 // 열마다 줄 사이가 다르다
	float y = q.y - TIME * speed * (0.75 + 0.5 * c2) - c1 * 997.0;
	float row = floor(y / gap);
	float r = hash(vec2(col * 1.31 + seed, row));
	if (r > fill) {
		return 0.0;
	}
	float l = len * (0.5 + hash(vec2(row, col + seed)));
	float fy = fract(y / gap) * gap;                     // 칸 안 위치 (클수록 아래 = 앞머리)
	if (fy > l) {
		return 0.0;
	}
	float x = q.x - (col + 0.15 + 0.7 * hash(vec2(row + 3.1, col))) * colw;
	float line = 1.0 - smoothstep(0.35, 1.1, abs(x));
	return line * (fy / l) * (0.45 + 0.55 * hash(vec2(row + 9.4, col)));
}

// 땅에 튀는 물방울: 칸마다 하나, 다른 때·자리·크기로 납작한 고리가 잠깐 퍼진다
float splash(vec2 g, float cell, float seed, float amount) {
	vec2 c = floor(g / cell);
	float h = hash(c + seed);
	float period = 0.5 + 1.1 * hash(c + seed + 2.3);
	float ph = fract(TIME / period + h);
	if (ph > 0.22 || hash(c + floor(TIME / period + h) * 7.1) > amount) {
		return 0.0;
	}
	vec2 at = (c + 0.15 + 0.7 * vec2(hash(c + 5.1), hash(c + 8.3))) * cell;
	vec2 d = (g - at) * vec2(1.0, 2.0);                 // 사선 화면이라 땅 위 동그라미는 납작하다
	float k = ph / 0.22;
	float size = (2.0 + 3.0 * h) * zoom;
	return smoothstep(1.2, 0.0, abs(length(d) - k * size)) * (1.0 - k);
}

void fragment() {
	vec2 px = UV / SCREEN_PIXEL_SIZE;
	// 바람: 기울기가 천천히 흔들리고, 가끔 돌풍
	float gust = smoothstep(0.55, 0.9, noise(vec2(TIME * 0.15, 3.7)));
	float lean = -0.17 + 0.08 * (noise(vec2(TIME * 0.3, 1.3)) - 0.5) - 0.12 * gust;
	// 빗발 얼룩: 굵은 곳과 가는 곳이 바람 따라 흘러간다
	float patch = noise((px - ground * 0.6) / 420.0 + vec2(TIME * 0.12, TIME * 0.05));
	float heavy = rain * (0.45 + 0.75 * patch) * (1.0 + 0.35 * gust);

	float a = 0.0;
	a += streaks(px - ground * 0.9, lean, 7.0, 7.0, 520.0, 0.32 * heavy, 11.0) * 0.45;   // 멀리
	a += streaks(px - ground * 0.75, lean * 1.1, 11.0, 13.0, 760.0, 0.24 * heavy, 23.0) * 0.6;
	a += streaks(px - ground * 0.55, lean * 1.2, 19.0, 26.0, 1150.0, 0.12 * heavy, 37.0) * 0.8;   // 가까이

	vec2 g = (px - ground) / zoom;   // 땅 위 점 (카메라를 따라 움직이지 않는다)
	float s = splash(g, 38.0, 1.0, 0.5 * heavy) + splash(g + 17.0, 61.0, 4.0, 0.6 * heavy);

	COLOR = vec4(0.78, 0.86, 1.0, clamp(a * 0.55 + s * 0.35, 0.0, 1.0) * min(rain * 1.5, 1.0));
}
"""
