class_name CityAmbience
extends Node
## 도시 배경음 (Main이 붙인다): AmbienceSynth 토막을 처음에 한 번 굽고(따로 만든 스레드), 되풀이 틀면서 크기만 바꾼다.
## 크기는 `mix`(노드 없는 계산 — 테스트가 본다)가 정한다: 차 웅웅은 늘(밤에는 조금 작게, 강가·산에서는 더 작게),
## 풀벌레는 밤, 새는 낮(비 오면 없다), 빗소리는 비, 강물은 카메라가 강에 가까울수록,
## 비트는 카메라가 한자리에서 춤추는 DJ(휴대 스피커, NpcType.station_prop)에 가까울수록 — 틀기 시작할 때 그 DJ의 춤 박자에 맞춘다.
## 헤드리스에서는 소리를 내지 않고 `levels`(이름 → 0..1)만 매 프레임 남긴다.

const BASE_DB := -16.0
const FADE := 0.6                  ## 크기가 따라가는 빠르기 (초당 몫)
const RIVER_NEAR := 260.0          ## 이보다 가까우면 강물 소리가 다 들린다
const RIVER_FAR := 1100.0          ## 이보다 멀면 안 들린다
const BEAT_NEAR := 90.0            ## DJ 스피커가 이보다 가까우면 비트가 다 들린다
const BEAT_FAR := 520.0            ## 이보다 멀면 안 들린다

var sky: DayNight
var pedestrians: PedestrianManager   ## 비트를 울리는 DJ를 찾는다 (없으면 비트 없음)
var levels := {}                   ## 이름 → 지금 크기 0..1
var _players := {}                 ## 이름 → AudioStreamPlayer
var _silent := false
var _thread: Thread
var _stop := false
var _water: Array[Rect2] = []
var _dj: Pedestrian                 ## 가장 가까운 스피커 DJ (비트 박자를 맞춘다)


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


## 시각·비·강까지 거리·스피커 DJ까지 거리 → 이름마다 크기 0..1
static func mix(hour: float, raining: bool, river_distance: float, dj_distance := INF) -> Dictionary:
	var night := DayNight.is_night(hour)
	var dawn := hour >= 5.0 and hour < 9.0
	var river := clampf(1.0 - (river_distance - RIVER_NEAR) / (RIVER_FAR - RIVER_NEAR), 0.0, 1.0)
	return {
		&"city": (0.6 if night else 0.9) * (1.0 - 0.45 * river),
		&"night": 0.0 if raining or not night else 0.55,
		&"birds": 0.0 if raining or night else (0.7 if dawn else 0.35),
		&"rain": 0.85 if raining else 0.0,
		&"river": river * 0.8,
		&"beat": clampf(1.0 - (dj_distance - BEAT_NEAR) / (BEAT_FAR - BEAT_NEAR), 0.0, 1.0) * 0.9,
	}


func river_distance(at: Vector2) -> float:
	var best := INF
	for r in _water:
		best = minf(best, (at - at.clamp(r.position, r.end)).length())
	return best


## 카메라에서 가장 가까운, 한자리에서 스피커를 틀어 둔 DJ까지 거리 (_dj에 남긴다)
func dj_distance(at: Vector2) -> float:
	_dj = null
	var best := INF
	if pedestrians == null:
		return best
	for p: Pedestrian in pedestrians.peds:
		if p.stationed and p.active and p.npc.station_prop == &"speaker" and not p.is_scared() and not p.is_dead():
			var d := at.distance_to(p.global_position + p.prop_offset)
			if d < best:
				best = d
				_dj = p
	return best


func _process(delta: float) -> void:
	var cam := ChaseCamera.current_cam()
	var at := cam.global_position if cam else Vector2.ZERO
	var goal := mix(sky.hour if sky else 12.0, sky.raining if sky else false, river_distance(at), dj_distance(at))
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
				p.play(_beat_phase() if k == &"beat" else 0.0)
		elif p.playing:
			p.stop()


## 비트를 틀기 시작할 자리 (초): 가장 가까운 DJ 대기 그림 시각(PersonRig.idle_frame과 같은 식)에 맞춰 스피커가 울리는 박에 킥이 오게
func _beat_phase() -> float:
	var t := Time.get_ticks_msec() / 1000.0
	if _dj:
		t += float(_dj.get_instance_id() % 1000) * 0.0137
	return fposmod(t, float(AmbienceSynth.LOOPS[&"beat"]))


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
