class_name HeliSound
extends Node
## 헬기 소리: 탈 수 있는 헬기(Vehicle, stats.flies)에 붙는다. 소리는 RotorSynth가 코드로 만든다.
## 날개가 돌기 시작하면(시동) 천천히 빨라지고, 내려서 멈추면 천천히 느려진다.
## 카메라(화면 가운데)에서 멀수록 작다. 헤드리스(테스트)에서는 소리를 내지 않고 빠르기만 계산한다.

const SPIN_UP := 0.33         ## 초당 오르는 날개 빠르기 (약 3초에 다 돈다)
const SPIN_DOWN := 0.2        ## 초당 내리는 빠르기 (약 5초에 멈춘다)
const LOAD_RATE := 2.0        ## 힘 쓰는 정도가 따라가는 속도 (1/s)
const HEAR_RANGE := 1500.0    ## 이 거리 밖이면 안 들린다 (px)
const VOLUME_DB := -5.0
const BUFFER := 0.12          ## 소리 버퍼 길이 (초). 짧을수록 반응이 빠르지만 프레임이 늦으면 끊긴다

var spin := 0.0               ## 날개 빠르기 0..1
var load := 0.0               ## 힘 쓰는 정도 0..1 (가속·상승)
var car: Vehicle
var synth := RotorSynth.new()
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback


func _ready() -> void:
	car = get_parent() as Vehicle
	if DisplayServer.get_name() == "headless":
		return
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = RotorSynth.MIX_RATE
	stream.buffer_length = BUFFER
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	add_child(_player)


func _process(delta: float) -> void:
	if car == null:
		return
	if car._rotor_spinning():
		spin = move_toward(spin, 1.0, SPIN_UP * delta)
	else:
		spin = move_toward(spin, 0.0, SPIN_DOWN * delta)
	var climbing := car.controlled and not car.landing and car.altitude < car.stats.fly_height
	var goal := 1.0 if climbing else clampf(absf(car.throttle_input), 0.0, 1.0)
	load = move_toward(load, goal, LOAD_RATE * delta)
	if _player == null:
		return
	var gain := _near()    # 날개 빠르기에 따른 크기는 합성기가 정한다
	if spin <= 0.001 or gain < 0.002:
		if _player.playing:
			_player.stop()
			_playback = null
		return
	if not _player.playing:
		_player.play()
		_playback = _player.get_stream_playback()
	_player.volume_db = VOLUME_DB + linear_to_db(gain)
	var n := _playback.get_frames_available()
	if n > 0:
		_playback.push_buffer(synth.fill(n, spin, load))


## 카메라에 가까운 정도 0..1 (가까울수록 크다)
func _near() -> float:
	var cam := ChaseCamera.current_cam()
	if cam == null:
		return 1.0
	var k := clampf(1.0 - car.global_position.distance_to(cam.global_position) / HEAR_RANGE, 0.0, 1.0)
	return k * k
