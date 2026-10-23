class_name HeadingRing
extends Node2D
## 조종 중인 주인공(도보·차) 발밑 원과 진행 방향 화살표. 바닥에 그려 2.5D에서는 납작한 타원이 된다.
## 서 있는 사람·차 바로 밑 차례(z − 1)에 그려 몸에 가리고, 떠 있는 헬기에는 그리지 않는다.

const FOOT_RADIUS := 13.0         ## 도보일 때 원 반지름 (월드 px)
const CAR_MARGIN := 6.0           ## 차일 때 차 반 길이에 더하는 몫
const COLOR := Color(1.0, 0.24, 0.2)
const ARROW := 7.0                ## 화살표 길이
const GAP := 0.42                 ## 화살표 쪽 원을 비우는 반각 (rad)

var director: Director


func _ready() -> void:
	z_as_relative = false


func _process(_delta: float) -> void:
	var car := director.current_vehicle
	var me := director.player
	visible = not (car and car.airborne()) and (car != null or not (me.is_dead() or me.knocked_down))
	queue_redraw()


func _draw() -> void:
	var target := director.controlled_target()
	var car := director.current_vehicle
	var level: int = target.get("level")
	var at := target.global_position
	z_index = maxi(target.z_index - 1, 0) if IsoView.enabled else 0
	var up := IsoView.lift(IsoView.ground(at, level)) if IsoView.enabled else Vector2.ZERO
	var heading := car.motor.heading if car else director.player.facing
	var r := car.stats.size.y * 0.5 + CAR_MARGIN if car else FOOT_RADIUS
	var c := at + up - global_position
	var dir := Vector2.UP.rotated(heading)
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 220.0)
	var start := dir.angle() + GAP
	var span := TAU - GAP * 2.0
	draw_arc(c, r, start, start + span, 48, Color(0, 0, 0, 0.45), 4.0, true)
	draw_arc(c, r, start, start + span, 48, Color(COLOR, 0.85 * pulse), 2.0, true)
	# 진행 방향 화살표: 원 바깥으로 내민 삼각형
	var side := dir.orthogonal()
	var tip := c + dir * (r + ARROW)
	var base := c + dir * (r - 1.5)
	var tri := PackedVector2Array([tip, base + side * ARROW * 0.7, base - side * ARROW * 0.7])
	draw_colored_polygon(tri, Color(COLOR, pulse))
	tri.append(tri[0])
	draw_polyline(tri, Color(0, 0, 0, 0.6), 1.2, true)
