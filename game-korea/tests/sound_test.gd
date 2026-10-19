extends Node
## 효과음 검증.
##  1. 합성기(GunSynth): 종류마다 소리가 나고 찢어지지 않으며, 맨 앞이 크고 사그라진다. 같은 값이면 같은 소리.
##  2. 무거울수록 낮다: 낮은 소리(150Hz 아래) 몫이 권총 < 소총 < 포 < 폭발, 기관단총이 가장 짧다.
##  3. 총 데이터: 쏘는 총·로켓·포에는 소리가 있고, 모두 합성기가 아는 종류다.
##  4. 본편: 쏘면 그 총 소리가, 터지면 폭발 소리가 난다. 산탄 한 번은 한 소리.
## 실행: godot --headless --fixed-fps 60 --path . res://tests/sound_test.tscn

const PISTOL: WeaponType = preload("res://data/weapons/pistol.tres")
const SHOTGUN: WeaponType = preload("res://data/weapons/shotgun.tres")
const FIST: WeaponType = preload("res://data/weapons/fist.tres")

var _failures: Array[String] = []


func _ready() -> void:
	_test_synth()
	_test_weight()
	_test_data()
	await _test_in_game()
	if _failures.is_empty():
		print("sound_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _test_synth() -> void:
	for kind: StringName in GunSynth.KINDS:
		var s := GunSynth.render(kind)
		var want := int(float(GunSynth.KINDS[kind].len) * GunSynth.MIX_RATE)
		_expect(s.size() == want, "%s 길이 (%d ≠ %d)" % [kind, s.size(), want])
		var top := 0.0
		for v in s:
			top = maxf(top, absf(v))
		_expect(top > 0.3 and top <= 1.0, "%s 크기 0.3~1 (%.2f)" % [kind, top])
		var head := _rms(s, 0, int(0.03 * GunSynth.MIX_RATE))
		var tail := _rms(s, int(s.size() * 0.8), s.size())
		_expect(head > tail * 3.0, "%s 맨 앞이 크고 사그라진다 (앞 %.3f 끝 %.3f)" % [kind, head, tail])
		_expect(GunSynth.render(kind) == s, "%s 같은 값이면 같은 소리" % kind)
		_expect(GunSynth.render(kind, 1) != s, "%s 변형은 조금 다르다" % kind)


func _test_weight() -> void:
	var order := [&"pistol", &"rifle", &"cannon", &"explosion"]
	var lows: Array[float] = []
	for kind: StringName in order:
		lows.append(_low_share(GunSynth.render(kind)))
	for i in range(1, order.size()):
		_expect(lows[i] > lows[i - 1], "%s가 %s보다 낮다 (낮은 소리 몫 %.2f > %.2f)" % [order[i], order[i - 1], lows[i], lows[i - 1]])
	for kind: StringName in GunSynth.KINDS:
		_expect(kind == &"smg" or GunSynth.KINDS[kind].len > GunSynth.KINDS[&"smg"].len,
			"빨리 쏘는 기관단총 소리가 가장 짧다 (%s)" % kind)


func _test_data() -> void:
	var dir := "res://data/weapons/"
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".tres"):
			continue
		var w: WeaponType = load(dir + f)
		var shoots := not w.melee and not w.flame and not w.water and w.projectile in [&"", &"rocket"]
		if shoots:
			_expect(w.sound != &"", "%s: 쏘는 무기에는 소리가 있다" % w.id)
		if w.sound != &"":
			_expect(GunSynth.KINDS.has(w.sound), "%s: 소리 %s는 합성기가 아는 종류" % [w.id, w.sound])


func _test_in_game() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.traffic_count = 0
	main.bus_count = 0
	main.police_patrols = 0
	add_child(main)
	await _frames(2)
	var combat: Combat = main.combat
	var sfx := Sfx.current
	_expect(sfx != null and sfx.get_parent() == combat, "본편에 효과음 노드가 있다")
	if sfx == null:
		main.queue_free()
		return
	var at: Vector2 = main.player.global_position
	var none: Array[RID] = [main.player.get_rid()]
	combat.fire(at, Vector2.RIGHT, PISTOL, true, none)
	_expect(_last(sfx) == &"pistol", "권총을 쏘면 권총 소리 (%s)" % _last(sfx))
	await _frames(5)
	var n := sfx.heard.size()
	combat.fire(at, Vector2.RIGHT, SHOTGUN, true, none)
	_expect(sfx.heard.size() == n + 1 and _last(sfx) == &"shotgun",
		"산탄 한 번은 소리 한 번 (%d)" % (sfx.heard.size() - n))
	await _frames(5)
	n = sfx.heard.size()
	combat.fire(at, Vector2.RIGHT, FIST, true, none)
	_expect(sfx.heard.size() == n, "주먹은 소리가 없다")
	combat.explode(at + Vector2(600, 0), true, null, 2.0)
	_expect(_last(sfx) == &"explosion" and float(sfx.heard[-1][2]) == 2.0, "폭발은 크기를 담아 폭발 소리")
	# 창 모드로 돌렸을 때만: 다 구워지면 실제로 목소리가 운다
	if not sfx._silent:
		for i in 300:
			if sfx._streams.size() == GunSynth.KINDS.size():
				break
			await _frames(1)
		_expect(sfx._streams.size() == GunSynth.KINDS.size(), "효과음을 5초 안에 다 굽는다")
		await _frames(5)
		combat.fire(at, Vector2.RIGHT, PISTOL, true, none)
		_expect(sfx._voices.any(func(p: AudioStreamPlayer): return p.playing), "쏘면 소리가 난다")
	main.queue_free()
	await _frames(2)
	_expect(Sfx.current == null, "본편이 사라지면 효과음 노드도 비운다")


func _last(sfx: Sfx) -> StringName:
	return sfx.heard[-1][0] if not sfx.heard.is_empty() else &""


func _rms(s: PackedFloat32Array, a: int, b: int) -> float:
	var sum := 0.0
	for i in range(a, b):
		sum += s[i] * s[i]
	return sqrt(sum / maxi(b - a, 1))


## 150Hz 아래 소리가 차지하는 몫 (두 번 거른 낮은 소리의 힘 / 전체 힘)
func _low_share(s: PackedFloat32Array) -> float:
	var a := 1.0 - exp(-TAU * 150.0 / GunSynth.MIX_RATE)
	var l1 := 0.0
	var l2 := 0.0
	var low := 0.0
	var all := 0.0
	for v in s:
		l1 += (v - l1) * a
		l2 += (l1 - l2) * a
		low += l2 * l2
		all += v * v
	return low / all


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
