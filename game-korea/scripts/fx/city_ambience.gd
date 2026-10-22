class_name CityAmbience
extends Node
## 도시 배경음 (Main이 붙인다): AmbienceSynth 토막을 처음에 한 번 굽고(따로 만든 스레드), 되풀이 틀면서 크기만 바꾼다.
## 크기는 `mix`(노드 없는 계산 — 테스트가 본다)가 정한다: 차 웅웅은 늘(밤에는 조금 작게, 강가·산에서는 더 작게),
## 풀벌레는 밤, 새는 낮(비 오면 없다), 빗소리는 비, 강물은 카메라가 강에 가까울수록.
## 헤드리스에서는 소리를 내지 않고 `levels`(이름 → 0..1)만 매 프레임 남긴다.

const BASE_DB := -16.0
const FADE := 0.6                  ## 크기가 따라가는 빠르기 (초당 몫)
const RIVER_NEAR := 260.0          ## 이보다 가까우면 강물 소리가 다 들린다
const RIVER_FAR := 1100.0          ## 이보다 멀면 안 들린다

var sky: DayNight
var levels := {}                   ## 이름 → 지금 크기 0..1
var _players := {}                 ## 이름 → AudioStreamPlayer
var _silent := false
var _thread: Thread
var _stop := false
var _water: Array[Rect2] = []


func _ready() -> void:
	_water = City.water_rects()
	for k: StringName in AmbienceSynth.LOOPS:
		levels[k] = 0.0
	_silent = DisplayServer.get_name() == "headless"
	if _silent:
		return
	AudioSetup.ensure()
	for k: StringName in AmbienceSynth.LOOPS:
		var p := AudioStreamPlayer.new()
		p.bus = AudioSetup.AMBIENCE
		p.volume_db = -80.0
		add_child(p)
		_players[k] = p
	_thread = Thread.new()
	_thread.start(_bake_all, Thread.PRIORITY_LOW)


func _exit_tree() -> void:
	if _thread:
		_stop = true
		_thread.wait_to_finish()
		_thread = null


## 시각·비·강까지 거리 → 이름마다 크기 0..1
static func mix(hour: float, raining: bool, river_distance: float) -> Dictionary:
	var night := DayNight.is_night(hour)
	var dawn := hour >= 5.0 and hour < 9.0
	var river := clampf(1.0 - (river_distance - RIVER_NEAR) / (RIVER_FAR - RIVER_NEAR), 0.0, 1.0)
	return {
		&"city": (0.6 if night else 0.9) * (1.0 - 0.45 * river),
		&"night": 0.0 if raining or not night else 0.55,
		&"birds": 0.0 if raining or night else (0.7 if dawn else 0.35),
		&"rain": 0.85 if raining else 0.0,
		&"river": river * 0.8,
	}


func river_distance(at: Vector2) -> float:
	var best := INF
	for r in _water:
		best = minf(best, (at - at.clamp(r.position, r.end)).length())
	return best


func _process(delta: float) -> void:
	var cam := ChaseCamera.current_cam()
	var at := cam.global_position if cam else Vector2.ZERO
	var goal := mix(sky.hour if sky else 12.0, sky.raining if sky else false, river_distance(at))
	for k: StringName in goal:
		levels[k] = move_toward(levels[k], goal[k], FADE * delta)
		if _silent or not _players.has(k):
			continue
		var p: AudioStreamPlayer = _players[k]
		if p.stream == null:
			continue
		if levels[k] > 0.005:
			p.volume_db = BASE_DB + linear_to_db(levels[k])
			if not p.playing:
				p.play()
		elif p.playing:
			p.stop()


func _bake_all() -> void:
	for k: StringName in AmbienceSynth.LOOPS:
		if _stop:
			return
		var samples := AmbienceSynth.loop(k)
		_set_loop.call_deferred(k, Sfx.pcm16(samples), samples.size())


func _set_loop(k: StringName, bytes: PackedByteArray, n: int) -> void:
	var w := Sfx.wav_of(bytes)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	if _players.has(k):
		_players[k].stream = w
