extends SceneTree
## 합성한 효과음을 들어 보는 도구: output/sound/<종류>.wav (종류마다 변형 셋을 차례로)와 sfx_all.wav (전부 이어서).
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
	quit()


func _silence(sec: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(sec * GunSynth.MIX_RATE))
	return s
