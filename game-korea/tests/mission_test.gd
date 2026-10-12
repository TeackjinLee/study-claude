extends Node
## M5·M6 미션·갱 검증.
##  1. 존경도 계산: 범위, 전화 단계(쉬움·보통·어려움), 적대·아군.
##  2. 미션 단계 계산: 도착·탑승·배달·표적·수배 해제, 시간 초과·차 파손 실패.
##  3. 미션 데이터 60개: 갱·공중전화 묶음마다 쉬움 4·보통 3·어려움 3, 단계마다 필요한 칸이 있고,
##     지점이 건물 안·강물·그 장에 잠긴 구역이 아니다.
##  4. 공중전화: 밟으면 미션이 시작되고, 존경도가 모자란 전화는 잠겨 있다.
##  5. 1장부터 엔딩까지 미션 60개를 실제로 진행: 성공하면 돈·존경도, 보상으로 장이 열려 엔딩까지 간다.
##  6. 실패: 시간 초과, 차가 너무 망가짐, 사망. 실패한 미션은 다시 받을 수 있다.
##  7. 갱: 미션 경호원과 적대한 조직원은 주인공을 쏜다. 조직원을 죽이면 존경도가 깎이고 동료가 화를 낸다.
##  8. 운전 미션(배달·시운전·차 회수)은 자동 운전 봇이 교통 속에서 실제로 몰아도 제한 시간의 65% 안에 끝난다.
##     기본은 대표 몇 개, `-- --all-drives`면 운전 미션 전부.
##  9. 은신처 발판 → 슬롯 메뉴(게임 멈춤) → 슬롯 1~3에 따로 저장 → 새 게임에서 슬롯을 골라 불러오기.
##     수배 중에는 메뉴가 안 열리고, 빈 슬롯은 불러올 수 없다.
## 실행: godot --headless --fixed-fps 60 --path . res://tests/mission_test.tscn [-- --all-drives]

const GANGNAM: GangType = preload("res://data/gangs/gangnam.tres")
const OLDTOWN: GangType = preload("res://data/gangs/oldtown.tres")
const PISTOL: WeaponType = preload("res://data/weapons/pistol.tres")
const SAVE_PREFIX := "user://mission_test_save_"

var _failures: Array[String] = []


func _ready() -> void:
	_test_respect()
	_test_run_logic()
	_test_data()
	await _test_phones()
	await _test_all_missions()
	await _test_failures()
	await _test_gang()
	await _test_drive_missions()
	await _test_save_load()
	_remove_saves()
	if _failures.is_empty():
		print("mission_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _make_main(cars := 0, patrols := 0) -> Node2D:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = cars
	main.bus_count = 0
	main.police_patrols = patrols
	main.save_prefix = SAVE_PREFIX
	add_child(main)
	return main


func _free(main: Node2D) -> void:
	main.queue_free()
	await _frames(2)


# ── 순수 계산 ─────────────────────────────────────────────

func _test_respect() -> void:
	var r := Respect.new()
	_expect(r.of(&"gangnam") == 0, "존경도는 0에서 시작")
	_expect(r.tier_open(GANGNAM, 0) and not r.tier_open(GANGNAM, 1), "처음엔 쉬운 전화만 열린다")
	r.change(&"gangnam", GANGNAM.normal_respect)
	_expect(r.tier_open(GANGNAM, 1) and not r.tier_open(GANGNAM, 2), "존경도 %d면 보통 전화가 열린다" % GANGNAM.normal_respect)
	r.change(&"gangnam", 500)
	_expect(r.of(&"gangnam") == Respect.MAX and r.is_ally(GANGNAM), "존경도는 100에서 멈추고, 높으면 아군")
	r.change(&"gangnam", -500)
	_expect(r.of(&"gangnam") == Respect.MIN and r.is_hostile(GANGNAM), "존경도는 -100에서 멈추고, 낮으면 적대")


func _test_run_logic() -> void:
	var goto := MissionStep.new()
	goto.kind = MissionStep.Kind.GOTO
	goto.points = PackedVector2Array([Vector2(100, 0)])
	goto.radius = 30.0
	_expect(not MissionRun.step_done(goto, {"pos": Vector2.ZERO}), "멀면 도착이 아니다")
	_expect(MissionRun.step_done(goto, {"pos": Vector2(80, 0)}), "반경 안이면 도착")
	goto.need_vehicle = true
	_expect(not MissionRun.step_done(goto, {"pos": Vector2(80, 0), "in_vehicle": false}), "체크포인트는 미션 차로 지나야 한다")

	var deliver := MissionStep.new()
	deliver.kind = MissionStep.Kind.DELIVER
	deliver.points = PackedVector2Array([Vector2.ZERO])
	deliver.min_health = 0.5
	_expect(not MissionRun.step_done(deliver, {"pos": Vector2.ZERO, "in_vehicle": true, "speed": 400.0}), "달리면서 지나가면 배달이 아니다")
	_expect(MissionRun.step_done(deliver, {"pos": Vector2.ZERO, "in_vehicle": true, "speed": 10.0}), "세우면 배달")

	var kill := MissionStep.new()
	kill.kind = MissionStep.Kind.KILL
	_expect(not MissionRun.step_done(kill, {"targets_left": 1}) and MissionRun.step_done(kill, {"targets_left": 0}), "표적이 다 쓰러져야 끝")
	var lose := MissionStep.new()
	lose.kind = MissionStep.Kind.LOSE_WANTED
	_expect(MissionRun.step_done(lose, {"wanted": 0}) and not MissionRun.step_done(lose, {"wanted": 2}), "수배가 0이어야 끝")

	var enter := MissionStep.new()
	enter.kind = MissionStep.Kind.ENTER
	var m := MissionType.new()
	m.time_limit = 10.0
	m.steps = [enter, deliver]
	var run := MissionRun.new(m)
	var result := []
	run.finished.connect(func(passed, reason): result.append([passed, reason]))
	run.update(1.0, {"vehicle_lost": true})
	_expect(run.running(), "ENTER 단계에선 차가 아직 없으니 실패가 아니다")
	run.update(1.0, {"in_vehicle": true})
	_expect(run.step == 1 and run.needs_vehicle(), "타면 다음 단계, 이제 차가 필요하다")
	run.update(1.0, {"in_vehicle": true, "vehicle_health": 0.4})
	_expect(not run.running() and result == [[false, "차가 너무 망가졌다"]], "체력이 기준 밑이면 실패 (%s)" % [result])

	run = MissionRun.new(m)
	run.update(1.0, {"in_vehicle": true})
	run.update(9.5, {"in_vehicle": true})
	_expect(run.state == MissionRun.State.FAILED and run.fail_reason == "시간 초과", "제한 시간이 지나면 실패")
	run = MissionRun.new(m)
	run.update(1.0, {"in_vehicle": true})
	run.update(1.0, {"in_vehicle": false, "vehicle_lost": true})
	_expect(run.fail_reason == "차가 부서졌다", "미션 차가 부서지면 실패")
	run = MissionRun.new(m)
	run.update(1.0, {"in_vehicle": true})
	run.update(1.0, {"in_vehicle": true, "pos": Vector2.ZERO, "speed": 0.0})
	_expect(run.state == MissionRun.State.PASSED, "마지막 단계를 끝내면 성공")


func _test_data() -> void:
	var counts := {}                 ## "갱/묶음" → [쉬움, 보통, 어려움]
	var city := City.new()
	city._build_layout()
	var water := City.water_rects()
	var ids := {}
	for m in MissionSystem.MISSIONS:
		var g := _gang(m.gang)
		_expect(g != null and g.phones.size() >= (m.phone_set + 1) * 3, "%s: 갱과 공중전화 묶음이 있다" % m.id)
		if g == null:
			continue
		var key := "%s/%d" % [m.gang, m.phone_set]
		if not counts.has(key):
			counts[key] = [0, 0, 0]
		counts[key][m.tier] += 1
		_expect(not ids.has(m.id), "미션 id가 겹친다: %s" % m.id)
		ids[m.id] = true
		_expect(m.reward > 0 and m.respect > 0 and not m.steps.is_empty(), "%s: 보상·단계" % m.id)
		# 공중전화가 있는 구역이 열리는 장 — 미션 지점은 그때 열린 곳이어야 한다
		var chapter := CityMap.district_at(g.phones[m.phone_set * 3]).chapter
		for s in m.steps:
			match s.kind:
				MissionStep.Kind.GOTO, MissionStep.Kind.DELIVER:
					_expect(s.points.size() == 1, "%s: 도착 지점 하나" % m.id)
				MissionStep.Kind.ENTER, MissionStep.Kind.DESTROY:
					_expect(s.vehicle != null and not s.points.is_empty(), "%s: 차종과 자리" % m.id)
				MissionStep.Kind.KILL:
					_expect(s.npc != null and not s.npc_points.is_empty(), "%s: 표적과 자리" % m.id)
			for p in Array(s.points) + Array(s.npc_points):
				var bad := not City.world_rect().has_point(p)
				for b in city.buildings:
					bad = bad or b.grow(4.0).has_point(p)
				for w in water:
					bad = bad or w.has_point(p)
				_expect(not bad, "%s: 지점 %s가 건물 안·강물·맵 밖" % [m.id, p])
				var d := CityMap.district_at(p)
				_expect(d == null or d.chapter <= chapter, "%s: 지점 %s(%s)는 %d장에 아직 잠겨 있다" % [m.id, p, d.display_name if d else "", chapter])
	city.free()
	_expect(MissionSystem.MISSIONS.size() == 60, "미션 60개 (%d)" % MissionSystem.MISSIONS.size())
	for key: String in counts:
		_expect(counts[key] == [4, 3, 3], "%s: 쉬움 4·보통 3·어려움 3 (%s)" % [key, counts[key]])
	_expect(counts.size() == 6, "갱 3파 × 공중전화 묶음 2 (%s)" % [counts.keys()])


func _gang(id: StringName) -> GangType:
	for g: GangType in preload("res://scripts/main.gd").GANGS:
		if g.id == id:
			return g
	return null


# ── 공중전화 ──────────────────────────────────────────────

func _test_phones() -> void:
	var main := _make_main()
	await _frames(2)
	var missions: MissionSystem = main.missions
	var player: Player = main.player
	var refused := []
	missions.phone_refused.connect(func(t): refused.append(t))
	player.global_position = GANGNAM.phones[1]
	await _frames(2)
	_expect(not missions.active() and refused.size() == 1, "존경도 0이면 보통 전화는 잠겨 있다 (%s)" % [refused])
	_expect(missions.phone_prompt().contains("존경도"), "잠긴 전화 앞 안내: %s" % missions.phone_prompt())
	player.global_position = GANGNAM.phones[0] + Vector2(0, -40)
	await _frames(2)
	_expect(missions.phone_prompt().contains("첫 심부름"), "쉬운 전화 앞 안내에 다음 미션 이름 (%s)" % missions.phone_prompt())
	player.global_position = GANGNAM.phones[0]
	await _frames(2)
	_expect(missions.active() and missions.run.mission.id == &"gangnam_01", "쉬운 전화를 밟으면 첫 미션이 시작된다")
	_expect(main.hud.banner_visible(), "미션 제목이 화면에 뜬다")
	await _free(main)


# ── 미션 10개 진행 ────────────────────────────────────────

## 1장부터 엔딩까지: 장이 열리는 순서대로 공중전화 묶음의 미션을 다 끝내면, 보상만으로 다음 장이 열리고
## 마지막 장 목표(엔딩)에 닿는다. 전화 단계는 앞 미션들(라이벌 감점 포함)을 끝낸 존경도로 열려야 한다.
func _test_all_missions() -> void:
	var main := _make_main()
	await _frames(2)
	var missions: MissionSystem = main.missions
	var respect: Respect = main.respect
	var wallet: Wallet = main.wallet
	var money := wallet.money
	for pair in [[&"gangnam", 0], [&"oldtown", 0], [&"smuggler", 0], [&"gangnam", 1], [&"oldtown", 1], [&"smuggler", 1]]:
		var g := _gang(pair[0])
		var set: int = pair[1]
		var need := CityMap.district_at(g.phones[set * 3]).chapter
		_expect(main.chapter >= need, "%s %d묶음 전에 %d장이 열려 있다 (지금 %d장, ₩%d)" % [g.display_name, set, need, main.chapter, wallet.money])
		for tier in 3:
			while true:
				var m := missions.next_mission(g, tier, set)
				if m == null:
					break
				_expect(respect.tier_open(g, tier), "%s: %d단계 전화가 열려 있다 (존경도 %d)" % [m.id, tier, respect.of(g.id)])
				var before := respect.of(g.id)
				var passed := await _play(main, m)
				_expect(passed, "%s %s 성공" % [m.id, m.title])
				if not passed:
					await _free(main)
					return
				money += m.reward
				# 체포·사망 없이 끝내므로 보상이 그대로 쌓인다 (라이벌 조직원을 죽이면 존경도가 그만큼 더 오른다)
				_expect(wallet.money == money, "%s: 보상 %d원 (지갑 %d)" % [m.id, m.reward, wallet.money])
				_expect(respect.of(g.id) >= mini(before + m.respect, Respect.MAX) - 6, "%s: 존경도 +%d (%d → %d)" % [m.id, m.respect, before, respect.of(g.id)])
				await _frames(3)
		print("  %s %d묶음 끝: %d장, ₩%s, 존경도 %s" % [g.display_name, set, main.chapter, Hud.won(wallet.money), respect.values])
	_expect(missions.completed.size() == 60, "미션 60개를 모두 끝냈다 (%d)" % missions.completed.size())
	_expect(main.finished, "마지막 장 목표를 모아 엔딩을 봤다 (₩%s)" % Hud.won(wallet.money))
	await _free(main)


## 미션 하나를 '치트'로 끝까지 진행한다: 지점으로 순간 이동, 미션 차에 바로 타기, 표적은 주인공이 쏜 것으로 처리.
func _play(main: Node2D, m: MissionType) -> bool:
	var missions: MissionSystem = main.missions
	var director: Director = main.director
	var player: Player = main.player
	var police: PoliceDispatcher = main.police
	missions.start(m)
	await _frames(1)
	var guard := 0
	while missions.active() and guard < 60 * 30:
		guard += 1
		var s := missions.run.current()
		match s.kind:
			MissionStep.Kind.GOTO:
				await _arrive(main, s.points[0])
			MissionStep.Kind.ENTER:
				director.enter_immediately(missions.vehicle)
			MissionStep.Kind.DELIVER:
				await _arrive(main, s.points[0])
			MissionStep.Kind.KILL:
				for t in missions.targets:
					if is_instance_valid(t) and not t.is_dead():
						main.pedestrians.damage(t, 1000.0, Vector2.UP, true, false)
			MissionStep.Kind.DESTROY:
				if s.moving:
					var v: Vehicle = missions.targets[0]
					var from := v.global_position
					await _frames(120)
					_expect(v.global_position.distance_to(from) > 100.0, "%s: 표적 차는 도로를 달린다" % m.id)
				for t in missions.targets:
					if is_instance_valid(t) and not t.wrecked:
						t.take_damage(1000.0, true, 0.1)
				await _frames(20)
			MissionStep.Kind.LOSE_WANTED:
				_expect(police.wanted.level >= s.wanted, "%s: 수배 ★%d가 붙는다" % [m.id, s.wanted])
				police.wanted.clear()
		await _frames(2)
	if player.is_dead():
		printerr("  %s: 주인공이 죽었다" % m.id)
	if missions.run and not missions.run.running() and missions.run.state == MissionRun.State.FAILED:
		printerr("  %s 실패: %s" % [m.id, missions.run.fail_reason])
	director.exit_vehicle()
	return missions.run.state == MissionRun.State.PASSED


## 지금 조종하는 것(차·사람)을 그 자리로 옮겨 세운다
func _arrive(main: Node2D, at: Vector2) -> void:
	var v: Vehicle = main.director.current_vehicle
	if v:
		v.global_position = at
		v.motor.velocity = Vector2.ZERO
	else:
		main.player.global_position = at
	await _frames(2)


# ── 실패 ──────────────────────────────────────────────────

func _test_failures() -> void:
	var main := _make_main()
	await _frames(2)
	var missions: MissionSystem = main.missions
	var respect: Respect = main.respect
	var director: Director = main.director
	var results := []
	missions.mission_finished.connect(func(_m, passed, reason): results.append([passed, reason]))

	# 시간 초과
	var race := missions.by_id(&"gangnam_04")
	missions.start(race)
	await _frames(2)
	_expect(missions.vehicle != null and missions.objective_position() != null, "시운전: 미션 차가 세워지고 목표 위치가 있다")
	missions.run.elapsed = race.time_limit - 0.01
	await _frames(3)
	_expect(results.back() == [false, "시간 초과"], "시간이 다 되면 실패 (%s)" % [results])
	_expect(not missions.completed.has(&"gangnam_04") and missions.next_mission(GANGNAM, 0) != null, "실패한 미션은 다시 받을 수 있다")
	var leftover := missions.vehicle
	main.camera.target = null
	main.camera.global_position = Vector2(200, 200)
	await _frames(70)
	_expect(missions._leftovers.is_empty(), "실패 뒤 남은 미션 차는 화면 밖에서 치운다")
	main.camera.target = main.player
	main.camera.snap()

	# 회수할 차가 너무 망가짐
	respect.change(&"gangnam", GANGNAM.normal_respect)
	missions.start(missions.by_id(&"gangnam_05"))
	await _frames(2)
	var car := missions.vehicle
	_expect(car.has_driver, "제니스에는 운전자가 타고 있다")
	director.enter_immediately(car)
	await _frames(2)
	_expect(missions.run.step == 1, "빼앗으면 다음 단계")
	car.take_damage(car.stats.durability * 0.4, true)
	await _frames(2)
	_expect(results.back() == [false, "차가 너무 망가졌다"], "차 체력이 70%% 밑이면 실패 (%s)" % [results])
	director.exit_vehicle()
	await _frames(2)

	# 사망
	missions.start(missions.by_id(&"gangnam_01"))
	await _frames(2)
	main.player.take_damage(Player.MAX_HEALTH)
	await _frames(int(main.BUST_DELAY * 60) + 10)
	_expect(results.back() == [false, "사망"] and not missions.active(), "죽으면 미션 실패")
	_expect(main.player.global_position.distance_to(City.hospital_position()) < 5.0, "병원에서 다시 시작")
	await _free(main)


# ── 갱 ────────────────────────────────────────────────────

func _test_gang() -> void:
	var main := _make_main()
	await _frames(2)
	var gangs: GangManager = main.gangs
	var respect: Respect = main.respect
	var player: Player = main.player
	var residents: Array[GangMember] = []
	for m in gangs.members:
		if m.resident and m.gang == GANGNAM:
			residents.append(m)
	_expect(residents.size() == GANGNAM.member_count, "강남 조직원 %d명이 구역을 돈다 (%d)" % [GANGNAM.member_count, residents.size()])
	_expect(not main.pedestrians.is_alive_civilian(residents[0]), "조직원은 시민 수에 들지 않는다")

	# 평소(존경도 0)엔 쏘지 않는다
	var shots := [0]
	main.combat.gunfire.connect(func(_p, by_player): if not by_player: shots[0] += 1)
	var a := residents[0]
	var b := residents[1]
	a.global_position = player.global_position + Vector2(0, -120)
	b.global_position = player.global_position + Vector2(0, -170)
	await _frames(120)
	_expect(shots[0] == 0, "존경도 0인 조직원은 쏘지 않는다 (%d발)" % shots[0])

	# 하나를 죽이면 존경도가 깎이고, 옆 동료가 화가 나서 쏜다
	main.pedestrians.damage(a, 1000.0, Vector2.UP, true, false)
	_expect(respect.of(&"gangnam") == -GANGNAM.kill_penalty, "조직원을 죽이면 존경도 -%d (%d)" % [GANGNAM.kill_penalty, respect.of(&"gangnam")])
	_expect(b.aggro > 0.0, "옆 동료가 화가 난다")
	for f in 240:
		await _frames(1)
		if player.health < Player.MAX_HEALTH:
			break
	_expect(shots[0] > 0 and player.health < Player.MAX_HEALTH, "화난 조직원이 쏜다 (%d발, 체력 %.0f)" % [shots[0], player.health])

	# 존경도가 적대 수준이면 보이는 대로 쏜다
	gangs.calm()
	player.revive()
	respect.set_value(&"gangnam", GANGNAM.hostile_respect)
	var c := residents[2]
	c.global_position = player.global_position + Vector2(0, -150)
	_expect(gangs.is_hostile(c), "존경도 %d면 적대" % GANGNAM.hostile_respect)
	shots[0] = 0
	await _frames(150)
	_expect(shots[0] > 0, "적대한 갱은 화나지 않아도 쏜다 (%d발)" % shots[0])

	# 미션 경호원은 존경도와 상관없이 다가오면 쏜다
	gangs.calm()
	player.revive()
	respect.set_value(&"gangnam", 50)
	main.missions.start(main.missions.by_id(&"gangnam_06"))
	await _frames(2)
	var target: GangMember = main.missions.targets[0]
	_expect(target.guard and gangs.is_hostile(target), "미션 표적은 싸운다")
	player.global_position = target.global_position + Vector2(0, -200)
	shots[0] = 0
	for f in 240:
		await _frames(1)
		if player.health < Player.MAX_HEALTH:
			break
	_expect(shots[0] > 0 and player.health < Player.MAX_HEALTH, "경호원이 주인공을 쏜다 (%d발)" % shots[0])
	_expect(target.global_position.distance_to(player.global_position) < 200.0, "경호원이 다가온다")
	main.missions.fail("테스트")
	await _frames(2)
	_expect(not target.guard, "미션이 끝나면 경호원은 평범한 조직원이 된다")

	# 아군이면 때려도 참는다
	gangs.calm()
	respect.set_value(&"gangnam", GANGNAM.ally_respect)
	var d := residents[3]
	main.pedestrians.damage(d, 5.0, Vector2.UP, true, true)
	_expect(d.aggro == 0.0 and not gangs.is_hostile(d), "아군 조직원은 맞아도 화내지 않는다")
	await _frames(int(GangManager.MAINTAIN_INTERVAL * 60) + 5)
	var alive := 0
	for m in gangs.members:
		if m.resident and m.gang == GANGNAM and not m.is_dead():
			alive += 1
	_expect(alive == GANGNAM.member_count, "죽은 조직원 대신 새 조직원이 생긴다 (%d)" % alive)
	await _free(main)


# ── 실제 운전 ─────────────────────────────────────────────

## 봇이 미션 목표를 따라 실제 키 입력으로 운전한다. 걷는 구간만 순간 이동.
## 기본은 대표 몇 개만, `-- --all-drives`면 운전만으로 끝나는 미션 전부 (미션 지점·시간을 고쳤을 때)
const DRIVE_SAMPLE: Array[StringName] = [&"gangnam_02", &"gangnam_04", &"gangnam_05", &"gangnam_13", &"oldtown_06", &"smuggler_02"]


func _drive_ids() -> Array[StringName]:
	if not "--all-drives" in OS.get_cmdline_user_args():
		return DRIVE_SAMPLE
	var ids: Array[StringName] = []
	for m in MissionSystem.MISSIONS:
		var driving := true
		for s in m.steps:
			driving = driving and (s.kind == MissionStep.Kind.ENTER or s.kind == MissionStep.Kind.DELIVER \
				or (s.kind == MissionStep.Kind.GOTO and s.need_vehicle))
		if driving:
			ids.append(m.id)
	return ids


func _test_drive_missions() -> void:
	for id in _drive_ids():
		var main: Node2D = load("res://scenes/main.tscn").instantiate()
		main.traffic_count = 20
		main.bus_count = 0
		main.police_patrols = PoliceDispatcher.PATROL_COUNT
		main.save_prefix = SAVE_PREFIX
		main.chapter = CityMap.LAST_CHAPTER
		add_child(main)
		await _frames(2)
		var missions: MissionSystem = main.missions
		var director: Director = main.director
		var m := missions.by_id(id)
		main.respect.set_value(m.gang, 100)
		missions.start(m)
		await _frames(1)
		var bot: PursuitAI = null
		var frames := 0
		while missions.active() and frames < int(m.time_limit * 60) + 60:
			frames += 1
			var s := missions.run.current()
			if s.kind == MissionStep.Kind.ENTER:
				director.enter_immediately(missions.vehicle)
				bot = PursuitAI.new(missions.vehicle, main.vehicles)
			elif bot:
				var goal: Variant = missions.objective_position()
				if goal != null:
					bot.target = goal
					bot.stop_at_target = s.kind == MissionStep.Kind.DELIVER
					_drive_with_input(bot)
			await get_tree().physics_frame
		for a in ["accelerate", "brake", "steer_left", "steer_right", "handbrake"]:
			Input.action_release(a)
		var run := missions.run
		var used := run.elapsed
		var health := missions.vehicle.health / missions.vehicle.stats.durability if missions.vehicle else -1.0
		print("  %s %s: %s %.1f초 / 제한 %.0f초%s" % [m.id, m.title,
			"성공" if run.state == MissionRun.State.PASSED else "실패(%s)" % run.fail_reason, used, m.time_limit,
			"" if health < 0.0 else ", 차 체력 %.0f%%" % (health * 100.0)])
		_expect(run.state == MissionRun.State.PASSED, "%s: 봇이 운전해서 끝낸다 (%s)" % [m.id, run.fail_reason])
		# 봇은 사람보다 빠르고 정확하다 — 사람 몫의 여유가 남아야 한다
		_expect(used < m.time_limit * 0.65, "%s: 봇이 제한 시간의 65%% 안에 끝낸다 (%.1f / %.0f초)" % [m.id, used, m.time_limit])
		await _free(main)


func _drive_with_input(bot: PursuitAI) -> void:
	bot.drive(1.0 / 60.0)
	var v := bot.vehicle
	for pair in [["accelerate", maxf(v.throttle_input, 0.0)], ["brake", maxf(-v.throttle_input, 0.0)],
			["steer_right", maxf(v.steer_input, 0.0)], ["steer_left", maxf(-v.steer_input, 0.0)],
			["handbrake", 1.0 if v.handbrake_input else 0.0]]:
		if pair[1] > 0.01:
			Input.action_press(pair[0], pair[1])
		else:
			Input.action_release(pair[0])


# ── 저장 · 불러오기 ────────────────────────────────────────

func _test_save_load() -> void:
	_remove_saves()
	var main := _make_main()
	await _frames(2)
	var player: Player = main.player
	var menu: SaveMenu = main.save_menu
	main.wallet.earn(123456)
	main.respect.change(&"gangnam", 24)
	main.respect.change(&"oldtown", -30)
	main.missions.completed[&"gangnam_01"] = true
	main.missions.completed[&"gangnam_02"] = true
	player.arsenal.give(PISTOL, 9)
	var money: int = main.wallet.money

	main.police.wanted.raise_to(1)
	player.global_position = City.hideout_door()
	await _frames(2)
	_expect(not menu.is_open(), "수배 중에는 저장 메뉴가 안 열린다")
	main.police.wanted.clear()
	player.global_position = City.hideout_door() + Vector2(0, 120)
	await _frames(2)
	player.take_damage(30.0)
	player.global_position = City.hideout_door()
	await _frames(2)
	_expect(menu.is_open() and menu.mode == SaveMenu.Mode.SAVE and get_tree().paused, "은신처 발판을 밟으면 슬롯 메뉴가 뜨고 게임이 멈춘다")
	_expect(menu.choose(2), "슬롯 2를 고른다")
	_expect(not menu.is_open() and not get_tree().paused, "고르면 메뉴가 닫히고 게임이 다시 돈다")
	_expect(FileAccess.file_exists(main.slot_path(2)) and not FileAccess.file_exists(main.slot_path(1)), "슬롯 2에만 저장된다")
	_expect(player.health == Player.MAX_HEALTH, "저장하면 체력이 찬다")

	# 다시 밟으면 슬롯 2가 차 있다. 닫으면 저장하지 않는다
	player.global_position = City.hideout_door() + Vector2(0, 120)
	await _frames(2)
	player.global_position = City.hideout_door()
	await _frames(2)
	var lines: Array[String] = main.slot_lines()
	_expect(menu.is_open() and lines[0] == "" and lines[1].contains("미션 2/60") and lines[1].begins_with("1장") and lines[2] == "", "슬롯 목록 (%s)" % [lines])
	menu.cancel()
	_expect(not get_tree().paused and not FileAccess.file_exists(main.slot_path(1)), "Esc로 닫으면 저장하지 않는다")

	# 다른 상태를 슬롯 3에
	main.wallet.pay(100000)
	main.missions.completed[&"gangnam_03"] = true
	_expect(main.save_game(3), "슬롯 3에 저장")
	await _free(main)

	main = _make_main()
	await _frames(2)
	_expect(main.wallet.money == Wallet.START_MONEY and not main.save_menu.is_open(), "테스트에서는 이어 하기 메뉴를 띄우지 않는다")
	_expect(not main.load_game(1), "빈 슬롯 1은 불러올 수 없다")
	_expect(main.load_game(2), "슬롯 2를 불러온다")
	_expect(main.wallet.money == money, "돈 (%d)" % main.wallet.money)
	_expect(main.respect.of(&"gangnam") == 24 and main.respect.of(&"oldtown") == -30, "존경도")
	_expect(main.missions.completed.has(&"gangnam_01") and main.missions.completed.has(&"gangnam_02"), "끝낸 미션")
	_expect(main.missions.next_mission(GANGNAM, 0).id == &"gangnam_03", "다음 쉬운 미션은 3번")
	_expect(main.player.arsenal.ammo_of(PISTOL) == 9, "무기와 탄 (%d)" % main.player.arsenal.ammo_of(PISTOL))
	_expect(main.player.global_position.distance_to(City.hideout_door()) < 40.0, "은신처 앞에서 시작")

	# 이어 하기 메뉴: 빈 슬롯은 못 고르고, 슬롯 3을 고르면 그 상태가 된다
	var menu2: SaveMenu = main.save_menu
	menu2.open_load(main.slot_lines())
	_expect(get_tree().paused and not menu2.choose(1), "이어 하기: 빈 슬롯은 고를 수 없다")
	_expect(menu2.choose(3), "이어 하기: 슬롯 3")
	_expect(main.wallet.money == money - 100000 and main.missions.completed.has(&"gangnam_03"), "슬롯 3의 상태 (%d)" % main.wallet.money)
	menu2.open_load(main.slot_lines())
	_expect(menu2.choose(0) and not get_tree().paused, "새 게임을 고르면 그대로 시작한다")
	await _frames(5)
	await _free(main)


func _remove_saves() -> void:
	for slot in range(1, SaveGame.SLOTS + 1):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.slot_path(SAVE_PREFIX, slot)))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
