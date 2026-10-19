class_name RotorSynth
extends RefCounted
## 헬기 소리 합성기 (소리 파일 없이 코드로 만든다). 노드 없는 계산부라 헤드리스 테스트에서 그대로 쓴다.
##
## 섞는 소리:
## - 날개 치는 소리 "두두두": 날개가 지날 때마다 낮게 걸러낸 바람 소리 + 낮은 쿵 소리가 터지고 사그라진다.
##   쿵 소리는 높게 시작해 떨어지고(북 치듯), 배음을 섞어 작은 스피커에서도 묵직하게 들린다
## - 엔진 웅웅거림: 더 낮게 걸러낸 바람 소리
## - 터빈 소리: 높은 사인파 (날개가 빨리 돌수록 높아진다)
## - 꼬리 날개: 빠른 톱니파를 걸러 낸 붕붕거림
## spin(0..1)은 날개 도는 빠르기 — 시동을 걸면 천천히 올라 "두… 두… 두두두"가 된다.
## load(0..1)는 힘을 쓰는 정도 — 가속·상승 중이면 날개 치는 소리가 커진다.

const MIX_RATE := 22050.0
const BLADE_HZ := 5.5         ## 다 돌 때 날개가 지나는 횟수 (초당)
const SLAP_DECAY := 4.5       ## 한 번 친 소리가 사그라지는 빠르기 (한 주기 안에서)
const THUMP_HZ := 36.0        ## 날개 칠 때 쿵 소리 높이 (치는 순간엔 THUMP_SWEEP배 높다)
const THUMP_SWEEP := 2.2
const WHINE_HZ := 900.0       ## 다 돌 때 터빈 소리 높이
const TAIL_RATIO := 5.3       ## 꼬리 날개는 주 날개보다 이만큼 빨리 돈다

var _rng := RandomNumberGenerator.new()
var _blade := 0.0     ## 날개 주기 위치 0..1 (0에서 친다)
var _thump := 0.0
var _whine := 0.0
var _tail := 0.0
var _lp1 := 0.0       ## 걸러 낸 바람 소리 (날개)
var _lp2 := 0.0       ## 더 낮게 걸러 낸 바람 소리 (엔진)
var _tail_lp := 0.0


func _init() -> void:
	_rng.seed = 7


## n개 샘플(스테레오, 같은 소리)을 만든다
func fill(n: int, spin: float, load: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(n)
	if spin <= 0.001:
		return out
	var blade_step := BLADE_HZ * spin / MIX_RATE
	var whine_step := WHINE_HZ * (0.35 + 0.65 * spin) / MIX_RATE
	var tail_step := blade_step * TAIL_RATIO
	var slap_gain := 0.55 + 0.45 * clampf(load, 0.0, 1.0)
	for i in n:
		_blade += blade_step
		if _blade >= 1.0:
			_blade -= 1.0
			_thump = 0.0
		_whine = fmod(_whine + whine_step, 1.0)
		_tail = fmod(_tail + tail_step, 1.0)
		var white := _rng.randf() * 2.0 - 1.0
		_lp1 += (white - _lp1) * 0.03
		_lp2 += (_lp1 - _lp2) * 0.03
		_tail_lp += (_tail * 2.0 - 1.0 - _tail_lp) * 0.08
		var env := exp(-_blade * SLAP_DECAY)
		_thump += THUMP_HZ * (1.0 + (THUMP_SWEEP - 1.0) * env) / MIX_RATE
		var ph := TAU * _thump
		var thump := sin(ph) + sin(2.0 * ph) * 0.5 + sin(3.0 * ph) * 0.25
		var slap := env * (_lp1 * 5.0 + thump * 1.2)
		var whine := sin(TAU * _whine) * 0.7 + sin(TAU * 2.0 * _whine) * 0.3
		var s := (slap * slap_gain + _lp2 * 1.1 + whine * 0.015 * spin + _tail_lp * 0.04) * spin * 1.3
		s = s / (1.0 + absf(s))     # 부드럽게 눌러 찢어지지 않게
		out[i] = Vector2(s, s)
	return out
