class_name AmbienceSynth
extends RefCounted
## 도시 배경음 합성기 (파일 없이). 끊김 없이 되풀이되는 토막(loop)을 만든다 — 끝과 처음을 겹쳐 섞어 이음매가 없다.
## - city: 멀리서 웅웅거리는 차 소리 (낮게 거른 갈색 잡음이 천천히 부풀었다 가라앉는다) + 아주 가끔 먼 경적
## - night: 풀벌레 (귀뚜라미 몇 마리가 서로 다른 박자로 찌르르)
## - birds: 낮의 참새·까치 (짧게 짹짹 오르내리는 소리가 드문드문)
## - rain: 빗소리 (걸러 낸 흰 잡음 + 빗방울 톡톡)
## - river: 강물 출렁임 (낮은 대역 잡음이 느리게 일렁인다)
## - beat: 홍대 DJ 휴대 스피커의 댄스 비트 (킥 4박·뒷박 하이햇·2·4박 박수·뒷박 베이스·마디 첫 박 화음) — 박자는 DJ 대기 그림과 같다

const MIX_RATE := GunSynth.MIX_RATE
const LOOPS := {&"city": 12.0, &"night": 8.0, &"birds": 14.0, &"rain": 6.0, &"river": 10.0, &"beat": BEAT * 16}   ## 토막 길이 (초)
const XFADE := 0.6                 ## 이음매를 섞는 길이 (초)
const BEAT := 0.375                ## 비트 한 박 (초) — DJ 대기 그림 1.5초가 4박 (Pedestrian.SPEAKER_BEAT)


static func loop(kind: StringName) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(kind)) + 5
	var n := int(float(LOOPS[kind]) * MIX_RATE)
	if kind == &"beat":
		# 박자가 토막 길이에 딱 맞으니 섞지 않고 끝을 넘는 소리만 처음으로 감는다 (섞으면 박이 두 겹으로 번진다)
		var wrap := PackedFloat32Array()
		wrap.resize(n)
		_beat(wrap, rng)
		return _normalize(wrap, 0.5)
	var f := int(XFADE * MIX_RATE)
	var raw := PackedFloat32Array()
	raw.resize(n + f)
	match kind:
		&"city": _city(raw, rng)
		&"night": _night(raw, rng)
		&"birds": _birds(raw, rng)
		&"rain": _rain(raw, rng)
		&"river": _river(raw, rng)
	# 끝 f개를 처음 f개에 섞어 넣는다 → 마지막 샘플 다음이 처음과 이어진다
	var out := raw.slice(0, n)
	for i in f:
		var k := float(i) / f
		out[i] = raw[n + i] * (1.0 - k) + raw[i] * k
	return _normalize(out, 0.5)


static func _city(out: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var brown := 0.0
	var lp := 0.0
	var swell := rng.randf() * TAU
	var horns: Array = []
	for k in 2:
		horns.append([rng.randf_range(0.1, 0.9) * out.size(), rng.randf_range(330.0, 420.0)])
	for i in out.size():
		var t := i / MIX_RATE
		brown = clampf(brown + rng.randf_range(-1.0, 1.0) * 0.02, -1.0, 1.0) * 0.999
		lp += (brown - lp) * 0.05
		var s := lp * (0.75 + 0.25 * sin(swell + TAU * t / 5.3)) * (0.85 + 0.15 * sin(TAU * t / 2.1))
		for h: Array in horns:
			var dt := (i - float(h[0])) / MIX_RATE
			if dt > 0.0 and dt < 0.35:
				s += 0.05 * (sin(TAU * h[1] * t) + 0.5 * sin(TAU * h[1] * 1.26 * t)) * sin(PI * dt / 0.35)
		out[i] = s


static func _night(out: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	for c in 4:
		var hz := rng.randf_range(3800.0, 4900.0)
		var rate := rng.randf_range(2.2, 3.4)          # 찌르르 묶음이 초당 몇 번
		var pulses := int(rng.randf_range(3.0, 6.0))
		var gain := rng.randf_range(0.25, 0.6)
		var off := rng.randf()
		for i in out.size():
			var t := i / MIX_RATE
			var cyc := fmod(t * rate + off, 1.0)
			if cyc > 0.35:
				continue
			var p := fmod(cyc / 0.35 * pulses, 1.0)
			out[i] += sin(TAU * hz * t) * sin(PI * p) * gain


static func _birds(out: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var calls := 9
	for c in calls:
		var at := int(rng.randf_range(0.02, 0.92) * out.size())
		var hz := rng.randf_range(2600.0, 4200.0)
		var notes := int(rng.randf_range(2.0, 5.0))
		var gain := rng.randf_range(0.3, 0.7)
		for k in notes:
			var start := at + int(k * 0.11 * MIX_RATE)
			var len := int(rng.randf_range(0.05, 0.09) * MIX_RATE)
			var up := rng.randf_range(0.8, 1.35)
			var ph := 0.0
			for i in len:
				if start + i >= out.size():
					break
				var u := float(i) / len
				ph += TAU * hz * lerpf(1.0, up, u) / MIX_RATE
				out[start + i] += sin(ph) * sin(PI * u) * gain


static func _rain(out: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var lp := 0.0
	var prev := 0.0
	for i in out.size():
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.45
		var hp := lp - prev
		prev = lp
		out[i] = hp * 0.6 + lp * 0.25
	for d in 140:   # 빗방울
		var at := rng.randi() % out.size()
		var hz := rng.randf_range(1800.0, 5200.0)
		var g := rng.randf_range(0.15, 0.5)
		for i in int(0.012 * MIX_RATE):
			if at + i < out.size():
				out[at + i] += sin(TAU * hz * i / MIX_RATE) * exp(-i / (0.003 * MIX_RATE)) * g


static func _river(out: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var a := 0.0
	var b := 0.0
	var ph := rng.randf() * TAU
	for i in out.size():
		var t := i / MIX_RATE
		var w := rng.randf_range(-1.0, 1.0)
		a += (w - a) * 0.08
		b += (a - b) * 0.08          # 두 번 걸러 낮은 출렁임
		out[i] = (a - b) * 2.0 * (0.6 + 0.4 * sin(ph + TAU * t / 2.7)) + b * 0.5


## 4박 × 4마디. 소리는 out 길이로 감아 쓴다 (마디 끝 꼬리가 처음 박 위에 겹친다 — 되풀이 이음매가 없다)
static func _beat(out: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var n := out.size()
	var b := int(BEAT * MIX_RATE)
	var bass := [55.0, 55.0, 65.41, 49.0]    # 마디마다 베이스 음 (A1·A1·C2·G1)
	var chords := [[220.0, 261.63, 329.63], [220.0, 261.63, 329.63], [261.63, 329.63, 392.0], [196.0, 246.94, 293.66]]
	for k in 16:
		var at := k * b
		var bar := k / 4
		# 킥: 120Hz에서 45Hz로 떨어지는 사인, 빨리 사라진다
		var ph := 0.0
		for i in int(0.28 * MIX_RATE):
			var t := float(i) / MIX_RATE
			ph += TAU * lerpf(45.0, 120.0, exp(-t * 28.0)) / MIX_RATE
			out[(at + i) % n] += sin(ph) * exp(-t * 11.0) * 0.9
		# 2·4박 박수: 잡음 덩이 셋이 조금씩 어긋나 겹친다
		if k % 2 == 1:
			for c in 3:
				var o := int(c * 0.011 * MIX_RATE)
				for i in int(0.12 * MIX_RATE):
					var t := float(i) / MIX_RATE
					out[(at + o + i) % n] += rng.randf_range(-1.0, 1.0) * exp(-t * 38.0) * 0.28
		# 뒷박: 열린 하이햇(흰 잡음의 차분) + 베이스 한 음
		var off := at + b / 2
		var prev := 0.0
		for i in int(0.07 * MIX_RATE):
			var t := float(i) / MIX_RATE
			var w := rng.randf_range(-1.0, 1.0)
			out[(off + i) % n] += (w - prev) * exp(-t * 45.0) * 0.18
			prev = w
		var hz: float = bass[bar]
		for i in int(BEAT * 0.45 * MIX_RATE):
			var t := float(i) / MIX_RATE
			var saw := 2.0 * fmod(hz * t, 1.0) - 1.0
			out[(off + i) % n] += (sin(TAU * hz * t) * 0.7 + saw * 0.18) * minf(t * 200.0, 1.0) * exp(-t * 6.0) * 0.55
		# 마디 첫 박: 짧은 신스 화음
		if k % 4 == 0:
			for i in int(BEAT * 0.8 * MIX_RATE):
				var t := float(i) / MIX_RATE
				var v := 0.0
				for f: float in chords[bar]:
					v += sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)
				out[(at + i) % n] += v * minf(t * 120.0, 1.0) * exp(-t * 5.0) * 0.07


static func _normalize(out: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0
	for v in out:
		m = maxf(m, absf(v))
	if m > 0.0:
		for i in out.size():
			out[i] *= peak / m
	return out
