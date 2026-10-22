extends Node
## 로켓포 자세: 영상 시트(조준·발사 — 탄두를 지운 빈 발사관), 서 있을 때만 로켓포 그림, 쏘면 그림 속 탄두 자리·발사관 뒤끝을 넘긴다.
## 날아가는 로켓은 탄두 자리에서 나와 맞히는 길로 내려앉고, 꼬리 연기는 끊기지 않게 이어진다. 쏜 자리에 앞 불꽃·후폭풍.
class ProbeCombat extends Combat:
	var shows: Array = []
	var rears: Array = []
	func _ready() -> void:
		pass
	func fire(_from: Vector2, _dir: Vector2, _w: WeaponType, _by: bool, _exclude: Array[RID] = [], _spread := 0.0, _level := -1,
			shown: Variant = null, rear: Variant = null) -> void:
		shows.append(shown)
		rears.append(rear)

var failures := 0

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func _ready() -> void:
	var rocket: WeaponType = load("res://data/weapons/rocket.tres")
	check(rocket.pose == &"rocket" and rocket.projectile == &"rocket", "로켓포 자세는 데이터 (rocket.tres)")
	var info := PersonRig.dir8_for(null)
	check(info.has("rocket_tex") and info.has("rocket_aim") and info.has("rocket_fire"), "로켓포 시트·조준·발사 장면")
	var ok: Array = info.get("rocket_ok", [])
	var have := 0
	for o in ok:
		have += 1 if o != null else 0
	check(ok.size() == 8 and have == 7, "로켓포 그림: 영상 ↓·↘·→·↖ + 뒤집기 ↙·←·↗ (↑만 가까운 방향)")
	var muzzles: Dictionary = info.get("rocket_muzzle", {})
	var breeches: Dictionary = info.get("rocket_breech", {})
	check(muzzles.size() == 4 and breeches.size() == 4, "영상 4방향 모두 탄두 자리·발사관 뒤끝이 있다")
	check(float(muzzles["e"][0]) > float(breeches["e"][0]) and float(muzzles["nw"][0]) < float(breeches["nw"][0]),
			"→는 탄두가 오른쪽·뒤끝이 왼쪽, ↖는 반대")
	var fire: Dictionary = info.get("rocket_fire", {})
	check(not fire.get("loop", true) and float(fire.get("duration", 9.0)) < rocket.fire_interval, "발사 장면은 한 번, 다음 발 전에 끝난다")

	# 그리기: 서 있으면 로켓포 그림, 걸으면·뛰면 평소 그림 (겨눈 채 걷는 장면이 없다), NPC는 평소 그림
	var probe := Node2D.new()
	var drawn := []
	probe.draw.connect(func():
		drawn.assign([PersonRig._draw_gun(probe, 0.0, 0.0, 1.0, null, 0.0, rocket),
				PersonRig._draw_gun(probe, 0.0, 1.0, 1.0, null, 1.0, rocket),
				PersonRig._draw_gun(probe, 0.0, 0.0, 1.0, null, 2.0, rocket),
				PersonRig._draw_gun(probe, 0.0, 0.0, 1.0, NpcType.new(), 0.0, rocket)]))
	add_child(probe)
	probe.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	check(drawn.size() == 4 and drawn[0], "서 있으면 로켓포 그림")
	check(drawn.size() == 4 and not drawn[1] and not drawn[2], "걷거나 뛰면 평소 그림")
	check(drawn.size() == 4 and not drawn[3], "NPC는 평소 그림")

	# 쏘기: 그림 속 탄두 자리·발사관 뒤끝을 Combat에 넘기고 발사 장면을 시작한다
	var p := Player.new()
	p.control.use_external()
	add_child(p)
	p.set_physics_process(false)
	var d := Director.new()
	d.player = p
	var c := ProbeCombat.new()
	var w := PlayerWeapons.new()
	w.player = p
	w.director = d
	w.combat = c
	w.pedestrians = PedestrianManager.new()
	w.mouse_aim = false
	p.arsenal.give(rocket, 10)
	p.arsenal.index = p.arsenal.weapons.find(rocket)
	var scale := PersonRig.SPRITE_HEIGHT / PersonRig.SPRITE_BODY
	p.facing = Vector2.UP.angle_to(IsoView.BASIS.affine_inverse().basis_xform(Vector2.RIGHT))
	check(w.shoot() and p.has_meta(&"shot_at"), "로켓포를 쏘면 발사 장면 시작")
	var tip: Vector2 = IsoView.to_screen_dir(c.shows[0] - p.global_position) if c.shows.size() == 1 and c.shows[0] is Vector2 else Vector2.INF
	var back: Vector2 = IsoView.to_screen_dir(c.rears[0] - p.global_position) if c.rears.size() == 1 and c.rears[0] is Vector2 else Vector2.INF
	check(tip.distance_to(Vector2(muzzles["e"][0], muzzles["e"][1]) * scale) < 1.5, "로켓은 그림 속 탄두 자리에서 (화면 %s)" % tip)
	check(back.distance_to(Vector2(breeches["e"][0], breeches["e"][1]) * scale) < 1.5, "후폭풍은 그림 속 발사관 뒤끝에서 (화면 %s)" % back)
	w.pedestrians.free()
	w.free()
	c.free()
	d.free()

	# 날아가는 로켓: 그림 속 탄두 자리에서 맞히는 길로 내려앉고, 꼬리 연기가 끊기지 않는다
	var combat := Combat.new()
	combat.pedestrians = PedestrianManager.new()
	add_child(combat)
	var from := Vector2(50000, 50000)   # 건물·차가 없는 곳
	var shown := from + IsoView.lift(12.0 + 12.0) + Vector2(10, 0)
	combat.fire(from, Vector2.RIGHT, rocket, true, [], 0.0, 0, shown, shown - Vector2(20, 0))
	var pr: Dictionary = combat._projectiles[0] if combat._projectiles.size() == 1 else {}
	check(pr.has("off") and combat._backblasts.size() == 1, "쏜 자리에 앞 불꽃·후폭풍이 남는다")
	check(pr.has("off") and combat._rocket_at(pr).distance_to(shown - IsoView.lift(12.0)) < 0.5, "로켓은 그림 속 탄두 자리에서 시작")
	for i in 30:
		combat._fly(1.0 / 60.0)
	check(pr.has("off") and combat._rocket_at(pr).distance_to(pr.pos) < 0.01, "ROCKET_SETTLE을 날면 맞히는 길에 내려앉는다")
	var gaps := []
	for i in range(1, combat._rocket_smoke.size()):
		gaps.append((combat._rocket_smoke[i][0] as Vector2).distance_to(combat._rocket_smoke[i - 1][0]))
	check(combat._rocket_smoke.size() > 50 and gaps.max() < Combat.ROCKET_PUFF_EVERY * 1.6,
			"꼬리 연기가 끊기지 않는다 (%d덩이, 가장 큰 틈 %.1f)" % [combat._rocket_smoke.size(), gaps.max() if gaps else -1.0])
	combat.pedestrians.free()
	print("PLAYER_ROCKET_TEST ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
