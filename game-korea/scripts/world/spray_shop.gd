class_name SprayShop
extends Node2D
## 카센터 정비 칸 (docs/05 §4 즉시 감소). 차를 몰고 들어와 세우면 돈을 받고 새로 칠하고 고친다.
## 수배 중이면 별이 STARS_REMOVED개 떨어진다 — 단, 경찰 눈앞에서는 안 된다(따돌리고 와야 한다).
## ★4는 저절로 내려가지 않으므로 여기가 거의 유일한 탈출구다. ★5부터는(WantedSystem.locked) 고치고 칠해 주지만 별은 못 뗀다.

signal serviced(stars: int)          ## 도색 완료 (뗀 별 수)
signal notice(text: String)          ## HUD 알림 문구

const PRICE := 50000
const STARS_REMOVED := 2
const REACH := 36.0
const STOP_SPEED := 60.0
const REARM := 90.0
const SIZE := Vector2(44, 76)
const COLORS: Array[Color] = [
	Color(0.85, 0.15, 0.18), Color(0.15, 0.35, 0.8), Color(0.12, 0.12, 0.13), Color(0.92, 0.92, 0.94),
	Color(0.2, 0.55, 0.3), Color(0.95, 0.75, 0.15), Color(0.5, 0.2, 0.6),
]

var director: Director
var police: PoliceDispatcher
var wallet: Wallet
var _armed := true
var _next_color := 0
var _time := 0.0


func _ready() -> void:
	z_index = -3
	material = Terrain.material()   # 바닥 그림을 지형 높이만큼 올린다
	global_position = City.spray_bay()


func _physics_process(delta: float) -> void:
	_time += delta
	var v := director.current_vehicle
	if v == null or v.airborne():
		return
	var d := v.global_position.distance_to(global_position)
	if d > REARM:
		_armed = true
	if not _armed or d > REACH or v.speed() > STOP_SPEED:
		return
	_armed = false
	service(v)


## 그림은 화면 프레임마다 한 번 (물리 틱마다 부르면 느릴수록 한 프레임에 여러 번 그린다)
func _process(_delta: float) -> void:
	queue_redraw()


## 차 한 대를 받는다. 도색했으면 true (못 했으면 이유를 notice로 알린다)
func service(v: Vehicle) -> bool:
	var level := police.wanted.level
	if v.burning >= 0.0 or v.wrecked:
		notice.emit("불붙은 차는 못 받는다")
		return false
	if level == 0 and v.health >= v.max_health():
		notice.emit("카센터: 손볼 데가 없다")
		return false
	if level > 0 and police.seen:
		notice.emit("경찰이 보고 있다 — 따돌리고 와라")
		return false
	if wallet.money < PRICE:
		notice.emit("카센터: ₩%s 필요" % Hud.won(PRICE))
		return false
	wallet.pay(PRICE)
	v.health = v.max_health()
	v.paint = COLORS[_next_color % COLORS.size()]
	_next_color += 1
	v.queue_redraw()
	var locked := police.wanted.locked()
	var removed := 0 if locked else mini(STARS_REMOVED, level)
	if removed > 0:
		police.wanted.lower(STARS_REMOVED)
	var note := "   수배 −%d" % removed if removed > 0 else ("   ★5부터는 수배가 떨어지지 않는다" if locked else "")
	notice.emit("도색·수리 완료 −₩%s%s" % [Hud.won(PRICE), note])
	serviced.emit(removed)
	return true


func _draw() -> void:
	var r := Rect2(-SIZE * 0.5, SIZE)
	var glow := 0.5 + 0.5 * sin(_time * 3.0)
	draw_rect(r, Color(0.3, 0.8, 1.0, 0.08 + 0.08 * glow))
	draw_rect(r, Color(0.3, 0.8, 1.0, 0.8), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(r.position.x, 6), "도색", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14,
		Color(0.8, 0.95, 1.0, 0.9))
