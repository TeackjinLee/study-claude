class_name RiverView
extends RefCounted
## 한강 물 그림: 도시 바닥(`City._draw`의 물 사각형)에 거는 셰이더. 물이 하류(서쪽, -x)로 흐른다.
## - 물살: 흐름 쪽으로 길게 늘인 무늬 몇 겹이 저마다 다른 빠르기로 흘러간다(느린 큰 물결 + 빠른 잔물결 줄 + 반짝임)
## - 깊이: 강변에서 멀수록 짙다. 강변까지 거리는 시작할 때 한 번 구운 거리 그림(`shore_field`, 물 +, 땅 -)으로 잰다
## - 강변: 땅 가장자리에 콘크리트 비탈 호안(`BANK` 폭) + 물가 흰 물거품 줄
## - 밤: 강변 가까이 도시 불빛이 물살에 부서져 비친다(`set_lights`, 화면 색으로 나눠 어두워지지 않게)
## - 비: 빗방울 동그라미가 퍼진다
## 그림이 있으면 쓴다: `assets/water/river_tile.png`(물 무늬, 이음매 없는 타일) · `assets/water/river_bank.png`(호안 띠, 위 = 땅 쪽).
## 그림 요청은 `output/imagegen/water/GPT_WATER_PROMPT.md`, 받은 그림은 `python3 tools/prepare_water_textures.py`로 다듬어 넣는다.
## 물 그림은 코드 무늬를 대신하지 않고 그 밑에 깔린다 — 흐름·물살 줄·반짝임·밤 불빛·물거품·비는 그림이 있어도 셰이더가 그린다.

const TEXEL := 32.0            ## 거리 그림 한 칸 (월드 px). 블록·도로 경계가 모두 32의 배수라 직선 강변이 정확하다
const MAX_DIST := 640.0        ## 거리는 여기까지만 잰다
const BANK := 34.0             ## 호안 비탈 폭 (월드 px)
const TILE_PATH := "res://assets/water/river_tile.png"
const BANK_PATH := "res://assets/water/river_bank.png"
const TILE_WORLD := 512.0      ## 물 그림 한 장이 덮는 월드 크기 (px)

static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SHADER
		_material.shader = sh
		var r := CityMap.world_rect()
		_material.set_shader_parameter("shore", ImageTexture.create_from_image(shore_field()))
		_material.set_shader_parameter("field_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
		_material.set_shader_parameter("bank_w", BANK)
		_material.set_shader_parameter("tile_world", TILE_WORLD)
		_material.set_shader_parameter("bank_drop", RiverBank.HEIGHT if IsoView.enabled else 0.0)
		var tile := BuildingSkin.texture(TILE_PATH)
		if tile:
			_material.set_shader_parameter("tile", tile)
			_material.set_shader_parameter("has_tile", true)
		var bank := BuildingSkin.texture(BANK_PATH)
		if bank:
			_material.set_shader_parameter("bank", bank)
			_material.set_shader_parameter("has_bank", true)
			_material.set_shader_parameter("bank_aspect", float(bank.get_width()) / bank.get_height())
	return _material


## 2.5D 옹벽 높이 (`City.set_iso`가 부른다, 위에서 보기면 0)
static func set_drop(h: float) -> void:
	material().set_shader_parameter("bank_drop", h)


## 밤 불빛 (DayNight가 부른다). screen은 화면 색(CanvasModulate) — 비친 불빛은 그만큼 나눠 밝게 남긴다
static func set_lights(on: float, screen: Color, rain: float) -> void:
	var m := material()
	m.set_shader_parameter("lights_on", on)
	m.set_shader_parameter("boost", Vector3(1.0 / screen.r, 1.0 / screen.g, 1.0 / screen.b))
	m.set_shader_parameter("rain", rain)


## 물인 곳: 물 사각형(강 블록·도로 없는 물 위 구간) + 다리 구간·다리 위 교차로 (2.5D에서는 다리 밑이 물이다)
static func is_water_at(p: Vector2) -> bool:
	for r in _water_rects():
		if r.has_point(p):
			return true
	return false


static var _rects: Array[Rect2] = []


static func _water_rects() -> Array[Rect2]:
	if _rects.is_empty():
		_rects = City.water_rects()
		for j in range(CityMap.MIN.y, CityMap.MAX.y + 2):
			for k in CityMap.BRIDGES:
				var c := Vector2i(k, j)
				if CityMap.is_bridge(c, 2):
					_rects.append(City.segment_rect(c, 2))
				var all_water := true
				for b in CityMap.node_blocks(c):
					all_water = all_water and CityMap.is_water(b)
				if all_water:
					_rects.append(City.node_rect(c))
	return _rects


## 물 칸 표 (칸 = TEXEL px): water 1 = 물, bridge 1 = 다리 밑 물 (2.5D에서 상판이 덮는 구간)
static func _mask() -> Dictionary:
	var r := CityMap.world_rect()
	var w := ceili(r.size.x / TEXEL)
	var h := ceili(r.size.y / TEXEL)
	var water := PackedByteArray()
	water.resize(w * h)
	var bridge := PackedByteArray()
	bridge.resize(w * h)
	var under := _bridge_rects()
	for rect in _water_rects():
		var a := Vector2i(((rect.position - r.position) / TEXEL).floor())
		var b := Vector2i(((rect.end - r.position) / TEXEL).ceil())
		var deck := under.has(rect)
		for y in range(maxi(a.y, 0), mini(b.y, h)):
			for x in range(maxi(a.x, 0), mini(b.x, w)):
				water[y * w + x] = 1
				if deck:
					bridge[y * w + x] = 1
	return {"water": water, "bridge": bridge, "w": w, "h": h, "origin": r.position}


static func _bridge_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for j in range(CityMap.MIN.y, CityMap.MAX.y + 2):
		for k in CityMap.BRIDGES:
			var c := Vector2i(k, j)
			if CityMap.is_bridge(c, 2):
				out.append(City.segment_rect(c, 2))
	return out


## 강변 선분: [{a, b, into (땅 → 물 방향), bridge (다리 밑으로 들어가는 곳)}]. 칸 경계를 따라 같은 것끼리 이어 붙인다
static func shore_edges() -> Array:
	var m := _mask()
	var water: PackedByteArray = m.water
	var bridge: PackedByteArray = m.bridge
	var w: int = m.w
	var h: int = m.h
	var o: Vector2 = m.origin
	var out := []
	# 가로 경계 (y-1 칸과 y 칸 사이)
	for y in range(1, h):
		var run := {}
		for x in w + 1:
			var e := {}
			if x < w:
				var up := water[(y - 1) * w + x]
				var dn := water[y * w + x]
				if up != dn:
					var wi := (y * w + x) if dn == 1 else ((y - 1) * w + x)
					e = {"into": Vector2.DOWN if dn == 1 else Vector2.UP, "bridge": bridge[wi] == 1}
			if not run.is_empty() and (e.is_empty() or e.into != run.into or e.bridge != run.bridge):
				out.append({"a": o + Vector2(run.x0, y) * TEXEL, "b": o + Vector2(x, y) * TEXEL, "into": run.into, "bridge": run.bridge})
				run = {}
			if not e.is_empty() and run.is_empty():
				run = e
				run.x0 = x
	# 세로 경계 (x-1 칸과 x 칸 사이)
	for x in range(1, w):
		var run := {}
		for y in h + 1:
			var e := {}
			if y < h:
				var lf := water[y * w + x - 1]
				var rt := water[y * w + x]
				if lf != rt:
					var wi := (y * w + x) if rt == 1 else (y * w + x - 1)
					e = {"into": Vector2.RIGHT if rt == 1 else Vector2.LEFT, "bridge": bridge[wi] == 1}
			if not run.is_empty() and (e.is_empty() or e.into != run.into or e.bridge != run.bridge):
				out.append({"a": o + Vector2(x, run.y0) * TEXEL, "b": o + Vector2(x, y) * TEXEL, "into": run.into, "bridge": run.bridge})
				run = {}
			if not e.is_empty() and run.is_empty():
				run = e
				run.y0 = y
	return out


## 강변까지 거리 그림 (칸 = TEXEL px, 값 = 월드 px, 물 +, 땅 -). 칸 가운데끼리의 거리를 두 번 훑어(체임퍼) 잰다
static func shore_field() -> Image:
	var m := _mask()
	var water: PackedByteArray = m.water
	var w: int = m.w
	var h: int = m.h
	var to_land := _chamfer(water, w, h, 0)
	var to_water := _chamfer(water, w, h, 1)
	var img := Image.create(w, h, false, Image.FORMAT_RF)
	for y in h:
		for x in w:
			var i := y * w + x
			var d: float
			if water[i] == 1:
				d = to_land[i] * TEXEL - TEXEL * 0.5
			else:
				d = -(to_water[i] * TEXEL - TEXEL * 0.5)
			img.set_pixel(x, y, Color(clampf(d, -MAX_DIST, MAX_DIST), 0, 0))
	return img


## 각 칸에서 값이 target인 가장 가까운 칸까지 거리 (칸 단위, 대각 1.414)
static func _chamfer(cls: PackedByteArray, w: int, h: int, target: int) -> PackedFloat32Array:
	var big := MAX_DIST / TEXEL + 2.0
	var d := PackedFloat32Array()
	d.resize(w * h)
	for i in w * h:
		d[i] = 0.0 if cls[i] == target else big
	const DIAG := 1.4142
	for y in h:
		for x in w:
			var i := y * w + x
			var v := d[i]
			if x > 0: v = minf(v, d[i - 1] + 1.0)
			if y > 0:
				v = minf(v, d[i - w] + 1.0)
				if x > 0: v = minf(v, d[i - w - 1] + DIAG)
				if x < w - 1: v = minf(v, d[i - w + 1] + DIAG)
			d[i] = v
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			var v := d[i]
			if x < w - 1: v = minf(v, d[i + 1] + 1.0)
			if y < h - 1:
				v = minf(v, d[i + w] + 1.0)
				if x < w - 1: v = minf(v, d[i + w + 1] + DIAG)
				if x > 0: v = minf(v, d[i + w - 1] + DIAG)
			d[i] = v
	return d


const SHADER := """
shader_type canvas_item;

uniform sampler2D shore : filter_linear, repeat_disable;
uniform vec4 field_rect;
uniform float bank_w = 20.0;
uniform float lights_on = 0.0;
uniform vec3 boost = vec3(1.0);
uniform float rain = 0.0;
uniform sampler2D tile : filter_linear_mipmap, repeat_enable;
uniform bool has_tile = false;
uniform float tile_world = 512.0;
uniform sampler2D bank : filter_linear_mipmap, repeat_enable;
uniform bool has_bank = false;
uniform float bank_aspect = 4.0;   // 호안 그림 가로/세로 — 한 장이 강변을 따라 덮는 길이 = 폭 × 이 값
uniform float bank_drop = 0.0;          // 2.5D 옹벽 높이 (화면 px). 0이면 위에서 보기 — 평면 호안 띠를 칠한다

varying vec2 world;

void vertex() {
	world = VERTEX;
}

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

float fbm(vec2 p) {
	return noise(p) * 0.55 + noise(p * 2.03 + 17.1) * 0.3 + noise(p * 4.1 + 41.7) * 0.15;
}

float sd_at(vec2 w) {
	return texture(shore, (w - field_rect.xy) / field_rect.zw).r;
}

void fragment() {
	vec2 p = world;
	float t = TIME;
	float sd = sd_at(p);
	// 강변 결: 강변이 가로면 x, 세로면 y를 따라간다
	vec2 g = vec2(sd_at(p + vec2(24.0, 0.0)) - sd_at(p - vec2(24.0, 0.0)), sd_at(p + vec2(0.0, 24.0)) - sd_at(p - vec2(0.0, 24.0)));
	float along = abs(g.x) > abs(g.y) ? p.y : p.x;

	// 깊이: 강변 가까이는 얕고 탁한 녹갈색, 가운데는 짙은 청록
	float depth = smoothstep(0.0, 420.0, sd);
	vec3 col = mix(vec3(0.24, 0.32, 0.30), vec3(0.11, 0.20, 0.25), depth);

	// 느린 큰 물결 (흐름 쪽으로 길게)
	float swell = fbm(vec2((p.x + t * 18.0) / 560.0, p.y / 190.0));
	if (has_tile) {
		// 그림 두 장을 다른 빠르기·크기로 흘려 겹친다 (흐르는 물처럼)
		vec3 a = texture(tile, (p + vec2(t * 26.0, 0.0)) / tile_world).rgb;
		vec3 b = texture(tile, (p * 0.73 + vec2(t * 15.0 + 211.0, 97.0)) / tile_world).rgb;
		vec3 tex = (a + b) * 0.5;
		col = mix(col, tex * mix(1.05, 0.8, depth), 0.85);
	}
	col *= 0.86 + 0.28 * swell;

	// 물살 줄: 빠른 잔물결 두 겹이 겹치는 곳이 밝은 줄이 된다
	float r1 = noise(vec2((p.x + t * 48.0) / 95.0, p.y / 15.0));
	float r2 = noise(vec2((p.x + t * 33.0) / 150.0, (p.y + 57.0) / 23.0));
	float streak = smoothstep(0.66, 0.92, r1 * 0.55 + r2 * 0.55);
	col = mix(col, vec3(0.40, 0.50, 0.53), streak * 0.32);
	float trough = smoothstep(0.35, 0.1, r1 * 0.5 + r2 * 0.5);
	col *= 1.0 - trough * 0.12;

	// 하늘 반짝임
	float gl = noise(vec2((p.x + t * 62.0) / 17.0, p.y / 6.5));
	col += vec3(0.16, 0.2, 0.22) * smoothstep(0.9, 0.98, gl) * (0.4 + 0.6 * swell) * (1.0 - lights_on * 0.6);

	// 밤: 강변 가까이 도시 불빛이 물살에 부서져 비친다 (흐름 쪽으로 짧은 조각)
	if (lights_on > 0.0) {
		float zone = 1.0 - smoothstep(20.0, 300.0, sd);
		// 가는 줄: 흐름 쪽으로 길고 가로로 아주 얇다. 줄마다 깜박이며 흘러간다
		float line = noise(vec2((p.x + t * 40.0) / 46.0, p.y / 3.2));
		float flick = noise(vec2((p.x + t * 25.0) / 120.0, p.y / 14.0 + t * 0.7));
		float hue = noise(p / 260.0);
		vec3 lc = hue < 0.55 ? vec3(1.0, 0.72, 0.38) : (hue < 0.8 ? vec3(0.95, 0.9, 0.8) : vec3(0.5, 0.85, 1.0));
		float lit = smoothstep(0.7, 0.9, line) * smoothstep(0.4, 0.75, flick) * zone * lights_on;
		col += lc * lit * 0.6 * boost;
	}

	// 비: 빗방울 동그라미가 퍼진다. 크기가 다른 칸 두 겹, 칸마다 떨어지는 때·간격·자리·크기가 다르고 (떨어질 때마다 자리를 새로 뽑는다)
	// 빗발 얼룩(굵은 곳·가는 곳)이 바람 따라 흘러간다
	if (rain > 0.0) {
		float heavy = rain * (0.35 + 0.8 * noise(p / 700.0 + vec2(t * 0.1, t * 0.04)));
		for (int k = 0; k < 2; k++) {
			float cell = k == 0 ? 31.0 : 53.0;
			vec2 q = p + float(k) * vec2(17.0, 29.0);
			vec2 cid = floor(q / cell);
			float h = hash(cid + float(k) * 3.7);
			float period = 0.6 + 1.3 * hash(cid + 5.3);
			float n = floor(t / period + h);              // 이 칸에 몇 번째로 떨어지는 방울인가
			float ph = fract(t / period + h);
			vec2 drop = cid + vec2(float(k) * 9.1 + n * 0.37);
			if (hash(drop) < heavy * (k == 0 ? 0.5 : 0.7)) {
				vec2 c = (cid + 0.15 + 0.7 * vec2(hash(drop + 1.3), hash(drop + 4.9))) * cell - float(k) * vec2(17.0, 29.0);
				float size = (k == 0 ? 7.0 : 13.0) * (0.6 + 0.8 * hash(drop + 2.2));
				float life = min(ph * 1.8, 1.0);
				float ring = abs(length(p - c) - life * size);
				col += vec3(0.24, 0.29, 0.31) * smoothstep(1.4, 0.0, ring) * (1.0 - life);
			}
		}
	}

	// 물가: 흰 물거품 줄이 흐름 따라 끊겼다 이어진다.
	// 2.5D에서는 수면이 옹벽(`RiverBank`) 높이만큼 낮다 — 화면 위로 bank_drop만큼 올라간 자리(물가의 옹벽 발치)에서 강변까지 잰다.
	// 그래서 거품은 보이는 옹벽(북·서 둑) 발치에 서고, 앞 둑(남·동) 밑은 땅에 가려 없다
	float se = bank_drop > 0.0 ? sd_at(p + vec2(-1.2820513, -1.2820513) * bank_drop) : sd;
	float edge = se - (bank_drop > 0.0 ? 0.0 : bank_w);
	float foam_n = noise(vec2((along + t * 30.0) / 14.0, t * 0.6 + along / 400.0));
	float foam_w = bank_drop > 0.0 ? 12.0 : 6.0;   // 옹벽 발치는 물이 부딪혀 거품이 더 넓다
	float foam = (1.0 - smoothstep(0.0, foam_w + foam_w * 0.6 * foam_n, edge)) * (0.45 + 0.55 * foam_n);
	if (bank_drop > 0.0) {
		// 옹벽에 부딪힌 물: 끊긴 흰 물보라 조각이 흘러간다
		float burst = smoothstep(0.35, 0.75, noise(vec2((along + t * 42.0) / 9.0, t * 0.9)));
		col = mix(col, vec3(0.78, 0.84, 0.84), clamp(foam * (0.35 + burst), 0.0, 1.0) * 0.8);
	} else {
		col = mix(col, vec3(0.62, 0.68, 0.68), clamp(foam, 0.0, 1.0) * 0.55);
	}
	col *= mix(0.78, 1.0, smoothstep(0.0, 14.0, edge));   // 물가 그늘

	// 호안 (콘크리트 비탈): 땅에서 물 쪽으로 내려간다 — 위는 밝고 물에 가까울수록 젖어 어둡다 (위에서 보기만, 2.5D는 옹벽이 덮는다)
	if (edge < 0.0 && bank_drop <= 0.0) {
		float k = clamp(sd / bank_w, 0.0, 1.0);
		vec3 bc;
		if (has_bank) {
			bc = texture(bank, vec2(along / (bank_w * bank_aspect), k)).rgb;
		} else {
			float step_line = step(0.82, fract(sd / 5.0));
			float block = step(0.94, fract(along / 38.0));
			bc = vec3(0.47, 0.47, 0.45) * (1.0 - 0.18 * max(step_line, block)) * (0.92 + 0.12 * noise(vec2(along / 9.0, sd / 3.0)));
		}
		bc *= mix(1.0, 0.62, smoothstep(0.45, 1.0, k));
		col = bc;
	}
	COLOR = vec4(col, 1.0);
}
"""
