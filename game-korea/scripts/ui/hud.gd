class_name Hud
extends CanvasLayer
## HUD: 조종 중인 것(차/도보), 체력, 돈, 수배 별, 무기·탄약, 존경도, 미션 목표·시간·화살표, 원형 미니맵,
## 탑승·공중전화 안내, 알림, 체포·사망·미션 화면, 조작 안내.

const KMH_PER_PX := 0.22   ## 720px/s ≈ 160km/h
const NOTICE_TIME := 2.0
const HINT_FOOT := "WASD 이동   Shift 달리기   Z·J 공격   Q/E 무기   F 차 타기   R 출발점으로"
const HINT_DRIVE := "W/S 가속·브레이크   A/D 조향   Space 핸드브레이크   Z·J 드라이브바이   Q/E 무기   F 내리기   T 라디오   1·2·3 차종"
const HINT_SPG := "W/S 전진·후진   A/D 제자리 돌기   마우스 포탑·사거리 (Q/E 포탑)   클릭·Z·J 포격   차를 깔고 넘는다   F 내리기"
const HINT_TURRET := "W/S 가속·브레이크   A/D 조향   Space 핸드브레이크   마우스 기관총 (Q/E 돌리기)   클릭·Z·J 사격   F 내리기"
const HINT_DIGGER := "W/S 전진·후진   A/D 제자리 돌기   마우스 상부·팔 뻗기 (Q/E 상부)   클릭·Z·J 퍼 올리기 (차 집기·놓기)   F 내리기"
const HINT_DOZER := "W/S 전진·후진   A/D 제자리 돌기   클릭·Z·J 블레이드 올리기·내리기 (내리면 밀어붙인다)   F 내리기"
const HINT_FLY := "W/S 앞으로·멈춤   A/D 돌기   Space 급선회   Z·J 사격   Q/E 무기   F 착륙 (빈 땅·도로 위)"
const METERS_PER_HEIGHT := 0.4   ## 헬기 높이(화면 px) → 고도 표시(m)
const BAR_SIZE := Vector2(180, 12)
const GOLD := Color(1.0, 0.82, 0.3)
const BANNER_RED := Color(1.0, 0.25, 0.25)
const RADIO_TIME := 4.0
const DJ_TIME := 6.0
const ARROW_MARGIN := 46.0

const STAR_SLOTS := 6         ## 별칸은 6개 (M3에서는 ★3까지 찬다)
const STAR_RADIUS := 13.0
const STAR_FLASH_TIME := 2.0
const STAR_ON := Color(0.95, 0.18, 0.2)
const STAR_OFF := Color(0.55, 0.57, 0.62, 0.55)
const MONEY_GREEN := Color(0.45, 1.0, 0.45)
const MISSION_RED := Color(0.95, 0.22, 0.2)
const MISSION_WIDTH := 400.0   ## 미션 상자 글자 폭
const RADIO_WIDTH := 400.0     ## 라디오 상자 폭
const MAP_MARGIN := 34.0       ## 미니맵: 왼쪽 아래 (테·N 표가 화면 밖으로 나가지 않게 띄운다)

var director: Director
var police: PoliceDispatcher
var wallet: Wallet
var player: Player
var missions: MissionSystem
var respect: Respect
var city: City
var sky: DayNight
var jobs: SideJobs
var events: StreetEvents
var rampages: Rampages
var _info: Label
var _clock: Label
var _respect: Label
var _mission_title: Label
var _objective: Label
var _arrow: Control
var _minimap: Minimap
var _banner_id := 0
var _bars: Control
var _weapon: WeaponPanel
var _money: Label
var _stars: Control
var _banner: Label
var _banner_sub: Label
var _star_flash := 0.0
var _drift: Label
var _prompt: Label
var _notice: Label
var _mission_box: PanelContainer
var _mission_style: StyleBoxFlat
var _mission_icon: Control
var _radio_box: PanelContainer
var _radio_icon: Control
var _radio_wave: Control
var _channel: RadioChannel       ## 상자에 띄운 채널 (null = 껐다)
var _radio: Label                ## 차 라디오 채널 이름 (맞출 때 잠깐)
var _dj: Label                   ## DJ 자막
var _radio_time := 0.0
var _dj_time := 0.0
var _hint: Label
var _notice_time := 0.0
var _goal: Label
var _district: Label
var _district_sub: Label
var _district_time := 0.0
## 장 목표 한 줄 (main이 정한다)
var goal_text := ""


func _ready() -> void:
	_info = _label(22, Color(0.45, 1.0, 0.55))
	_info.position = Vector2(24, 18)

	_drift = _centered(30, Color(1.0, 0.85, 0.25), 80)
	_drift.text = "드리프트!"

	_prompt = _centered(20, Color(1, 1, 1, 0.9), 630)

	_notice = _label(20, Color.WHITE)
	_notice.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_notice.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_notice.offset_left = -360
	_notice.offset_right = -24
	_notice.offset_top = -310
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_hint = _label(15, Color(1, 1, 1, 0.75))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 24
	_hint.offset_top = -40

	_build_radio_box()

	# 오른쪽 위: 무기 칸 → 돈 → 수배 별 → 존경도
	_weapon = WeaponPanel.new()
	_weapon.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_weapon.offset_left = -24 - WeaponPanel.SIZE.x
	_weapon.offset_right = -24
	_weapon.offset_top = 16
	_weapon.offset_bottom = 16 + WeaponPanel.SIZE.y
	add_child(_weapon)

	_money = _label(30, MONEY_GREEN)
	_money.add_theme_constant_override("outline_size", 9)
	_money.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_money.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_money.offset_left = -300
	_money.offset_right = -24
	_money.offset_top = 128
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_stars = Control.new()
	_stars.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_stars.offset_left = -24 - STAR_SLOTS * STAR_RADIUS * 2.3
	_stars.offset_right = -24
	_stars.offset_top = 172
	_stars.offset_bottom = 172 + STAR_RADIUS * 2
	_stars.draw.connect(_draw_stars)
	add_child(_stars)

	_respect = _label(17, GOLD)
	_respect.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_respect.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_respect.offset_left = -300
	_respect.offset_right = -24
	_respect.offset_top = 206
	_respect.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# 미션: 위쪽 가운데 제목·목표·남은 시간
	_build_mission_box()

	# 화면 밖 목표를 가리키는 테두리 화살표
	_arrow = Control.new()
	_arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.draw.connect(_draw_arrow)
	add_child(_arrow)

	_minimap = Minimap.new()
	_minimap.director = director
	_minimap.police = police
	_minimap.missions = missions
	_minimap.city = city
	_minimap.jobs = jobs
	_minimap.events = events
	_minimap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_minimap.offset_left = MAP_MARGIN
	_minimap.offset_top = -78 - Minimap.RADIUS * 2
	_minimap.offset_right = MAP_MARGIN + Minimap.RADIUS * 2
	_minimap.offset_bottom = -78
	add_child(_minimap)

	# 체력 막대 (차에 타면 그 아래 차 체력 막대도)
	_bars = Control.new()
	_bars.position = Vector2(24, 92)
	_bars.size = Vector2(BAR_SIZE.x, BAR_SIZE.y * 3 + 8)
	_bars.draw.connect(_draw_bars)
	add_child(_bars)

	_goal = _label(16, Color(1, 1, 1, 0.8))
	_goal.position = Vector2(24, 132)

	# 미니맵 위 시계와 날씨
	_clock = _label(16, Color(0.85, 0.9, 1.0))
	_clock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_clock.offset_left = MAP_MARGIN
	_clock.offset_right = MAP_MARGIN + Minimap.RADIUS * 2
	_clock.offset_top = -126 - Minimap.RADIUS * 2
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 구역 이름표: 다른 구역에 들어서면 잠깐 (위쪽 가운데, 미션 목표 아래)
	_district = _centered(34, Color.WHITE, 96)
	_district_sub = _centered(17, Color(1, 1, 1, 0.75), 140)
	_district.visible = false
	_district_sub.visible = false

	_banner = _centered(64, Color(1.0, 0.25, 0.25), 250)
	_banner_sub = _centered(26, Color.WHITE, 340)
	_banner.visible = false
	_banner_sub.visible = false

	director.vehicle_stolen.connect(func(_v, _d): notify("차량 탈취!"))
	police.wanted.level_changed.connect(_on_level_changed)
	police.wanted.escaped.connect(func(): notify("경찰을 따돌렸다"))
	police.crime_witnessed.connect(_on_crime)
	missions.phone_refused.connect(notify)


## 12,345 처럼 세 자리마다 쉼표
static func won(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## 돈은 8자리 고정 폭 (docs/05 §6)
static func money_text(n: int) -> String:
	return "₩ %08d" % clampi(n, 0, 99999999)


## 화면 가운데 큰 글씨 (체포·미션 등). seconds 뒤에 사라진다 (그 사이 새 배너가 뜨면 새 것이 남는다).
func banner(title: String, sub: String, seconds := 2.5, color := BANNER_RED) -> void:
	_banner_id += 1
	var id := _banner_id
	_banner.text = Locale.t(title)
	_banner_sub.text = Locale.t(sub)
	_banner.add_theme_color_override("font_color", color)
	_banner.visible = true
	_banner_sub.visible = true
	await get_tree().create_timer(seconds, true, true).timeout
	if id != _banner_id:
		return
	_banner.visible = false
	_banner_sub.visible = false


func banner_visible() -> bool:
	return _banner.visible


const DISTRICT_TIME := 3.0


## 구역 이름을 잠깐 띄운다
func show_district(name: String, tagline: String, color: Color) -> void:
	_district.text = Locale.t(name)
	_district_sub.text = Locale.t(tagline)
	_district.add_theme_color_override("font_color", color)
	_district_time = DISTRICT_TIME


func district_visible() -> bool:
	return _district.visible


const LEVEL_NOTICES := {4: "특공대 출동! 다리에 검문소가 섰다", 5: "경찰 헬기가 떴다 — 탐조등을 피해라", 6: "군 병력 투입!"}


func _on_level_changed(level: int, previous: int) -> void:
	if level > previous:
		_star_flash = STAR_FLASH_TIME
		if previous == 0:
			notify("경찰이 추격 중입니다!")
		elif LEVEL_NOTICES.has(level):
			notify(LEVEL_NOTICES[level])


func _on_crime(crime: WantedSystem.Crime, raised: bool) -> void:
	if raised and police.wanted.level > 1:
		notify(Locale.t("수배 %s — %s") % ["★".repeat(police.wanted.level), Locale.t(WantedSystem.crime_name(crime))])


func _draw_stars() -> void:
	var level := police.wanted.level
	var alpha := 1.0
	if _star_flash > 0.0:
		alpha = 1.0 if int(_star_flash * 8.0) % 2 == 0 else 0.25
	elif level > 0 and not police.seen:
		# 시야 밖: 별이 천천히 깜빡이고, 내려갈 때가 가까울수록 빨라진다
		var rate := lerpf(2.0, 7.0, police.wanted.lose_progress())
		alpha = 0.55 + 0.45 * cos(Time.get_ticks_msec() / 1000.0 * rate * TAU * 0.5)
	for k in STAR_SLOTS:
		var c := Vector2(STAR_RADIUS + k * STAR_RADIUS * 2.3, STAR_RADIUS)
		var on := k < level
		var pts := PackedVector2Array()
		for p in 10:
			var r := STAR_RADIUS if p % 2 == 0 else STAR_RADIUS * 0.45
			pts.append(c + Vector2.UP.rotated(p * TAU / 10.0) * r)
		var color := Color(STAR_ON, alpha) if on else STAR_OFF
		_stars.draw_colored_polygon(pts, color)
		pts.append(pts[0])
		_stars.draw_polyline(pts, Color(0, 0, 0, 0.85), 3.5)
		_stars.draw_polyline(pts, Color(1, 1, 1, 0.9 if on else 0.35), 1.5)


func _draw_bars() -> void:
	_bar(0.0, player.health / Player.MAX_HEALTH, Color(0.9, 0.2, 0.25))
	var v := director.current_vehicle
	if v:
		_bar(BAR_SIZE.y + 6.0, v.health / v.max_health(), Color(0.95, 0.7, 0.2))


func _bar(y: float, ratio: float, color: Color) -> void:
	var r := Rect2(Vector2(0, y), BAR_SIZE)
	_bars.draw_rect(r.grow(2), Color(0, 0, 0, 0.7))
	_bars.draw_rect(r, color.darkened(0.7))
	_bars.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(ratio, 0.0, 1.0), r.size.y)), color)


## 왼쪽 위 미션 상자: 어두운 판 + 색 테두리(미션 빨강 · 부업 청록 · 광란 빨강), 표적 그림, 제목·남은 시간, 목표
func _build_mission_box() -> void:
	_mission_style = _box_style(Color(0.04, 0.05, 0.08, 0.84), MISSION_RED, 2)
	_mission_box = PanelContainer.new()
	_mission_box.add_theme_stylebox_override("panel", _mission_style)
	_mission_box.position = Vector2(24, 162)
	_mission_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mission_box.visible = false
	add_child(_mission_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_mission_box.add_child(row)
	_mission_icon = Control.new()
	_mission_icon.custom_minimum_size = Vector2(28, 28)
	_mission_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_mission_icon.draw.connect(_draw_mission_icon)
	row.add_child(_mission_icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	_mission_title = _make_label(21, GOLD)
	_objective = _make_label(16, Color(1, 1, 1, 0.92))
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.custom_minimum_size.x = MISSION_WIDTH
	col.add_child(_mission_title)
	col.add_child(_objective)


## 표적 그림 (테두리 색)
func _draw_mission_icon() -> void:
	var c := _mission_icon.size * 0.5 + Vector2(0, 2)
	var color := _mission_style.border_color
	_mission_icon.draw_arc(c, 10.0, 0.0, TAU, 32, color, 2.5, true)
	_mission_icon.draw_circle(c, 3.0, color)
	for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		_mission_icon.draw_line(c + d * 7.0, c + d * 14.0, color, 2.5)


## 오른쪽 아래 라디오 상자: 라디오 그림 · 채널(주파수·이름)과 소리 막대 · DJ 자막
func _build_radio_box() -> void:
	_radio_box = PanelContainer.new()
	_radio_box.add_theme_stylebox_override("panel", _box_style(Color(0.04, 0.05, 0.08, 0.84), Color(0.92, 0.94, 1.0, 0.7), 2))
	_radio_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_radio_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_radio_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_radio_box.offset_left = -24 - RADIO_WIDTH
	_radio_box.offset_right = -24
	_radio_box.offset_top = -64
	_radio_box.offset_bottom = -24
	_radio_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radio_box.visible = false
	add_child(_radio_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_radio_box.add_child(row)
	_radio_icon = Control.new()
	_radio_icon.custom_minimum_size = Vector2(46, 46)
	_radio_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_radio_icon.draw.connect(_draw_radio_icon)
	row.add_child(_radio_icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_radio = _make_label(18, GOLD)
	_radio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_radio)
	_radio_wave = Control.new()
	_radio_wave.custom_minimum_size = Vector2(54, 20)
	_radio_wave.draw.connect(_draw_radio_wave)
	head.add_child(_radio_wave)
	_dj = _make_label(16, Color(1, 1, 1, 0.92))
	_dj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dj.custom_minimum_size.x = RADIO_WIDTH - 90
	_dj.visible = false
	col.add_child(_dj)


## 라디오 그림: 몸통·스피커 망·안테나 (채널 색)
func _draw_radio_icon() -> void:
	var color := _radio.get_theme_color("font_color")
	var body := Rect2(4, 14, 38, 26)
	_radio_icon.draw_line(Vector2(30, 14), Vector2(38, 3), Color(0.8, 0.82, 0.86), 2.0, true)
	var st := _box_style(Color(0.16, 0.17, 0.2), color, 2)
	st.set_corner_radius_all(5)
	_radio_icon.draw_style_box(st, body)
	_radio_icon.draw_circle(Vector2(16, 27), 8.0, Color(0.08, 0.09, 0.1))
	for k in 3:
		_radio_icon.draw_arc(Vector2(16, 27), 2.0 + k * 2.5, 0.0, TAU, 16, Color(color, 0.8), 1.0, true)
	_radio_icon.draw_rect(Rect2(28, 20, 9, 3), color)
	_radio_icon.draw_rect(Rect2(28, 26, 9, 2), Color(1, 1, 1, 0.5))
	_radio_icon.draw_rect(Rect2(28, 31, 9, 2), Color(1, 1, 1, 0.5))


## 소리 막대: 켜져 있으면 막대가 오르내리고, 껐으면 납작하다
func _draw_radio_wave() -> void:
	var on := _channel != null
	var t := Time.get_ticks_msec() / 1000.0
	var color := Color(_radio.get_theme_color("font_color"), 0.9)
	for k in 9:
		var h := 2.0 if not on else 3.0 + 13.0 * absf(sin(t * (5.0 + k * 0.7) + k * 1.3)) * (1.0 - absf(k - 4) / 6.0)
		_radio_wave.draw_rect(Rect2(2 + k * 6, 10 - h * 0.5, 3, h), color)


func _box_style(bg: Color, edge: Color, width: int) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = edge
	st.set_border_width_all(width)
	st.set_corner_radius_all(9)
	st.set_content_margin_all(12)
	st.shadow_color = Color(0, 0, 0, 0.45)
	st.shadow_size = 5
	return st


## 차 라디오 채널을 맞췄다 (null = 껐다)
func show_radio(ch: RadioChannel) -> void:
	_channel = ch
	_radio.text = "♪ " + Locale.t("라디오 끔") if ch == null else "♪ %s  %s" % [ch.frequency, Locale.t(ch.display_name)]
	_radio.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7) if ch == null else ch.color)
	_radio_time = RADIO_TIME
	if ch == null:
		_dj_time = 0.0


## DJ 자막
func show_dj(ch: RadioChannel, text: String) -> void:
	_channel = ch
	_radio.text = "♪ %s  %s" % [ch.frequency, Locale.t(ch.display_name)]
	_radio.add_theme_color_override("font_color", ch.color)
	_dj.text = "DJ  " + text
	_dj.add_theme_color_override("font_color", ch.color.lerp(Color.WHITE, 0.6))
	_dj_time = DJ_TIME


func notify(text: String) -> void:
	_notice.text = Locale.t(text)
	_notice_time = NOTICE_TIME


func _label(size: int, color: Color) -> Label:
	var l := _make_label(size, color)
	add_child(l)
	return l


## 글자 (붙이지 않는다 — 상자 안에 넣을 때)
func _make_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _centered(size: int, color: Color, top: float) -> Label:
	var l := _label(size, color)
	l.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.offset_top = top
	return l


func _process(delta: float) -> void:
	_notice_time -= delta
	_notice.visible = _notice_time > 0.0
	_radio_time -= delta
	_dj_time -= delta
	_dj.visible = _dj_time > 0.0 and director.current_vehicle != null
	_radio_box.visible = _radio_time > 0.0 or _dj.visible
	if _radio_box.visible:
		_radio_box.modulate.a = clampf(maxf(_radio_time, _dj_time if _dj.visible else 0.0) / 0.4, 0.0, 1.0)
		_radio_box.offset_top = _radio_box.offset_bottom - _radio_box.get_combined_minimum_size().y   # 아래에 붙여 위로 자란다
		_radio_wave.queue_redraw()
		_radio_icon.queue_redraw()
	_district_time -= delta
	_district.visible = _district_time > 0.0
	_district_sub.visible = _district.visible
	var fade := clampf(_district_time / 0.6, 0.0, 1.0)
	_district.modulate.a = fade
	_district_sub.modulate.a = fade
	_goal.text = goal_text
	if sky:
		_clock.text = "%s  %s" % [sky.clock_text(), Locale.t("비" if sky.raining else ("밤" if DayNight.is_night(sky.hour) else "맑음"))]
	_star_flash = maxf(_star_flash - delta, 0.0)
	_money.text = money_text(wallet.money)
	_update_mission()
	_mission_box.visible = _mission_title.visible
	if _mission_box.visible:
		# 테두리·표적: 미션 빨강, 부업 청록, 남은 시간이 적으면 깜박인다
		var color := MISSION_RED
		if not missions.active() and jobs != null and jobs.active() and not (rampages and rampages.active()):
			color = Color(0.4, 0.95, 1.0)
		if _mission_title.get_theme_color("font_color").is_equal_approx(Color(1.0, 0.4, 0.35)) and int(Time.get_ticks_msec() / 300) % 2 == 0:
			color = Color.WHITE
		_mission_style.border_color = color
		_mission_icon.queue_redraw()
		_mission_box.reset_size()
	_stars.queue_redraw()
	_bars.queue_redraw()
	var w := player.arsenal.current()
	_weapon.show_weapon(w, player.arsenal.ammo_of(w))
	var v := director.current_vehicle
	if v:
		_info.text = "%s\n%d km/h" % [Locale.t(v.stats.display_name), roundi(v.speed() * KMH_PER_PX)]
		_drift.visible = absf(v.motor.lateral_speed()) > 220.0 and not v.stats.flies
		if v.stats.flies:
			_info.text += Locale.t("  ·  고도 %d m") % roundi(v.altitude * METERS_PER_HEIGHT)
		_prompt.visible = v.burning >= 0.0 or v.on_fire
		_prompt.text = Locale.t("불이 붙었다!  F 내려!" if v.burning >= 0.0 else "차에 불이 났다! 곧 터진다  F 내려!")
		var job := jobs.available() if jobs else null
		if job and not _prompt.visible:
			_prompt.text = Locale.t("B  %s 부업 시작 (최고 %d단계)") % [Locale.t(job.display_name), jobs.best.get(job.id, 0)]
			_prompt.visible = true
		_hint.text = Locale.t(HINT_FLY if v.stats.flies else HINT_SPG if v.stats.cannon_max > 0.0 \
			else HINT_DIGGER if v.stats.arm_reach.y > 0.0 else HINT_DOZER if v.stats.blade \
			else HINT_TURRET if v.stats.turret_rate > 0.0 else HINT_DRIVE)
		if v.stats.flies and not _prompt.visible:
			_prompt.text = Locale.t("착륙 중…  F 취소" if v.landing else ("F  착륙" if v.airborne() else "W  이륙"))
			_prompt.visible = true
		return
	_info.text = Locale.t("도보")
	_drift.visible = false
	_hint.text = Locale.t(HINT_FOOT)
	var near := director.nearest_enterable()
	_prompt.visible = near != null and not director.is_entering()
	if near:
		_prompt.text = Locale.t("F  %s 빼앗기" if near.has_driver else "F  %s 타기") % Locale.t(near.stats.display_name)
	var phone := missions.phone_prompt()
	if phone != "" and not _prompt.visible:
		_prompt.text = phone
		_prompt.visible = true


func _update_mission() -> void:
	var parts: Array[String] = []
	for g in missions.gangs.gangs:
		if missions.gang_reachable(g):
			var v := respect.of(g.id)
			parts.append(Locale.t("%s 존경도 %s%d") % [Locale.t(g.display_name), "+" if v > 0 else "", v])
	_respect.text = "\n".join(parts)
	_arrow.queue_redraw()
	if not missions.active() and rampages and rampages.active():
		_mission_title.text = rampages.title_text()
		_mission_title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35) if rampages.time_left < 15.0 else Color(1.0, 0.25, 0.2))
		_objective.text = rampages.objective_text()
		_mission_title.visible = true
		_objective.visible = true
		return
	if not missions.active():
		var job_on := jobs != null and jobs.active()
		_mission_title.visible = job_on
		_objective.visible = job_on
		if job_on:
			_mission_title.text = jobs.title_text()
			_mission_title.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0) if jobs.time_left >= 10.0 else Color(1.0, 0.4, 0.35))
			_objective.text = jobs.objective_text()
		return
	var run := missions.run
	var left := run.time_left()
	_mission_title.text = run.mission.title if left == INF else "%s   %d:%02d" % [run.mission.title, int(left) / 60, int(left) % 60]
	_mission_title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35) if left < 15.0 else GOLD)
	_objective.text = missions.objective_text()
	_mission_title.visible = true
	_objective.visible = true


## 목표가 화면 밖이면 그쪽 테두리에 노란 화살표
func _draw_arrow() -> void:
	var goal: Variant = missions.objective_position()
	if goal == null and jobs:
		goal = jobs.objective_position()
	if goal == null:
		return
	var view := _arrow.get_viewport_rect()
	var screen: Vector2 = _arrow.get_viewport().get_canvas_transform() * (goal as Vector2)
	if view.grow(-20.0).has_point(screen):
		return
	var center := view.get_center()
	var dir := (screen - center).normalized()
	var inner := view.grow(-ARROW_MARGIN)
	# 화면 가운데에서 dir 쪽으로 가다 안쪽 사각형 테두리에 닿는 점
	var tx := (inner.size.x * 0.5) / maxf(absf(dir.x), 0.001)
	var ty := (inner.size.y * 0.5) / maxf(absf(dir.y), 0.001)
	var at := center + dir * minf(tx, ty)
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 150.0)
	var tri := PackedVector2Array([Vector2(18, 0), Vector2(-10, -13), Vector2(-4, 0), Vector2(-10, 13)])
	for k in tri.size():
		tri[k] = at + tri[k].rotated(dir.angle())
	_arrow.draw_colored_polygon(tri, Color(1.0, 0.85, 0.2, pulse))
	tri.append(tri[0])
	_arrow.draw_polyline(tri, Color(0, 0, 0, 0.8), 2.0)
