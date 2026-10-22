class_name Radio
extends Node
## 차 라디오 (docs/06 §라디오, Main이 붙인다): 차에 타면 그 차의 채널(차마다 정해져 있다)이 켜지고, T(패드 십자 아래)로
## 채널을 넘긴다 (5채널 → 끔 → 처음). 음악은 RadioSynth가 채널마다 만든 한 토막을 처음에 굽고(따로 만든 스레드),
## 채널은 '방송 중'이라 다시 돌아오면 그동안 흐른 만큼 뒤에서 튼다. DJ 말은 화면 아래 자막(dj_line)으로 띄운다.
## 자전거·무한궤도·헬기처럼 라디오가 없는 탈것에서는 켜지지 않는다. 헤드리스에서는 소리 없이 고르기만 한다.

signal tuned(channel: RadioChannel)        ## 채널이 바뀌었다 (null = 껐다)
signal dj_line(channel: RadioChannel, text: String)

const CHANNELS: Array[RadioChannel] = [
	preload("res://data/radio/kpop.tres"),
	preload("res://data/radio/trot.tres"),
	preload("res://data/radio/lofi.tres"),
	preload("res://data/radio/rock.tres"),
	preload("res://data/radio/news.tres"),
]
const VOLUME_DB := -10.0
const DJ_FIRST := 3.0                ## 채널을 맞추고 첫 DJ 자막까지
const DJ_EVERY := Vector2(22.0, 38.0)
const NO_RADIO: Array[StringName] = [&"", &"tracked", &"bike"]   ## 이 엔진 종류(CarSynth.engine_kind)의 탈것엔 라디오가 없다 (자전거·오토바이·무한궤도·헬기)

var director: Director
var channel: RadioChannel = null     ## 지금 나오는 채널 (없으면 null)
var off_by_player := false           ## 주인공이 껐다 — 다음 차에 타도 꺼진 채
var _car: Vehicle = null
var _picked := {}                    ## 차 → 고른 채널 번호 (-1 = 끔)
var _clock := 0.0                    ## 방송 시계 (채널 위치를 정한다)
var _dj_wait := DJ_FIRST
var _dj_salt := 0
var _songs := {}                     ## 채널 id → AudioStreamWAV
var _player: AudioStreamPlayer
var _silent := false
var _thread: Thread
var _stop := false


func _ready() -> void:
	_silent = DisplayServer.get_name() == "headless"
	if _silent:
		return
	AudioSetup.ensure()
	_player = AudioStreamPlayer.new()
	_player.bus = AudioSetup.MUSIC
	_player.volume_db = VOLUME_DB
	add_child(_player)
	_thread = Thread.new()
	_thread.start(_bake_all, Thread.PRIORITY_LOW)


func _exit_tree() -> void:
	if _thread:
		_stop = true
		_thread.wait_to_finish()
		_thread = null


static func has_radio(v: Vehicle) -> bool:
	return v != null and not v.stats.flies and not NO_RADIO.has(CarSynth.engine_kind(v.stats))


## 차마다 처음 나오는 채널 (늘 같다 — 무작위를 쓰지 않는다)
static func default_index(v: Vehicle) -> int:
	return posmod(hash(v.stats.id) + v.get_instance_id(), CHANNELS.size())


func _process(delta: float) -> void:
	_clock += delta
	var v := director.current_vehicle if director else null
	if v != _car:
		_car = v
		if has_radio(v):
			var i: int = _picked.get(v, -1 if off_by_player else default_index(v))
			_tune(CHANNELS[i] if i >= 0 else null)
		else:
			_tune(null, false)
	if channel:
		_dj_wait -= delta
		if _dj_wait <= 0.0:
			_dj_wait = lerpf(DJ_EVERY.x, DJ_EVERY.y, fmod(_dj_salt * 0.618, 1.0))
			var text := Dialogue.pick(channel.dj, &"radio", _dj_salt)
			_dj_salt += 1
			if text != "":
				dj_line.emit(channel, text)
	if not _silent:
		_sync_audio()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("radio_next"):
		next()


## 다음 채널 (마지막 다음은 끔, 끔 다음은 처음)
func next() -> void:
	if not has_radio(_car):
		return
	var i := CHANNELS.find(channel)
	var n := i + 1
	if n >= CHANNELS.size():
		n = -1
	_picked[_car] = n
	off_by_player = n < 0
	_tune(CHANNELS[n] if n >= 0 else null)


func _tune(ch: RadioChannel, announce := true) -> void:
	if ch == channel:
		return
	channel = ch
	_dj_wait = DJ_FIRST
	if announce:
		tuned.emit(ch)


func _sync_audio() -> void:
	if channel == null or not _songs.has(channel.id):
		if _player.playing:
			_player.stop()
		return
	var song: AudioStreamWAV = _songs[channel.id]
	if _player.stream != song:
		_player.stream = song
		var length := song.get_length()
		_player.play(fmod(_clock, length) if length > 0.0 else 0.0)
	elif not _player.playing:
		_player.play()


func _bake_all() -> void:
	for ch in CHANNELS:
		if _stop:
			return
		var samples := RadioSynth.song(ch)
		_set_song.call_deferred(ch.id, Sfx.pcm16(samples), samples.size())


func _set_song(id: StringName, bytes: PackedByteArray, n: int) -> void:
	var w := Sfx.wav_of(bytes)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	_songs[id] = w
