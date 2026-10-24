extends Node
## 새 사격 경로의 32방향·무기 교체·반동·총구·기존 이동 모션 보존을 확인한다.

class ProbeCombat extends Combat:
	var fired: Array = []
	func _ready() -> void:
		pass
	func fire(from: Vector2, dir: Vector2, weapon: WeaponType, _by: bool, _exclude: Array[RID] = [], _spread := 0.0,
			_level := -1, shown: Variant = null, _rear: Variant = null) -> void:
		fired.append({"from": from, "dir": dir, "weapon": weapon, "shown": shown})

var failures := 0

func check(ok: bool, text: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", text)

func _ready() -> void:
	var p := Player.new()
	p.control.use_external()
	add_child(p)
	p.set_physics_process(false)
	var director := Director.new()
	director.player = p
	var combat := ProbeCombat.new()
	var controls := PlayerWeapons.new()
	controls.player = p
	controls.director = director
	controls.combat = combat
	controls.pedestrians = PedestrianManager.new()
	controls.mouse_aim = false
	for pose: String in ["pistol", "smg", "shotgun", "rifle"]:
		var weapon: WeaponType = load("res://data/weapons/" + pose + ".tres")
		var info := PersonRig.gun32_for(pose)
		check(not info.is_empty() and int(info.get("directions", 0)) == 32, pose + " 32방향 자료")
		check(weapon.pose == StringName(pose), pose + " 무기별 자세 연결")
		if info.is_empty():
			continue
		check(info["tex"].get_size() == Vector2(896, 3584), pose + " 별도 시트 규격")
		p.arsenal.give(weapon, 100)
		p.arsenal.index = p.arsenal.weapons.find(weapon)
		for k in 32:
			var screen := Vector2.DOWN.rotated(-k * TAU / 32.0)
			var world := IsoView.BASIS.affine_inverse().basis_xform(screen).normalized()
			p.facing = Vector2.UP.angle_to(world)
			check(PersonRig.gun32_pick(screen) == k, pose + " 방향 %d" % k)
			p.arsenal.cooldown = 0.0
			combat.fired.clear()
			check(controls.shoot(), pose + " 발사 %d" % k)
			check(combat.fired.size() == 1, pose + " 한 발에 판정 호출 한 번")
			if combat.fired.size() == 1:
				var shot: Dictionary = combat.fired[0]
				check(shot["weapon"] == weapon and shot["dir"].dot(world) > 0.999, pose + " 기존 무기·연속 발사 각도")
				var m: Array = info["muzzles"][k][1]
				var expected := Vector2(float(m[0]), float(m[1])) * PersonRig.SPRITE_HEIGHT / PersonRig.SPRITE_BODY
				var shown: Variant = shot["shown"]
				check(shown is Vector2 and IsoView.to_screen_dir(shown - p.global_position).distance_to(expected) < 0.1,
						pose + " 그림과 같은 총구 %d" % k)
			check(not controls.shoot(), pose + " 기존 연사 간격 유지")
		var duration: float = info["fire_duration"]
		p.set_meta(&"shot_at", Time.get_ticks_msec() / 1000.0 - duration * 0.4)
		check(PersonRig.gun32_col(p, weapon, info) > 1, pose + " 반동 진행")
		p.set_meta(&"shot_at", Time.get_ticks_msec() / 1000.0 - duration - 0.01)
		check(PersonRig.gun32_col(p, weapon, info) == 0, pose + " 조준 복귀")
		p.set_meta(&"shot_at", Time.get_ticks_msec() / 1000.0)
		p.set_meta(&"shot_weapon", &"OTHER")
		check(PersonRig.gun32_col(p, weapon, info) == 0, pose + " 다른 총의 반동을 물려받지 않음")
		p.velocity = Vector2(Player.WALK_SPEED * 3.0, 0)
		check(PersonRig.gun_muzzle(p, p.facing, 1.0, 2.0, weapon) == null, pose + " 달리기 기존 경로")
		p.velocity = Vector2.ZERO
		print("32방향 확인: ", pose)
	controls.pedestrians.free()
	controls.free()
	combat.free()
	director.free()
	print("PLAYER_GUNS32_TEST ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
