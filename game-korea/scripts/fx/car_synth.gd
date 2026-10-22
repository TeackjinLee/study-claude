class_name CarSynth
extends RefCounted
## 차 소리 합성기 (소리 파일 없이 코드로 만든다). 노드 없는 계산부라 헤드리스 테스트에서 그대로 쓴다.
##
## 계속 나는 소리는 끊김 없이 되풀이되는 한 토막(loop)으로 만든다 — 게임은 그것을 되풀이해 틀면서
## 엔진은 회전수만큼 빠르기(pitch_scale = rpm / base_rpm)를, 사이렌·타이어는 크기만 바꾼다.
## - 엔진: 실린더가 터질 때마다 울리는 배음 묶음(부르릉) + 터질 때마다 조금씩 다른 세기(거친 맛) + 걸러 낸 바람 소리(흡기·배기).
##   토막 안에 터지는 횟수가 딱 떨어지게 길이를 맞추고, 바람 소리는 토막을 돌아 한 번 더 걸러 이음매가 없다.
##   힘을 쓸 때(on)와 뗄 때(off) 두 토막 — 게임이 가속 페달만큼 섞는다.
## - 사이렌: 오르내리는 울음(wail)과 빠른 울음(yelp). 한 토막 안에서 높이가 한 바퀴 돌고 위상이 딱 떨어진다.
## - 타이어 끌림: 높게 걸러 낸 바람 소리 + 떨리는 끽 소리.
## 한 번 울리는 소리(SHOTS: 충돌·부딪힘·경적·물에 빠짐)는 render로 만들어 Sfx가 튼다.

const MIX_RATE := 22050.0
const VARIANTS := 3

## 엔진 종류. cyl 실린더 수(한 바퀴에 cyl/2번 터진다), base_rpm 토막을 만든 회전수, harm 배음 크기(터지는 높이의 1·2·3…배),
## sub 크랭크 한 바퀴 낮은 울림, rough 터질 때마다 세기 흔들림, noise 바람 소리 크기, noise_lp 거르는 정도(작을수록 낮다),
## idle·red 공회전·최고 회전수, gears 기어 수
const ENGINES := {
	&"car": {"cyl": 4, "base_rpm": 2000.0, "harm": [1.0, 0.6, 0.35, 0.2, 0.12, 0.06], "sub": 0.25, "rough": 0.18,
		"noise": 0.35, "noise_lp": 0.06, "idle": 850.0, "red": 6200.0, "gears": 5},
	&"truck": {"cyl": 6, "base_rpm": 1300.0, "harm": [1.0, 0.8, 0.55, 0.4, 0.25, 0.15], "sub": 0.45, "rough": 0.3,
		"noise": 0.6, "noise_lp": 0.1, "idle": 600.0, "red": 2800.0, "gears": 6},
	&"bike": {"cyl": 2, "base_rpm": 3500.0, "harm": [1.0, 0.7, 0.5, 0.35, 0.2, 0.1], "sub": 0.15, "rough": 0.25,
		"noise": 0.3, "noise_lp": 0.12, "idle": 1300.0, "red": 10500.0, "gears": 6},
	&"tracked": {"cyl": 8, "base_rpm": 1200.0, "harm": [1.0, 0.7, 0.5, 0.45, 0.3, 0.2], "sub": 0.6, "rough": 0.35,
		"noise": 0.7, "noise_lp": 0.05, "idle": 650.0, "red": 2400.0, "gears": 4},
}
const ENGINE_LOOP := 1.0        ## 엔진 토막 길이 (초)

## 사이렌: lo~hi Hz를 period초에 한 번 오르내린다 (rise는 한 바퀴 중 오르는 몫)
const SIRENS := {
	&"wail": {"lo": 650.0, "hi": 1450.0, "period": 4.0, "rise": 0.45},
	&"yelp": {"lo": 700.0, "hi": 1500.0, "period": 0.36, "rise": 0.5},
}

## 한 번 울리는 소리. len 길이(초), peak 최대 크기
const SHOTS := {
	&"crash": {"len": 0.9, "peak": 0.9},     ## 세게 부딪힘: 쿵 + 찌그러지는 쇳소리 + 유리 부스러기
	&"bump": {"len": 0.35, "peak": 0.55},    ## 살짝 부딪힘: 둔한 쿵
	&"horn": {"len": 0.5, "peak": 0.6},      ## 경적 "빵" (두 음)
}


## 엔진 토막 (모노, -1..1, ENGINE_LOOP초 — 되풀이해도 이음매가 없다). on이면 힘을 쓰는 소리(배음·바람이 세다)
static func engine_loop(kind: StringName, on: bool) -> PackedFloat32Array:
	var e: Dictionary = ENGINES[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(kind)) + (1 if on else 2)
	var n := int(ENGINE_LOOP * MIX_RATE)
	var fire_hz: float = float(e.base_rpm) / 60.0 * float(e.cyl) * 0.5
	var fires := maxi(roundi(fire_hz * ENGINE_LOOP), 1)    # 토막 안에 터지는 횟수 (정수 — 이음매)
	var amps := PackedFloat32Array()
	for k in fires:
		amps.append(1.0 + rng.randf_range(-1.0, 1.0) * float(e.rough))
	var noise := _loop_noise(rng, n, float(e.noise_lp))
	var harm: Array = e.harm
	var out := PackedFloat32Array()
	out.resize(n)
	var cranks := maxi(roundi(fires * 2.0 / float(e.cyl)), 1)   # 크랭크 바퀴 수 (낮은 울림)
	for i in n:
		var cyc := float(i) * fires / n          # 지금까지 터진 횟수 (실수)
		var k := int(cyc) % fires
		var ph := cyc - floorf(cyc)
		# 터질 때마다 부풀었다 가라앉는다 — 주기마다 부드럽게 이어지는 곡선이라 딱딱 튀지 않는다. 세기도 다음 번으로 이어 간다
		var env := pow(0.5 + 0.5 * cos(TAU * (ph - 0.15)), 4.0 if on else 2.0)
		var amp := lerpf(amps[k], amps[(k + 1) % fires], smoothstep(0.0, 1.0, ph))
		var tone := 0.0
		for h in harm.size():
			var a: float = harm[h] * (1.0 if on or h < 2 else 0.4)
			tone += sin(TAU * (h + 1) * cyc) * a
		var sub := sin(TAU * float(i) * cranks / n) * float(e.sub)
		var s := tone * (0.55 + 0.45 * env) * amp * 0.35 + sub * 0.4 \
			+ noise[i] * float(e.noise) * (1.6 if on else 0.6) * (0.4 + 0.6 * env)
		out[i] = s
	return _normalize(out, 0.7 if on else 0.5)


## 사이렌 토막: 한 바퀴(period초)를 위상이 딱 떨어지게
static func siren_loop(kind: StringName) -> PackedFloat32Array:
	var c: Dictionary = SIRENS[kind]
	var period: float = c.period
	if period < 1.0:
		period *= ceilf(1.0 / period)        # 짧은 울음은 여러 번 담아 토막을 1초 넘게
	var n := int(period * MIX_RATE)
	var freqs := PackedFloat32Array()
	freqs.resize(n)
	var total := 0.0
	for i in n:
		var t := fmod(float(i) / MIX_RATE / float(c.period), 1.0)
		var rise: float = c.rise
		var k := t / rise if t < rise else 1.0 - (t - rise) / (1.0 - rise)
		freqs[i] = lerpf(float(c.lo), float(c.hi), smoothstep(0.0, 1.0, k))
		total += freqs[i] / MIX_RATE
	var scale := roundf(total) / total             # 한 토막의 위상이 정수 바퀴가 되게 높이를 살짝 맞춘다
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		ph += freqs[i] * scale / MIX_RATE
		var p := TAU * ph
		# 네모파에 가까운 소리 (홀수 배음) — 작은 스피커에서도 잘 들린다
		out[i] = sin(p) + sin(3.0 * p) * 0.3 + sin(5.0 * p) * 0.12
	return _normalize(out, 0.6)


## 타이어 끌림 토막 (1초)
static func skid_loop() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var n := int(MIX_RATE)
	var noise := _loop_noise(rng, n, 0.5)
	var low := _loop_noise(rng, n, 0.15)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var hiss := noise[i] - low[i]          # 높게 걸러 낸 바람 소리 (쉬익)
		var squeal := sin(TAU * (950.0 * t + 6.0 * sin(TAU * 7.0 * t) / TAU)) * (0.6 + 0.4 * sin(TAU * 3.0 * t))
		out[i] = hiss * 0.8 + squeal * 0.35
	return _normalize(out, 0.55)


## 한 번 울리는 소리 kind의 variant번째 (모노, -1..1). 같은 값이면 늘 같은 소리다
static func render(kind: StringName, variant := 0) -> PackedFloat32Array:
	var c: Dictionary = SHOTS[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(kind)) + variant * 7919
	var n := int(float(c.len) * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	match kind:
		&"crash", &"bump":
			_crash(out, rng, kind == &"crash")
		&"horn":
			_horn(out, rng)
	var fade := mini(int(0.02 * MIX_RATE), n)
	for i in fade:
		out[n - 1 - i] *= float(i) / fade
	return _normalize(out, float(c.peak))


## 쿵(낮게 걸러 낸 바람 + 떨어지는 사인) + 쇳소리(어긋난 배음 몇 개가 울리다 사그라진다) + 유리 부스러기(드문드문 높은 딸깍)
static func _crash(out: PackedFloat32Array, rng: RandomNumberGenerator, heavy: bool) -> void:
	var metal: Array = []
	for m in (5 if heavy else 2):
		metal.append([rng.randf_range(260.0, 1900.0), rng.randf_range(0.3, 1.0), rng.randf_range(0.06, 0.25 if heavy else 0.08)])
	var lp := 0.0
	var lp2 := 0.0
	var ph := 0.0
	var glass := 0.0
	var glass_lp := 0.0
	for i in out.size():
		var t := float(i) / MIX_RATE
		var white := rng.randf() * 2.0 - 1.0
		lp += (white - lp) * 0.08
		lp2 += (lp - lp2) * 0.08
		ph += lerpf(45.0, 120.0, exp(-t / 0.03)) / MIX_RATE
		var thud := (sin(TAU * ph) * 1.2 + lp2 * 6.0) * exp(-t / (0.09 if heavy else 0.05))
		var ring := 0.0
		for m: Array in metal:
			ring += sin(TAU * float(m[0]) * t + float(m[1]) * 3.0) * float(m[1]) * exp(-t / float(m[2]))
		var crunch := lp * 3.0 * exp(-t / (0.12 if heavy else 0.03))
		var s := thud + ring * (0.35 if heavy else 0.15) + crunch
		if heavy:
			if rng.randf() < 0.004 * exp(-t / 0.25):
				glass = rng.randf_range(0.4, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0)
			glass *= 0.8
			glass_lp += (glass - glass_lp) * 0.5
			s += (glass - glass_lp) * 0.9
		out[i] = s


## 두 음(약 420·525Hz) 네모파에 가까운 소리, 짧게 올라 붙었다가 끊긴다
static func _horn(out: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var a := 420.0 * rng.randf_range(0.97, 1.03)
	var b := a * 1.25
	var lp := 0.0
	for i in out.size():
		var t := float(i) / MIX_RATE
		var env := minf(t / 0.012, 1.0) * clampf((float(out.size()) / MIX_RATE - t) / 0.06, 0.0, 1.0)
		var s := 0.0
		for f: float in [a, b]:
			var p := TAU * f * t
			s += sin(p) + sin(3.0 * p) * 0.35 + sin(5.0 * p) * 0.18
		lp += (s - lp) * 0.35
		out[i] = lp * env


## 되풀이해도 이음매가 없는 걸러 낸 바람 소리: 토막을 두 바퀴 돌며 걸러 둘째 바퀴를 쓴다
static func _loop_noise(rng: RandomNumberGenerator, n: int, k: float) -> PackedFloat32Array:
	var white := PackedFloat32Array()
	white.resize(n)
	for i in n:
		white[i] = rng.randf() * 2.0 - 1.0
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for pass_i in 2:
		for i in n:
			lp += (white[i] - lp) * k
			lp2 += (lp - lp2) * k
			if pass_i == 1:
				out[i] = lp2 / sqrt(k)     # 낮게 거를수록 작아지는 것을 되돌린다
	return out


## 부드럽게 눌러 최대 크기를 peak에 맞춘다 (GunSynth와 같은 방식)
static func _normalize(out: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var top := 0.0
	for v in out:
		top = maxf(top, absf(v))
	if top <= 0.0:
		return out
	var g := 2.0 / top
	for i in out.size():
		var v := out[i] * g
		out[i] = v / (1.0 + absf(v) * 0.5) * peak
	return out


## 차종이 내는 엔진 소리 종류 ("" 이면 엔진 소리 없음 — 자전거·헬기)
static func engine_kind(t: VehicleType) -> StringName:
	if t.flies or t.category == &"bicycle":
		return &""
	if t.category == &"bike":
		return &"bike"
	if t.tracked:
		return &"tracked"
	if t.category in Vehicle.TRUCKS or t.category in [&"bus", &"van"] or t.mass >= 3.0:
		return &"truck"
	return &"car"


## 빠르기(최고 속도에 대한 몫)로 회전수: 기어마다 낮은 회전수에서 최고 회전수까지 오르고 다음 기어로 넘어가면 떨어진다
static func gear_rpm(kind: StringName, speed_frac: float) -> float:
	var e: Dictionary = ENGINES[kind]
	var idle: float = e.idle
	var red: float = e.red
	var gears: int = e.gears
	var f := clampf(absf(speed_frac), 0.0, 1.0)
	if f < 0.02:
		return idle
	var x := f * gears
	var g := mini(int(x), gears - 1)
	var within := x - g
	var low := lerpf(idle, red, 0.45) if g > 0 else idle
	return lerpf(low, red * 0.92, within)
