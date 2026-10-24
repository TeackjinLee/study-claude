class_name TargetRing
extends Node2D
## 주인공이 고른 표적(PlayerWeapons.selected) 발밑의 빨간 원과 원을 도는 네 꺾쇠. 바닥에 그려 2.5D에서는 납작한 타원이 된다.
## 그 사람 바로 밑 차례(z − 1)에 그려 몸에 가린다. 고른 사람이 없으면 숨는다.

const RADIUS := 12.0
const COLOR := Color(1.0, 0.2, 0.18)
const SPIN := 1.6                 ## 꺾쇠가 도는 빠르기 (rad/s)

var weapons: PlayerWeapons


func _ready() -> void:
	z_as_relative = false


func _process(_delta: float) -> void:
	visible = weapons.locked()
	if visible:
		queue_redraw()


func _draw() -> void:
	if not weapons.locked():
		return    # 다시 그리기를 부른 뒤 같은 프레임에 풀렸다
	var p := weapons.selected
	var at := p.global_position
	z_index = maxi(p.z_index - 1, 0) if IsoView.enabled else 0
	var up := IsoView.lift(IsoView.ground(at, p.level)) if IsoView.enabled else Vector2.ZERO
	var c := at + up - global_position
	var r := RADIUS * p.npc.body_scale
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.7 + 0.3 * sin(t * 6.0)
	draw_circle(c, r, Color(COLOR, 0.18 * pulse))
	draw_arc(c, r, 0.0, TAU, 40, Color(0, 0, 0, 0.5), 4.0, true)
	draw_arc(c, r, 0.0, TAU, 40, Color(COLOR, 0.95), 2.0, true)
	# 원 밖에서 안을 가리키는 꺾쇠 넷 (천천히 돈다)
	for k in 4:
		var d := Vector2.from_angle(t * SPIN + k * TAU / 4.0)
		var side := d.orthogonal()
		var tip := c + d * (r + 2.0)
		var tri := PackedVector2Array([tip, tip + d * 6.0 + side * 4.0, tip + d * 6.0 - side * 4.0])
		draw_colored_polygon(tri, Color(COLOR, pulse))
		tri.append(tri[0])
		draw_polyline(tri, Color(0, 0, 0, 0.6), 1.0, true)
