extends Node
## 소총 자세: 시트·8방향 그림, 쏠 때만 발사 장면 표시(shot_at), 총구 거리(muzzle)로 총알이 나가고 궤적은 그림 속 총구에서 시작한다.
class ProbeCombat extends Combat:
	var froms: Array[Vector2] = []
	var shows: Array = []
	func _ready() -> void:
		pass
	func fire(from: Vector2, _dir: Vector2, _w: WeaponType, _by: bool, _exclude: Array[RID] = [], _spread := 0.0, _level := -1,
			shown: Variant = null, _rear: Variant = null) -> void:
		froms.append(from)
		shows.append(shown)

var failures := 0

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func _ready() -> void:
	var rifle: WeaponType = load("res://data/weapons/rifle.tres")
	var info := PersonRig.dir8_for(null)
	check(info.has("rifle_tex") and info.has("rifle_aim") and info.has("rifle_fire"), "소총 시트·조준·발사 장면")
	var ok: Array = info.get("rifle_ok", [])
	var real := 0
	for o in ok:
		real += 1 if o != null and not o[1] else 0
	check(ok.size() == 8 and real == 4 and ok[PersonRig.DIR8.find("s")] == null and ok[PersonRig.DIR8.find("n")] == null,
			"소총 그림: 영상 4방향(↘ → ← ↖) + 뒤집기 2방향, ↓·↑는 없다")
	var drawable := true
	for k in 8:
		drawable = drawable and PersonRig.dir8_pick(Vector2.RIGHT.rotated(k * PI / 4.0), -1, ok) >= 0
	check(drawable, "8방향 모두 그릴 그림이 있다 (↓·↑는 가까운 방향)")
	check(rifle.pose == &"rifle" and rifle.muzzle > Player.FIST.muzzle, "소총 자세·총구 거리는 데이터 (rifle.tres)")

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
	check(not p.has_meta(&"shot_at"), "쏘기 전에는 발사 장면 없음")
	w.shoot()
	check(not p.has_meta(&"shot_at"), "주먹은 소총 발사 장면을 쓰지 않는다")
	w._cancel_punch()
	p.arsenal.give(rifle, 30)
	p.arsenal.index = p.arsenal.weapons.find(rifle)
	p.arsenal.cooldown = 0.0
	c.froms.clear()
	c.shows.clear()
	w.mouse_aim = false
	p.facing = Vector2.UP.angle_to(IsoView.BASIS.affine_inverse().basis_xform(Vector2.RIGHT))   # 화면 → 쪽
	check(w.shoot() and p.has_meta(&"shot_at"), "소총을 쏘면 발사 장면 시작")
	check(c.froms.size() == 1 and absf(c.froms[0].distance_to(p.global_position) - rifle.muzzle) < 0.5, "총알은 총구 거리에서 나간다")
	# 궤적 시작: 화면 → 쪽으로 서서 쏘면 그림 속 총구(발끝에서 화면 오른쪽 위, .json rifle_muzzle e)
	var muzzle: Array = info.get("rifle_muzzle", {}).get("e", [])
	var scale := PersonRig.SPRITE_HEIGHT / PersonRig.SPRITE_BODY
	var seen: Vector2 = IsoView.to_screen_dir(c.shows[0] - p.global_position) if c.shows.size() == 1 and c.shows[0] is Vector2 else Vector2.INF
	check(muzzle.size() == 2 and seen.distance_to(Vector2(muzzle[0], muzzle[1]) * scale) < 1.5,
			"궤적은 그림 속 총구에서 시작한다 (화면 %s)" % seen)
	p.velocity = Vector2(80, 0)
	p.arsenal.cooldown = 0.0
	w.shoot()
	check(c.shows.size() == 2 and c.shows[1] == null, "걸으며 쏘면 평소 자리 (소총 자세 그림이 아니다)")
	p.velocity = Vector2.ZERO
	# 그리기: 서 있으면 소총 그림, 걸으면 평소 그림
	var probe := Node2D.new()
	var drawn := []
	var smg: WeaponType = load("res://data/weapons/smg.tres")
	probe.draw.connect(func():
		drawn.assign([PersonRig._draw_gun(probe, 0.0, 0.0, 1.0, null, 0.0, rifle),
				PersonRig._draw_gun(probe, 0.0, 0.0, 1.0, null, 1.0, rifle),
				PersonRig._draw_gun(probe, 0.0, 0.0, 1.0, null, 0.0, smg)]))
	add_child(probe)
	probe.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	check(drawn.size() == 3 and drawn[0], "서 있으면 소총 그림")
	check(drawn.size() == 3 and not drawn[1], "걸을 때는 평소 걷기 그림")
	check(drawn.size() == 3 and not drawn[2], "기관단총은 총 자세 그림이 없다 (평소 그림)")
	w.pedestrians.free()
	w.free()
	c.free()
	d.free()
	print("PLAYER_RIFLE_TEST ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
