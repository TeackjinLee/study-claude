extends Node
## M4 무기 검증.
##  1. 무기 계산: 탄 소모·연사 간격·탄 상한·무기 순서·압수, 산탄 부채꼴, 자동 조준.
##  2. 무기 상자를 밟으면 무기를 얻고, 상자는 잠시 뒤 다시 생긴다.
##  3. 권총 두 발·산탄총 한 발에 시민이 죽고, 주먹은 넘어뜨리다 세 번째에 죽인다.
##  4. 총소리에 주변 시민이 도망친다.
##  5. 드라이브바이: 차 옆의 표적을 쏜다. 차 안에서 주먹은 못 쓴다.
##  6. 경찰 앞에서 쏘면 ★1, 시민을 죽이면 ★2, 경찰을 죽이면 ★3.
##  7. ★2부터 도보 경찰이 총을 쏜다.
##  8. 죽으면 치료비를 내고 무기를 잃은 채 병원 앞에서, 체포되면 무기를 압수당한 채 경찰서 앞에서 다시 시작한다.
## 실행: godot --headless --fixed-fps 60 --path . res://tests/weapon_test.tscn

const FIST: WeaponType = preload("res://data/weapons/fist.tres")
const PISTOL: WeaponType = preload("res://data/weapons/pistol.tres")
const SMG: WeaponType = preload("res://data/weapons/smg.tres")
const SHOTGUN: WeaponType = preload("res://data/weapons/shotgun.tres")
const DT := 1.0 / 60.0

var _failures: Array[String] = []


func _ready() -> void:
	_test_arsenal()
	_test_ballistics()
	await _test_pickup()
	await _test_kills()
	await _test_mouse_aim()
	await _test_drive_by()
	await _test_crimes()
	await _test_police_shoot_back()
	await _test_death_and_bust()
	if _failures.is_empty():
		print("weapon_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _make_main(patrols := 0) -> Node2D:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = 0
	main.bus_count = 0
	main.police_patrols = patrols
	add_child(main)
	return main


func _free(main: Node2D) -> void:
	for a in ["accelerate", "brake", "steer_left", "steer_right", "fire", "sprint"]:
		Input.action_release(a)
	main.queue_free()
	await _frames(2)


func _test_arsenal() -> void:
	var a := Arsenal.new(FIST)
	_expect(a.current() == FIST and a.ammo_of(FIST) == -1, "처음엔 주먹 (탄 무한)")
	a.give(PISTOL, 12)
	_expect(a.current() == PISTOL and a.ammo_of(PISTOL) == 12, "주먹을 들고 있다가 권총을 얻으면 바로 든다")
	a.give(SMG, 30)
	_expect(a.current() == PISTOL, "다른 총을 들고 있으면 새 무기를 주워도 바꾸지 않는다")
	_expect(Array(a.weapons) == [FIST, PISTOL, SMG], "무기는 순서대로")
	_expect(a.fire(), "쏜다")
	_expect(not a.fire(), "연사 간격 전에는 못 쏜다")
	a.update(PISTOL.fire_interval)
	_expect(a.fire() and a.ammo_of(PISTOL) == 10, "간격이 지나면 다시 쏜다 (남은 탄 %d)" % a.ammo_of(PISTOL))

	a.cycle(1)
	_expect(a.current() == SMG, "다음 무기")
	a.update(1.0)
	var shots := 0
	for i in 120:
		if a.fire():
			shots += 1
		a.update(DT)
	var expected := roundi(2.0 / SMG.fire_interval)
	_expect(absi(shots - expected) <= 2, "SMG는 2초에 약 %d발 (%d)" % [expected, shots])

	a.cycle(-1)
	_expect(a.current() == PISTOL, "이전 무기")
	for i in 30:
		a.update(1.0)
		a.fire()
	_expect(not a.has(PISTOL) and a.current() == FIST, "탄을 다 쓰면 권총이 빠지고 주먹으로")
	a.give(PISTOL, 1000)
	_expect(a.ammo_of(PISTOL) == PISTOL.max_ammo, "탄은 상한까지만 (%d)" % a.ammo_of(PISTOL))
	a.index = 0
	a.cycle(-1)
	_expect(a.current() == SMG, "맨 앞에서 이전 무기는 맨 끝으로 돈다")
	a.clear()
	_expect(Array(a.weapons) == [FIST] and a.current() == FIST, "압수하면 주먹만 남는다")


func _test_ballistics() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var dirs := Ballistics.pellet_dirs(Vector2.UP, SHOTGUN, rng)
	_expect(dirs.size() == SHOTGUN.pellets, "산탄 %d알" % dirs.size())
	var lo := INF
	var hi := -INF
	for d in dirs:
		var a := Vector2.UP.angle_to(d)
		lo = minf(lo, a)
		hi = maxf(hi, a)
	_expect(hi - lo > SHOTGUN.spread * 1.5 and hi < SHOTGUN.spread * 1.2 and lo > -SHOTGUN.spread * 1.2,
		"산탄은 부채꼴로 고르게 퍼진다 (%.2f ~ %.2f rad)" % [lo, hi])
	var targets: Array[Vector2] = [Vector2(300, -10), Vector2(100, 0), Vector2(0, -50), Vector2(900, 0)]
	_expect(Ballistics.pick_target(Vector2.ZERO, Vector2.RIGHT, targets, 500.0) == 1, "자동 조준은 앞쪽 가까운 표적")
	_expect(Ballistics.pick_target(Vector2.ZERO, Vector2.DOWN, targets, 500.0) == -1, "부채꼴 밖은 겨누지 않는다")
	_expect(Ballistics.side_dir(Vector2.UP, 1.0).is_equal_approx(Vector2.RIGHT), "위를 보는 차의 오른쪽은 +x")
	_expect(DamageModel.run_over_damage(300.0) >= 20.0, "300px/s로 치면 시민이 죽는다")


func _test_pickup() -> void:
	var main := _make_main()
	await _frames(2)
	var player: Player = main.player
	var crate: Dictionary = main.pickups.crates[0]
	_expect(crate.weapon == PISTOL, "출발점 위 인도에 권총 상자")
	player.screen_walk = false         # 2.5D 화면 방향이 아니라 월드 북쪽으로 걷는다
	Input.action_press("accelerate")   # 도보에서는 위로
	for f in 120:
		await _frames(1)
		if player.arsenal.has(PISTOL):
			break
	Input.action_release("accelerate")
	_expect(player.arsenal.current() == PISTOL and player.arsenal.ammo_of(PISTOL) == PISTOL.pickup_ammo, "상자를 밟으면 권총을 든다")
	_expect(crate.wait > 0.0, "먹은 상자는 사라진다")
	player.global_position += Vector2(0, 200)   # 상자에서 비켜서야 다시 생긴 걸 볼 수 있다
	crate.wait = 0.05
	await _frames(10)
	_expect(crate.wait <= 0.0, "잠시 뒤 다시 생긴다")
	await _free(main)


## 주인공 앞(위쪽) dist 거리 인도에 시민 하나를 세운다
func _civilian_ahead(main: Node2D, index: int, dist: float) -> Pedestrian:
	var p: Pedestrian = main.pedestrians.peds[index]
	p.global_position = main.player.global_position + Vector2(0, -dist)
	p.set_active(true)
	p.set_physics_process(false)   # 걷지 않고 서 있게
	return p


## 표적을 옮긴 직후에는 물리 공간에 아직 반영되지 않았다 — 두 프레임 기다린 뒤 쏜다
func _hold_fire_until(cond: Callable, max_frames: int) -> int:
	await _frames(2)
	Input.action_press("fire")
	var f := 0
	while f < max_frames and not cond.call():
		await _frames(1)
		f += 1
	Input.action_release("fire")
	await _frames(1)
	return f


func _test_kills() -> void:
	var main := _make_main()
	await _frames(2)
	var player: Player = main.player
	player.facing = 0.0
	var hurt := []
	main.pedestrians.person_hurt.connect(func(p, by_player, killed): hurt.append([p, by_player, killed]))

	# 권총: 시민 체력 20, 한 발 12 → 두 발
	player.arsenal.give(PISTOL, 12)
	var p := _civilian_ahead(main, 0, 180.0)
	await _hold_fire_until(func(): return p.is_dead(), 120)
	var used: int = 12 - player.arsenal.ammo_of(PISTOL)
	_expect(p.is_dead(), "권총으로 시민을 쏘면 죽는다")
	_expect(used == 2, "권총 두 발 (%d발)" % used)
	_expect(hurt.size() == 2 and hurt[1][1] and hurt[1][2], "피해는 주인공 탓, 두 번째에 사망으로 알린다")

	# 산탄총: 가까우면 한 방
	player.arsenal.give(SHOTGUN, 8)
	player.arsenal.index = player.arsenal.weapons.find(SHOTGUN)
	p = _civilian_ahead(main, 1, 30.0)
	await _hold_fire_until(func(): return p.is_dead(), 60)
	_expect(p.is_dead() and player.arsenal.ammo_of(SHOTGUN) == 7, "산탄총은 가까운 시민을 한 방에 (남은 탄 %d)" % player.arsenal.ammo_of(SHOTGUN))

	# 주먹: 넘어뜨리고, 세 번째에 죽인다 (7 × 3 ≥ 20)
	player.arsenal.index = 0
	p = _civilian_ahead(main, 2, 16.0)
	await _frames(2)
	player.arsenal.cooldown = 0.0
	var hits_before := hurt.size()
	main.weapons.shoot()
	await _frames(1)
	_expect(p.state == Pedestrian.State.KNOCKED, "주먹에 맞으면 넘어진다")
	await _hold_fire_until(func(): return p.is_dead(), 120)
	_expect(p.is_dead() and hurt.size() - hits_before == 3, "주먹 세 번에 죽는다 (%d번)" % (hurt.size() - hits_before))

	# 총소리에 옆 시민이 도망친다 (아무것도 없는 쪽으로 쏴도)
	player.arsenal.index = player.arsenal.weapons.find(PISTOL)
	player.arsenal.cooldown = 0.0
	var q: Pedestrian = main.pedestrians.peds[3]
	q.global_position = player.global_position + Vector2(0, 150)
	q.set_active(true)
	q.resume_walking()
	player.facing = PI * 0.5   # 오른쪽 (건물 벽)
	main.weapons.shoot()
	await _frames(2)
	_expect(q.state == Pedestrian.State.FLEE, "총소리에 근처 시민이 도망친다 (%d)" % q.state)
	_expect(main.wallet.money == Wallet.START_MONEY, "돈은 그대로")
	await _free(main)


## 마우스 조준: 2.5D에서 서 있는 사람의 몸을 누르면 그 사람을, 빈 곳은 커서 아래 바닥 점을 겨눈다
func _test_mouse_aim() -> void:
	var main := _make_main()
	await _frames(2)
	var player: Player = main.player
	var w: PlayerWeapons = main.weapons
	var at := player.global_position
	var ct := IsoView.canvas(Vector2(1280, 720), at, 2.0)
	var p := _civilian_ahead(main, 1, 60.0)
	p.global_position += Vector2(18, 0)
	var torso := ct * (p.global_position + IsoView.lift(IsoView.ground(p.global_position) + IsoView.PERSON_HEIGHT * 0.6 * p.npc.body_scale))
	var d := w.screen_dir(at, torso, ct)
	var want := (p.global_position - at).normalized()
	_expect(d.angle_to(want) < 0.01, "몸통을 누르면 그 사람 발밑을 겨눈다 (%.3f rad 차이)" % d.angle_to(want))
	var spot := at + Vector2(-70, 40)
	d = w.screen_dir(at, ct * (spot + IsoView.lift(IsoView.ground(at))), ct)
	_expect(absf(d.angle_to((spot - at).normalized())) < 0.01, "빈 곳은 커서 아래 바닥 점 쪽으로 정확히 (부채꼴 자동 조준 없음)")
	d = w.screen_dir(at, ct * (at + IsoView.lift(IsoView.ground(at))), ct)
	_expect(d.is_equal_approx(Vector2.UP.rotated(player.facing)), "커서가 발밑이면 바라보는 쪽")
	player.face(Vector2.RIGHT, 0.3)
	Input.action_press("accelerate")
	await _frames(5)
	_expect(absf(angle_difference(player.facing, Vector2.UP.angle_to(Vector2.RIGHT))) < 0.01, "겨눈 뒤 잠깐은 걸어도 겨눈 쪽을 본다")
	await _frames(30)
	Input.action_release("accelerate")
	_expect(absf(angle_difference(player.facing, Vector2.UP.angle_to(Vector2.RIGHT))) > 0.5, "잠시 뒤엔 다시 걷는 쪽을 본다")
	await _free(main)


func _test_drive_by() -> void:
	var main := _make_main()
	await _frames(2)
	var player: Player = main.player
	var car: Vehicle = main.start_vehicle
	main.director.enter_immediately(car)
	await _frames(1)
	player.arsenal.give(SMG, 30)
	player.arsenal.index = 0
	_expect(not main.weapons.shoot(), "차 안에서 주먹은 못 쓴다")
	player.arsenal.index = player.arsenal.weapons.find(SMG)
	await _frames(20)
	# 차는 위를 본다 — 오른쪽 인도에 시민
	var p: Pedestrian = main.pedestrians.peds[0]
	p.global_position = car.global_position + Vector2(45, 5)
	p.set_active(true)
	p.set_physics_process(false)
	var frames := await _hold_fire_until(func(): return p.is_dead(), 120)
	_expect(p.is_dead(), "드라이브바이로 차 오른쪽 시민을 맞힌다 (%d프레임)" % frames)
	_expect(car.health == car.stats.durability, "자기 차는 맞지 않는다 (%.0f)" % car.health)
	await _free(main)


## 주인공 뒤(아래쪽) 인도에 서서 지켜보기만 하는 경찰 (260px 밖이라 쫓아오지 않는다)
func _witness(main: Node2D) -> PoliceOfficer:
	var o: PoliceOfficer = main.police._spawn_officer(main.player.global_position + Vector2(0, 320), null, PoliceOfficer.Duty.GUARD)
	o.set_physics_process(false)
	return o


func _test_crimes() -> void:
	var main := _make_main()
	await _frames(2)
	var police: PoliceDispatcher = main.police
	var player: Player = main.player
	player.arsenal.give(PISTOL, 12)
	player.facing = PI * 0.5
	main.weapons.shoot()
	await _frames(2)
	_expect(police.wanted.level == 0, "경찰이 없으면 총을 쏴도 수배 없음")

	_witness(main)
	await _frames(2)
	_expect(police.sees(player.global_position), "경찰이 주인공을 본다")
	await _frames(30)
	main.weapons.shoot()
	await _frames(2)
	_expect(police.wanted.level == 1, "경찰 앞에서 총을 쏘면 ★1 (%d)" % police.wanted.level)

	player.facing = 0.0
	await _frames(30)
	var p := _civilian_ahead(main, 0, 150.0)
	await _hold_fire_until(func(): return p.is_dead(), 120)
	_expect(police.wanted.level == 2, "경찰 앞에서 시민을 죽이면 ★2 (%d)" % police.wanted.level)

	var cop := police._spawn_officer(player.global_position + Vector2(0, -120), null, PoliceOfficer.Duty.GUARD)
	cop.set_physics_process(false)
	await _frames(30)
	await _hold_fire_until(func(): return cop.is_dead(), 180)
	await _frames(2)
	_expect(cop.is_dead(), "경찰관도 총에 죽는다")
	_expect(police.wanted.level == 3, "경찰관을 죽이면 ★3 (%d)" % police.wanted.level)
	_expect(not police.officers.has(cop), "죽은 경찰은 명단에서 빠진다")
	await _free(main)


func _test_police_shoot_back() -> void:
	var main := _make_main()
	await _frames(2)
	var police: PoliceDispatcher = main.police
	var player: Player = main.player
	police.wanted.report(WantedSystem.Crime.HIT_OFFICER)
	_expect(police.wanted.level == 2, "★2")
	var cop := police._spawn_officer(player.global_position + Vector2(0, -260), null, PoliceOfficer.Duty.CHASE)
	var shots := [0]
	main.combat.gunfire.connect(func(_pos, by_player): if not by_player: shots[0] += 1)
	var busted := [false]
	police.busted.connect(func(_f): busted[0] = true)
	for f in 240:
		await _frames(1)
		if player.health < Player.MAX_HEALTH or busted[0]:
			break
	_expect(shots[0] > 0, "★2 도보 경찰은 총을 쏜다 (%d발)" % shots[0])
	_expect(player.health < Player.MAX_HEALTH, "경찰 총에 맞는다 (체력 %.0f)" % player.health)
	await _free(main)

	# ★1에서는 쏘지 않는다
	main = _make_main()
	await _frames(2)
	police = main.police
	police.wanted.report(WantedSystem.Crime.CAR_THEFT)
	police._spawn_officer(main.player.global_position + Vector2(0, -260), null, PoliceOfficer.Duty.CHASE)
	shots[0] = 0
	main.combat.gunfire.connect(func(_pos, by_player): if not by_player: shots[0] += 1)
	await _frames(90)
	_expect(shots[0] == 0, "★1 경찰은 쏘지 않는다 (%d발)" % shots[0])
	await _free(main)


func _test_death_and_bust() -> void:
	var main := _make_main()
	await _frames(2)
	var player: Player = main.player
	var police: PoliceDispatcher = main.police
	player.arsenal.give(SMG, 30)
	police.wanted.report(WantedSystem.Crime.CAR_THEFT)
	player.take_damage(Player.MAX_HEALTH)
	_expect(player.is_dead() and not player.input_enabled, "체력 0이면 죽는다")
	await _frames(int(main.BUST_DELAY * 60) + 10)
	_expect(player.global_position.distance_to(City.hospital_position()) < 5.0, "병원 앞에서 다시 시작")
	_expect(main.wallet.money == Wallet.START_MONEY - main.HOSPITAL_FEE, "치료비 %d원" % main.HOSPITAL_FEE)
	_expect(player.arsenal.weapons.size() == 1, "죽으면 무기를 잃는다")
	_expect(player.health == Player.MAX_HEALTH and player.input_enabled, "체력이 차고 다시 움직인다")
	_expect(police.wanted.level == 0, "수배도 풀린다")

	player.arsenal.give(PISTOL, 12)
	police.wanted.report(WantedSystem.Crime.CAR_THEFT)
	main._on_busted(PoliceDispatcher.FINE_PER_STAR)
	await _frames(int(main.BUST_DELAY * 60) + 10)
	_expect(player.global_position.distance_to(City.police_station_position()) < 5.0, "체포되면 경찰서 앞")
	_expect(player.arsenal.weapons.size() == 1, "체포되면 무기 압수")
	await _free(main)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
