class_name GunSynth
extends RefCounted
## 총소리·폭발 소리 합성기 (소리 파일 없이 코드로 만든다). 노드 없는 계산부라 헤드리스 테스트에서 그대로 쓴다.
## 한 번 울리고 끝나는 소리라 미리 한 번 만들어 두고(`render`) Sfx가 되풀이해 튼다.
##
## 한 발은 네 겹을 섞는다:
## - 탁 (crack): 아주 짧은 높은 바람 소리 — 화약이 터지는 순간
## - 몸통 (body): 걸러 낸 바람 소리가 빠르게 사그라진다 — 총마다 길이·두께가 다르다
## - 쿵 (thump): 높게 시작해 떨어지는 낮은 사인파 — 무거운 총·포일수록 낮고 길다
## - 울림 (tail): 아주 낮게 걸러 낸 바람 소리가 길게 남는다 + 건물에 한 번 튕겨 온 메아리 (echo)
## 폭발은 여기에 타닥거림(crackle — 파편·불꽃 튀는 소리)을 더한다.

const MIX_RATE := 22050.0
const VARIANTS := 3            ## 종류마다 조금씩 다른 소리 수 (연발이 똑같이 들리지 않게)

## 종류별 값. len 길이(초), attack 커지는 시간, *_t 사그라지는 시간 상수(초), *_lp 거르는 정도(작을수록 낮다),
## thump_hz → thump_end 쿵 소리 높이(Hz), echo 메아리 [지연(초), 크기], peak 다 만든 뒤 맞추는 최대 크기
const KINDS := {
	&"pistol": {"len": 0.55, "attack": 0.0, "crack": 0.8, "crack_t": 0.003, "body": 1.0, "body_t": 0.035, "body_lp": 0.25,
		"thump": 0.6, "thump_hz": 160.0, "thump_end": 70.0, "thump_t": 0.03,
		"tail": 0.35, "tail_t": 0.18, "tail_lp": 0.04, "echo": [0.11, 0.25], "crackle": 0.0, "peak": 0.75},
	&"smg": {"len": 0.35, "attack": 0.0, "crack": 0.7, "crack_t": 0.002, "body": 0.9, "body_t": 0.025, "body_lp": 0.3,
		"thump": 0.4, "thump_hz": 180.0, "thump_end": 90.0, "thump_t": 0.02,
		"tail": 0.25, "tail_t": 0.1, "tail_lp": 0.05, "echo": [0.09, 0.2], "crackle": 0.0, "peak": 0.6},
	&"rifle": {"len": 0.8, "attack": 0.0, "crack": 1.0, "crack_t": 0.004, "body": 1.0, "body_t": 0.05, "body_lp": 0.2,
		"thump": 0.8, "thump_hz": 140.0, "thump_end": 55.0, "thump_t": 0.045,
		"tail": 0.45, "tail_t": 0.28, "tail_lp": 0.035, "echo": [0.14, 0.3], "crackle": 0.0, "peak": 0.85},
	&"shotgun": {"len": 0.9, "attack": 0.0, "crack": 0.6, "crack_t": 0.006, "body": 1.2, "body_t": 0.07, "body_lp": 0.12,
		"thump": 1.0, "thump_hz": 110.0, "thump_end": 45.0, "thump_t": 0.06,
		"tail": 0.5, "tail_t": 0.3, "tail_lp": 0.03, "echo": [0.14, 0.3], "crackle": 0.0, "peak": 0.9},
	&"mg": {"len": 0.45, "attack": 0.0, "crack": 0.8, "crack_t": 0.003, "body": 1.0, "body_t": 0.04, "body_lp": 0.18,
		"thump": 0.9, "thump_hz": 120.0, "thump_end": 55.0, "thump_t": 0.035,
		"tail": 0.3, "tail_t": 0.15, "tail_lp": 0.035, "echo": [0.1, 0.2], "crackle": 0.0, "peak": 0.7},
	&"rocket": {"len": 0.9, "attack": 0.02, "crack": 0.3, "crack_t": 0.005, "body": 1.0, "body_t": 0.25, "body_lp": 0.15,
		"thump": 0.5, "thump_hz": 90.0, "thump_end": 60.0, "thump_t": 0.08,
		"tail": 0.4, "tail_t": 0.4, "tail_lp": 0.03, "echo": [0.0, 0.0], "crackle": 0.0, "peak": 0.7},
	&"cannon": {"len": 1.8, "attack": 0.0, "crack": 0.5, "crack_t": 0.01, "body": 1.2, "body_t": 0.12, "body_lp": 0.06,
		"thump": 1.4, "thump_hz": 70.0, "thump_end": 28.0, "thump_t": 0.15,
		"tail": 0.7, "tail_t": 0.6, "tail_lp": 0.02, "echo": [0.2, 0.35], "crackle": 0.0, "peak": 0.95},
	&"explosion": {"len": 2.2, "attack": 0.004, "crack": 0.4, "crack_t": 0.01, "body": 1.3, "body_t": 0.25, "body_lp": 0.05,
		"thump": 1.6, "thump_hz": 60.0, "thump_end": 22.0, "thump_t": 0.3,
		"tail": 1.0, "tail_t": 0.9, "tail_lp": 0.015, "echo": [0.25, 0.3], "crackle": 0.002, "peak": 1.0},
}


## 종류 kind의 variant번째 소리 (모노, -1..1). 같은 값이면 늘 같은 소리다
static func render(kind: StringName, variant := 0) -> PackedFloat32Array:
	var k: Dictionary = KINDS[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(kind)) + variant * 7919
	var n := int(float(k.len) * MIX_RATE)
	var dry := PackedFloat32Array()
	dry.resize(n)
	var crack_lp := 0.0
	var body := 0.0
	var tail := 0.0
	var tail2 := 0.0
	var ph := 0.0
	var spark := 0.0
	# 같은 종류라도 몸통 두께·쿵 높이를 조금씩 흔든다
	var body_lp: float = k.body_lp * rng.randf_range(0.85, 1.15)
	var thump_hz: float = k.thump_hz * rng.randf_range(0.92, 1.08)
	for i in n:
		var t := i / MIX_RATE
		var white := rng.randf() * 2.0 - 1.0
		crack_lp += (white - crack_lp) * 0.3
		var crack := (white - crack_lp) * exp(-t / float(k.crack_t))
		body += (white - body) * body_lp
		tail += (white - tail) * float(k.tail_lp)
		tail2 += (tail - tail2) * float(k.tail_lp) * 2.0
		var thump_env := exp(-t / float(k.thump_t))
		ph += TAU * lerpf(float(k.thump_end), thump_hz, thump_env) / MIX_RATE
		var thump := (sin(ph) + 0.4 * sin(2.0 * ph)) * thump_env
		var s := crack * float(k.crack) \
			+ body * exp(-t / float(k.body_t)) * float(k.body) * 3.0 \
			+ thump * float(k.thump) \
			+ tail2 * exp(-t / float(k.tail_t)) * float(k.tail) * 12.0
		if float(k.crackle) > 0.0:
			# 타닥: 드문드문 짧은 딸깍이 터지고, 시간이 갈수록 줄어든다
			if rng.randf() < float(k.crackle) * exp(-t / 0.8):
				spark = rng.randf_range(0.4, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0)
			spark *= 0.93
			s += spark * 0.6
		if float(k.attack) > 0.0:
			s *= minf(t / float(k.attack), 1.0)
		dry[i] = s
	# 메아리: 조금 늦게, 더 뭉개져서 한 번 더 들린다
	var echo: Array = k.echo
	var out := dry.duplicate()
	if float(echo[1]) > 0.0:
		var lag := int(float(echo[0]) * MIX_RATE)
		var lp := 0.0
		for i in range(lag, n):
			lp += (dry[i - lag] - lp) * 0.15
			out[i] += lp * float(echo[1])
	# 끝은 살짝 줄여 딸깍 소리 없이 끝낸다
	var fade := mini(int(0.03 * MIX_RATE), n)
	for i in fade:
		out[n - 1 - i] *= float(i) / fade
	# 부드럽게 눌러(맨 앞 탁 소리가 몸통을 가리지 않게) 최대 크기를 peak에 맞춘다:
	# 꼭대기를 2로 키워 v/(1+|v|/2)로 누르면 꼭대기가 1이 된다
	var top := 0.0
	for v in out:
		top = maxf(top, absf(v))
	if top > 0.0:
		var g := 2.0 / top
		for i in n:
			var v := out[i] * g
			out[i] = v / (1.0 + absf(v) * 0.5) * float(k.peak)
	return out
