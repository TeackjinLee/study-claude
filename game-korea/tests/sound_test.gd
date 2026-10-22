extends Node
## 효과음 검증.
##  1. 합성기(GunSynth): 종류마다 소리가 나고 찢어지지 않으며, 맨 앞이 크고 사그라진다. 같은 값이면 같은 소리.
##  2. 무거울수록 낮다: 낮은 소리(150Hz 아래) 몫이 권총 < 소총 < 포 < 폭발, 기관단총이 가장 짧다.
##  3. 총 데이터: 쏘는 총·로켓·포에는 소리가 있고, 모두 합성기가 아는 종류다.
##  4. 본편: 쏘면 그 총 소리가, 터지면 폭발 소리가 난다. 산탄 한 번은 한 소리.
##  5. 차 소리 합성기(CarSynth): 엔진·사이렌·타이어 토막은 되풀이해도 이음매가 없고, 사이렌은 정한 높이 사이를 오르내린다.
##     회전수는 공회전에서 시작해 기어 안에서 오르고 기어가 바뀌면 떨어지며 최고 회전수를 넘지 않는다. 한 번 울리는 소리
##     (충돌·부딪힘·경적)가 나고, 충돌이 부딪힘보다 크고 길다. 차종마다 엔진 종류가 맞다.
##  6. 본편 차 소리(CarSounds): 주인공 차가 엔진 0번 자리, 가까운 NPC 차가 나머지(먼 차는 아니다), 경광등 켠 차가 사이렌.
##     벽에 세게 박으면 충돌 소리, NPC 경적.
##  7. 사람 소리(VoiceSynth): 비명·신음·맞는 소리·쓰러짐·발소리가 나고 찢어지지 않는다. 비명은 여자 > 남자 높이.
##     본편: 겁먹어 소리치는 사람은 비명, 맞으면 맞는 소리·신음, 기절하면 쓰러지는 소리, 주인공이 걸으면 발소리.
##  9. 차 라디오(Radio·RadioSynth): 채널 5개 곡이 나고 이음매가 없다. 차에 타면 그 차 채널이 켜지고 T로 넘기며 마지막 다음은 끔,
##     내리면 꺼지고, 오토바이엔 라디오가 없다. 켜 두면 DJ 자막이 뜬다.
##  8. 도시 배경음(AmbienceSynth·CityAmbience): 토막은 이음매가 없다. 밤엔 풀벌레·낮엔 새, 비 오면 빗소리(새·벌레 없음),
##     강에 가까우면 강물 소리.
## 실행: godot --headless --fixed-fps 60 --path . res://tests/sound_test.tscn

const PISTOL: WeaponType = preload("res://data/weapons/pistol.tres")
const SHOTGUN: WeaponType = preload("res://data/weapons/shotgun.tres")
const FIST: WeaponType = preload("res://data/weapons/fist.tres")

var _failures: Array[String] = []


func _ready() -> void:
	_test_synth()
	_test_weight()
	_test_data()
	await _test_in_game()
	_test_car_synth()
	await _test_car_sounds()
	_test_voice_synth()
	_test_ambience()
	if _failures.is_empty():
		print("sound_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _test_synth() -> void:
	for kind: StringName in GunSynth.KINDS:
		var s := GunSynth.render(kind)
		var want := int(float(GunSynth.KINDS[kind].len) * GunSynth.MIX_RATE)
		_expect(s.size() == want, "%s 길이 (%d ≠ %d)" % [kind, s.size(), want])
		var top := 0.0
		for v in s:
			top = maxf(top, absf(v))
		_expect(top > 0.3 and top <= 1.0, "%s 크기 0.3~1 (%.2f)" % [kind, top])
		var head := _rms(s, 0, int(0.03 * GunSynth.MIX_RATE))
		var tail := _rms(s, int(s.size() * 0.8), s.size())
		_expect(head > tail * 3.0, "%s 맨 앞이 크고 사그라진다 (앞 %.3f 끝 %.3f)" % [kind, head, tail])
		_expect(GunSynth.render(kind) == s, "%s 같은 값이면 같은 소리" % kind)
		_expect(GunSynth.render(kind, 1) != s, "%s 변형은 조금 다르다" % kind)


func _test_weight() -> void:
	var order := [&"pistol", &"rifle", &"cannon", &"explosion"]
	var lows: Array[float] = []
	for kind: StringName in order:
		lows.append(_low_share(GunSynth.render(kind)))
	for i in range(1, order.size()):
		_expect(lows[i] > lows[i - 1], "%s가 %s보다 낮다 (낮은 소리 몫 %.2f > %.2f)" % [order[i], order[i - 1], lows[i], lows[i - 1]])
	for kind: StringName in GunSynth.KINDS:
		_expect(kind == &"smg" or GunSynth.KINDS[kind].len > GunSynth.KINDS[&"smg"].len,
			"빨리 쏘는 기관단총 소리가 가장 짧다 (%s)" % kind)


func _test_data() -> void:
	var dir := "res://data/weapons/"
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".tres"):
			continue
		var w: WeaponType = load(dir + f)
		var shoots := not w.melee and not w.flame and not w.water and w.projectile in [&"", &"rocket"]
		if shoots:
			_expect(w.sound != &"", "%s: 쏘는 무기에는 소리가 있다" % w.id)
		if w.sound != &"":
			_expect(GunSynth.KINDS.has(w.sound), "%s: 소리 %s는 합성기가 아는 종류" % [w.id, w.sound])


func _test_in_game() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = 0
	main.bus_count = 0
	main.police_patrols = 0
	add_child(main)
	await _frames(2)
	var combat: Combat = main.combat
	var sfx := Sfx.current
	_expect(sfx != null and sfx.get_parent() == combat, "본편에 효과음 노드가 있다")
	if sfx == null:
		main.queue_free()
		return
	var at: Vector2 = main.player.global_position
	var none: Array[RID] = [main.player.get_rid()]
	combat.fire(at, Vector2.RIGHT, PISTOL, true, none)
	_expect(_last(sfx) == &"pistol", "권총을 쏘면 권총 소리 (%s)" % _last(sfx))
	await _frames(5)
	var n := sfx.heard.size()
	combat.fire(at, Vector2.RIGHT, SHOTGUN, true, none)
	_expect(sfx.heard.size() == n + 1 and _last(sfx) == &"shotgun",
		"산탄 한 번은 소리 한 번 (%d)" % (sfx.heard.size() - n))
	await _frames(5)
	n = sfx.heard.size()
	combat.fire(at, Vector2.RIGHT, FIST, true, none)
	_expect(sfx.heard.size() == n, "주먹은 소리가 없다")
	combat.explode(at + Vector2(600, 0), true, null, 2.0)
	_expect(_last(sfx) == &"explosion" and float(sfx.heard[-1][2]) == 2.0, "폭발은 크기를 담아 폭발 소리")
	# 창 모드로 돌렸을 때만: 다 구워지면 실제로 목소리가 운다
	if not sfx._silent:
		for i in 300:
			if sfx._streams.size() == GunSynth.KINDS.size() + CarSynth.SHOTS.size() + VoiceSynth.SHOTS.size():
				break
			await _frames(1)
		_expect(sfx._streams.size() == GunSynth.KINDS.size() + CarSynth.SHOTS.size() + VoiceSynth.SHOTS.size(), "효과음을 5초 안에 다 굽는다")
		await _frames(5)
		combat.fire(at, Vector2.RIGHT, PISTOL, true, none)
		_expect(sfx._voices.any(func(p: AudioStreamPlayer): return p.playing), "쏘면 소리가 난다")
	# 사람 소리
	var peds: PedestrianManager = main.pedestrians
	var screamer: Pedestrian = null
	for q in peds.peds:
		if q.active and not q.is_dead() and q.get_instance_id() % 3 == 0 and not q.npc.fearless:
			screamer = q
			break
	if screamer:
		screamer.panic(Vector2.RIGHT)
		_expect(String(_last(sfx)).begins_with("scream"), "겁먹어 소리치면 비명 (%s)" % _last(sfx))
	var victim: Pedestrian = null
	for q in peds.peds:
		if q.active and not q.is_dead() and not q.npc.protected and q != screamer:
			victim = q
			break
	if victim:
		n = sfx.heard.size()
		peds.damage(victim, 1.0, Vector2.RIGHT, true, true)
		var kinds: Array = sfx.heard.slice(n).map(func(h): return h[0])
		_expect(kinds.has(&"hit") and kinds.any(func(k): return String(k).begins_with("grunt")), "맞으면 맞는 소리·신음 (%s)" % [kinds])
		await _frames(SFX_GAP)
		peds.damage(victim, 999.0, Vector2.RIGHT, true, false)
		_expect(_last(sfx) == &"fall", "기절하면 쓰러지는 소리 (%s)" % _last(sfx))
	var player: Player = main.player
	player.screen_walk = false
	n = sfx.heard.size()
	Input.action_press("steer_right")
	await _frames(40)
	Input.action_release("steer_right")
	_expect(sfx.heard.slice(n).any(func(h): return h[0] == &"step"), "주인공이 걸으면 발소리")
	_expect(main.ambience != null, "본편에 배경음 노드가 있다")
	await _test_radio(main)
	main.queue_free()
	await _frames(2)
	_expect(Sfx.current == null, "본편이 사라지면 효과음 노드도 비운다")


const SFX_GAP := 3


func _test_voice_synth() -> void:
	for kind: StringName in VoiceSynth.SHOTS:
		var a := VoiceSynth.render(kind, 0)
		var peak := 0.0
		for v in a:
			peak = maxf(peak, absf(v))
		_expect(a.size() > 0 and peak > 0.1 and peak <= 1.0, "%s: 소리가 나고 찢어지지 않는다 (%.2f)" % [kind, peak])
		_expect(a == VoiceSynth.render(kind, 0), "%s: 같은 값이면 같은 소리" % kind)
	_expect(_pitch(VoiceSynth.render(&"scream_f")) > _pitch(VoiceSynth.render(&"scream_m")) * 1.3, "여자 비명이 남자보다 높다")
	_expect(VoiceSynth.scream_of(preload("res://data/npc/civ_f.tres")) == &"scream_f", "시민(여) 비명")
	var child: NpcType = preload("res://data/npc/child.tres")
	_expect(VoiceSynth.scream_of(child) == &"" and VoiceSynth.grunt_of(child) == &"", "아이는 소리를 내지 않는다")
	_expect(not VoiceSynth.SHOTS.keys().any(func(k): return String(k).ends_with("_c")), "아이 목소리는 만들지 않는다")


## 영점 교차로 잰 높이 (Hz)
func _pitch(s: PackedFloat32Array) -> float:
	var cross := 0
	for i in range(1, s.size()):
		if (s[i - 1] < 0.0) != (s[i] < 0.0):
			cross += 1
	return cross * 0.5 / (s.size() / VoiceSynth.MIX_RATE)


func _test_radio(main: Node2D) -> void:
	var radio: Radio = main.radio
	var director: Director = main.director
	var tunes := []
	var djs := []
	radio.tuned.connect(func(ch): tunes.append(ch))
	radio.dj_line.connect(func(ch, text): djs.append(text))
	_expect(radio.channel == null, "걸을 때는 라디오가 없다")
	var car: Vehicle = main.vehicles[0]
	director.enter_immediately(car)
	await _frames(3)
	_expect(director.current_vehicle != null and radio.channel == Radio.CHANNELS[Radio.default_index(director.current_vehicle)],
		"차에 타면 그 차 채널 (%s)" % radio.channel)
	var first: RadioChannel = radio.channel
	radio.next()
	_expect(radio.channel != first and tunes.size() >= 2, "T로 다음 채널")
	while radio.channel != null:
		radio.next()
	_expect(tunes[-1] == null, "마지막 다음은 끔")
	radio.next()
	_expect(radio.channel == Radio.CHANNELS[0], "끔 다음은 처음 채널")
	radio._dj_wait = 0.0
	await _frames(2)
	_expect(not djs.is_empty() and Dialogue.lines(Radio.CHANNELS[0].dj, &"radio").has(djs[-1]), "DJ 자막 (%s)" % [djs])
	director.exit_vehicle()
	await _frames(3)
	_expect(radio.channel == null, "내리면 꺼진다")
	var bike_car := Vehicle.new()
	bike_car.stats = preload("res://data/vehicles/etc_bike.tres")
	_expect(not Radio.has_radio(bike_car), "오토바이엔 라디오가 없다")
	bike_car.free()
	for ch in Radio.CHANNELS:
		var song := RadioSynth.song(ch)
		var peak := 0.0
		for v in song:
			peak = maxf(peak, absf(v))
		_expect(song.size() > RadioSynth.MIX_RATE * 8.0 and peak > 0.3 and peak <= 1.0, "%s 곡이 난다" % ch.id)
		_expect(absf(song[0] - song[song.size() - 1]) < 0.25, "%s: 되풀이 이음매" % ch.id)
		_expect(Dialogue.has(ch.dj, &"radio"), "%s DJ 자막이 있다" % ch.id)


func _test_ambience() -> void:
	for kind: StringName in AmbienceSynth.LOOPS:
		var a := AmbienceSynth.loop(kind)
		_expect(a.size() == int(float(AmbienceSynth.LOOPS[kind]) * AmbienceSynth.MIX_RATE), "%s 토막 길이" % kind)
		var jump := absf(a[0] - a[a.size() - 1])
		var typical := 0.0
		for i in range(1, 2000):
			typical = maxf(typical, absf(a[i] - a[i - 1]))
		_expect(jump <= typical + 0.02, "%s: 되풀이 이음매가 없다 (%.3f / %.3f)" % [kind, jump, typical])
	var night := CityAmbience.mix(23.0, false, INF)
	var day := CityAmbience.mix(13.0, false, INF)
	var rain := CityAmbience.mix(13.0, true, INF)
	_expect(night[&"night"] > 0.0 and day[&"night"] == 0.0, "풀벌레는 밤에")
	_expect(day[&"birds"] > 0.0 and night[&"birds"] == 0.0, "새는 낮에")
	_expect(rain[&"rain"] > 0.0 and rain[&"birds"] == 0.0 and day[&"rain"] == 0.0, "비 오면 빗소리, 새는 없다")
	_expect(CityAmbience.mix(13.0, false, 100.0)[&"river"] > 0.5 and day[&"river"] == 0.0, "강가에서는 강물 소리")
	_expect(day[&"city"] > 0.0 and night[&"city"] > 0.0, "도시 웅웅은 늘")


func _test_car_synth() -> void:
	for kind: StringName in CarSynth.ENGINES:
		for on in [true, false]:
			var s := CarSynth.engine_loop(kind, on)
			var name := "%s 엔진(%s)" % [kind, "힘" if on else "뗌"]
			_expect(s.size() == int(CarSynth.ENGINE_LOOP * CarSynth.MIX_RATE), name + " 길이")
			_check_loop(s, name)
			_expect(CarSynth.engine_loop(kind, on) == s, name + " 같은 값이면 같은 소리")
		var rpm_idle := CarSynth.gear_rpm(kind, 0.0)
		var red: float = CarSynth.ENGINES[kind].red
		var gears: int = CarSynth.ENGINES[kind].gears
		_expect(is_equal_approx(rpm_idle, CarSynth.ENGINES[kind].idle), "%s 서 있으면 공회전" % kind)
		var g1 := 1.0 / gears
		_expect(CarSynth.gear_rpm(kind, g1 * 0.3) < CarSynth.gear_rpm(kind, g1 * 0.9), "%s 1단 안에서 회전수가 오른다" % kind)
		_expect(CarSynth.gear_rpm(kind, g1 * 0.99) > CarSynth.gear_rpm(kind, g1 * 1.01), "%s 기어가 바뀌면 회전수가 떨어진다" % kind)
		var top := 0.0
		for i in 101:
			top = maxf(top, CarSynth.gear_rpm(kind, i / 100.0))
		_expect(top <= red, "%s 최고 회전수를 넘지 않는다 (%.0f)" % [kind, top])
	for kind: StringName in CarSynth.SIRENS:
		var s := CarSynth.siren_loop(kind)
		_check_loop(s, "사이렌 %s" % kind)
		var hz := _crossings(s) / (s.size() / CarSynth.MIX_RATE)
		var c: Dictionary = CarSynth.SIRENS[kind]
		_expect(hz > float(c.lo) and hz < float(c.hi), "사이렌 %s 높이가 %.0f~%.0fHz 사이 (평균 %.0f)" % [kind, c.lo, c.hi, hz])
	_check_loop(CarSynth.skid_loop(), "타이어 끌림")
	for kind: StringName in CarSynth.SHOTS:
		var s := CarSynth.render(kind)
		var top := 0.0
		for v in s:
			top = maxf(top, absf(v))
		_expect(top > 0.3 and top <= 1.0, "%s 크기 0.3~1 (%.2f)" % [kind, top])
		_expect(CarSynth.render(kind, 1) != s, "%s 변형은 조금 다르다" % kind)
	var crash := CarSynth.render(&"crash")
	var bump := CarSynth.render(&"bump")
	_expect(crash.size() > bump.size() and _rms(crash, 0, crash.size() / 3) > _rms(bump, 0, bump.size() / 3) * 0.9,
		"충돌이 부딪힘보다 크고 길다")
	var horn := CarSynth.render(&"horn")
	_expect(_rms(horn, horn.size() / 2, horn.size() / 2 + 2000) > _rms(horn, 200, 2200) * 0.6, "경적은 사그라지지 않고 이어진다")
	var kinds := {"car_avela": &"car", "bus_city": &"truck", "etc_bike": &"bike", "etc_bicycle": &"", "sp_heli": &"",
		"army_spg": &"tracked", "trk_tanker": &"truck", "police_patrol": &"car"}
	for id: String in kinds:
		var t: VehicleType = load("res://data/vehicles/%s.tres" % id)
		_expect(CarSynth.engine_kind(t) == kinds[id], "%s 엔진 종류 %s (%s)" % [id, kinds[id], CarSynth.engine_kind(t)])


## 되풀이 토막: 크기가 알맞고, 끝에서 처음으로 넘어가는 차이가 토막 안 이웃 샘플 차이보다 크지 않다 (이음매가 없다)
func _check_loop(s: PackedFloat32Array, name: String) -> void:
	var top := 0.0
	var step := 0.0
	for i in s.size():
		top = maxf(top, absf(s[i]))
		if i > 0:
			step = maxf(step, absf(s[i] - s[i - 1]))
	_expect(top > 0.2 and top <= 1.0, "%s 크기 0.2~1 (%.2f)" % [name, top])
	var seam := absf(s[0] - s[-1])
	_expect(seam <= step, "%s 이음매가 없다 (%.3f, 안쪽 가장 큰 차이 %.3f)" % [name, seam, step])


## 위로 올라가며 0을 지나는 횟수
func _crossings(s: PackedFloat32Array) -> float:
	var n := 0
	for i in range(1, s.size()):
		if s[i - 1] < 0.0 and s[i] >= 0.0:
			n += 1
	return n


func _test_car_sounds() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = 0
	main.bus_count = 0
	main.police_patrols = 0
	add_child(main)
	main.player.died.disconnect(main._on_died)
	await _frames(2)
	var sounds: CarSounds = main.car_sounds
	_expect(sounds != null, "본편에 차 소리 노드가 있다")
	if sounds == null:
		main.queue_free()
		return
	var at: Vector2 = City.start_position()
	var mine := _car(main, "car_avela", at, 0.0)
	main.director.enter_immediately(mine)
	var near := _car(main, "car_taxi", at + Vector2(0, 150), 0.0)
	near.has_driver = true
	var far := _car(main, "car_sonato", at + Vector2(0, 3000), 0.0)
	far.has_driver = true
	var cop := _car(main, "police_patrol", at + Vector2(200, 0), 0.0)
	cop.siren = true
	main.camera.global_position = at
	await _process_frames(20)
	_expect(sounds.engines[0] == mine, "주인공 차가 엔진 0번 자리")
	_expect(sounds.engines.has(near) and not sounds.engines.has(far), "가까운 NPC 차는 엔진 소리를 내고 먼 차는 아니다")
	_expect(sounds.sirens.has(cop), "경광등 켠 경찰차가 사이렌을 낸다")
	_expect(absf(float(sounds.rpm.get(mine, 0.0)) - CarSynth.ENGINES[&"car"].idle) < 50.0, "서 있는 주인공 차는 공회전 (%.0f)" % float(sounds.rpm.get(mine, 0.0)))
	mine.motor.velocity = Vector2.UP * mine.stats.max_speed * 0.15
	await _process_frames(20)
	_expect(float(sounds.rpm.get(mine, 0.0)) > CarSynth.ENGINES[&"car"].idle * 1.5, "달리면 회전수가 오른다 (%.0f)" % float(sounds.rpm.get(mine, 0.0)))
	# 창 모드로 돌렸을 때만: 토막을 다 구우면 엔진·사이렌 목소리가 실제로 운다
	if not sounds._silent:
		var loops := CarSynth.ENGINES.size() * 2 + CarSynth.SIRENS.size() + 1
		for i in 300:
			if sounds._loops.size() == loops:
				break
			await _process_frames(1)
		_expect(sounds._loops.size() == loops, "차 소리 토막을 5초 안에 다 굽는다 (%d/%d)" % [sounds._loops.size(), loops])
		await _process_frames(3)
		_expect(sounds._engine_players[0][0].playing, "주인공 차 엔진 소리가 난다")
		_expect(sounds._siren_players.any(func(p: AudioStreamPlayer): return p.playing), "사이렌 소리가 난다")
	cop.siren = false
	await _process_frames(2)
	_expect(not sounds.sirens.has(cop), "경광등을 끄면 사이렌도 멈춘다")
	# 경적
	var sfx := Sfx.current
	var piece: LanePiece = main.traffic.graph.segment(Vector2i(3, 3), 1)
	var honker: Vehicle = main.traffic.spawn_at(load("res://data/vehicles/car_sorea.tres"), piece, 10.0)
	main.camera.global_position = honker.global_position
	honker.ai.honking = true
	sounds._horns(honker.global_position)
	_expect(_last(sfx) == &"horn", "NPC 차가 경적을 울리면 빵 (%s)" % _last(sfx))
	var n := sfx.heard.size()
	sounds._horns(honker.global_position)
	_expect(sfx.heard.size() == n, "경적은 울리기 시작할 때 한 번")
	main.camera.global_position = at
	# 벽에 박기: 주인공 차를 건물 쪽으로 세게
	main.director.exit_vehicle()
	await _frames(70)   # 같은 곳 같은 소리 거르기(SAME_GAP)를 넘기게
	var wall := _wall_point(mine)
	if wall != Vector2.INF:
		var from := wall
		while _blocked(mine, from):
			from.y -= 8.0
		mine.place(from + Vector2(0, -40), PI)
		await _frames(2)
		mine.motor.velocity = Vector2.DOWN * 600.0
		for i in 30:
			await _frames(1)
			if _heard(sfx, &"crash"):
				break
		_expect(_heard(sfx, &"crash"), "벽에 세게 박으면 충돌 소리")
	main.queue_free()
	await _frames(2)


func _car(main: Node2D, id: String, pos: Vector2, heading: float) -> Vehicle:
	var v := Vehicle.new()
	v.stats = load("res://data/vehicles/%s.tres" % id)
	main.add_child(v)
	v.place(pos, heading)
	main.vehicles.append(v)
	return v


## 강남 (3,3) 블록에서 건물에 걸리는 점 (없으면 INF)
func _wall_point(v: Vehicle) -> Vector2:
	var block := City.block_rect(3, 3)
	for j in 12:
		for i in 12:
			var p := block.position + block.size * Vector2((i + 0.5) / 12.0, (j + 0.5) / 12.0)
			if _blocked(v, p):
				return p
	return Vector2.INF


## 차 모양을 pos에 놓으면 건물·벽에 걸리는가
func _blocked(v: Vehicle, pos: Vector2) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = v._shape.shape
	q.transform = Transform2D(v.rotation, pos)
	q.collision_mask = Layers.at(Layers.WORLD, v.level)
	return not v.get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


func _heard(sfx: Sfx, kind: StringName) -> bool:
	for h: Array in sfx.heard.slice(-8):
		if h[0] == kind:
			return true
	return false


func _process_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _last(sfx: Sfx) -> StringName:
	return sfx.heard[-1][0] if not sfx.heard.is_empty() else &""


func _rms(s: PackedFloat32Array, a: int, b: int) -> float:
	var sum := 0.0
	for i in range(a, b):
		sum += s[i] * s[i]
	return sqrt(sum / maxi(b - a, 1))


## 150Hz 아래 소리가 차지하는 몫 (두 번 거른 낮은 소리의 힘 / 전체 힘)
func _low_share(s: PackedFloat32Array) -> float:
	var a := 1.0 - exp(-TAU * 150.0 / GunSynth.MIX_RATE)
	var l1 := 0.0
	var l2 := 0.0
	var low := 0.0
	var all := 0.0
	for v in s:
		l1 += (v - l1) * a
		l2 += (l1 - l2) * a
		low += l2 * l2
		all += v * v
	return low / all


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
