class_name RadioSynth
extends RefCounted
## 라디오 음악 합성기 (파일 없이). 채널 스타일마다 8마디 곡 한 토막을 만들어 끊김 없이 되풀이한다.
## 음 하나하나를 그 길이만큼만 버퍼에 더해 그린다(샘플마다 모든 악기를 돌지 않는다 — 스레드에서 1초쯤).
## - kpop: 4박 킥·2·4박 박수·8분 하이햇, 톱니 화음 패드, 8분 베이스, 5음 음계 뜯는 선율
## - trot: 2박 쿵짝(베이스·스네어), 떨림 있는 사각파 선율(아코디언 느낌), 단조 Am–Dm–E7–Am
## - lofi: 느린 스윙 드럼, 전자 피아노 화음(종소리 배음), 레코드 지직
## - rock: 일그러진 파워 코드, 킥·스네어 8비트, 베이스
## - news: 음악 대신 잔잔한 패드와 정각 알림음 (DJ 자막이 방송을 맡는다)
## 토막 끝의 울림은 앞쪽에 접어 넣어(되풀이 이음매에서 끊기지 않게) 이음매가 없다.

const MIX_RATE := 22050.0
const BARS := 8


## 곡 한 토막 (모노, -1..1)
static func song(ch: RadioChannel) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = ch.seed * 7907 + hash(String(ch.style))
	var beat := 60.0 / ch.bpm
	var n := int(BARS * 4 * beat * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	match ch.style:
		&"kpop": _kpop(out, ch, beat, rng)
		&"trot": _trot(out, ch, beat, rng)
		&"lofi": _lofi(out, ch, beat, rng)
		&"rock": _rock(out, ch, beat, rng)
		_: _news(out, ch, beat, rng)
	return _normalize(out, 0.7)


# ── 곡 ───────────────────────────────────────────────────

static func _kpop(out: PackedFloat32Array, ch: RadioChannel, beat: float, rng: RandomNumberGenerator) -> void:
	var prog := [0, -4, 3, -2] if ch.minor else [0, 5, -3, 7]      # vi–IV–I–V 느낌 (단조 기준 i–VI–III–VII)
	var scale := [0, 3, 5, 7, 10] if ch.minor else [0, 2, 4, 7, 9]
	var melody := _phrase(rng, 16, scale)
	for bar in BARS:
		var chord: int = prog[bar % 4]
		var t0 := bar * 4 * beat
		for b in 4:
			_kick(out, t0 + b * beat, 0.9)
			if b % 2 == 1:
				_clap(out, t0 + b * beat, 0.45, rng)
		for e in 8:
			_hat(out, t0 + e * beat * 0.5, 0.18 if e % 2 == 0 else 0.1, rng)
			_saw(out, t0 + e * beat * 0.5, beat * 0.45, _hz(ch.root - 24 + chord), 0.35, 0.08)
		for k in _triad(ch.minor):
			_saw(out, t0, beat * 4.0, _hz(ch.root + chord + k), 0.11, 0.03, 0.05, 0.5)
		for e in 8:
			var m: int = melody[(bar % 2) * 8 + e]
			if m >= 0:
				_pluck(out, t0 + e * beat * 0.5, beat * 0.5, _hz(ch.root + 12 + m), 0.3, rng)


static func _trot(out: PackedFloat32Array, ch: RadioChannel, beat: float, rng: RandomNumberGenerator) -> void:
	var prog := [0, 5, 7, 0]                                         # Am–Dm–E–Am
	var scale := [0, 2, 3, 7, 8] if ch.minor else [0, 2, 4, 7, 9]   # 트로트 단조 5음 (라·시·도·미·파)
	var melody := _phrase(rng, 16, scale, 0.15)
	for bar in BARS:
		var root: int = ch.root + prog[bar % 4]
		var t0 := bar * 4 * beat
		for b in 4:
			if b % 2 == 0:
				_kick(out, t0 + b * beat, 0.7)
				_saw(out, t0 + b * beat, beat * 0.8, _hz(root - 24), 0.4, 0.06)
			else:
				_snare(out, t0 + b * beat, 0.35, rng)
				_saw(out, t0 + b * beat, beat * 0.8, _hz(root - 17), 0.3, 0.06)   # 5도
			# 쿵짝의 짝: 화음을 짧게
			for k in _triad(prog[bar % 4] != 7):
				_square(out, t0 + (b + 0.5) * beat, beat * 0.25, _hz(root + k), 0.05, 0.0)
		for e in 4:
			var m: int = melody[(bar % 4) * 4 + e]
			if m >= 0:
				_square(out, t0 + e * beat, beat * 0.95, _hz(ch.root + 12 + m), 0.22, 0.03)


static func _lofi(out: PackedFloat32Array, ch: RadioChannel, beat: float, rng: RandomNumberGenerator) -> void:
	var prog := [0, 5, -2, 3]                                       # ii–V 느낌으로 맴도는 화음
	var swing := 0.16
	for bar in BARS:
		var chord: int = prog[bar % 4]
		var t0 := bar * 4 * beat
		_kick(out, t0, 0.6)
		_kick(out, t0 + 2.5 * beat, 0.45)
		_snare(out, t0 + beat, 0.25, rng)
		_snare(out, t0 + 3.0 * beat, 0.25, rng)
		for e in 8:
			_hat(out, t0 + (e + (swing if e % 2 == 1 else 0.0)) * beat * 0.5, 0.07, rng)
		for k in [0, 3 if ch.minor else 4, 7, 10]:
			_epiano(out, t0, beat * 3.5, _hz(ch.root + chord + k), 0.12)
		_epiano(out, t0, beat * 4.0, _hz(ch.root - 12 + chord), 0.18)
	# 따뜻하게: 높은 소리를 깎는다
	var y := 0.0
	for i in out.size():
		y += (out[i] - y) * 0.35
		out[i] = y
	# 레코드 지직 (드문드문)
	for i in int(out.size() / 5000):
		var at := rng.randi() % out.size()
		out[at] += rng.randf_range(-0.12, 0.12)


static func _rock(out: PackedFloat32Array, ch: RadioChannel, beat: float, rng: RandomNumberGenerator) -> void:
	var prog := [0, 0, -4, -2, 0, 0, 3, 5]
	for bar in BARS:
		var root: int = ch.root - 12 + prog[bar]
		var t0 := bar * 4 * beat
		for e in 8:
			var at := t0 + e * beat * 0.5
			if e in [0, 3, 4]:
				_kick(out, at, 0.85)
			if e in [2, 6]:
				_snare(out, at, 0.55, rng)
			_hat(out, at, 0.12, rng)
			_power(out, at, beat * 0.45, _hz(root), 0.28)
			_saw(out, at, beat * 0.45, _hz(root - 12), 0.3, 0.07)


static func _news(out: PackedFloat32Array, ch: RadioChannel, beat: float, rng: RandomNumberGenerator) -> void:
	for bar in BARS:
		var t0 := bar * 4 * beat
		for k in _triad(ch.minor):
			_saw(out, t0, beat * 4.0, _hz(ch.root + k), 0.06, 0.015, 0.4, 0.8)
		if bar % 4 == 0:   # 정각 알림 "삐–삐–삐–삐익"
			for k in 4:
				var hz := 880.0 if k < 3 else 1760.0
				_sine(out, t0 + k * beat, beat * (0.15 if k < 3 else 0.6), hz, 0.25)


# ── 악기 ─────────────────────────────────────────────────

static func _kick(out: PackedFloat32Array, at: float, g: float) -> void:
	var ph := 0.0
	var start := int(at * MIX_RATE)
	for i in int(0.3 * MIX_RATE):
		var t := i / MIX_RATE
		ph += TAU * (45.0 + 85.0 * exp(-t / 0.04)) / MIX_RATE
		_add(out, start + i, sin(ph) * exp(-t / 0.12) * g)


static func _snare(out: PackedFloat32Array, at: float, g: float, rng: RandomNumberGenerator) -> void:
	var start := int(at * MIX_RATE)
	var prev := 0.0
	for i in int(0.2 * MIX_RATE):
		var t := i / MIX_RATE
		var w := rng.randf_range(-1.0, 1.0)
		var hp := w - prev * 0.6
		prev = w
		_add(out, start + i, (hp * 0.7 * exp(-t / 0.06) + sin(TAU * 185.0 * t) * 0.4 * exp(-t / 0.03)) * g)


static func _clap(out: PackedFloat32Array, at: float, g: float, rng: RandomNumberGenerator) -> void:
	var start := int(at * MIX_RATE)
	for i in int(0.15 * MIX_RATE):
		var t := i / MIX_RATE
		var bursts := 1.0 if t > 0.02 else (1.0 if fmod(t, 0.007) < 0.003 else 0.0)
		_add(out, start + i, rng.randf_range(-1.0, 1.0) * bursts * exp(-maxf(t - 0.02, 0.0) / 0.05) * g)


static func _hat(out: PackedFloat32Array, at: float, g: float, rng: RandomNumberGenerator) -> void:
	var start := int(at * MIX_RATE)
	var prev := 0.0
	for i in int(0.05 * MIX_RATE):
		var w := rng.randf_range(-1.0, 1.0)
		_add(out, start + i, (w - prev) * 0.5 * exp(-(i / MIX_RATE) / 0.012) * g)
		prev = w


## 톱니파 (한 극으로 걸러 부드럽게). lp 작을수록 어둡다, attack·release 초
static func _saw(out: PackedFloat32Array, at: float, dur: float, hz: float, g: float, lp: float,
		attack := 0.005, release := 0.05) -> void:
	var start := int(at * MIX_RATE)
	var len := int((dur + release) * MIX_RATE)
	var ph := 0.0
	var y := 0.0
	var k := clampf(lp * 4.0, 0.01, 1.0)
	for i in len:
		var t := i / MIX_RATE
		ph = fmod(ph + hz / MIX_RATE, 1.0)
		y += ((2.0 * ph - 1.0) - y) * k
		_add(out, start + i, y * _env(t, dur, attack, release) * g)


## 사각파 + 떨림 (아코디언·하모니카)
static func _square(out: PackedFloat32Array, at: float, dur: float, hz: float, g: float, vibrato: float) -> void:
	var start := int(at * MIX_RATE)
	var len := int((dur + 0.04) * MIX_RATE)
	var ph := 0.0
	var y := 0.0
	for i in len:
		var t := i / MIX_RATE
		ph = fmod(ph + hz * (1.0 + vibrato * sin(TAU * 5.5 * t) * smoothstep(0.08, 0.3, t)) / MIX_RATE, 1.0)
		y += ((1.0 if ph < 0.5 else -1.0) - y) * 0.25
		_add(out, start + i, y * _env(t, dur, 0.01, 0.04) * g)


static func _sine(out: PackedFloat32Array, at: float, dur: float, hz: float, g: float) -> void:
	var start := int(at * MIX_RATE)
	for i in int((dur + 0.03) * MIX_RATE):
		var t := i / MIX_RATE
		_add(out, start + i, sin(TAU * hz * t) * _env(t, dur, 0.005, 0.03) * g)


## 줄 뜯는 소리 (Karplus–Strong)
static func _pluck(out: PackedFloat32Array, at: float, dur: float, hz: float, g: float, rng: RandomNumberGenerator) -> void:
	var period := maxi(2, int(MIX_RATE / hz))
	var line := PackedFloat32Array()
	line.resize(period)
	for i in period:
		line[i] = rng.randf_range(-1.0, 1.0)
	var start := int(at * MIX_RATE)
	var len := int((dur + 0.15) * MIX_RATE)
	var idx := 0
	for i in len:
		var a := line[idx]
		var b := line[(idx + 1) % period]
		line[idx] = (a + b) * 0.497
		idx = (idx + 1) % period
		_add(out, start + i, a * g * (1.0 - smoothstep(dur, dur + 0.15, i / MIX_RATE)))


## 전자 피아노: 사인 + 종소리 배음이 먼저 사그라진다
static func _epiano(out: PackedFloat32Array, at: float, dur: float, hz: float, g: float) -> void:
	var start := int(at * MIX_RATE)
	for i in int((dur + 0.3) * MIX_RATE):
		var t := i / MIX_RATE
		var v := sin(TAU * hz * t) + 0.35 * sin(TAU * hz * 4.0 * t) * exp(-t / 0.15) + 0.1 * sin(TAU * hz * 2.0 * t)
		_add(out, start + i, v * exp(-t / 1.2) * _env(t, dur, 0.004, 0.3) * g)


## 일그러진 파워 코드 (으뜸음 + 5도 + 옥타브를 tanh로 찌그러뜨린다)
static func _power(out: PackedFloat32Array, at: float, dur: float, hz: float, g: float) -> void:
	var start := int(at * MIX_RATE)
	var y := 0.0
	for i in int((dur + 0.05) * MIX_RATE):
		var t := i / MIX_RATE
		var v := 0.0
		for m in [1.0, 1.4983, 2.0]:
			v += 2.0 * fmod(t * hz * m, 1.0) - 1.0
		y += (tanh(v * 2.5) - y) * 0.35
		_add(out, start + i, y * _env(t, dur, 0.003, 0.05) * g)


# ── 거들기 ───────────────────────────────────────────────

## 되풀이 토막: 끝을 넘친 소리는 앞으로 접는다
static func _add(out: PackedFloat32Array, i: int, v: float) -> void:
	out[i % out.size()] += v


static func _env(t: float, dur: float, attack: float, release: float) -> float:
	if t < attack:
		return t / attack
	if t < dur:
		return 1.0
	return maxf(0.0, 1.0 - (t - dur) / release)


static func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


static func _triad(minor: bool) -> Array:
	return [0, 3, 7] if minor else [0, 4, 7]


## 음계 안에서 걷는 선율 n개 (음계 도수 → 반음, 쉼은 -1). 같은 rng면 같은 선율
static func _phrase(rng: RandomNumberGenerator, n: int, scale: Array, rest := 0.25) -> Array:
	var out := []
	var step := 2
	for i in n:
		if rng.randf() < rest and i % 4 != 0:
			out.append(-1)
			continue
		step = clampi(step + rng.randi_range(-2, 2), 0, scale.size() * 2 - 1)
		out.append(int(scale[step % scale.size()]) + 12 * (step / scale.size()))
	return out


static func _normalize(out: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0
	for v in out:
		m = maxf(m, absf(v))
	if m > 0.0:
		for i in out.size():
			out[i] *= peak / m
	return out
