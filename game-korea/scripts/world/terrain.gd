class_name Terrain
## 서울 지형 높이 (TerrainMap, data/terrain/seoul.tres). 노드 없는 정적 계산 — 그림에만 쓴다. 물리·충돌은 평면 그대로다.
## 도시는 평지이고 산(TerrainMap.hills — 남산·북악·관악 끝자락) 둘레만 솟는다. 산 블록 몇은 건물 대신 숲(TerrainMap.forests)이다.
##
## 높이는 CELL(192px) 격자 표본을 쌍선형으로 잇는다. 셰이더(material)가 바닥 노드의 꼭짓점을 같은 수식으로 올린다 —
## 큰 사각형은 꼭짓점 사이를 곧게 잇게 되므로 격자 선마다 잘라 그린다(rect·texture_rect·line).
## 한강 띠(둑 도로 포함)는 0이고 shore_fall까지 부드럽게 오른다. 고가차도 둘레는 한 높이로 고른다(OverpassView가 그만큼 올려 그린다).
## 다리·고가 상판 높이(CityMap.ground_height)는 이 위에 더한다 — IsoView.ground가 둘을 합친다.
## 비탈에 선 건물 부지는 가장 높은 땅만큼 고른 단(축대)이다(set_terrace — City._place_views). height는 단 위를 그 높이로 돌려주고,
## 청크 셰이더는 단을 모른다 — 단의 바닥은 City.Terrace가 셰이더 없이 그 높이에 그리고, 낮은 앞(남·동) 면에 축대를 세운다.
## 표시·아이템 재질(material())은 단 목록을 받아 단 위 꼭짓점을 단 높이로 올린다.

const DATA := preload("res://data/terrain/seoul.tres")
const MAX_TERRACES := 96                        ## 셰이더가 아는 단 수 (넘으면 표시가 비탈대로 그려진다)
const FOUNDATION := Color(0.42, 0.41, 0.39)     ## 비탈 부지 단의 축대 (돌)
const FOUNDATION_LINE := Color(0.3, 0.29, 0.28)
const FOUNDATION_CAP := Color(0.6, 0.59, 0.56)   ## 축대 위 갓돌
const STONE_ROW := 9.0                          ## 축대 돌 한 줄 높이 (화면 px)
const STONE_LEN := 26.0                         ## 축대 돌 한 장 길이 (월드 px)
const STEP_RAMP := 14.0                         ## 단 가장자리에서 사람·차가 단 높이까지 오르는 거리 (월드 px, 단 안쪽)
## 산으로 솟은 합친 블록 (남산): [그 안 블록, 꼭대기 평지 반폭(월드 px), 높이(화면 px)]. 부지(인도 안) 가장자리에서 0이고
## 가운데로 갈수록 부드럽게 솟는다 — 격자 표본(192px)으로는 모자라 수식으로 더하고, 셰이더도 같은 수식을 쓴다
const MOUNDS := [[Vector2i(2, -6), Vector2(150, 84), 230.0]]
const MOUND_SHADING := 2.6                      ## 산 비탈 그늘을 지형보다 세게 (나무 사이로 비탈이 읽히게)
const MOUND_CELL := 48.0                        ## 산 안에서 바닥 도형을 자르는 간격 (월드 px)
const MAX_MOUNDS := 4

const SHADER := """
shader_type canvas_item;
render_mode world_vertex_coords;
// 바닥을 땅 높이만큼 올리고(Terrain.height와 같은 수식), 비탈 방향으로 밝기를 바꾼다(빛은 화면 왼쪽 위 = 월드 서쪽에서 — 서쪽 비탈이 밝고 동쪽 비탈이 어둡다)
uniform sampler2D heights : filter_nearest;
uniform vec2 origin;
uniform float cell = 192.0;
uniform float strength = 1.0;
uniform float shading = 0.0;
uniform vec2 light = vec2(0.95, 0.32);
// 비탈 부지의 단 (Terrain.set_terrace) — 표시·아이템 재질에만 넣는다. 청크는 단을 모른다 (부지 바닥은 City.Terrace가 그린다)
uniform int terrace_count = 0;
uniform vec4 terrace_rects[MAX_TERRACES];
uniform float terrace_heights[MAX_TERRACES];
// 산 (Terrain.MOUNDS — 수식은 Terrain._mound와 같다): 부지 (x0, y0, x1, y1), (평지 반폭 x, y, 높이, 0)
uniform int mound_count = 0;
uniform vec4 mound_rects[MAX_MOUNDS];
uniform vec4 mound_shapes[MAX_MOUNDS];
varying vec2 ground;

float mound(vec2 p) {
	float h = 0.0;
	for (int i = 0; i < mound_count; i++) {
		vec4 r = mound_rects[i];
		vec4 s = mound_shapes[i];
		vec2 c = (r.xy + r.zw) * 0.5;
		vec2 half_size = (r.zw - r.xy) * 0.5;
		vec2 q = max(abs(p - c) - s.xy, vec2(0.0)) / max(half_size - s.xy, vec2(1.0));
		h += s.z * (1.0 - smoothstep(0.0, 1.0, length(q)));
	}
	return h;
}

float h_at(ivec2 k) {
	ivec2 s = textureSize(heights, 0);
	return texelFetch(heights, clamp(k, ivec2(0), s - ivec2(1)), 0).r;
}

void vertex() {
	ground = VERTEX;
	vec2 g = (VERTEX - origin) / cell;
	vec2 f = floor(g);
	ivec2 k = ivec2(f);
	vec2 t = g - f;
	float h = mix(mix(h_at(k), h_at(k + ivec2(1, 0)), t.x), mix(h_at(k + ivec2(0, 1)), h_at(k + ivec2(1, 1)), t.x), t.y);
	h += mound(VERTEX);
	for (int i = 0; i < terrace_count; i++) {
		vec4 r = terrace_rects[i];
		if (VERTEX.x >= r.x && VERTEX.y >= r.y && VERTEX.x < r.z && VERTEX.y < r.w) {
			h = terrace_heights[i];
			break;
		}
	}
	VERTEX += vec2(-1.2820513, -1.2820513) * h * strength;
}

void fragment() {
	vec4 c = COLOR;   // 텍스처 색이 이미 곱해져 있다
	if (shading > 0.0) {
		vec2 g = (ground - origin) / cell;
		vec2 f = floor(g);
		ivec2 k = ivec2(f);
		vec2 t = g - f;
		float h00 = h_at(k);
		float h10 = h_at(k + ivec2(1, 0));
		float h01 = h_at(k + ivec2(0, 1));
		float h11 = h_at(k + ivec2(1, 1));
		vec2 grad = vec2(mix(h10 - h00, h11 - h01, t.y), mix(h01 - h00, h11 - h10, t.x)) / cell;
		if (mound_count > 0) {
			grad += vec2(mound(ground + vec2(2.0, 0.0)) - mound(ground - vec2(2.0, 0.0)),
				mound(ground + vec2(0.0, 2.0)) - mound(ground - vec2(0.0, 2.0))) * 0.25 * MOUND_SHADING;
		}
		c.rgb *= clamp(1.0 + dot(grad, light) * shading * strength, 0.62, 1.3);
	}
	COLOR = c;
}
"""

## false면 모든 높이가 0 (도구·테스트에서 끈다)
static var enabled := true
static var _h := PackedFloat32Array()       ## 표본 높이 (화면 px)
static var _materials: Array[ShaderMaterial] = []   ## [표시용, 그늘 있는 바닥용]
static var _over_heights := {}              ## 고가 번호 → 고른 높이
static var _band := Vector2.INF             ## 한강 띠의 y 범위 (둑 도로 포함)
static var _terraces := {}                  ## 블록 → [[부지, 단 높이], ...]
static var _mounds: Array = []              ## [부지, 평지 반폭, 높이] (MOUNDS를 월드 좌표로)


static func _ensure() -> void:
	if not _h.is_empty():
		return
	var n := DATA.size.x * DATA.size.y
	_h.resize(n)
	for k in n:
		var p := _point(k)
		_h[k] = pow(DATA.values[k], DATA.contrast) * DATA.max_height * smoothstep(0.0, DATA.shore_fall, _shore_distance(p)) * _hill_mask(p)
	_flatten_overpasses()
	_mounds.clear()
	for m: Array in MOUNDS:
		_mounds.append([City.block_area(m[0]).grow(-City.SIDEWALK), m[1], m[2]])


## 산이 더하는 높이 (셰이더의 mound와 같은 수식)
static func _mound(p: Vector2) -> float:
	var h := 0.0
	for m: Array in _mounds:
		var r: Rect2 = m[0]
		if not r.has_point(p):
			continue
		var flat: Vector2 = m[1]
		var half := r.size * 0.5
		var d := ((p - r.get_center()).abs() - flat).max(Vector2.ZERO) / (half - flat).max(Vector2.ONE)
		h += m[2] * (1.0 - smoothstep(0.0, 1.0, d.length()))
	return h


## 산 부지들 (남산 — 그리는 쪽에서 길·나무를 놓을 때)
static func mound_rects() -> Array[Rect2]:
	_ensure()
	var out: Array[Rect2] = []
	for m: Array in _mounds:
		out.append(m[0])
	return out


## 산 둘레면 1, 산 반지름 밖은 0 (가운데 35%는 그림 높이 그대로, 그 밖은 부드럽게 줄인다)
static func _hill_mask(p: Vector2) -> float:
	var m := 0.0
	for h in DATA.hills:
		var c := Vector2(h.x, h.y) * City.PITCH + Vector2.ONE * City.ROAD * 0.5
		var r := h.z * City.PITCH
		m = maxf(m, smoothstep(r, r * 0.35, p.distance_to(c)))
	return m


## 건물 대신 숲이 서는 블록인가
static func is_forest(b: Vector2i) -> bool:
	return DATA.forests.has(b)


static func _point(k: int) -> Vector2:
	return DATA.origin + Vector2(k % DATA.size.x, k / DATA.size.x) * DATA.cell


## 한강 띠(북쪽 둑 도로 ~ 남쪽 둑 도로)까지 거리 (월드 px, 띠 안은 0)
static func _shore_distance(p: Vector2) -> float:
	if _band == Vector2.INF:
		_band = Vector2(INF, -INF)
		for j in range(CityMap.MIN.y, CityMap.MAX.y + 1):
			for i in range(CityMap.MIN.x, CityMap.MAX.x + 1):
				if CityMap.is_water(Vector2i(i, j)):
					var r := City.block_rect(i, j)
					_band = Vector2(minf(_band.x, r.position.y - City.ROAD), maxf(_band.y, r.end.y + City.ROAD))
	return maxf(maxf(_band.x - p.y, p.y - _band.y), 0.0)


## 고가차도(경사로 입구~출구) 둘레를 그 안 평균 높이로 고른다 — 상판·옹벽은 평평한 땅을 전제로 그린다
static func _flatten_overpasses() -> void:
	for oi in CityMap.OVERPASSES.size():
		var zone := _over_zone(oi)
		var sum := 0.0
		var count := 0
		for k in _h.size():
			if zone.has_point(_point(k)):
				sum += _h[k]
				count += 1
		var flat := sum / maxi(count, 1)
		_over_heights[oi] = flat
		for k in _h.size():
			var d := _rect_distance(zone, _point(k))
			if d < DATA.flat_fall:
				_h[k] = lerpf(flat, _h[k], smoothstep(0.0, DATA.flat_fall, d))


static func _over_zone(oi: int) -> Rect2:
	var o := CityMap.OVERPASSES[oi]
	var ext := CityMap.over_extent(o)
	var rc := City.road_center(o.y)
	var p := CityMap.over_point(o, ext.x, rc - City.ROAD * 0.5)
	var q := CityMap.over_point(o, ext.y, rc + City.ROAD * 0.5)
	return Rect2(p, q - p).abs().grow(City.SIDEWALK)


static func _rect_distance(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dy := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	return Vector2(dx, dy).length()


static func _sample(i: int, j: int) -> float:
	i = clampi(i, 0, DATA.size.x - 1)
	j = clampi(j, 0, DATA.size.y - 1)
	return _h[j * DATA.size.x + i]


## 비탈 부지 r을 높이 h의 평평한 단으로 둔다 (그 안의 사람·차·바닥 것은 이 높이에 선다)
static func set_terrace(r: Rect2, h: float) -> void:
	var b := CityMap.block_at(r.get_center())
	if not _terraces.has(b):
		_terraces[b] = []
	_terraces[b].append([r, h])
	_sync_terraces()


static func clear_terraces() -> void:
	_terraces.clear()
	_sync_terraces()


## 그 자리 땅 높이 (2.5D 화면 px, 단 위면 단 높이). 꺼져 있거나 위에서 보기면 0
## 단 가장자리 STEP_RAMP 안은 땅에서 단 높이로 부드럽게 오른다 — 부지 경계를 넘는 순간 사람·차가 툭 올라서 보이지 않게
static func height(pos: Vector2) -> float:
	if not enabled or not IsoView.enabled:
		return 0.0
	if not _terraces.is_empty():
		var list: Variant = _terraces.get(CityMap.block_at(pos))
		if list != null:
			for t: Array in list:
				var r: Rect2 = t[0]
				if r.has_point(pos):
					var edge := minf(minf(pos.x - r.position.x, r.end.x - pos.x), minf(pos.y - r.position.y, r.end.y - pos.y))
					if edge >= STEP_RAMP:
						return t[1]
					return lerpf(slope(pos), t[1], smoothstep(0.0, STEP_RAMP, edge))
	return slope(pos)


## 지금 놓인 단 사각형들 (잠긴 구역 그늘처럼 단을 비워 그릴 때)
static func terraces_in(b: Vector2i) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for t: Array in _terraces.get(b, []):
		out.append(t[0])
	return out


## 단을 빼고 본 땅 높이 (지형 그대로 — 셰이더가 바닥을 올리는 높이)
static func slope(pos: Vector2) -> float:
	if not enabled or not IsoView.enabled:
		return 0.0
	_ensure()
	var g := (pos - DATA.origin) / DATA.cell
	var i := floori(g.x)
	var j := floori(g.y)
	var tx := g.x - i
	var ty := g.y - j
	return lerpf(lerpf(_sample(i, j), _sample(i + 1, j), tx), lerpf(_sample(i, j + 1), _sample(i + 1, j + 1), tx), ty) + _mound(pos)


## 사각형 안 가장 높은 땅 — 단은 빼고 지형 그대로
static func max_height(r: Rect2) -> float:
	var h := -INF
	for p in _corners(r):
		h = maxf(h, slope(p))
	return h


## 사각형 안 가장 낮은 땅 — 단은 빼고 지형 그대로
static func min_height(r: Rect2) -> float:
	var h := INF
	for p in _corners(r):
		h = minf(h, slope(p))
	return h


## 사각형의 네 모서리와 그 안·둘레가 격자 선과 만나는 점 — 쌍선형이라 이 점들 밖은 더 높거나 낮지 않다
static func _corners(r: Rect2) -> PackedVector2Array:
	var out := PackedVector2Array([r.position, r.end, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y)])
	if not enabled or not IsoView.enabled:
		return out
	var xs := _cuts(r.position.x, r.end.x, DATA.origin.x, 0)
	var ys := _cuts(r.position.y, r.end.y, DATA.origin.y, 1)
	for y in ys:
		for x in xs:
			out.append(Vector2(x, y))
	return out


## 고가 oi 둘레를 고른 높이
static func overpass_height(oi: int) -> float:
	if not enabled or not IsoView.enabled:
		return 0.0
	_ensure()
	return _over_heights.get(oi, 0.0)


## 바닥 노드에 거는 재질: 꼭짓점을 땅 높이만큼 올린다. shaded면 비탈 그늘도 (도로·인도·마당 — 표시·아이템은 끈다)
static func material(shaded := false) -> ShaderMaterial:
	if _materials.is_empty():
		_ensure()
		var img := Image.create_from_data(DATA.size.x, DATA.size.y, false, Image.FORMAT_RF, _h.to_byte_array())
		var tex := ImageTexture.create_from_image(img)
		var shader := Shader.new()
		shader.code = SHADER.replace("MAX_TERRACES", str(MAX_TERRACES)).replace("MAX_MOUNDS", str(MAX_MOUNDS)).replace("MOUND_SHADING", str(MOUND_SHADING))
		for k in 2:
			var m := ShaderMaterial.new()
			m.shader = shader
			m.set_shader_parameter(&"heights", tex)
			m.set_shader_parameter(&"origin", DATA.origin)
			m.set_shader_parameter(&"cell", DATA.cell)
			m.set_shader_parameter(&"shading", DATA.shading if k == 1 else 0.0)
			var rects := PackedVector4Array()
			var shapes := PackedVector4Array()
			rects.resize(MAX_MOUNDS)
			shapes.resize(MAX_MOUNDS)
			for i in mini(_mounds.size(), MAX_MOUNDS):
				var r: Rect2 = _mounds[i][0]
				var flat: Vector2 = _mounds[i][1]
				rects[i] = Vector4(r.position.x, r.position.y, r.end.x, r.end.y)
				shapes[i] = Vector4(flat.x, flat.y, _mounds[i][2], 0.0)
			m.set_shader_parameter(&"mound_count", mini(_mounds.size(), MAX_MOUNDS))
			m.set_shader_parameter(&"mound_rects", rects)
			m.set_shader_parameter(&"mound_shapes", shapes)
			_materials.append(m)
		_sync_terraces()
	for m in _materials:
		m.set_shader_parameter(&"strength", 1.0 if enabled and IsoView.enabled else 0.0)
	return _materials[1 if shaded else 0]


## 단 목록을 표시용 재질에 넣는다
static func _sync_terraces() -> void:
	if _materials.is_empty():
		return
	var rects := PackedVector4Array()
	var heights := PackedFloat32Array()
	rects.resize(MAX_TERRACES)
	heights.resize(MAX_TERRACES)
	var n := 0
	for list: Array in _terraces.values():
		for t: Array in list:
			if n >= MAX_TERRACES:
				push_warning("Terrain: 단이 MAX_TERRACES보다 많다")
				break
			var r: Rect2 = t[0]
			rects[n] = Vector4(r.position.x, r.position.y, r.end.x, r.end.y)
			heights[n] = t[1]
			n += 1
	var m := _materials[0]
	m.set_shader_parameter(&"terrace_count", n)
	m.set_shader_parameter(&"terrace_rects", rects)
	m.set_shader_parameter(&"terrace_heights", heights)


## 2.5D ↔ 위에서 보기를 바꾼 뒤 부른다
static func refresh() -> void:
	if not _materials.is_empty():
		material()


# ── 격자 선마다 잘라 그리기 ────────────────────────────────
# 셰이더는 꼭짓점에서만 높이를 재므로, 격자 칸보다 큰 도형은 칸마다 잘라야 땅(Terrain.height)과 맞는다.

## 구간 [a, b]를 격자 선에서 자른 좌표들 (양끝 포함). axis(0 x · 1 y)를 주면 산 부지 안은 MOUND_CELL마다 더 자른다
static func _cuts(a: float, b: float, o: float, axis := -1) -> PackedFloat32Array:
	var out := PackedFloat32Array([a])
	var c := DATA.cell
	var x := floorf((a - o) / c) * c + o + c
	while x < b - 0.01:
		out.append(x)
		x += c
	out.append(b)
	if axis < 0 or _mounds.is_empty() or not enabled or not IsoView.enabled:
		return out
	var fine := PackedFloat32Array()
	for m: Array in _mounds:
		var r: Rect2 = m[0]
		var lo := maxf(a, r.position[axis])
		var hi := minf(b, r.end[axis])
		var v := r.position[axis] + ceilf((lo - r.position[axis]) / MOUND_CELL) * MOUND_CELL
		while v < hi:
			if v > a + 0.5 and v < b - 0.5:
				fine.append(v)
			v += MOUND_CELL
	return out if fine.is_empty() else _merge(out, fine)


## r을 칠하되 holes(단 부지)는 비운다 — 격자 선과 구멍 경계에서 잘라, 단 경계를 걸친 꼭짓점이 없게 한다
static func rect_except(ci: CanvasItem, r: Rect2, color: Color, holes: Array[Rect2]) -> void:
	var hx := PackedFloat32Array()
	var hy := PackedFloat32Array()
	for h in holes:
		# 셰이더는 단의 왼쪽·위 변을 단 안으로 친다 — 그 변에서 자르면 바깥 칸 꼭짓점까지 단 높이로 들려, 조금 바깥에서 자른다
		for v in [h.position.x - 0.02, h.end.x]:
			if v > r.position.x and v < r.end.x:
				hx.append(v)
		for v in [h.position.y - 0.02, h.end.y]:
			if v > r.position.y and v < r.end.y:
				hy.append(v)
	var xs := _merge(_cuts(r.position.x, r.end.x, DATA.origin.x, 0), hx)
	var ys := _merge(_cuts(r.position.y, r.end.y, DATA.origin.y, 1), hy)
	for j in ys.size() - 1:
		for i in xs.size() - 1:
			var cell := Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j])
			var c := cell.get_center()
			var inside := false
			for h in holes:
				if h.has_point(c):
					inside = true
					break
			if not inside:
				ci.draw_rect(cell, color)


static func rect(ci: CanvasItem, r: Rect2, color: Color, filled := true, width := -1.0) -> void:
	if not filled:
		var p := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for k in 4:
			line(ci, p[k], p[(k + 1) % 4], color, width)
		return
	var xs := _cuts(r.position.x, r.end.x, DATA.origin.x, 0)
	var ys := _cuts(r.position.y, r.end.y, DATA.origin.y, 1)
	for j in ys.size() - 1:
		for i in xs.size() - 1:
			ci.draw_rect(Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j]), color)


## 되풀이 그림을 r에 깐다 (draw_texture_rect의 tile처럼 r 왼쪽 위부터 이어진다). 바닥 노드는 텍스처 되풀이가 꺼져 있어
## 격자 선과 그림 한 장의 경계 둘 다에서 잘라, 조각마다 그림 안쪽 영역만 쓴다
static func texture_rect(ci: CanvasItem, tex: Texture2D, r: Rect2) -> void:
	var size := tex.get_size()
	var xs := _merge(_cuts(r.position.x, r.end.x, DATA.origin.x, 0), _tile_cuts(r.position.x, r.end.x, size.x))
	var ys := _merge(_cuts(r.position.y, r.end.y, DATA.origin.y, 1), _tile_cuts(r.position.y, r.end.y, size.y))
	for j in ys.size() - 1:
		for i in xs.size() - 1:
			var part := Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j])
			var off := part.position - r.position
			var src := Rect2(Vector2(fposmod(off.x, size.x), fposmod(off.y, size.y)), part.size)
			ci.draw_texture_rect_region(tex, part, src)


static func _tile_cuts(a: float, b: float, step: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var x := a + step
	while x < b - 0.01:
		out.append(x)
		x += step
	return out


static func _merge(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a + b
	out.sort()
	var clean := PackedFloat32Array()
	for v in out:
		if clean.is_empty() or v - clean[clean.size() - 1] > 0.5:
			clean.append(v)
	return clean


## 축에 나란한 선은 격자 선마다, 비스듬한 선은 칸 길이마다 잘라 그린다
static func line(ci: CanvasItem, a: Vector2, b: Vector2, color: Color, width := -1.0) -> void:
	var step := DATA.cell
	for m: Array in _mounds:
		if (m[0] as Rect2).intersects(Rect2(a, Vector2.ZERO).expand(b).grow(1.0)):
			step = MOUND_CELL
	var n := maxi(ceili(a.distance_to(b) / step), 1)
	if is_equal_approx(a.y, b.y) or is_equal_approx(a.x, b.x):
		var horizontal := is_equal_approx(a.y, b.y)
		var lo := minf(a.x, b.x) if horizontal else minf(a.y, b.y)
		var hi := maxf(a.x, b.x) if horizontal else maxf(a.y, b.y)
		var cuts := _cuts(lo, hi, DATA.origin.x if horizontal else DATA.origin.y, 0 if horizontal else 1)
		var pts := PackedVector2Array()
		for v in cuts:
			pts.append(Vector2(v, a.y) if horizontal else Vector2(a.x, v))
		ci.draw_polyline(pts, color, width)
		return
	var pts2 := PackedVector2Array()
	for k in n + 1:
		pts2.append(a.lerp(b, float(k) / n))
	ci.draw_polyline(pts2, color, width)


## 단(바닥 높이 pad)의 앞 면 a→b 밑 축대: 땅에서 pad까지. 단 노드 안(pad만큼 올린 좌표)에서 부른다. n은 면 바깥 법선
static func foundation_face(ci: CanvasItem, a: Vector2, b: Vector2, pad: float, n: Vector2, overlay := Color(0, 0, 0, 0)) -> void:
	var horizontal := is_equal_approx(a.y, b.y)
	var xs := _cuts(a.x, b.x, DATA.origin.x) if horizontal else _cuts(a.y, b.y, DATA.origin.y)
	var top := PackedVector2Array()
	var depth := PackedFloat32Array()
	var deep := 0.0
	for v in xs:
		var p := Vector2(v, a.y) if horizontal else Vector2(a.x, v)
		var d := pad - slope(p)
		deep = maxf(deep, d)
		top.append(p)
		depth.append(maxf(d, 0.0) + 1.0)   # 1px 더 묻어 땅과 틈이 없게
	if deep < 1.0:
		return
	var shade := IsoView.face_shade(n)
	var face := FOUNDATION.darkened(shade)
	# 칸마다 사각형 (땅에 닿는 깊이가 칸 끝마다 다르다 — 평지 쪽은 납작해도 된다)
	for k in top.size() - 1:
		var q0 := top[k]
		var q1 := top[k + 1]
		ci.draw_primitive(PackedVector2Array([q0, q1, q1 + IsoView.lift(-depth[k + 1]), q0 + IsoView.lift(-depth[k])]),
			PackedColorArray([face]), PackedVector2Array())
	# 돌 쌓은 줄눈: 가로줄 STONE_ROW마다, 세로 이음은 STONE_LEN마다 줄마다 반 칸씩 엇갈린다 (땅에 묻힌 데까지만)
	var joint := FOUNDATION_LINE.darkened(shade)
	var lines := PackedVector2Array()
	for k in top.size() - 1:
		var q0 := top[k]
		var q1 := top[k + 1]
		var row := STONE_ROW
		while row < maxf(depth[k], depth[k + 1]) - 1.0:
			var t0 := 0.0 if depth[k] > row else (row - depth[k]) / (depth[k + 1] - depth[k])
			var t1 := 1.0 if depth[k + 1] > row else (row - depth[k]) / (depth[k + 1] - depth[k])
			lines.append(q0.lerp(q1, t0) + IsoView.lift(-row))
			lines.append(q0.lerp(q1, t1) + IsoView.lift(-row))
			row += STONE_ROW
	var along := (b - a).normalized()
	var length := a.distance_to(b)
	var course := 0
	var row2 := 0.0
	while row2 < deep:
		var s0 := STONE_LEN * 0.5 * (course % 2)
		while s0 < length:
			var p := a + along * s0
			var d := pad - slope(p)
			if d > row2 + 2.0:
				lines.append(p + IsoView.lift(-row2))
				lines.append(p + IsoView.lift(-minf(row2 + STONE_ROW, d)))
			s0 += STONE_LEN
		row2 += STONE_ROW
		course += 1
	if not lines.is_empty():
		ci.draw_multiline(lines, joint, 1.0)
	ci.draw_polyline(top, FOUNDATION_CAP.darkened(shade * 0.5), 2.0)   # 단 끝 갓돌
	if overlay.a > 0.0:   # 잠긴 구역 그늘을 축대 면에도
		var tint := PackedColorArray([overlay])
		for k in top.size() - 1:
			var q0 := top[k] + IsoView.lift(1.0)
			var q1 := top[k + 1] + IsoView.lift(1.0)
			ci.draw_primitive(PackedVector2Array([q0, q1, top[k + 1] + IsoView.lift(-depth[k + 1]), top[k] + IsoView.lift(-depth[k])]),
				tint, PackedVector2Array())
