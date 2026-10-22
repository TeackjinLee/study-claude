extends Node
## 웹 실행 진단. ?perf=1 주소에서만 10초마다 실제 프레임 간격을 콘솔에 기록한다.
var multiplayer_requested := false
var _samples: Array[float] = []
var _last := 0
var _elapsed := 0.0
var _warmup := 5.0

func _ready() -> void:
	set_process(false)
	if not OS.has_feature("web"):
		return
	var query: String = JavaScriptBridge.eval("window.location.search")
	if "multiplayer=1" in query:
		multiplayer_requested = true
	if "perf=1" in query:
		_last = Time.get_ticks_usec()
		set_process(true)

func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last) / 1000.0
	_last = now
	if _warmup > 0.0:
		_warmup -= delta
		return
	_samples.append(ms)
	_elapsed += ms / 1000.0
	if _elapsed < 10.0:
		return
	var sum := 0.0
	var hitches := 0
	for value in _samples:
		sum += value
		if value > 34.0:
			hitches += 1
	_samples.sort()
	var p95: float = _samples[mini(int(_samples.size() * 0.95), _samples.size() - 1)]
	print("WEB_PERF frames=%d avg=%.2fms p95=%.2fms hitches=%d draw_calls=%d process=%.2fms physics=%.2fms" % [
		_samples.size(), sum / _samples.size(), p95, hitches,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	_samples.clear()
	_elapsed = 0.0
