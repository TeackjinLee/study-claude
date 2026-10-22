extends Node
## 단일 입력, 예약 한 개, 타격 시점과 방향 잠금을 결정적으로 검사한다.
class ProbeCombat extends Combat:
	var hits := 0
	var directions: Array[Vector2] = []
	func _ready() -> void:
		pass
	func fire(_from: Vector2, dir: Vector2, _w: WeaponType, _by: bool, _exclude: Array[RID] = [], _spread := 0.0, _level := -1,
			_shown: Variant = null, _rear: Variant = null) -> void:
		hits += 1
		directions.append(dir)

var failures := 0
var p: Player
var w: PlayerWeapons
var c: ProbeCombat

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func step(seconds: float) -> void:
	for i in int(ceil(seconds * 120.0)):
		p.arsenal.update(1.0 / 120.0)
		w._step_punch(1.0 / 120.0)

func _ready() -> void:
	p = Player.new()
	p.control.use_external()
	add_child(p)
	p.set_physics_process(false)
	var d := Director.new()
	d.player = p
	c = ProbeCombat.new()
	w = PlayerWeapons.new()
	w.player = p
	w.director = d
	w.combat = c
	w.pedestrians = PedestrianManager.new()
	var attacks := PersonRig.punch_attacks()
	check(attacks.size() == 4 and attacks.map(func(a): return a["name"]) == ["jab", "straight", "uppercut", "counter"],
			"영상 공격 4가지 (잽·스트레이트·어퍼컷·카운터)")
	var ok: Array = PersonRig.dir8_for(null).get("attack_ok", [])
	check(ok.size() == 8 and ok.count(null) == 1 and ok[PersonRig.DIR8.find("n")] == null, "공격 그림: 영상 4방향 + 뒤집기 3방향, ↑만 없다")
	var drawable := true
	for k in 8:
		drawable = drawable and PersonRig.dir8_pick(Vector2.RIGHT.rotated(k * PI / 4.0), -1, ok) >= 0
	check(drawable, "8방향 모두 그릴 그림이 있다 (↑는 가까운 ↖·↗)")
	check(PersonRig.dir8_for(null).has("attack_tex"), "공격 시트 따로 한 장")
	var jab: Dictionary = attacks[0]
	var hit_at := float(jab["duration"]) * float(jab["hit_frame"]) / float(jab["frames"])
	check(w.shoot(), "첫 입력 시작")
	check(c.hits == 0, "준비 중 피해 없음")
	var locked := p.facing
	p.face(Vector2.RIGHT)
	check(p.facing == locked, "공격 중 조준 방향 고정")
	step(hit_at - 0.01)
	check(c.hits == 0, "잽 타격 프레임 전 피해 없음")
	step(0.02)
	check(c.hits == 1, "잽 타격 프레임 한 번 판정")
	step(float(jab["duration"]) - hit_at + 0.05)
	check(not w._punch_active and c.hits == 1, "회수 완료 후 추가 피해·자동 콤보 없음")
	check(p.get_meta(&"combat_stance", false), "전투 대기 복귀")
	check(w.shoot() and w._punch_index == 1, "두 번째 입력 스트레이트")
	for i in 30:
		w.shoot()
	step(0.60)
	check(w._punch_active and w._punch_index == 2, "연타는 어퍼컷 한 번만 예약")
	step(1.0)
	check(not w._punch_active and c.hits == 3, "예약 공격 뒤 입력 누적 없음")
	check(w.shoot() and w._punch_index == 3, "네 번째 입력 카운터")
	step(1.3)
	check(w.shoot() and w._punch_index == 0, "다음 입력 잽으로 순환")
	step(1.3)
	check(w.shoot() and w._punch_index == 0, "종료 후 0.7초 만료하면 잽")
	w._cancel_punch()
	p.arsenal.cooldown = 0
	var cmd := PlayerInputCommand.new()
	cmd.fire = true
	p.control.submit(cmd)
	var before := c.hits
	for i in 360:
		w._physics_process(1.0 / 120.0)
	check(c.hits == before + 1 and not w._punch_active, "3초 길게 누르기 공격 한 번")
	cmd.fire = false
	p.control.submit(cmd)
	w._physics_process(0.01)
	cmd.fire = true
	p.control.submit(cmd)
	w._physics_process(0.01)
	check(w._punch_active, "뗐다 다시 누르면 새 공격")
	p.knocked_down = true
	step(1.0)
	check(not w._punch_active and not w._punch_queued, "넘어지면 공격·예약 취소")
	w.pedestrians.free()
	w.free()
	c.free()
	d.free()
	print("PLAYER_PUNCH_TEST ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
