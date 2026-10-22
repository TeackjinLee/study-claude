extends Node
## 기절·구급대(EmsDispatcher)·기절 드롭(Pickups) 검증.
##  1. 사람은 죽지 않는다: 체력이 0이면 기절해 누운 채 남고(일어나지 않는다), 구급차가 와서
##     구급대원 둘이 들것으로 구급차 뒤까지 옮겨 싣고 떠난다.
##  2. 구급대원을 기절시키면 목격과 상관없이 바로 수배 ★4.
##  3. 한 곳에 10명 넘게 쓰러지면 병원 옥상의 구급헬기가 떠서 끌어올리고, 병원 옥상으로 돌아가 내려앉는다.
##  4. 배달원을 기절시키면 상자 속 무엇(무기·구급상자)이 떨어진다. 조직원은 총알 상자, 드물게(5%) 총.
##     총알 상자를 먹으면 그 총의 탄이 는다.
## 실행: godot --headless --fixed-fps 60 --path . res://tests/ems_test.tscn

const CIV: NpcType = preload("res://data/npc/civ_m.tres")
const DELIVERY: NpcType = preload("res://data/npc/delivery.tres")
const GANG: NpcType = preload("res://data/npc/gang_oldtown.tres")
const PISTOL: WeaponType = preload("res://data/weapons/pistol.tres")

var _failures: Array[String] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_test_data()
	await _test_in_game()
	if _failures.is_empty():
		print("ems_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _test_data() -> void:
	var w := WantedSystem.new()
	w.report(WantedSystem.Crime.KO_PARAMEDIC)
	_expect(w.level == 4, "구급대원을 기절시키면 바로 ★4 (%d)" % w.level)
	_expect(not DELIVERY.ko_loot.is_empty(), "배달원 상자에 든 것이 있다")
	_expect(GANG.ko_ammo > 0 and is_equal_approx(GANG.ko_gun_chance, 0.05) and GANG.ko_ammo_weapon == PISTOL,
		"조직원은 권총 총알, 5% 확률로 권총")
	_expect(PedestrianManager.NPC_TYPES.has(DELIVERY), "배달원이 거리를 걷는다")
	var pad := SpecialBuilding.hospital_helipad(City.block_rect(City.HOSPITAL.x, City.HOSPITAL.y).grow(-City.SIDEWALK))
	_expect(pad.size.x > 40.0 and pad.size.y > 40.0, "병원 옥상 헬리패드가 헬기보다 넓다 (%s)" % pad.size)


func _test_in_game() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = 0
	main.bus_count = 0
	main.police_patrols = 0
	main.save_prefix = "user://ems_test_save_"
	add_child(main)
	await _frames(10)
	_rng.seed = 5
	main.street_events.enabled = false
	var ems: EmsDispatcher = main.ems
	var peds: PedestrianManager = main.pedestrians
	var player: Player = main.player
	var police: PoliceDispatcher = main.police
	var pickups: Pickups = main.pickups

	# 헬기는 처음에 병원 옥상에 날개를 세우고 서 있다
	_expect(ems.heli != null and ems.heli.parked and ems.air == EmsDispatcher.Air.PARKED, "구급헬기가 병원 옥상에 서 있다")
	_expect(ems.heli.global_position.distance_to(ems.pad) < 1.0 and ems.pad_height > City.HOSPITAL_FLOORS * IsoView.FLOOR_HEIGHT,
		"헬기는 헬리패드 높이 %.0f에 있다" % ems.pad_height)
	await _frames(30)
	_expect(ems.heli.global_position.distance_to(ems.pad) < 1.0 and ems.heli._look.rotor_off, "서 있는 헬기는 움직이지 않고 날개가 멈춰 있다")

	# ── 1. 기절 → 구급차 ──
	var block := City.nearest_block(player.global_position)
	var loop := City.sidewalk_loop(block)
	var spot := loop[0].lerp(loop[1], 0.5)
	var p := _person(peds, CIV, spot)
	peds.damage(p, 999.0, Vector2.RIGHT, false, true)
	_expect(p.is_dead() and is_instance_valid(p), "체력이 0이면 기절해 누운 채 남는다")
	await _frames(240)
	_expect(is_instance_valid(p) and p.is_dead() and p.state == Pedestrian.State.DEAD, "기절한 사람은 일어나지 않는다")
	_expect(ems.dispatches == 1 and ems.units.size() == 1 and p.rescuer == ems.units[0].car, "구급차가 출동해 그 사람을 맡는다")
	var car: Vehicle = ems.units[0].car if not ems.units.is_empty() else null
	_expect(car != null and car.siren and car.stats == EmsDispatcher.AMBULANCE_TYPE, "사이렌 켠 구급차")
	var deployed := await _until(func(): return ems.units.is_empty() or ems.units[0].phase != EmsDispatcher.Amb.DRIVE, 60.0)
	_expect(deployed and not ems.units.is_empty() and ems.units[0].medics.size() == 2, "구급차가 길가에 서고 대원 둘이 내린다")
	var carried := await _until(func(): return is_instance_valid(p) and p.carried, 30.0)
	_expect(carried, "대원 둘이 들것으로 든다")
	await _frames(20)
	if carried and not ems.units.is_empty() and is_instance_valid(p):
		var u: Dictionary = ems.units[0]
		var gap := (u.medics[0] as Paramedic).global_position.distance_to((u.medics[1] as Paramedic).global_position)
		_expect(absf(gap - EmsDispatcher.STRETCHER) < 1.0, "들것 앞뒤에 대원이 선다 (%.1f)" % gap)
	var gone: WeakRef = weakref(p)    # 실리면 사라진다 (풀린 노드를 람다에 잡아 두지 않게)
	p = null
	var loaded := await _until(func(): return gone.get_ref() == null, 30.0)
	_expect(loaded and ems.rescued == 1, "구급차 뒤까지 옮겨 싣는다")
	var left := await _until(func(): return ems.units.is_empty(), 30.0)
	_expect(left and is_instance_valid(car) and not car.siren and car.ai != null, "대원이 타고 구급차는 사이렌을 끄고 떠난다")
	_expect(_count_medics(peds) == 0, "대원은 모두 구급차에 탔다")

	# ── 2. 구급대원을 기절시키면 ★4 ──
	police.reset()
	var p2 := _person(peds, CIV, spot)
	peds.damage(p2, 999.0, Vector2.RIGHT, false, true)
	var out := await _until(func(): return not ems.units.is_empty() and ems.units[0].phase != EmsDispatcher.Amb.DRIVE, 70.0)
	_expect(out, "두 번째 구급차의 대원이 내린다")
	if out:
		var medic: Paramedic = ems.units[0].medics[0]
		_expect(police.wanted.level == 0, "처음엔 수배가 없다")
		peds.damage(medic, 999.0, Vector2.RIGHT, true, true)
		await _frames(2)
		_expect(police.wanted.level == 4, "구급대원을 기절시키면 바로 ★4 (%d)" % police.wanted.level)
		_expect(ems.units.is_empty() and is_instance_valid(p2) and p2.rescuer == null, "구급대는 그만두고 환자를 놓는다")
	police.reset()
	player.revive()
	# 남은 사람·대원 정리
	for q: Pedestrian in peds.peds.duplicate():
		if q.is_dead() or q is Paramedic:
			peds.remove(q)
	for u: Dictionary in ems.units.duplicate():
		ems._abort(u)
	await _frames(5)

	# ── 3. 10명 넘게 쓰러지면 구급헬기 ──
	var center := spot
	var crowd: Array[Pedestrian] = []
	for i in 11:
		var at := center + Vector2.from_angle(i * TAU / 11.0) * 50.0
		var q := _person(peds, CIV, at)
		crowd.append(q)
		peds.damage(q, 999.0, Vector2.RIGHT, false, true)
	var launched := await _until(func(): return ems.heli_calls == 1, 3.0)
	_expect(launched and not ems.heli.parked, "한 곳에 11명이 쓰러지면 구급헬기가 뜬다")
	var picked := await _until(func(): return ems.hoisting != null, 60.0)
	_expect(picked, "헬기가 쓰러진 사람 위에 멈춰 줄을 내린다")
	var done := await _until(func(): return crowd.all(func(q): return not is_instance_valid(q)), 120.0)
	_expect(done, "쓰러진 사람을 모두 실어 간다 (헬기 %d · 구급차 %d)" % [ems.heli_rescued, ems.rescued - 1])
	_expect(ems.heli_rescued >= 8, "대부분은 헬기가 끌어올린다 (%d)" % ems.heli_rescued)
	print("  구급헬기: 끌어올림 %d명 · 구급차 %d명" % [ems.heli_rescued, ems.rescued])
	var home := await _until(func(): return ems.air == EmsDispatcher.Air.PARKED, 90.0)
	_expect(home and ems.heli.parked and ems.heli.global_position.distance_to(ems.pad) < 1.0
		and absf(ems.heli.altitude() - ems.pad_height) < 1.0, "헬기는 병원 옥상으로 돌아가 내려앉는다")

	# ── 4. 기절 드롭 ──
	for u: Dictionary in ems.units.duplicate():
		ems._abort(u)
	ems.enabled = false
	var before := pickups.crates.size()
	var d := _person(peds, DELIVERY, spot)
	peds.damage(d, 999.0, Vector2.RIGHT, true, true)
	_expect(pickups.crates.size() == before + 1, "배달원을 기절시키면 상자에서 하나가 떨어진다")
	if pickups.crates.size() == before + 1:
		var c: Dictionary = pickups.crates.back()
		_expect(c.once and (c.weapon == null or DELIVERY.ko_loot.has(c.weapon)), "배달 상자 속 무기나 구급상자")
	var g := _person(peds, GANG, spot + Vector2(0, 30))
	var guns := 0
	var ammo := 0
	for i in 600:
		var n := pickups.crates.size()
		pickups.drop_loot(g)
		var c: Dictionary = pickups.crates.back()
		if c.ammo > 0:
			ammo += 1
		elif c.weapon == PISTOL:
			guns += 1
		pickups.crates.resize(n)
	_expect(guns + ammo == 600 and guns >= 12 and guns <= 54, "조직원: 총알 상자, 드물게 총 (600번에 총 %d)" % guns)
	# 총알 상자를 먹으면 권총 탄이 는다 (권총이 없으면 못 먹는다)
	player.arsenal.clear()
	pickups.crates.clear()
	pickups.drop(player.global_position, PISTOL, GANG.ko_ammo)
	await _frames(3)
	_expect(pickups.crates.size() == 1, "총이 없으면 총알 상자를 못 먹는다")
	player.arsenal.give(PISTOL, 5)
	await _frames(3)
	_expect(pickups.crates.is_empty() and player.arsenal.ammo_of(PISTOL) == 5 + GANG.ko_ammo,
		"총알 상자를 먹으면 권총 탄이 는다 (%d)" % player.arsenal.ammo_of(PISTOL))


func _person(peds: PedestrianManager, npc: NpcType, at: Vector2) -> Pedestrian:
	var p := Pedestrian.new()
	p.setup(npc, _rng, City.sidewalk_loop(City.nearest_block(at)), 0, 0.0, 1)
	p.position = at
	peds.add(p)
	return p


func _count_medics(peds: PedestrianManager) -> int:
	return peds.peds.filter(func(q): return q is Paramedic).size()


## cond가 참이 될 때까지 물리 틱을 돈다 (게임 시간 seconds까지). 참이 됐으면 true
func _until(cond: Callable, seconds: float) -> bool:
	for i in int(seconds * 60.0):
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
