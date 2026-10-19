class_name Sfx
extends Node
## 한 번 울리는 효과음(총소리·폭발)을 트는 곳. Combat이 하나 만들어 붙이고, 어디서든 `Sfx.play(종류, 위치)`로 부른다.
## 소리는 GunSynth가 코드로 만든 것을 처음에 한 번 AudioStreamWAV로 구워 두고(전부 굽는 데 1초쯤 걸려 뒤 스레드에서 굽는다 —
## 다 구워지기 전에 부른 종류는 소리 없이 넘어간다), 목소리(AudioStreamPlayer) 몇 개를 돌려 쓴다.
## 카메라(화면 가운데)에서 멀수록 작다. 목소리가 모자라면 가장 오래 운 것을 끊는다.
## 헤드리스(테스트)에서는 소리를 내지 않고 부른 기록(`heard`)만 남긴다.

const VOICES := 14             ## 동시에 나는 소리 수
const HEAR_RANGE := 1400.0     ## 총소리가 들리는 거리 (px)
const BLAST_RANGE := 2600.0    ## 폭발은 더 멀리 들린다
const VOLUME_DB := -6.0
const PITCH_JITTER := 0.05     ## 같은 소리도 높이를 조금씩 흔든다
const SAME_GAP := 2            ## 같은 종류가 같은 곳에서 이 물리 틱 안에 또 나면 한 번만 (동시 발사)
const LOG_SIZE := 64

static var current: Sfx

var heard: Array = []          ## 최근에 부른 소리 [종류, 위치, 크기] (테스트용, 헤드리스에서도 남는다)
var _streams := {}             ## 종류 → [AudioStreamWAV …] (VARIANTS개)
var _voices: Array[AudioStreamPlayer] = []
var _started: Array[float] = []
var _last := {}                ## 종류 → [시각, 위치]
var _rng := RandomNumberGenerator.new()   # 게임 rng와 따로 (소리가 게임 결과를 바꾸지 않게)
var _silent := false
var _tasks: Array[int] = []


func _ready() -> void:
	current = self
	_rng.seed = 31
	_silent = DisplayServer.get_name() == "headless"
	if _silent:
		return
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)
		_started.append(-INF)
	for kind: StringName in GunSynth.KINDS:
		_tasks.append(WorkerThreadPool.add_task(_bake.bind(kind), false, "효과음 굽기"))


func _exit_tree() -> void:
	if current == self:
		current = null
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()


## 종류 kind의 소리를 pos에서 낸다. size는 크기 배율(폭발 크기 등, 클수록 크고 낮다)
static func play(kind: StringName, pos: Vector2, size := 1.0) -> void:
	if current != null and kind != &"":
		current._play(kind, pos, size)


func _play(kind: StringName, pos: Vector2, size: float) -> void:
	if not GunSynth.KINDS.has(kind):
		return
	var tick := Engine.get_physics_frames()
	var last: Array = _last.get(kind, [-SAME_GAP, Vector2.ZERO])
	if tick - int(last[0]) < SAME_GAP and pos.distance_to(last[1]) < 40.0:
		return
	_last[kind] = [tick, pos]
	var now := Time.get_ticks_msec() / 1000.0
	heard.append([kind, pos, size])
	if heard.size() > LOG_SIZE:
		heard.remove_at(0)
	if _silent:
		return
	var gain := _near(pos, BLAST_RANGE if kind == &"explosion" else HEAR_RANGE) * minf(sqrt(size), 1.4)
	if gain < 0.01:
		return
	var v := _free_voice()
	var list: Array = _streams.get(kind, [])
	if list.is_empty():
		return
	_voices[v].stream = list[_rng.randi() % list.size()]
	_voices[v].volume_db = VOLUME_DB + linear_to_db(gain)
	# 큰 폭발은 낮게 (유조차 3배면 0.72배 높이)
	_voices[v].pitch_scale = _rng.randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER) * pow(maxf(size, 0.25), -0.3)
	_voices[v].play()
	_started[v] = now


## 놀고 있는 목소리, 없으면 가장 오래 운 것
func _free_voice() -> int:
	var oldest := 0
	for i in VOICES:
		if not _voices[i].playing:
			return i
		if _started[i] < _started[oldest]:
			oldest = i
	return oldest


## 카메라에 가까운 정도 0..1 (가까울수록 크다)
func _near(pos: Vector2, reach: float) -> float:
	var cam := ChaseCamera.current_cam()
	if cam == null:
		return 1.0
	var k := clampf(1.0 - pos.distance_to(cam.global_position) / reach, 0.0, 1.0)
	return k * k


## 뒤 스레드에서 돈다: 다 구우면 본 스레드에서 넣는다
func _bake(kind: StringName) -> void:
	var list: Array = []
	for variant in GunSynth.VARIANTS:
		list.append(to_wav(GunSynth.render(kind, variant)))
	_set_streams.call_deferred(kind, list)


func _set_streams(kind: StringName, list: Array) -> void:
	_streams[kind] = list


## -1..1 모노 샘플을 16비트 소리로
static func to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(GunSynth.MIX_RATE)
	w.stereo = false
	w.data = bytes
	return w
