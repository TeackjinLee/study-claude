extends Node
## 권총 자세: 영상 8방향 시트(조준·발사·겨눈 채 걷기), 서 있을 때·걸을 때 권총 그림, 뛰면 평소 그림,
## 쏠 때 발사 장면(shot_at), 궤적은 그림 속 총구에서 시작한다.
class ProbeCombat extends Combat:
	var shows: Array = []
	func _ready() -> void:
		pass
	func fire(_from: Vector2, _dir: Vector2, _w: WeaponType, _by: bool, _exclude: Array[RID] = [], _spread := 0.0, _level := -1,
			shown: Variant = null, _rear: Variant = null) -> void:
		shows.append(shown)

var failures := 0

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func _ready() -> void:
	var pistol: WeaponType = load("res://data/weapons/pistol.tres")
	var info := PersonRig.dir8_for(null)
	check(info.has("pistol_tex") and info.has("pistol_aim") and info.has("pistol_fire") and info.has("pistol_walk"),
			"권총 시트·조준·발사·겨눈 채 걷기 장면")
	var ok: Array = info.get("pistol_ok", [])
	var real := 0
	for o in ok:
		real += 1 if o != null and not o[1] else 0
	check(ok.size() == 8 and real == 8, "권총 그림: 영상 8방향 모두 (뒤집기 없음)")
	var muzzles: Dictionary = info.get("pistol_muzzle", {})
	check(muzzles.size() == 8, "8방향 모두 총구 자리가 있다")
	check(pistol.pose == &"pistol", "권총 자세는 데이터 (pistol.tres)")
	var walk: Dictionary = info.get("pistol_walk", {})
	check(walk.get("loop", false) and int(walk.get("frames", 0)) > 20, "겨눈 채 걷기는 한 바퀴 되풀이")

	# 그리기: 서 있으면·걸으면 권총 그림, 뛰면 평소 그림, NPC는 평소 그림
	var probe := Node2D.new()
	var drawn := []
	var cols := []
	probe.draw.connect(func():
		drawn.assign([PersonRig._draw_gun(probe, 0.0, 0.0, 1.0, null, 0.0, pistol),
				PersonRig._draw_gun(probe, 0.0, 1.0, 1.0, null, 1.0, pistol),
				PersonRig._draw_gun(probe, 0.0, 0.0, 1.0, null, 2.0, pistol),
				PersonRig._draw_gun(probe, 0.0, 0.0, 1.0, NpcType.new(), 0.0, pistol)]))
	add_child(probe)
	probe.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	check(drawn.size() == 4 and drawn[0], "서 있으면 권총 그림")
	check(drawn.size() == 4 and drawn[1], "걸으면 겨눈 채 걷는 그림")
	check(drawn.size() == 4 and not drawn[2], "뛰면 평소 달리기 그림")
	check(drawn.size() == 4 and not drawn[3], "NPC는 평소 그림")

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
	p.arsenal.give(pistol, 30)
	p.arsenal.index = p.arsenal.weapons.find(pistol)
	var scale := PersonRig.SPRITE_HEIGHT / PersonRig.SPRITE_BODY
	for spec in [["e", Vector2.RIGHT], ["s", Vector2.DOWN]]:
		if p.has_meta(&"shot_at"):
			p.remove_meta(&"shot_at")
		p.arsenal.cooldown = 0.0
		p.facing = Vector2.UP.angle_to(IsoView.BASIS.affine_inverse().basis_xform(spec[1]))
		c.shows.clear()
		check(w.shoot() and p.has_meta(&"shot_at"), "권총을 쏘면 발사 장면 시작 (%s)" % spec[0])
		var row := 8 if spec[0] == "e" else 0
		var m: Array = PersonRig.gun32_for("pistol")["muzzles"][row][1]
		var seen: Vector2 = IsoView.to_screen_dir(c.shows[0] - p.global_position) if c.shows.size() == 1 and c.shows[0] is Vector2 else Vector2.INF
		check(m.size() == 2 and seen.distance_to(Vector2(m[0], m[1]) * scale) < 1.5, "궤적은 그림 속 총구에서 (%s, 화면 %s)" % [spec[0], seen])
	p.velocity = Vector2(Player.WALK_SPEED, 0)
	p.arsenal.cooldown = 0.0
	c.shows.clear()
	w.shoot()
	check(c.shows.size() == 1 and c.shows[0] is Vector2, "걸으며 쏴도 그림 속 총구에서")
	p.velocity = Vector2(Player.WALK_SPEED * 3.0, 0)
	p.arsenal.cooldown = 0.0
	c.shows.clear()
	w.shoot()
	check(c.shows.size() == 1 and c.shows[0] == null, "뛰며 쏘면 평소 자리")
	w.pedestrians.free()
	w.free()
	c.free()
	d.free()
	print("PLAYER_PISTOL_TEST ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
