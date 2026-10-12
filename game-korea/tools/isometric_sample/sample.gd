extends "res://tools/visual_sample/sample.gd"
## 시뮬레이션은 원래 XY 평면, 표시는 독립 CanvasLayer의 사선 투영.

const ISO = preload("res://tools/isometric_sample/renderer.gd")
var iso: Node2D


func _ready() -> void:
	super._ready()
	get_window().title = "서울 거리 프로젝트 — 2.5D 강남 교차로"
	game.save_prefix = "user://isometric_sample_save_"
	game.hide()
	game.player.set_physics_process(false)
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	iso = ISO.new()
	iso.game = game
	iso.grain = street.grain
	iso.glow = street.glow
	iso.focus = intersection + Vector2(0, 80)
	layer.add_child(iso)
	follow = true
	_update_mode()
	game.hud.notify("2.5D 샘플 — WASD 화면 방향 이동 · F 탑승 · 운전 W/S 가감속 A/D 조향")
	if "--preview-shot" in OS.get_cmdline_user_args():
		for frame in 10:
			await get_tree().process_frame
		await _save("m7_isometric_gangnam")
		get_tree().quit()


func _update_mode() -> void:
	if mode_label:
		mode_label.text = "2.5D 강남 · C 카메라 · V 비 · P 추격 · WASD 이동 · F 탑승 · 건물 가림 자동 완화"


func _process(delta: float) -> void:
	if is_instance_valid(iso):
		if follow:
			iso.focus = iso.focus.lerp(game.director.controlled_target().global_position, 1.0 - exp(-delta * 7.0))
		else:
			iso.focus = intersection + Vector2(0, 80)
		iso.queue_redraw()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(iso):
		return
	var player: Player = game.player
	if not player.input_enabled or player.is_dead():
		player.velocity = Vector2.ZERO
		return
	var screen_dir := Input.get_vector("steer_left", "steer_right", "accelerate", "brake")
	var world_dir: Vector2 = iso.basis.affine_inverse().basis_xform(screen_dir).normalized() * screen_dir.length()
	player.velocity = world_dir * (Player.RUN_SPEED if Input.is_action_pressed("sprint") else Player.WALK_SPEED)
	if world_dir != Vector2.ZERO:
		player.facing = Vector2.UP.angle_to(world_dir)
		player.walk_phase += delta * player.velocity.length() / 9.0
	player.move_and_slide()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_B:
		return
	super._unhandled_key_input(event)


func _capture() -> void:
	# 상위 샘플의 --capture 자동 운전 시퀀스는 이 씬에서 사용하지 않는다.
	pass
