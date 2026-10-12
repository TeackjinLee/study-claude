class_name Hud
extends CanvasLayer
## HUD: 조종 중인 것(차/도보), 체력, 돈, 수배 별, 무기·탄약, 존경도, 미션 목표·시간·화살표, 원형 미니맵,
## 탑승·공중전화 안내, 알림, 체포·사망·미션 화면, 조작 안내.

const KMH_PER_PX := 0.22   ## 720px/s ≈ 160km/h
const NOTICE_TIME := 2.0
const HINT_FOOT := "WASD 이동   Shift 달리기   Ctrl·J 공격   Q/E 무기   F 차 타기   R 출발점으로"
const HINT_DRIVE := "W/S 가속·브레이크   A/D 조향   Space 핸드브레이크   Ctrl·J 드라이브바이   Q/E 무기   F 내리기   1·2·3 차종"
const BAR_SIZE := Vector2(180, 12)
const GOLD := Color(1.0, 0.82, 0.3)
const BANNER_RED := Color(1.0, 0.25, 0.25)
const ARROW_MARGIN := 46.0

const STAR_SLOTS := 6         ## 별칸은 6개 (M3에서는 ★3까지 찬다)
const STAR_RADIUS := 13.0
const STAR_FLASH_TIME := 2.0
const STAR_ON := Color(1.0, 0.85, 0.2)
const STAR_OFF := Color(0.1, 0.28, 0.16, 0.85)

var director: Director
var police: PoliceDispatcher
var wallet: Wallet
var player: Player
var missions: MissionSystem
var respect: Respect
var city: City
var sky: DayNight
var jobs: SideJobs
var _info: Label
var _clock: Label
var _respect: Label
var _mission_title: Label
var _objective: Label
var _arrow: Control
var _minimap: Minimap
var _banner_id := 0
var _bars: Control
var _weapon: Label
var _money: Label
var _stars: Control
var _banner: Label
var _banner_sub: Label
var _star_flash := 0.0
var _drift: Label
var _prompt: Label
var _notice: Label
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

	_money = _label(26, Color(0.45, 1.0, 0.55))
	_money.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_money.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_money.offset_left = -300
	_money.offset_right = -24
	_money.offset_top = 14
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_stars = Control.new()
	_stars.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_stars.offset_left = -24 - STAR_SLOTS * STAR_RADIUS * 2.3
	_stars.offset_right = -24
	_stars.offset_top = 54
	_stars.offset_bottom = 54 + STAR_RADIUS * 2
	_stars.draw.connect(_draw_stars)
	add_child(_stars)

	_weapon = _label(22, Color(1.0, 0.95, 0.8))
	_weapon.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_weapon.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_weapon.offset_left = -300
	_weapon.offset_right = -24
	_weapon.offset_top = 90
	_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_respect = _label(17, GOLD)
	_respect.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_respect.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_respect.offset_left = -300
	_respect.offset_right = -24
	_respect.offset_top = 124
	_respect.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# 미션: 위쪽 가운데 제목·목표·남은 시간
	_mission_title = _centered(22, GOLD, 14)
	_objective = _centered(20, Color.WHITE, 44)

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
	_minimap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap.offset_left = -24 - Minimap.RADIUS * 2
	_minimap.offset_top = -60 - Minimap.RADIUS * 2
	_minimap.offset_right = -24
	_minimap.offset_bottom = -60
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
	_clock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_clock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_clock.offset_left = -24 - Minimap.RADIUS * 2
	_clock.offset_right = -24
	_clock.offset_top = -86 - Minimap.RADIUS * 2
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
	_banner.text = title
	_banner_sub.text = sub
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
	_district.text = name
	_district_sub.text = tagline
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
		notify("수배 %s — %s" % ["★".repeat(police.wanted.level), WantedSystem.crime_name(crime)])


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
		_stars.draw_polyline(pts, Color(0, 0, 0, 0.8), 2.0)


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


func notify(text: String) -> void:
	_notice.text = text
	_notice_time = NOTICE_TIME


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	add_child(l)
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
	_district_time -= delta
	_district.visible = _district_time > 0.0
	_district_sub.visible = _district.visible
	var fade := clampf(_district_time / 0.6, 0.0, 1.0)
	_district.modulate.a = fade
	_district_sub.modulate.a = fade
	_goal.text = goal_text
	if sky:
		_clock.text = "%s  %s" % [sky.clock_text(), "비" if sky.raining else ("밤" if DayNight.is_night(sky.hour) else "맑음")]
	_star_flash = maxf(_star_flash - delta, 0.0)
	_money.text = money_text(wallet.money)
	_update_mission()
	_stars.queue_redraw()
	_bars.queue_redraw()
	var w := player.arsenal.current()
	var ammo := player.arsenal.ammo_of(w)
	_weapon.text = w.display_name if ammo < 0 else "%s  %d" % [w.display_name, ammo]
	var v := director.current_vehicle
	if v:
		_info.text = "%s\n%d km/h" % [v.stats.display_name, roundi(v.speed() * KMH_PER_PX)]
		_drift.visible = absf(v.motor.lateral_speed()) > 220.0
		_prompt.visible = v.burning >= 0.0
		_prompt.text = "불이 붙었다!  F 내려!"
		var job := jobs.available() if jobs else null
		if job and not _prompt.visible:
			_prompt.text = "B  %s 부업 시작 (최고 %d단계)" % [job.display_name, jobs.best.get(job.id, 0)]
			_prompt.visible = true
		_hint.text = HINT_DRIVE
		return
	_info.text = "도보"
	_drift.visible = false
	_hint.text = HINT_FOOT
	var near := director.nearest_enterable()
	_prompt.visible = near != null and not director.is_entering()
	if near:
		_prompt.text = "F  %s 빼앗기" % near.stats.display_name if near.has_driver \
			else "F  %s 타기" % near.stats.display_name
	var phone := missions.phone_prompt()
	if phone != "" and not _prompt.visible:
		_prompt.text = phone
		_prompt.visible = true


func _update_mission() -> void:
	var parts: Array[String] = []
	for g in missions.gangs.gangs:
		if missions.gang_reachable(g):
			var v := respect.of(g.id)
			parts.append("%s 존경도 %s%d" % [g.display_name, "+" if v > 0 else "", v])
	_respect.text = "\n".join(parts)
	_arrow.queue_redraw()
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
