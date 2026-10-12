class_name DayNight
extends Node
## 시간대와 날씨 (docs/01 §7). 게임 하루 = 실제 24분. 밤(기본 네온) → 새벽 → 낮 → 저녁.
## 화면 색은 CanvasModulate로 시간대에 맞춰 바꾸고, 비가 오면 빗줄기를 그리고 노면이 미끄러워진다(VehicleMotor.road_grip).
## 시각은 보행자 출현(NpcType.hours)에도 쓴다.

signal weather_changed(raining: bool)

const DAY_SECONDS := 24.0 * 60.0     ## 실제 24분에 하루
const START_HOUR := 21.0             ## 기본 비주얼은 야간 네온 — 밤에 시작한다
const SEED := 777
const WEATHER_CHECK := 3.0           ## 이만큼(게임 시간) 마다 날씨를 다시 정한다
const RAIN_CHANCE := 0.3
const RAIN_GRIP := 0.78              ## 비 오면 옆 미끄러짐을 잡는 힘이 이만큼으로
const RAIN_FADE := 0.25              ## 빗발이 세지고 약해지는 속도 (1/초)
## [시각, 색] — 사이는 섞는다
const TINTS := [
	[0.0, Color(0.8, 0.82, 0.96)], [5.0, Color(0.8, 0.82, 0.96)], [6.5, Color(0.88, 0.8, 0.9)],
	[8.0, Color(1, 1, 1)], [17.0, Color(1, 1, 1)], [18.5, Color(1.0, 0.86, 0.74)],
	[20.5, Color(0.8, 0.82, 0.96)], [24.0, Color(0.8, 0.82, 0.96)],
]
const RAIN_TINT := Color(0.82, 0.86, 0.92)

var hour := START_HOUR
var raining := false
var rain := 0.0                      ## 지금 빗발 세기 (0~1)
var paused_clock := false            ## 테스트용: 시계를 멈춘다
var pedestrians: PedestrianManager
var rng := RandomNumberGenerator.new()
var _until_check := WEATHER_CHECK
var _modulate: CanvasModulate
var _rain_layer: CanvasLayer
var _rain_view: Control
var _time := 0.0


func _ready() -> void:
	rng.seed = SEED
	VehicleMotor.road_grip = 1.0
	_modulate = CanvasModulate.new()
	add_child(_modulate)
	_rain_layer = CanvasLayer.new()
	_rain_layer.layer = 1   # HUD와 같은 층, HUD보다 먼저 붙어 HUD 밑에 그려진다
	add_child(_rain_layer)
	_rain_view = Control.new()
	_rain_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rain_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rain_view.draw.connect(_draw_rain)
	_rain_layer.add_child(_rain_view)
	_apply()


func _process(delta: float) -> void:
	_time += delta
	if not paused_clock:
		var hours := delta * 24.0 / DAY_SECONDS
		hour = fposmod(hour + hours, 24.0)
		_until_check -= hours
		if _until_check <= 0.0:
			_until_check = WEATHER_CHECK
			set_raining(rng.randf() < RAIN_CHANCE)
	rain = move_toward(rain, 1.0 if raining else 0.0, RAIN_FADE * delta)
	_apply()
	if rain > 0.0:
		_rain_view.queue_redraw()


func set_raining(on: bool) -> void:
	if on == raining:
		return
	raining = on
	weather_changed.emit(on)


func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	_apply()


func _apply() -> void:
	_modulate.color = tint(hour).lerp(tint(hour) * RAIN_TINT, rain)
	VehicleMotor.road_grip = lerpf(1.0, RAIN_GRIP, rain)
	_rain_view.visible = rain > 0.0
	if pedestrians:
		pedestrians.hour = hour


static func tint(h: float) -> Color:
	for k in range(1, TINTS.size()):
		if h <= TINTS[k][0]:
			var a: Array = TINTS[k - 1]
			var b: Array = TINTS[k]
			return (a[1] as Color).lerp(b[1], (h - a[0]) / (b[0] - a[0]))
	return TINTS[0][1]


static func is_night(h: float) -> bool:
	return h >= 20.0 or h < 6.0


## "21:30"
func clock_text() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]


func _draw_rain() -> void:
	var size := _rain_view.size
	var n := int(160 * rain)
	var fall := Vector2(-90, 520)
	for i in n:
		var x := fposmod(float(i * 73) + _time * fall.x * 0.3, size.x + 100.0)
		var y := fposmod(float(i * 151) + _time * fall.y * (0.8 + 0.4 * fmod(i * 0.37, 1.0)), size.y + 40.0) - 20.0
		var p := Vector2(x, y)
		_rain_view.draw_line(p, p + fall.normalized() * 14.0, Color(0.75, 0.85, 1.0, 0.35 * rain), 1.5)
