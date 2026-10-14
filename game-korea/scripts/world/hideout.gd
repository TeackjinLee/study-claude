class_name Hideout
extends Node2D
## 은신처 문 앞 발판. 걸어서 밟으면 알린다 — 내 것이면 저장 메뉴, 아니면 살지 묻는다 (main이 정한다).
## 잠긴 구역의 은신처는 보이지 않고 밟을 수도 없다.

signal stepped_on

const REACH := 16.0
const REARM := 50.0
const SIZE := Vector2(30, 20)

var type: HideoutType
var owned := true
var player: Player
var director: Director
var _armed := true
var _time := 0.0


func _ready() -> void:
	z_index = -1
	global_position = type.door


func _physics_process(delta: float) -> void:
	_time += delta
	visible = CityMap.is_open_block(City.nearest_block(global_position))
	if not visible:
		return
	var d := player.global_position.distance_to(global_position)
	if d > REARM:
		_armed = true
	elif _armed and d < REACH and director.current_vehicle == null and player.visible and not player.is_dead():
		_armed = false
		stepped_on.emit()


## 그림은 화면 프레임마다 한 번 (물리 틱마다 부르면 느릴수록 한 프레임에 여러 번 그린다)
func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var r := Rect2(-SIZE * 0.5, SIZE)
	var glow := 0.5 + 0.5 * sin(_time * 3.0)
	var font := ThemeDB.fallback_font
	if owned:
		draw_rect(r.grow(4), Color(0.3, 1.0, 0.5, 0.12 + 0.12 * glow))
		draw_rect(r, Color(0.1, 0.35, 0.2))
		draw_rect(r, Color(0.4, 1.0, 0.6), false, 2.0)
		draw_string(font, Vector2(r.position.x, r.end.y - 5), "저장", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, Color(0.8, 1.0, 0.85))
		return
	# 아직 안 산 은신처: 금색 발판에 값
	var gold := Color(1.0, 0.82, 0.3)
	draw_rect(r.grow(4), Color(gold, 0.08 + 0.08 * glow))
	draw_rect(r, Color(0.3, 0.24, 0.08))
	draw_rect(r, gold, false, 2.0)
	draw_string(font, Vector2(r.position.x - 30, r.end.y - 5), "매물", HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 60, 12, gold)
	draw_string(font, Vector2(r.position.x - 40, r.end.y + 13), "₩" + Hud.won(type.price), HORIZONTAL_ALIGNMENT_CENTER,
		r.size.x + 80, 11, Color(gold, 0.85))
