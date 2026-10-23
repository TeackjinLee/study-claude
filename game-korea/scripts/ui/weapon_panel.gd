class_name WeaponPanel
extends Control
## HUD 오른쪽 위 무기 칸: 둥근 어두운 판에 든 무기 그림(코드로 그린 실루엣)·이름·탄약 "남은 / 최대".
## 무기를 바꾸면 판 테두리가 잠깐 밝아진다.

const SIZE := Vector2(236, 104)
const BG := Color(0.05, 0.06, 0.09, 0.82)
const EDGE := Color(0.92, 0.94, 1.0, 0.9)
const METAL := Color(0.72, 0.74, 0.78)
const DARK := Color(0.2, 0.21, 0.24)
const OUTLINE := Color(0, 0, 0, 0.85)
const SWAP_FLASH := 0.35

var weapon: WeaponType
var ammo := -1                    ## −1 = 탄약 없음 (주먹·방망이)
var _flash := 0.0
var _shown: WeaponType


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_weapon(w: WeaponType, n: int) -> void:
	if w != _shown:
		_shown = w
		_flash = SWAP_FLASH
	if w != weapon or n != ammo or _flash > 0.0:
		weapon = w
		ammo = n
		queue_redraw()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
		queue_redraw()


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, SIZE)
	var panel := StyleBoxFlat.new()
	panel.bg_color = BG
	panel.set_corner_radius_all(12)
	panel.set_border_width_all(2)
	panel.border_color = EDGE.lerp(Color(1.0, 0.85, 0.3), _flash / SWAP_FLASH)
	panel.shadow_color = Color(0, 0, 0, 0.5)
	panel.shadow_size = 6
	draw_style_box(panel, box)
	if weapon == null:
		return
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(14, 24), Locale.t(weapon.display_name), HORIZONTAL_ALIGNMENT_LEFT, SIZE.x - 28, 15, 4, OUTLINE)
	draw_string(font, Vector2(14, 24), Locale.t(weapon.display_name), HORIZONTAL_ALIGNMENT_LEFT, SIZE.x - 28, 15, Color(1, 1, 1, 0.75))
	draw_icon(self, Rect2(16, 32, SIZE.x * 0.62, 58), weapon.id)
	if ammo >= 0:
		var text := "%d / %d" % [ammo, weapon.max_ammo] if weapon.max_ammo > 0 else str(ammo)
		var color := Color(1.0, 0.4, 0.35) if ammo == 0 else Color.WHITE
		draw_string_outline(font, Vector2(0, SIZE.y - 12), text, HORIZONTAL_ALIGNMENT_RIGHT, SIZE.x - 14, 26, 6, OUTLINE)
		draw_string(font, Vector2(0, SIZE.y - 12), text, HORIZONTAL_ALIGNMENT_RIGHT, SIZE.x - 14, 26, color)


## 무기 실루엣 (rect 안, 총구가 오른쪽). 모르는 무기는 권총 모양
static func draw_icon(ci: CanvasItem, rect: Rect2, id: StringName) -> void:
	var s := rect.size.y / 64.0
	var o := rect.position + Vector2(0, rect.size.y * 0.5)
	var shapes: Array = []    # [다각형(50 높이 기준 좌표), 색]
	match id:
		&"FIST":
			shapes = [[[Vector2(30, -12), Vector2(62, -14), Vector2(70, -6), Vector2(70, 10), Vector2(60, 16), Vector2(32, 14), Vector2(26, 2)], Color(0.86, 0.7, 0.56)],
				[[Vector2(10, -8), Vector2(30, -10), Vector2(30, 12), Vector2(10, 10)], Color(0.25, 0.3, 0.45)]]
			for k in 3:
				var x := 40.0 + k * 9.0
				shapes.append([[Vector2(x, -14), Vector2(x + 1, -4), Vector2(x, -4)], Color(0.6, 0.45, 0.35)])
		&"BAT":
			shapes = [[[Vector2(4, 4), Vector2(30, 1), Vector2(118, -9), Vector2(124, -5), Vector2(124, 5), Vector2(118, 9), Vector2(30, 5), Vector2(4, 7)], Color(0.68, 0.5, 0.3)],
				[[Vector2(4, 1), Vector2(28, 0), Vector2(28, 6), Vector2(4, 8)], Color(0.15, 0.15, 0.18)]]
		&"SMG", &"SWAT_SMG", &"HELI_MG", &"CAR_MG", &"JEEP_MG":
			shapes = [[[Vector2(10, -12), Vector2(96, -12), Vector2(96, -2), Vector2(112, -2), Vector2(112, 3), Vector2(96, 3), Vector2(88, 6), Vector2(50, 6), Vector2(46, 22), Vector2(36, 22), Vector2(38, 6), Vector2(22, 6), Vector2(10, 0)], METAL],
				[[Vector2(56, 6), Vector2(66, 6), Vector2(64, 30), Vector2(56, 30)], DARK],
				[[Vector2(0, -10), Vector2(12, -10), Vector2(12, -2), Vector2(0, 2)], DARK],
				[[Vector2(30, -18), Vector2(70, -18), Vector2(70, -12), Vector2(30, -12)], DARK]]
		&"RIFLE", &"ARMY_RIFLE":
			shapes = [[[Vector2(0, -6), Vector2(30, -10), Vector2(108, -10), Vector2(108, -5), Vector2(128, -5), Vector2(128, -1), Vector2(108, -1), Vector2(96, 3), Vector2(60, 3), Vector2(54, 20), Vector2(46, 20), Vector2(48, 3), Vector2(30, 3), Vector2(0, 12)], METAL],
				[[Vector2(64, 3), Vector2(74, 3), Vector2(80, 26), Vector2(70, 28)], DARK],
				[[Vector2(36, -18), Vector2(76, -18), Vector2(76, -10), Vector2(36, -10)], DARK]]
		&"SHOTGUN":
			shapes = [[[Vector2(0, -2), Vector2(36, -8), Vector2(124, -8), Vector2(124, -2), Vector2(36, 2), Vector2(32, 6), Vector2(0, 14)], Color(0.55, 0.38, 0.24)],
				[[Vector2(36, -8), Vector2(124, -8), Vector2(124, -3), Vector2(36, -3)], METAL],
				[[Vector2(56, 0), Vector2(98, 0), Vector2(98, 6), Vector2(56, 6)], Color(0.42, 0.3, 0.2)]]
		&"ROCKET", &"TANK_CANNON":
			shapes = [[[Vector2(0, -10), Vector2(128, -10), Vector2(128, 6), Vector2(0, 6)], Color(0.38, 0.45, 0.32)],
				[[Vector2(118, -14), Vector2(132, -14), Vector2(132, 10), Vector2(118, 10)], DARK],
				[[Vector2(-4, -13), Vector2(8, -13), Vector2(8, 9), Vector2(-4, 9)], DARK],
				[[Vector2(50, 6), Vector2(60, 6), Vector2(58, 22), Vector2(50, 22)], DARK],
				[[Vector2(70, -18), Vector2(84, -18), Vector2(84, -10), Vector2(70, -10)], DARK]]
		&"GRENADE":
			shapes = [[_ellipse(Vector2(56, 4), Vector2(17, 20)), Color(0.33, 0.42, 0.28)],
				[[Vector2(48, -22), Vector2(64, -22), Vector2(64, -14), Vector2(48, -14)], METAL],
				[[Vector2(62, -22), Vector2(78, -12), Vector2(74, -8), Vector2(62, -16)], METAL]]
		&"MOLOTOV":
			shapes = [[[Vector2(46, -8), Vector2(66, -8), Vector2(70, 2), Vector2(70, 24), Vector2(42, 24), Vector2(42, 2)], Color(0.35, 0.55, 0.3, 0.9)],
				[[Vector2(51, -24), Vector2(61, -24), Vector2(61, -8), Vector2(51, -8)], Color(0.35, 0.55, 0.3, 0.9)],
				[[Vector2(52, -30), Vector2(60, -30), Vector2(64, -38), Vector2(56, -46), Vector2(50, -36)], Color(1.0, 0.6, 0.15)],
				[[Vector2(43, 8), Vector2(69, 8), Vector2(69, 22), Vector2(43, 22)], Color(0.85, 0.55, 0.2, 0.8)]]
		&"FLAMETHROWER", &"WATER_CANNON":
			shapes = [[[Vector2(10, -6), Vector2(104, -6), Vector2(104, 2), Vector2(10, 2)], METAL],
				[_ellipse(Vector2(36, 12), Vector2(22, 9)), Color(0.75, 0.2, 0.15) if id == &"FLAMETHROWER" else Color(0.25, 0.45, 0.8)],
				[[Vector2(70, 2), Vector2(80, 2), Vector2(78, 22), Vector2(70, 22)], DARK],
				[[Vector2(104, -9), Vector2(116, -9), Vector2(116, 5), Vector2(104, 5)], DARK]]
		_:
			shapes = [[[Vector2(22, -12), Vector2(86, -12), Vector2(86, 0), Vector2(46, 0), Vector2(42, 4), Vector2(48, 26), Vector2(32, 28), Vector2(28, 4), Vector2(22, 0)], METAL],
				[[Vector2(30, 4), Vector2(44, 4), Vector2(48, 26), Vector2(32, 28)], DARK],
				[[Vector2(50, 0), Vector2(56, 0), Vector2(58, 8), Vector2(50, 8)], DARK]]
	for sh in shapes:
		var pts := PackedVector2Array()
		for p: Vector2 in sh[0]:
			pts.append(o + p * s)
		ci.draw_colored_polygon(pts, sh[1])
		pts.append(pts[0])
		ci.draw_polyline(pts, OUTLINE, 1.5)


static func _ellipse(c: Vector2, r: Vector2) -> Array:
	var pts := []
	for k in 16:
		pts.append(c + Vector2(cos(k * TAU / 16.0) * r.x, sin(k * TAU / 16.0) * r.y))
	return pts
