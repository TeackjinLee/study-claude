class_name VoiceSynth
extends RefCounted
## 사람 소리 합성기 (파일 없이 코드로 만든다). 노드 없는 계산부 — Sfx가 GunSynth·CarSynth와 함께 굽는다.
## - 비명(scream_m·scream_f): 성대 펄스(톱니파 + 떨림)를 "아" 모음 포먼트 세 개로 걸러 낸다. 높이가 확 올랐다 내려온다.
## - 맞은 소리(grunt_m·grunt_f): 짧고 낮게 "윽" — 모음 "으" 포먼트, 빠르게 떨어진다.
## - 맞는 소리(hit): 주먹·방망이가 몸에 닿는 둔탁한 퍽 (낮게 거른 잡음 + 낮은 사인)
## - 쓰러짐(fall): 몸이 땅에 털썩 + 옷 스치는 소리
## - 발소리(step): 아주 짧은 딱 + 걸러 낸 잡음 (주인공 걸음 박자마다, 작게)

const MIX_RATE := GunSynth.MIX_RATE
const VARIANTS := 3

## len 길이(초), f0 처음 높이, f_peak 꼭대기, f_end 끝 높이(Hz), vowel 포먼트 [F1, F2, F3], peak 정규화 크기
const SHOTS := {
	&"scream_m": {"len": 0.95, "f0": 190.0, "f_peak": 330.0, "f_end": 230.0, "vowel": [800.0, 1250.0, 2600.0], "peak": 0.6},
	&"scream_f": {"len": 0.95, "f0": 330.0, "f_peak": 620.0, "f_end": 430.0, "vowel": [950.0, 1450.0, 2900.0], "peak": 0.6},
	&"grunt_m": {"len": 0.22, "f0": 150.0, "f_peak": 165.0, "f_end": 105.0, "vowel": [330.0, 1100.0, 2300.0], "peak": 0.5},
	&"grunt_f": {"len": 0.22, "f0": 270.0, "f_peak": 290.0, "f_end": 200.0, "vowel": [380.0, 1300.0, 2700.0], "peak": 0.5},
	&"hit": {"len": 0.18, "peak": 0.7},
	&"fall": {"len": 0.45, "peak": 0.55},
	&"step": {"len": 0.08, "peak": 0.3},
}
## 여자 목소리를 쓰는 사람 (NpcType.id)
const FEMALE: Array[StringName] = [&"CIV_F", &"GANG_F", &"FLYER"]
## 소리를 내지 않는 사람 — 아이는 어떤 소리에도 넣지 않는다 (사용자 요청)
const SILENT: Array[StringName] = [&"CHILD"]


## 비명 종류 (소리 없는 사람은 &"" — Sfx.play가 건너뛴다)
static func scream_of(npc: NpcType) -> StringName:
	if SILENT.has(npc.id):
		return &""
	return &"scream_f" if FEMALE.has(npc.id) else &"scream_m"


static func grunt_of(npc: NpcType) -> StringName:
	if SILENT.has(npc.id):
		return &""
	return &"grunt_f" if FEMALE.has(npc.id) else &"grunt_m"


## 한 번 울리는 소리 kind의 variant번째 (모노, -1..1). 같은 값이면 늘 같은 소리다
static func render(kind: StringName, variant := 0) -> PackedFloat32Array:
	var c: Dictionary = SHOTS[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(kind)) + variant * 104729
	var n := int(float(c.len) * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	match kind:
		&"hit":
			_thud(out, rng, 95.0, 0.04, 0.35)
		&"fall":
			_thud(out, rng, 70.0, 0.09, 0.2)
			_rustle(out, rng, 0.05, 0.1)
		&"step":
			_thud(out, rng, 140.0, 0.015, 0.6)
		_:
			_voice(out, rng, c, variant)
	var fade := mini(int(0.015 * MIX_RATE), n)
	for i in fade:
		out[n - 1 - i] *= float(i) / fade
	return _normalize(out, float(c.peak))


## 성대 펄스 → 포먼트 세 개(두 극 공진기)로 거른다. 높이는 처음 → 꼭대기(앞 20%) → 끝
static func _voice(out: PackedFloat32Array, rng: RandomNumberGenerator, c: Dictionary, variant: int) -> void:
	var n := out.size()
	var shift := 1.0 + (variant - 1) * 0.06            # 같은 종류도 목소리마다 조금 다르게
	var f0: float = c.f0 * shift
	var fp: float = c.f_peak * shift
	var fe: float = c.f_end * shift
	var formants: Array = c.vowel
	var res := []                                       # 공진기 상태 [y1, y2, a1, a2, gain]
	for k in formants.size():
		var f: float = formants[k] * (1.0 + (variant - 1) * 0.04)
		var bw := 90.0 + f * 0.06
		var r := exp(-PI * bw / MIX_RATE)
		var a1 := 2.0 * r * cos(TAU * f / MIX_RATE)
		var a2 := -r * r
		res.append([0.0, 0.0, a1, a2, (1.0 - r) * [1.0, 0.7, 0.35][k]])
	var phase := 0.0
	var vib := rng.randf() * TAU
	var breath := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, fp, smoothstep(0.0, 0.2, t)) if t < 0.2 else lerpf(fp, fe, (t - 0.2) / 0.8)
		f *= 1.0 + 0.025 * sin(vib + TAU * 6.5 * i / MIX_RATE)   # 떨림
		f *= 1.0 + 0.01 * rng.randf_range(-1.0, 1.0)              # 거친 목
		phase = fmod(phase + f / MIX_RATE, 1.0)
		breath = breath * 0.7 + rng.randf_range(-1.0, 1.0) * 0.3
		var src := (1.0 - 2.0 * phase) * 0.8 + breath * 0.25     # 톱니파 + 숨소리
		var y := 0.0
		for st: Array in res:
			var v: float = st[4] * src + st[2] * st[0] + st[3] * st[1]
			st[1] = st[0]
			st[0] = v
			y += v
		var env := smoothstep(0.0, 0.04, t) * (1.0 - smoothstep(0.65, 1.0, t))
		out[i] = y * env


## 둔탁한 쿵: 떨어지는 낮은 사인 + 낮게 거른 잡음, decay초로 사그라진다
static func _thud(out: PackedFloat32Array, rng: RandomNumberGenerator, hz: float, decay: float, noise: float) -> void:
	var lp := 0.0
	var ph := 0.0
	for i in out.size():
		var t := float(i) / MIX_RATE
		var env := exp(-t / decay)
		ph += TAU * hz * (1.0 - 0.4 * minf(t / decay, 1.0)) / MIX_RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.18
		out[i] += (sin(ph) * (1.0 - noise) + lp * noise * 2.0) * env


## 옷 스치는 소리: 높게 거른 잡음이 잠깐
static func _rustle(out: PackedFloat32Array, rng: RandomNumberGenerator, at: float, amount: float) -> void:
	var prev := 0.0
	var lp := 0.0
	var start := int(at * MIX_RATE)
	for i in range(start, out.size()):
		var t := float(i - start) / MIX_RATE
		var w := rng.randf_range(-1.0, 1.0)
		var hp := w - prev
		prev = w
		lp += (hp - lp) * 0.35          # 너무 높은 쉿 소리는 깎는다
		hp = lp
		out[i] += hp * amount * exp(-t / 0.12) * smoothstep(0.0, 0.02, t)


static func _normalize(out: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0
	for v in out:
		m = maxf(m, absf(v))
	if m > 0.0:
		var k := peak / m
		for i in out.size():
			out[i] *= k
	return out
