extends SceneTree
## 합성한 효과음을 들어 보는 도구: output/sound/<종류>.wav (종류마다 변형 셋을 차례로)와 sfx_all.wav (전부 이어서),
## 차 소리 engine_<종류>.wav(가속)·siren_<종류>.wav·skid.wav.
## 실행: godot --headless --path . -s res://tools/sound_preview.gd

const GAP := 0.35


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/sound"))
	var all := PackedFloat32Array()
	for kind: StringName in GunSynth.KINDS:
		var one := PackedFloat32Array()
		for variant in GunSynth.VARIANTS:
			one.append_array(GunSynth.render(kind, variant))
			one.append_array(_silence(GAP))
		Sfx.to_wav(one).save_to_wav("res://output/sound/%s.wav" % kind)
		all.append_array(one)
		all.append_array(_silence(GAP))
		print(kind, ": ", snappedf(GunSynth.render(kind).size() / GunSynth.MIX_RATE, 0.01), "s")
	Sfx.to_wav(all).save_to_wav("res://output/sound/sfx_all.wav")
	_car_sounds()
	quit()


## 차 소리: 한 번 울리는 것(충돌·부딪힘·경적·첨벙), 엔진 가속(공회전 → 기어 올리며 최고 속도 → 떼기), 사이렌, 타이어 끌림
func _car_sounds() -> void:
	for kind: StringName in CarSynth.SHOTS:
		var one := PackedFloat32Array()
		for variant in CarSynth.VARIANTS:
			one.append_array(CarSynth.render(kind, variant))
			one.append_array(_silence(GAP))
		Sfx.to_wav(one).save_to_wav("res://output/sound/%s.wav" % kind)
	for kind: StringName in CarSynth.ENGINES:
		Sfx.to_wav(_engine_run(kind)).save_to_wav("res://output/sound/engine_%s.wav" % kind)
	for kind: StringName in CarSynth.SIRENS:
		var loop := CarSynth.siren_loop(kind)
		var out := PackedFloat32Array()
		while out.size() < int(8.0 * CarSynth.MIX_RATE):
			out.append_array(loop)
		Sfx.to_wav(out).save_to_wav("res://output/sound/siren_%s.wav" % kind)
	var skid := CarSynth.skid_loop()
	skid.append_array(CarSynth.skid_loop())
	Sfx.to_wav(skid).save_to_wav("res://output/sound/skid.wav")
	print("차 소리: output/sound/engine_*.wav · siren_*.wav · skid.wav · crash/bump/horn.wav")


## 엔진 가속 8초: 2초 공회전 → 5초 동안 최고 속도까지 (기어가 바뀐다) → 1초 떼기. 게임처럼 토막을 회전수만큼 빠르게 읽는다
func _engine_run(kind: StringName) -> PackedFloat32Array:
	var on := CarSynth.engine_loop(kind, true)
	var off := CarSynth.engine_loop(kind, false)
	var base: float = CarSynth.ENGINES[kind].base_rpm
	var n := int(8.0 * CarSynth.MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var pos := 0.0
	var rpm := 0.0
	for i in n:
		var t := i / CarSynth.MIX_RATE
		var frac := clampf((t - 2.0) / 5.0, 0.0, 1.0)
		var pedal := 1.0 if t >= 2.0 and t < 7.0 else 0.0
		var goal := CarSynth.gear_rpm(kind, frac) + (0.0 if t < 7.0 else -0.25 * base)
		rpm = move_toward(rpm if rpm > 0.0 else goal, goal, 9000.0 / CarSynth.MIX_RATE)
		pos = fmod(pos + rpm / base, on.size())
		var k := int(pos)
		var f := pos - k
		var a := lerpf(on[k], on[(k + 1) % on.size()], f)
		var b := lerpf(off[k], off[(k + 1) % off.size()], f)
		out[i] = a * pedal + b * (1.0 - pedal * 0.7)
	return out


func _silence(sec: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(sec * GunSynth.MIX_RATE))
	return s
