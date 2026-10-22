extends Node
## 말풍선 대사 CSV(Dialogue)와 랜덤 거리 이벤트(StreetEvents·StreetCriminal) 검증.
##  1. 대사: lines.csv를 읽는다(쉼표 든 대사·주석 줄), 거리에 나오는 사람·이벤트 상황마다 대사가 있다,
##     없는 사람은 * 줄을 쓴다, 영어 칸이 비면 한국어, 같은 salt면 같은 줄.
##  2. 이벤트 데이터: 범인·보상이 있고, 달아나는 빠르기가 주인공 달리기보다 느리다.
##  3. 소매치기: 피해자 뒤에서 나타나 낚아채고(대사·알림) 주인공에게서 멀어진다. 주먹으로 넘어뜨리면
##     보상·수배 −1, 시민을 친 범죄로 치지 않는다. 엎드려 항복한다.
##  4. 강도: 위협하는 동안 피해자를 붙잡아 두고, 주인공이 다가오면 들켜 달아난다. 죽여서 막으면 보상 절반.
##  5. 멀어지면 놓친다. 수배 ★2 이상·미션 중에는 벌어지지 않는다. 곁에 서 있으면 시민이 CSV 대사로 말한다.
## 실행: godot --headless --fixed-fps 60 --path . res://tests/street_event_test.tscn

const THIEF: StreetEventType = preload("res://data/events/thief.tres")
const ROBBER: StreetEventType = preload("res://data/events/robber.tres")
const CIV: NpcType = preload("res://data/npc/civ_m.tres")
const FIST: WeaponType = preload("res://data/weapons/fist.tres")

var _failures: Array[String] = []


func _ready() -> void:
	_test_dialogue()
	_test_data()
	await _test_in_game()
	if _failures.is_empty():
		print("street_event_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _test_dialogue() -> void:
	Dialogue.reload()
	_expect(Dialogue.lines(&"ELDER", &"talk").has("젊은이, 천천히 다녀"), "쉼표가 든 대사를 한 줄로 읽는다")
	_expect(not Dialogue.has(&"#", &"talk"), "주석 줄은 대사가 아니다")
	for npc: NpcType in PedestrianManager.NPC_TYPES:
		_expect(Dialogue.has(npc.id, &"talk"), "%s는 곁에 서 있으면 할 말이 있다" % npc.id)
	for s: StringName in [&"flee", &"taxi", &"robbed", &"held", &"thanks"]:
		_expect(Dialogue.has(&"CIV_M", s), "시민은 %s 대사가 있다 (* 줄)" % s)
	for e: StreetEventType in StreetEvents.EVENTS:
		for s: StringName in [&"escape", &"caught", &"snatch" if e.act_time <= 0.0 else &"threat"]:
			_expect(Dialogue.has(e.npc.id, s), "%s 범인은 %s 대사가 있다" % [e.id, s])
		_expect(Dialogue.has(&"CIV_F", e.victim_situation), "%s 피해자 대사 %s" % [e.id, e.victim_situation])
	_expect(Dialogue.lines(&"POLICE", &"talk").is_empty(), "talk에는 * 줄이 없다 — 대사 없는 사람은 말하지 않는다")
	_expect(Dialogue.pick(&"MERCHANT", &"talk", 7) == Dialogue.pick(&"MERCHANT", &"talk", 7), "같은 salt면 같은 줄")
	_expect(Dialogue.pick(&"MERCHANT", &"talk", 0) != Dialogue.pick(&"MERCHANT", &"talk", 1), "salt가 다르면 다른 줄")
	Dialogue.lang = "en"
	_expect(Dialogue.pick(&"*", &"flee", 0) == "Run!", "영어 칸 (%s)" % Dialogue.pick(&"*", &"flee", 0))
	Dialogue.lang = "xx"
	_expect(Dialogue.pick(&"*", &"flee", 0) == "도망쳐!", "없는 언어는 한국어")
	Dialogue.lang = "ko"


func _test_data() -> void:
	for e: StreetEventType in StreetEvents.EVENTS:
		_expect(e.npc != null and e.reward > 0 and e.start_text != "", "%s 범인·보상·알림" % e.id)
		_expect(e.flee_speed < Player.RUN_SPEED, "%s는 주인공 달리기보다 느리게 달아난다" % e.id)
	_expect(ROBBER.npc.weapon != null and ROBBER.act_time > 0.0, "강도는 총을 들고 위협한다")


func _test_in_game() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = 0
	main.bus_count = 0
	main.police_patrols = 0
	main.save_prefix = "user://street_event_test_save_"
	add_child(main)
	await _frames(10)
	var events: StreetEvents = main.street_events
	events.enabled = false
	var player: Player = main.player
	var police: PoliceDispatcher = main.police
	var log := []
	events.started.connect(func(e: StreetEventType, _c: StreetCriminal): log.append(["started", e.id]))
	events.resolved.connect(func(e: StreetEventType, pay: int, alive: bool): log.append(["resolved", e.id, pay, alive]))
	events.failed.connect(func(e: StreetEventType): log.append(["failed", e.id]))
	var block := City.nearest_block(player.global_position)

	# ── 소매치기 ──
	var victim := _civilian(main, block, player.global_position, 260.0)
	var thief := events.start(THIEF, victim)
	_expect(thief != null and events.criminal == thief, "도둑이 나타난다")
	_expect(thief.global_position.distance_to(victim.global_position) > 30.0, "피해자 뒤 인도에서 나타난다")
	for i in 300:
		await _frames(1)
		if thief.phase == StreetCriminal.Phase.ESCAPE:
			break
	_expect(thief.phase == StreetCriminal.Phase.ESCAPE, "낚아채고 달아난다")
	_expect(log.has(["started", &"thief"]), "낚아챌 때 알린다")
	_expect(Dialogue.lines(&"*", &"robbed").has(victim.speech), "피해자가 외친다 (%s)" % victim.speech)
	_expect(Dialogue.lines(&"THIEF", &"snatch").has(thief.speech) or Dialogue.lines(&"THIEF", &"escape").has(thief.speech),
		"도둑이 말한다 (%s)" % thief.speech)
	_expect(events.target_position() != Vector2.INF, "미니맵에 쫓을 범인이 뜬다")
	var d0 := thief.global_position.distance_to(player.global_position)
	var from := thief.global_position
	await _frames(150)
	_expect(thief.global_position.distance_to(from) > 250.0, "달아난다 (%.0f px)" % thief.global_position.distance_to(from))
	_expect(thief.global_position.distance_to(player.global_position) > d0, "주인공에게서 멀어진다")
	police.wanted.raise_to(1)
	var money: int = main.wallet.money
	main.pedestrians.damage(thief, FIST.damage, thief.global_position - player.global_position, true, true)
	await _frames(2)
	_expect(log.has(["resolved", &"thief", THIEF.reward, true]), "주먹으로 넘어뜨리면 검거 (%s)" % [log])
	_expect(main.wallet.money == money + THIEF.reward, "보상 ₩%d" % THIEF.reward)
	_expect(police.wanted.level == 0, "수배 −1 (★%d), 범인을 친 건 범죄가 아니다" % police.wanted.level)
	_expect(thief.phase == StreetCriminal.Phase.CAUGHT and thief.state == Pedestrian.State.KNOCKED, "엎드려 항복한다")
	_expect(events.criminal == null and events.target_position() == Vector2.INF, "이벤트가 끝난다")
	await _frames(240)
	_expect(thief.state == Pedestrian.State.KNOCKED, "항복한 범인은 일어나 달아나지 않는다")

	# ── 강도 ──
	victim = _civilian(main, block, player.global_position, 300.0)
	var robber := events.start(ROBBER, victim)
	for i in 300:
		await _frames(1)
		if robber.phase == StreetCriminal.Phase.ACT:
			break
	_expect(robber.phase == StreetCriminal.Phase.ACT, "강도가 피해자를 위협한다")
	await _frames(60)
	_expect(robber.phase == StreetCriminal.Phase.ACT and victim.state == Pedestrian.State.IDLE, "위협하는 동안 피해자는 꼼짝 못 한다")
	_expect(Dialogue.lines(&"ROBBER", &"threat").has(robber.speech), "강도 대사 (%s)" % robber.speech)
	_expect(Dialogue.lines(&"*", &"held").has(victim.speech), "붙잡힌 사람 대사 (%s)" % victim.speech)
	player.global_position = robber.global_position + (player.global_position - robber.global_position).normalized() * 120.0
	await _frames(3)
	_expect(robber.alerted and robber.phase == StreetCriminal.Phase.ESCAPE, "주인공이 다가오면 들켜 달아난다")
	money = main.wallet.money
	main.pedestrians.damage(robber, 999.0, robber.global_position - player.global_position, true, false)
	await _frames(2)
	var half := roundi(ROBBER.reward * ROBBER.kill_reward_scale)
	_expect(log.has(["resolved", &"robber", half, false]), "죽여서 막으면 보상 절반 (%s)" % [log])
	_expect(main.wallet.money == money + half, "보상 ₩%d" % half)
	_expect(police.wanted.level == 0, "강도를 죽인 건 시민 살해가 아니다 (★%d)" % police.wanted.level)
	player.revive()

	# ── 놓치기 ──
	victim = _civilian(main, block, player.global_position, 240.0)
	var lost := events.start(THIEF, victim)
	for i in 300:
		await _frames(1)
		if lost.phase == StreetCriminal.Phase.ESCAPE:
			break
	player.global_position = lost.global_position + Vector2(THIEF.give_up_distance + 100.0, 0.0)
	await _frames(3)
	_expect(log.has(["failed", &"thief"]) and events.criminal == null, "멀어지면 놓친다")
	_expect(lost.phase == StreetCriminal.Phase.GONE and not lost.offender(), "놓친 도둑은 더는 쫓는 범인이 아니다")
	player.global_position = victim.global_position + Vector2(0, -200)

	# ── 벌어지는 조건 ──
	_expect(events.can_start(), "평소에는 벌어질 수 있다")
	police.wanted.raise_to(2)
	_expect(not events.can_start(), "수배 ★2면 안 벌어진다")
	police.wanted.clear()
	events.enabled = true
	events._wait = 0.0
	await _frames(2)
	_expect(events.criminal != null, "때가 되면 주인공 근처 시민에게 벌어진다")

	# ── 곁에 서 있으면 말한다 ──
	var talker := _civilian(main, block, player.global_position, 30.0)
	talker._set_state(Pedestrian.State.IDLE, 999.0)
	player.global_position = talker.global_position + Vector2(20, 0)
	player.velocity = Vector2.ZERO
	main.pedestrians._talked.clear()
	main.pedestrians._still = PedestrianManager.TALK_DELAY
	main.pedestrians._talk(0.0)
	var spoke := false
	for p in main.pedestrians.peds:
		if p.speech_time > 0.0 and Dialogue.lines(p.npc.id, &"talk").has(p.speech):
			spoke = true
	_expect(spoke, "CSV 대사로 말한다 (%s)" % talker.speech)
	main.queue_free()
	await _frames(2)


## block 인도에서 pos와 거의 dist만큼 떨어진 자리에 걷는 시민을 세운다
func _civilian(main: Node2D, block: Vector2i, pos: Vector2, dist: float) -> Pedestrian:
	var best := Vector2.INF
	var best_edge := 0
	var best_t := 0.0
	for b: Vector2i in [block, block + Vector2i(1, 0), block + Vector2i(0, 1), block + Vector2i(-1, 0), block + Vector2i(0, -1)]:
		if not CityMap.is_open_block(b):
			continue
		var loop := City.sidewalk_loop(b)
		for edge in 4:
			for k in range(6, 15):   # 모퉁이는 빼고
				var t := k / 20.0
				var p := loop[edge].lerp(loop[(edge + 1) % 4], t)
				if best == Vector2.INF or absf(p.distance_to(pos) - dist) < absf(best.distance_to(pos) - dist):
					best = p
					block = b
					best_edge = edge
					best_t = t
	var ped := Pedestrian.new()
	var rng := RandomNumberGenerator.new()
	ped.setup(CIV, rng, City.sidewalk_loop(block), best_edge, best_t, 1)
	main.pedestrians.add(ped)
	return ped


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
