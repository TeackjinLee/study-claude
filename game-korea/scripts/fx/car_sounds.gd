class_name CarSounds
extends Node
## 차에서 계속 나는 소리: 엔진·사이렌·타이어 끌림, 그리고 NPC 차 경적. Main이 하나 붙인다.
## 소리는 CarSynth가 만든 끊김 없는 토막을 처음에 한 번 AudioStreamWAV(되풀이)로 구워 두고(Sfx처럼 따로 만든 스레드에서),
## 목소리(AudioStreamPlayer) 몇 개를 가까운 차에 나눠 준다 — 차 수십 대마다 소리를 만들지 않는다.
## - 엔진: 주인공이 모는 차 + 가까운 차 ENGINE_VOICES−1대. 회전수(CarSynth.gear_rpm)만큼 빠르게 틀고(pitch_scale),
##   힘 쓰는 토막과 뗀 토막을 가속 페달만큼 섞는다. 목소리 하나에 두 토막(플레이어 둘).
## - 사이렌: 경광등을 켠 차 중 가까운 SIREN_VOICES대 (경찰은 울음·빠른 울음을 번갈아, 소방차·구급차는 울음).
## - 타이어 끌림: 주인공 차가 미끄러지면.
## - 경적: NPC 차가 경적을 울리기 시작하면 Sfx로 한 번.
## 고르는 일(누구에게 목소리를 줄지)은 헤드리스에서도 해서(`engines`·`sirens`) 테스트가 본다. 소리만 내지 않는다.
## 게임 rng를 쓰지 않는다 (소리가 게임 결과를 바꾸지 않게).

const ENGINE_VOICES := 4
const SIREN_VOICES := 2
const ENGINE_RANGE := 900.0     ## 엔진이 들리는 거리 (px)
const SIREN_RANGE := 2400.0
const HORN_RANGE := 1200.0
const PLAYER_DB := -9.0         ## 주인공 차 엔진
const NPC_DB := -15.0           ## 다른 차 엔진
const SIREN_DB := -12.0
const SKID_DB := -10.0
const RPM_RATE := 9000.0        ## 회전수가 따라가는 빠르기 (rpm/s) — 기어가 바뀌면 뚝 떨어지되 튀지 않게
const REV := 0.18               ## 서 있을 때 가속 페달을 밟으면 공회전에서 이만큼(최고 회전수 몫) 오른다
const YELP_EVERY := 6.0         ## 경찰 사이렌이 울음 ↔ 빠른 울음으로 바뀌는 간격 (초)

var vehicles: Array[Vehicle] = []
var director: Director
var engines: Array = []         ## 목소리마다 맡은 차 (없으면 null) — 0번은 늘 주인공 차 자리
var sirens: Array = []
var rpm := {}                   ## 차 → 지금 회전수
var skid := 0.0                 ## 타이어 끌림 크기 0..1
var _honked := {}               ## 경적을 울리고 있던 차
var _silent := false
var _engine_players: Array = [] ## 목소리마다 [힘 쓰는 토막, 뗀 토막]
var _siren_players: Array[AudioStreamPlayer] = []
var _skid_player: AudioStreamPlayer
var _loops := {}                ## 이름 → AudioStreamWAV (다 구워지기 전엔 없다)
var _thread: Thread
var _stop := false
var _time := 0.0
var _rng := RandomNumberGenerator.new()   # 게임 rng와 따로


func _ready() -> void:
	engines.resize(ENGINE_VOICES)
	sirens.resize(SIREN_VOICES)
	_silent = DisplayServer.get_name() == "headless"
	if _silent:
		return
	AudioSetup.ensure()
	for i in ENGINE_VOICES:
		var pair: Array = []
		for k in 2:
			var p := AudioStreamPlayer.new()
			p.bus = AudioSetup.SFX
			add_child(p)
			pair.append(p)
		_engine_players.append(pair)
	for i in SIREN_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = AudioSetup.SFX
		add_child(p)
		_siren_players.append(p)
	_skid_player = AudioStreamPlayer.new()
	_skid_player.bus = AudioSetup.SFX
	add_child(_skid_player)
	_thread = Thread.new()
	_thread.start(_bake_all, Thread.PRIORITY_LOW)


func _exit_tree() -> void:
	if _thread:
		_stop = true
		_thread.wait_to_finish()
		_thread = null


func _process(delta: float) -> void:
	_time += delta
	var cam := ChaseCamera.current_cam()
	var ear: Vector2 = cam.global_position if cam else Vector2.ZERO
	# 삭제된 객체는 타입 변수에 대입하는 순간에도 오류가 나므로 먼저 검사한다.
	var mine: Vehicle = null
	if is_instance_valid(director) and is_instance_valid(director.current_vehicle):
		mine = director.current_vehicle
	_pick_engines(mine, ear)
	_pick_sirens(ear)
	_horns(ear)
	skid = move_toward(skid, 1.0 if mine and mine.is_skidding() and mine.speed() > 60.0 else 0.0, delta * 6.0)
	for v in engines:
		if v:
			rpm[v] = move_toward(rpm.get(v, 0.0), target_rpm(v), RPM_RATE * delta)
	for v in rpm.keys():
		if not is_instance_valid(v) or not engines.has(v):
			rpm.erase(v)
	if not _silent:
		_play_engines(mine, ear)
		_play_sirens(ear)
		_play_skid()


## 차 v의 엔진이 내려는 회전수 (0이면 엔진 소리 없음)
static func target_rpm(v: Vehicle) -> float:
	if not is_instance_valid(v) or v.wrecked or not v.occupied():
		return 0.0
	var kind := CarSynth.engine_kind(v.stats)
	if kind == &"":
		return 0.0
	var e: Dictionary = CarSynth.ENGINES[kind]
	var r := CarSynth.gear_rpm(kind, v.motor.forward_speed() / v.stats.max_speed)
	var pedal := absf(v.throttle_input)
	return minf(r + pedal * REV * float(e.red) * (1.0 if v.speed() < 40.0 else 0.3), float(e.red))


## 엔진 목소리: 0번은 주인공 차, 나머지는 가까운 순서. 이미 맡은 차는 그대로 둔다 (소리가 끊겼다 다시 나지 않게)
func _pick_engines(mine: Vehicle, ear: Vector2) -> void:
	var want: Array[Vehicle] = []
	for v in vehicles:
		if not is_instance_valid(v) or v == mine or not v.occupied() or CarSynth.engine_kind(v.stats) == &"":
			continue
		if v.global_position.distance_to(ear) < ENGINE_RANGE:
			want.append(v)
	want.sort_custom(func(a: Vehicle, b: Vehicle) -> bool:
		return a.global_position.distance_squared_to(ear) < b.global_position.distance_squared_to(ear))
	want = want.slice(0, ENGINE_VOICES - 1)
	engines[0] = mine if mine and CarSynth.engine_kind(mine.stats) != &"" and not mine.wrecked else null
	_keep(engines, want, 1)


func _pick_sirens(ear: Vector2) -> void:
	var want: Array[Vehicle] = []
	for v in vehicles:
		if is_instance_valid(v) and v.siren and not v.wrecked and not v.stats.flies \
				and v.global_position.distance_to(ear) < SIREN_RANGE:
			want.append(v)
	want.sort_custom(func(a: Vehicle, b: Vehicle) -> bool:
		return a.global_position.distance_squared_to(ear) < b.global_position.distance_squared_to(ear))
	_keep(sirens, want.slice(0, SIREN_VOICES), 0)


## slots[from..]에 want를 나눠 준다: 이미 맡은 차는 그 자리에 두고, 빠진 차의 자리에 새 차를 넣는다
static func _keep(slots: Array, want: Array, from: int) -> void:
	for i in range(from, slots.size()):
		# 삭제된 객체는 null처럼 비교될 수 있어 유효성 검사를 먼저 한다.
		if not is_instance_valid(slots[i]) or not want.has(slots[i]):
			slots[i] = null
	for v in want:
		if slots.has(v):
			continue
		for i in range(from, slots.size()):
			if slots[i] == null:
				slots[i] = v
				break


## NPC 차가 경적을 울리기 시작하면 한 번 "빵"
func _horns(ear: Vector2) -> void:
	for v in vehicles:
		if not is_instance_valid(v):
			continue
		var on := v.ai != null and v.ai.honking and not v.wrecked
		if on and not _honked.has(v) and v.global_position.distance_to(ear) < HORN_RANGE:
			Sfx.play(&"horn", v.global_position)
		if on:
			_honked[v] = true
		else:
			_honked.erase(v)
	for v in _honked.keys():
		if not is_instance_valid(v):
			_honked.erase(v)


# ── 소리 내기 (창 모드만) ───────────────────────────────────

func _play_engines(mine: Vehicle, ear: Vector2) -> void:
	for i in ENGINE_VOICES:
		var pair: Array = _engine_players[i]
		if not is_instance_valid(engines[i]):
			engines[i] = null
			for p: AudioStreamPlayer in pair:
				p.stop()
			continue
		var v: Vehicle = engines[i]
		var kind := CarSynth.engine_kind(v.stats) if v else &""
		var on_wav: AudioStreamWAV = _loops.get(String(kind) + "_on")
		var off_wav: AudioStreamWAV = _loops.get(String(kind) + "_off")
		if v == null or rpm.get(v, 0.0) <= 0.0 or on_wav == null:
			for p: AudioStreamPlayer in pair:
				p.stop()
			continue
		var gain := 1.0 if v == mine else _near(v.global_position, ear, ENGINE_RANGE)
		var base := PLAYER_DB if v == mine else NPC_DB
		var pitch := clampf(float(rpm[v]) / float(CarSynth.ENGINES[kind].base_rpm), 0.2, 4.0)
		var pedal := clampf(absf(v.throttle_input), 0.0, 1.0) if v == mine else 0.5
		for k in 2:
			var p: AudioStreamPlayer = pair[k]
			var wav: AudioStreamWAV = on_wav if k == 0 else off_wav
			if p.stream != wav:
				p.stream = wav
				p.play(_rng.randf() * CarSynth.ENGINE_LOOP)   # 차마다 다른 곳에서 시작
			elif not p.playing:
				p.play()
			var mix := pedal if k == 0 else 1.0 - pedal * 0.7
			p.pitch_scale = pitch
			p.volume_db = base + linear_to_db(maxf(gain * mix, 0.0001))


func _play_sirens(ear: Vector2) -> void:
	for i in SIREN_VOICES:
		var p := _siren_players[i]
		if not is_instance_valid(sirens[i]):
			sirens[i] = null
			p.stop()
			continue
		var v: Vehicle = sirens[i]
		var yelp := v.stats.category == &"police" and fmod(_time + i * 2.7, YELP_EVERY * 2.0) > YELP_EVERY
		var wav: AudioStreamWAV = _loops.get("siren_yelp" if yelp else "siren_wail")
		if wav == null:
			continue
		if p.stream != wav:
			p.stream = wav
			p.play()
		elif not p.playing:
			p.play()
		p.volume_db = SIREN_DB + linear_to_db(maxf(_near(v.global_position, ear, SIREN_RANGE), 0.0001))


func _play_skid() -> void:
	var wav: AudioStreamWAV = _loops.get("skid")
	if wav == null:
		return
	if skid <= 0.01:
		_skid_player.stop()
		return
	if _skid_player.stream != wav:
		_skid_player.stream = wav
	if not _skid_player.playing:
		_skid_player.play()
	_skid_player.volume_db = SKID_DB + linear_to_db(skid)


static func _near(pos: Vector2, ear: Vector2, reach: float) -> float:
	var k := clampf(1.0 - pos.distance_to(ear) / reach, 0.0, 1.0)
	return k * k


## 굽는 스레드: 샘플만 계산하고, 소리 자원은 본 스레드에서 만든다 (Sfx와 같은 까닭)
func _bake_all() -> void:
	var jobs: Array = []
	for kind: StringName in CarSynth.ENGINES:
		jobs.append([String(kind) + "_on", func(): return CarSynth.engine_loop(kind, true)])
		jobs.append([String(kind) + "_off", func(): return CarSynth.engine_loop(kind, false)])
	for kind: StringName in CarSynth.SIRENS:
		jobs.append(["siren_" + String(kind), func(): return CarSynth.siren_loop(kind)])
	jobs.append(["skid", func(): return CarSynth.skid_loop()])
	for job: Array in jobs:
		if _stop:
			return
		var samples: PackedFloat32Array = job[1].call()
		_set_loop.call_deferred(job[0], Sfx.pcm16(samples), samples.size())


func _set_loop(name: String, bytes: PackedByteArray, n: int) -> void:
	var w := Sfx.wav_of(bytes)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	_loops[name] = w
