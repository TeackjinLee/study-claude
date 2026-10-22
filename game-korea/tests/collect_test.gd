extends Node
## 수집 요소 검증 (docs/05 §7): 비밀 패키지(HiddenPackages)·광란 모드(Rampages).
##  1. 패키지 데이터: 50개, 블록마다 하나, 맵 안·강물 밖·건물 장애물 밖, 그 블록 인도에서 걸어서 닿고 인도보다 안쪽(숨은 자리).
##     milestones와 unlocks 수가 같다.
##  2. 광란 데이터: 20개, id가 겹치지 않는다, 아이콘은 땅 블록 인도에 서고 공중전화·무기 상자·은신처 문·다른 아이콘과 떨어져 있다.
##     조직 목표는 있는 조직이다. 7구역에 모두 있다.
##  3. 본편 — 패키지: 지나가면 줍고 돈, 열 번째에 무기 해금(바로 받고 은신처 문 옆에 늘 생기는 상자), 저장·불러오기.
##  4. 본편 — 광란: 밟으면 시작해 무기를 들고 탄이 줄지 않는다, 목표만큼 쓰러뜨리면 보상·끝낸 표시·무기 되돌림,
##     다른 조직원·차는 세지 않는다, 시간이 다 되면 실패하고 다시 할 수 있다, 미션 중엔 시작하지 않는다, 저장된다.
## 실행: godot --headless --fixed-fps 60 --path . res://tests/collect_test.tscn

const PISTOL: WeaponType = preload("res://data/weapons/pistol.tres")

var _failures: Array[String] = []


func _ready() -> void:
	_test_package_data()
	_test_rampage_data()
	await _test_in_game()
	if _failures.is_empty():
		print("collect_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _test_package_data() -> void:
	var set := HiddenPackages.SET
	_expect(set.spots.size() == 50, "비밀 패키지 50개 (%d)" % set.spots.size())
	_expect(set.milestones.size() == set.unlocks.size() and not set.unlocks.has(null), "해금 단계마다 무기")
	var city := City.new()
	city._build_layout()
	var obstacles := city.obstacle_rects()
	var water := City.water_rects()
	obstacles.append_array(water)
	var blocks := {}
	var districts := {}
	for p in set.spots:
		var b := CityMap.block_at(p)
		_expect(not blocks.has(b), "블록 %s에 패키지가 둘" % b)
		blocks[b] = true
		_expect(City.world_rect().has_point(p), "패키지 %s가 맵 밖" % p)
		var bad := false
		for r in obstacles:
			bad = bad or r.has_point(p)
		_expect(not bad, "패키지 %s가 건물·강물 안" % p)
		_expect(HiddenPackages.is_reachable(p, obstacles), "패키지 %s에 걸어서 못 간다" % p)
		var area := City.block_rect(b.x, b.y)
		var depth := minf(minf(p.x - area.position.x, area.end.x - p.x), minf(p.y - area.position.y, area.end.y - p.y))
		_expect(depth > City.SIDEWALK + 20.0, "패키지 %s는 인도에서 안쪽에 숨어 있다 (%.0f)" % [p, depth])
		var d := CityMap.district_at(p)
		_expect(d != null, "패키지 %s가 구역 밖" % p)
		if d:
			districts[d.id] = true
	_expect(districts.size() == 7, "7구역에 모두 있다 (%s)" % [districts.keys()])
	city.free()


func _test_rampage_data() -> void:
	var all := RampageList.ALL
	_expect(all.size() == 20, "광란 모드 20개 (%d)" % all.size())
	var city := City.new()
	city._build_layout()
	var obstacles := city.obstacle_rects()
	var avoid: Array[Vector2] = []
	var pickups := Pickups.new()
	pickups.crates.clear()
	pickups._ready()
	for c in pickups.crates:
		avoid.append(c.pos)
	pickups.free()
	for g: GangType in preload("res://scripts/main.gd").GANGS:
		for q in g.phones:
			avoid.append(q)
	for h: HideoutType in preload("res://scripts/main.gd").HIDEOUTS:
		avoid.append(h.door)
	var ids := {}
	var districts := {}
	var gang_ids: Array = preload("res://scripts/main.gd").GANGS.map(func(g): return g.id)
	for r in all:
		_expect(not ids.has(r.id), "광란 id가 겹친다: %s" % r.id)
		ids[r.id] = true
		_expect(r.weapon != null and r.count > 0 and r.time_limit > 0.0 and r.reward > 0, "%s: 무기·목표·시간·보상" % r.id)
		_expect(CityMap.is_land(r.block), "%s: 블록 %s는 땅" % [r.id, r.block])
		var p := r.position()
		var bad := false
		for o in obstacles:
			bad = bad or o.has_point(p)
		_expect(not bad, "%s: 아이콘이 건물 안" % r.id)
		for q in avoid:
			_expect(p.distance_to(q) > 60.0, "%s: 아이콘이 공중전화·상자·은신처 %s와 겹친다" % [r.id, q])
		for o in all:
			if o != r:
				_expect(p.distance_to(o.position()) > 200.0, "%s: %s와 너무 가깝다" % [r.id, o.id])
		if r.target == RampageType.Target.GANG:
			_expect(gang_ids.has(r.gang), "%s: 조직 %s가 있다" % [r.id, r.gang])
		var d := CityMap.district_of(r.block)
		if d:
			districts[d.id] = true
	_expect(districts.size() == 7, "광란 7구역 (%s)" % [districts.keys()])
	city.free()


func _test_in_game() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = 0
	main.bus_count = 0
	main.police_patrols = 0
	main.save_prefix = "user://collect_test_save_"
	add_child(main)
	await _frames(10)
	main.street_events.enabled = false
	main.set_chapter(4)
	var player: Player = main.player
	var pk: HiddenPackages = main.packages
	var set := HiddenPackages.SET

	# ── 패키지 ──
	var money: int = main.wallet.money
	player.global_position = set.spots[0]
	await _frames(3)
	_expect(pk.got.has(0) and pk.count() == 1, "지나가면 줍는다")
	_expect(main.wallet.money == money + set.reward, "하나에 ₩%d" % set.reward)
	await _frames(3)
	_expect(pk.count() == 1, "같은 패키지는 한 번만")
	for i in range(1, set.milestones[0] - 1):
		pk.got[i] = true
	var w := set.unlocks[0]
	_expect(not player.arsenal.has(w), "해금 전에는 %s가 없다" % w.display_name)
	player.global_position = set.spots[set.milestones[0] - 1]
	await _frames(3)
	_expect(pk.count() == set.milestones[0], "%d개째" % set.milestones[0])
	_expect(player.arsenal.has(w), "%d개면 %s를 준다" % [set.milestones[0], w.display_name])
	var stock: Array = main.pickups.crates.filter(func(c): return c.get("stock", false) and c.weapon == w)
	var owned: Array = main.hideouts.filter(func(h): return h.owned)
	_expect(stock.size() == owned.size() and owned.size() > 0, "산 은신처마다 %s 상자 (%d/%d)" % [w.display_name, stock.size(), owned.size()])
	for c in stock:
		_expect(main.city.obstacle_rects().all(func(r): return not r.has_point(c.pos)), "은신처 상자가 건물 안이 아니다 %s" % c.pos)
	_expect(main.save_game(1), "저장")
	pk.got.clear()
	var none: Array[WeaponType] = []
	main.pickups.set_stock([], none)
	_expect(main.load_game(1), "불러오기")
	_expect(pk.count() == set.milestones[0], "불러오면 모은 패키지 그대로 (%d)" % pk.count())
	_expect(main.pickups.crates.any(func(c): return c.get("stock", false) and c.weapon == w), "불러오면 은신처 상자도 그대로")

	# ── 광란 ──
	var rp: Rampages = main.rampages
	var log := []
	rp.started.connect(func(r: RampageType): log.append(["started", r.id]))
	rp.finished.connect(func(r: RampageType, passed: bool, pay: int): log.append(["finished", r.id, passed, pay]))
	var first: RampageType = RampageList.ALL[0]          # 강남 권총 — 아무나
	player.arsenal.clear()
	player.global_position = first.position()
	await _frames(3)
	_expect(rp.current == first and log.has(["started", first.id]), "아이콘을 밟으면 시작")
	_expect(player.arsenal.current() == first.weapon, "광란 무기를 든다 (%s)" % player.arsenal.current().display_name)
	var full: int = player.arsenal.ammo_of(first.weapon)
	player.arsenal.fire()
	await _frames(2)
	_expect(player.arsenal.ammo_of(first.weapon) == full, "탄이 줄지 않는다")
	var civ := _any_ped(main)
	money = main.wallet.money
	for i in first.count - 1:
		main.pedestrians.person_hurt.emit(civ, true, true)
	main.pedestrians.person_hurt.emit(civ, false, true)     # 남이 쓰러뜨린 건 세지 않는다
	_expect(rp.active() and rp.kills == first.count - 1, "주인공이 쓰러뜨린 것만 센다 (%d)" % rp.kills)
	main.pedestrians.person_hurt.emit(civ, true, true)
	await _frames(2)
	_expect(log.has(["finished", first.id, true, first.reward]), "목표를 채우면 성공 (%s)" % [log])
	_expect(main.wallet.money == money + first.reward, "보상 ₩%d" % first.reward)
	_expect(not player.arsenal.has(first.weapon), "없던 광란 무기는 끝나면 빠진다")
	_expect(not rp.available(first), "끝낸 광란 아이콘은 사라진다")
	await _frames(int(Rampages.RETRY_WAIT * 60) + 5)
	_expect(not rp.active(), "끝낸 아이콘 자리에서 다시 시작하지 않는다")

	# 조직 목표: 다른 조직원·시민·차는 세지 않는다
	var gang_r: RampageType = null
	for r in RampageList.ALL:
		if r.target == RampageType.Target.GANG and r.gang == &"gangnam":
			gang_r = r
	player.arsenal.give(PISTOL, 30)
	rp.start(gang_r)
	main.pedestrians.person_hurt.emit(civ, true, true)
	main.combat.vehicle_exploded.emit(null, true)
	_expect(rp.kills == 0, "조직 목표는 시민·차를 세지 않는다")
	var member := GangMember.new()
	member.npc = civ.npc
	member.gang = main.GANGS[0] if main.GANGS[0].id == &"gangnam" else main.GANGS[2]
	main.pedestrians.person_hurt.emit(member, true, true)
	_expect(rp.kills == 1, "그 조직 조직원은 센다")
	member.free()
	rp.time_left = 0.01
	await _frames(3)
	_expect(log.has(["finished", gang_r.id, false, 0]) and rp.available(gang_r), "시간이 다 되면 실패, 다시 할 수 있다")
	_expect(player.arsenal.has(PISTOL) and player.arsenal.ammo_of(PISTOL) == 30 or gang_r.weapon != PISTOL, "있던 무기는 예전 탄으로")

	# 미션 중에는 시작하지 않는다
	var cars_r: RampageType = null
	for r in RampageList.ALL:
		if r.target == RampageType.Target.CARS and CityMap.district_of(r.block).id == &"gangnam":
			cars_r = r
	main.missions.start(MissionSystem.MISSIONS[0])
	player.global_position = cars_r.position()
	await _frames(3)
	_expect(not rp.active(), "미션 중엔 광란이 켜지지 않는다")
	main.missions.fail("테스트")
	await _frames(int(Rampages.RETRY_WAIT * 60) + 5)
	_expect(rp.current == cars_r, "미션이 끝나면 밟아서 시작")
	main.combat.vehicle_exploded.emit(null, true)
	_expect(rp.kills == 1, "차 목표는 터뜨린 차를 센다")
	main.rampages.abort()
	_expect(main.save_game(2), "저장")
	rp.done.clear()
	_expect(main.load_game(2) and rp.done.has(first.id) and not rp.done.has(cars_r.id), "끝낸 광란이 저장된다")
	for slot in [1, 2]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(main.slot_path(slot)))
	main.queue_free()
	await _frames(2)


func _any_ped(main: Node) -> Pedestrian:
	for p in main.pedestrians.peds:
		if p.active:
			return p
	return main.pedestrians.peds[0]


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
