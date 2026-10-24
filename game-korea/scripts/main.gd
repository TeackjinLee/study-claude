extends Node2D
## 게임 루트: 도시 + 교통 + 주차된 차들 + 주인공(도보) + 보행자 + 조종권 + 경찰 + 전투·무기 상자
## + 갱·미션·은신처(저장) + 카메라 + HUD.

const VEHICLE_TYPES: Array[VehicleType] = [
	preload("res://data/vehicles/car_avela.tres"),
	preload("res://data/vehicles/car_avela_r.tres"),
	preload("res://data/vehicles/trk_porta.tres"),
	preload("res://data/vehicles/car_sonato.tres"),
	preload("res://data/vehicles/car_sorea.tres"),
	preload("res://data/vehicles/car_rumi.tres"),
	preload("res://data/vehicles/car_taxi.tres"),
	preload("res://data/vehicles/etc_bike.tres"),
	preload("res://data/vehicles/etc_camper.tres"),
	preload("res://data/vehicles/bus_express.tres"),
	preload("res://data/vehicles/trk_tanker.tres"),
	preload("res://data/vehicles/etc_truck.tres"),
	preload("res://data/vehicles/trk_mixer.tres"),
	preload("res://data/vehicles/etc_bicycle.tres"),
	preload("res://data/vehicles/car_striker.tres"),
	preload("res://data/vehicles/trk_bongo.tres"),
	preload("res://data/vehicles/trk_titan.tres"),
	preload("res://data/vehicles/sp_tow.tres"),
	preload("res://data/vehicles/trk_garbage.tres"),
]
## 터미널 승강장에 세워 두는 차종
const LANDMARK_BUS: VehicleType = preload("res://data/vehicles/bus_express.tres")
const DEV_SWITCH_TYPES := 3
const MAX_CATCH_UP := 3       ## 늦은 프레임에 몰아서 도는 물리 틱 최대 수   ## 1·2·3 키로 바꿀 수 있는 차종 수 (VEHICLE_TYPES 앞쪽)

const GANGS: Array[GangType] = [
	preload("res://data/gangs/gangnam.tres"),
	preload("res://data/gangs/oldtown.tres"),
	preload("res://data/gangs/smuggler.tres"),
]

## 장 1~4 (docs/05 §1). 목표 금액을 모으면 다음 장 — 마지막 장 목표가 엔딩
const CHAPTERS: Array[ChapterType] = [
	preload("res://data/chapters/ch1.tres"),
	preload("res://data/chapters/ch2.tres"),
	preload("res://data/chapters/ch3.tres"),
	preload("res://data/chapters/ch4.tres"),
]

## 부업 6종 (docs/05 §5.4)
const SIDE_JOBS: Array[SideJobType] = [
	preload("res://data/sidejobs/taxi.tres"),
	preload("res://data/sidejobs/bus.tres"),
	preload("res://data/sidejobs/delivery.tres"),
	preload("res://data/sidejobs/ambulance.tres"),
	preload("res://data/sidejobs/fire.tres"),
	preload("res://data/sidejobs/vigilante.tres"),
]

## 은신처 (docs/04 §2). 첫 줄이 시작 은신처
const HIDEOUTS: Array[HideoutType] = [
	preload("res://data/hideouts/gangnam_officetel.tres"),
	preload("res://data/hideouts/hongdae_gosiwon.tres"),
	preload("res://data/hideouts/riverside_camp.tres"),
	preload("res://data/hideouts/outskirts_house.tres"),
	preload("res://data/hideouts/jongno_hanok.tres"),
]

## [차종 번호, 세로 도로?, 도로 번호, 구간, 위치 t, 운전자 있음]
## 첫 줄은 출발 차 — 주인공 바로 옆에 빈 차로 서 있다.
const PARKED := [
	[0, true, 3, 3, 0.5, false],
	[1, true, 3, 3, 0.8, true],
	[2, true, 4, 2, 0.4, false],
	[3, false, 3, 2, 0.3, true],
	[1, false, 4, 3, 0.6, false],
	[2, true, 4, 3, 0.25, true],
	[4, true, 2, 4, 0.5, false],
	[5, false, 2, 3, 0.7, false],       # 가로 2번 도로 1~2구간은 고가차도 (CityMap.OVERPASSES)
	[6, true, 5, 1, 0.6, true],
	[7, false, 5, 4, 0.5, false],
	# M6 구역들 (잠긴 구역의 차는 그 장이 열릴 때까지 통제 구역 안에 서 있다)
	[8, false, -4, -2, 0.4, false],     # 한강변 강변북로: 캠핑카
	[9, false, -4, 3, 0.5, false],      # 강변북로: 고속버스
	[8, false, -4, 4, 0.3, false],      # 한강공원 동쪽: 캠핑카
	[10, true, -2, 3, 0.5, false],      # 공단: 유조차
	[11, true, -4, 1, 0.4, false],      # 공단: 대형 트럭
	[12, false, 3, -3, 0.6, false],     # 공단: 레미콘
	[13, true, -3, -7, 0.3, false],     # 홍대: 자전거
	[13, true, -1, -6, 0.6, false],     # 홍대: 자전거
	[14, true, -2, -2, 0.5, false],     # 여의도: 스트라이커
	[15, true, 1, -6, 0.5, false],      # 종로: 봉고르
	[16, true, 2, -10, 0.5, false],     # 변두리: 타이탄
	[17, false, -8, 3, 0.5, false],     # 종로: 견인차
	[18, false, -10, -1, 0.5, false],   # 변두리: 청소차
]

## 테스트에서 add_child 전에 바꿀 수 있다 (0이면 도로에 NPC 차가 없다)
var traffic_count := 20
var bus_count := 2
var traffic_seed := TrafficSystem.SEED
var police_patrols := PoliceDispatcher.PATROL_COUNT
## 세이브 슬롯 파일 이름 앞부분 (슬롯 n → <save_prefix>n.json). 테스트는 다른 이름을 쓴다
var save_prefix := SaveGame.DEFAULT_PREFIX
## 게임을 켤 때 저장이 있으면 이어 하기 메뉴를 띄운다 (테스트처럼 다른 노드 밑에 붙으면 띄우지 않는다)
var load_on_start := true
## 지금 장(Chapter). 열린 구역이 정해진다 (docs/05 §1)
var chapter := 1

const BUST_DELAY := 2.5   ## 체포·사망 화면을 보여 주는 시간
const HOSPITAL_FEE := 100000

var city: City
var traffic: TrafficSystem
var skid_marks: SkidMarks
var vehicles: Array[Vehicle] = []
var start_vehicle: Vehicle
var work_zone: WorkZone       ## 도로 공사 현장 장식 (그 구역이 열리면 생긴다)
var _registered_player_id := 0
var session := GameSessionContext.new()   ## 기존 본편은 싱글 세션. 네트워크 역할은 SessionActors 진입점을 사용한다
var player: Player
var pedestrians: PedestrianManager
var director: Director
var police: PoliceDispatcher
var combat: Combat
var weapons: PlayerWeapons
var pickups: Pickups
var fires: Fires
var ems: EmsDispatcher                    ## 구급대 (기절한 사람을 구급차·병원 구급헬기로 실어 간다)
var sky: DayNight
var jobs: SideJobs
var street_events: StreetEvents
var packages: HiddenPackages
var rampages: Rampages
var ambience: CityAmbience
var radio: Radio
var pause_menu: PauseMenu
const TITLE_SCENE := "res://scenes/title.tscn"
var car_sounds: CarSounds
var wallet := Wallet.new()
var respect := Respect.new()
var gangs: GangManager
var missions: MissionSystem
var hideout: Hideout                      ## 시작 은신처 (강남 오피스텔)
var hideouts: Array[Hideout] = []
var current_hideout: Hideout              ## 마지막으로 밟은 은신처 — 여기 저장하고, 불러오면 여기서 시작
var finished := false                     ## 마지막 장 목표를 모았다 (엔딩을 봤다)
var spray_shop: SprayShop
var save_menu: SaveMenu
var camera: ChaseCamera
var hud: Hud
var _respawning := false
var _district: DistrictType
var _buying: Hideout                      ## 살지 묻고 있는 은신처
var _last_vehicle: Vehicle
var _landmark_parked := {}                ## 랜드마크 차를 세운 자리 (Vector2i) — 장이 열릴 때 겹쳐 세우지 않게


func _ready() -> void:
	# 단일 플레이어용 AI·HUD 세계를 네트워크 클라이언트에서 중복 실행하지 않는다.
	if session.role() != GameSessionContext.Role.OFFLINE or session.players.size() != 0:
		push_error("Main은 새 싱글 세션 전용입니다. 서버·클라이언트는 SessionActors를 사용하세요.")
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	# 시험용: `godot --path . -- --chapter=N`으로 켜면 N장(그 장까지 열린 구역)부터 바로 시작한다.
	# 본편으로 켰을 때만 본다 — 테스트는 Main을 다른 노드 밑에 붙이므로 같은 인자(traffic_test --chapter)에 영향받지 않는다
	if get_parent() == get_tree().root:
		Settings.load_and_apply()     # 소리 크기·언어·화면 (테스트는 Main을 다른 노드 밑에 붙여 사용자 설정을 읽지 않는다)
	var start := start_chapter_arg() if get_parent() == get_tree().root else 0
	if start > 0:
		chapter = start
	CityMap.set_chapter(chapter)
	RoadNav.clear_cache()
	if DisplayServer.get_name() != "headless":
		limit_frame_rate()
	city = City.new()
	add_child(city)

	skid_marks = SkidMarks.new()
	add_child(skid_marks)

	for spec: Array in PARKED:
		vehicles.append(_spawn_parked(spec))
	start_vehicle = vehicles[0]
	_spawn_landmark_parking()
	skid_marks.vehicles = vehicles

	pedestrians = PedestrianManager.new()
	pedestrians.vehicles = vehicles
	add_child(pedestrians)

	player = Player.new()
	add_child(player)
	player.global_position = City.start_position()
	session.players.add(1)
	_registered_player_id = 1
	session.set_local_player(1)
	session.bind_actor(1, player)
	pedestrians.player = player

	director = Director.new()
	director.player = player
	director.vehicles = vehicles
	director.pedestrians = pedestrians
	add_child(director)
	var ring := HeadingRing.new()
	ring.director = director
	add_child(ring)
	director.control_changed.connect(func(t: Node2D): camera.target = t)
	director.control_changed.connect(_on_control_changed)

	traffic = TrafficSystem.new()
	traffic.traffic_count = traffic_count
	traffic.bus_count = bus_count
	traffic.seed = traffic_seed
	traffic.vehicles = vehicles
	traffic.pedestrians = pedestrians
	traffic.player = player
	add_child(traffic)
	director.vehicle_stolen.connect(func(v: Vehicle, _d): traffic.remove_ai(v))
	director.entering_started.connect(func(v: Vehicle): if v.ai: v.ai.halt = true)

	camera = ChaseCamera.new()
	camera.target = player
	add_child(camera)
	camera.make_current()

	combat = Combat.new()
	combat.vehicles = vehicles
	combat.pedestrians = pedestrians
	combat.player = player
	combat.director = director
	combat.traffic = traffic
	add_child(combat)

	police = PoliceDispatcher.new()
	police.director = director
	police.combat = combat
	police.traffic = traffic
	police.pedestrians = pedestrians
	police.vehicles = vehicles
	police.patrol_count = police_patrols
	add_child(police)
	director.police = police
	combat.police = police
	police.busted.connect(_on_busted)
	player.died.connect(_on_died)

	weapons = PlayerWeapons.new()
	weapons.director = director
	weapons.player = player
	weapons.combat = combat
	weapons.pedestrians = pedestrians
	weapons.vehicles = vehicles
	add_child(weapons)
	var target_ring := TargetRing.new()
	target_ring.weapons = weapons
	add_child(target_ring)
	var local_session := session.local_player()
	local_session.director = director
	local_session.weapons = weapons

	pickups = Pickups.new()
	pickups.director = director
	pickups.player = player
	pickups.pedestrians = pedestrians
	add_child(pickups)

	fires = Fires.new()
	fires.pedestrians = pedestrians
	fires.player = player
	fires.director = director
	fires.combat = combat
	fires.traffic = traffic
	fires.vehicles = vehicles
	add_child(fires)
	combat.fires = fires

	ems = EmsDispatcher.new()
	ems.pedestrians = pedestrians
	ems.traffic = traffic
	ems.vehicles = vehicles
	ems.obstacles = city.obstacle_rects()
	add_child(ems)

	gangs = GangManager.new()
	gangs.gangs = GANGS
	gangs.respect = respect
	gangs.director = director
	gangs.player = player
	gangs.combat = combat
	gangs.pedestrians = pedestrians
	add_child(gangs)

	missions = MissionSystem.new()
	missions.gangs = gangs
	missions.respect = respect
	missions.wallet = wallet
	missions.director = director
	missions.player = player
	missions.police = police
	missions.traffic = traffic
	missions.setup(vehicles)
	add_child(missions)

	for t in HIDEOUTS:
		var h := Hideout.new()
		h.type = t
		h.owned = t.price == 0
		h.player = player
		h.director = director
		add_child(h)
		h.stepped_on.connect(_on_hideout_stepped.bind(h))
		hideouts.append(h)
	hideout = hideouts[0]
	current_hideout = hideout

	spray_shop = SprayShop.new()
	spray_shop.director = director
	spray_shop.police = police
	spray_shop.wallet = wallet
	add_child(spray_shop)

	jobs = SideJobs.new()
	jobs.jobs = SIDE_JOBS
	jobs.director = director
	jobs.player = player
	jobs.wallet = wallet
	jobs.pedestrians = pedestrians
	jobs.traffic = traffic
	jobs.fires = fires
	jobs.police = police
	jobs.missions = missions
	add_child(jobs)
	Vehicle.durability_bonus = {}
	street_events = StreetEvents.new()
	street_events.director = director
	street_events.player = player
	street_events.pedestrians = pedestrians
	street_events.police = police
	street_events.wallet = wallet
	street_events.combat = combat
	street_events.missions = missions
	street_events.jobs = jobs
	street_events.city = city
	add_child(street_events)
	packages = HiddenPackages.new()
	packages.director = director
	packages.player = player
	packages.wallet = wallet
	add_child(packages)
	rampages = Rampages.new()
	rampages.director = director
	rampages.player = player
	rampages.wallet = wallet
	rampages.pedestrians = pedestrians
	rampages.combat = combat
	rampages.missions = missions
	rampages.jobs = jobs
	rampages.gangs = GANGS
	add_child(rampages)
	car_sounds = CarSounds.new()
	car_sounds.vehicles = vehicles
	car_sounds.director = director
	add_child(car_sounds)

	sky = DayNight.new()
	sky.pedestrians = pedestrians
	add_child(sky)
	ambience = CityAmbience.new()
	ambience.sky = sky
	ambience.pedestrians = pedestrians
	add_child(ambience)
	radio = Radio.new()
	radio.director = director
	add_child(radio)

	hud = Hud.new()
	hud.director = director
	hud.police = police
	hud.wallet = wallet
	hud.player = player
	hud.missions = missions
	hud.respect = respect
	hud.city = city
	hud.sky = sky
	hud.jobs = jobs
	hud.events = street_events
	hud.rampages = rampages
	add_child(hud)
	jobs.shift_started.connect(func(j: SideJobType): hud.banner(j.display_name + " 부업", j.intro, 2.5, Hud.GOLD))
	jobs.level_done.connect(func(j: SideJobType, n: int, reward: int): hud.notify(Locale.t("%s %d단계 — ₩%s") % [Locale.t(j.display_name), n, Hud.won(reward)]))
	jobs.shift_ended.connect(func(j: SideJobType, n: int, reason: String):
		if reason != "완료":
			hud.notify(Locale.t("%s 끝 — %s (%d단계)") % [Locale.t(j.display_name), reason, n]))
	jobs.job_mastered.connect(_on_job_mastered)
	street_events.started.connect(func(e: StreetEventType, _c: StreetCriminal): hud.notify(e.start_text))
	street_events.resolved.connect(func(e: StreetEventType, pay: int, alive: bool):
		hud.banner(Locale.t("%s %s") % [Locale.t(e.display_name), "검거" if alive else "제압"], Locale.t("보상 ₩%s") % Hud.won(pay), 2.5, Hud.GOLD))
	street_events.failed.connect(func(e: StreetEventType): hud.notify(Locale.t("%s를 놓쳤다") % e.display_name))
	packages.collected.connect(func(n: int, total: int, pay: int): hud.notify(Locale.t("비밀 패키지 %d/%d — ₩%s") % [n, total, Hud.won(pay)]))
	packages.milestone.connect(func(w: WeaponType, n: int):
		hud.banner(Locale.t("비밀 패키지 %d개") % n, Locale.t("%s 해금 — 은신처에 늘 놓인다") % Locale.t(w.display_name), 3.0, Hud.GOLD)
		_stock_hideouts())
	packages.completed.connect(func(pay: int): hud.banner("비밀 패키지 모두 찾았다", Locale.t("보너스 ₩%s") % Hud.won(pay), 3.5, Hud.GOLD))
	rampages.started.connect(func(r: RampageType):
		hud.banner("광란!", Locale.t("%d초 안에 %s") % [int(r.time_limit), r.goal_text(rampages.gang_name(r.gang))], 2.5, Hud.BANNER_RED))
	rampages.finished.connect(func(r: RampageType, passed: bool, pay: int):
		if passed:
			hud.banner("광란 성공", Locale.t("보상 ₩%s · %d/%d") % [Hud.won(pay), rampages.done.size(), rampages.all().size()], 3.0, Hud.GOLD)
		else:
			hud.banner("광란 실패", Locale.t("%d / %d") % [rampages.kills, r.count], 2.5))
	radio.tuned.connect(hud.show_radio)
	radio.dj_line.connect(hud.show_dj)
	_update_goal()
	director.notice.connect(hud.notify)
	pickups.picked.connect(hud.notify)
	ems.heli_launched.connect(func(_at: Vector2): hud.notify("병원 구급헬기 출동"))
	spray_shop.notice.connect(hud.notify)
	missions.mission_started.connect(_on_mission_started)
	missions.mission_finished.connect(_on_mission_finished)

	save_menu = SaveMenu.new()
	add_child(save_menu)
	save_menu.chosen.connect(_on_slot_chosen)
	pause_menu = PauseMenu.new()
	pause_menu.main = self
	add_child(pause_menu)
	pause_menu.quit_to_title.connect(func(): get_tree().change_scene_to_file.call_deferred(TITLE_SCENE))
	if not IsoView.enabled:
		city.set_iso(false)       # 설정에서 위에서 보기를 골라 두었다

	var from_title := entry
	entry = ""
	if start > 0:
		hud.banner(Locale.t("%d장 · %s") % [chapter, chapter_type().title], Locale.t("시험 시작 (--chapter=%d) — 저장 불러오기 없음") % chapter, 3.5, Hud.GOLD)
	if get_parent() == get_tree().root:
		_give_arg_weapons()
		_apply_test_args.call_deferred()
	elif from_title != "":
		# 타이틀에서 골랐다: 불러오기 메뉴를 다시 띄우지 않는다
		if from_title == "load" and not load_game(entry_slot):
			hud.notify("저장을 불러오지 못했다 — 새 게임으로 시작")
	elif load_on_start and get_parent() == get_tree().root and (auto_line() != "" or not slot_lines().all(func(l): return l == "")):
		save_menu.open_load(slot_lines(), auto_line())


func _exit_tree() -> void:
	if _registered_player_id > 0:
		session.players.remove(_registered_player_id)
		_registered_player_id = 0


## 화면을 물리(초당 60틱)에 맞춰 60프레임으로 묶는다. 120Hz 화면에서 더 그려 봐야 같은 장면이고,
## 프레임마다 물리 틱 수가 0·1·2로 들쭉날쭉하면 움직임이 떨린다. 한 프레임이 늦어도 물리를 몰아서 따라잡지 않는다
## (MAX_CATCH_UP틱까지만) — 따라잡느라 다음 프레임이 더 늦어지는 악순환을 막는다. 헤드리스 테스트는 건드리지 않는다
static func limit_frame_rate() -> void:
	# 웹은 그리기 비용이 커서 30프레임으로 고르게 표시하되 물리는 60틱을 유지한다.
	Engine.max_fps = 30 if OS.has_feature("web") else Engine.physics_ticks_per_second
	Engine.max_physics_steps_per_frame = MAX_CATCH_UP


## 타이틀 화면(TitleScreen)에서 정한 시작 방식. "" 이면 타이틀을 거치지 않았다 (직접 실행·테스트).
## "new" 새 게임, "load" 슬롯 entry_slot에서 이어 하기. 읽으면 비운다
static var entry := ""
static var entry_slot := 0


## 실행 인자 `--chapter=N` (없으면 0)
static func start_chapter_arg() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--chapter="):
			return clampi(int(a.get_slice("=", 1)), 1, CityMap.LAST_CHAPTER)
	return 0


## 시험용: `-- --god`이면 주인공 무적, `-- --wanted=N`이면 수배 ★N으로 시작한다 (본편으로 켰을 때만)
func _apply_test_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--god":
			player.invincible = true
			hud.notify("시험: 무적")
		elif a.begins_with("--wanted="):
			police.wanted.raise_to(clampi(int(a.get_slice("=", 1)), 1, 6))


## 시험용: `-- --give=rifle,pistol`이면 그 무기(data/weapons/<이름>.tres)를 탄 넉넉히 쥐고, 맨 앞 것을 든 채 시작한다
func _give_arg_weapons() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--give="):
			continue
		var first: WeaponType = null
		for id in a.get_slice("=", 1).split(",", false):
			var path := "res://data/weapons/%s.tres" % id.strip_edges()
			if not ResourceLoader.exists(path):
				push_warning("--give: 무기 %s 없음" % id)
				continue
			var w: WeaponType = load(path)
			player.arsenal.give(w, 999)
			if first == null:
				first = w
		if first:
			player.arsenal.index = player.arsenal.weapons.find(first)


func _physics_process(delta: float) -> void:
	# 구급차에 타고 있으면 체력이 찬다
	var v := director.current_vehicle
	if v and v.stats.heal_rate > 0.0 and not v.wrecked:
		player.heal(v.stats.heal_rate * delta)
	_check_chapter()
	_check_district()


## 열린 구역 랜드마크 공터에 세워 둔 차 (터미널 승강장의 고속버스·소방서 소방차·주유소 택시·부두 헬기 — 훔쳐 탈 수 있다).
## 장이 열릴 때마다 다시 불러, 아직 안 세운 자리에만 세운다
func _spawn_landmark_parking() -> void:
	if work_zone == null:
		var site := City.work_site()
		if not site.is_empty():
			work_zone = WorkZone.build(self, site)   # 4장 외곽 공단 도로 공사 현장 (굴삭기·불도저는 아래 주차로 선다)
	for spot: Array in city.landmark_parking():
		var key := Vector2i(spot[0].round())
		if _landmark_parked.has(key):
			continue
		var t: VehicleType = load(spot[2]) if spot.size() > 2 else LANDMARK_BUS
		if Vehicle.exists(vehicles, t):
			continue   # 한 대만 있는 차종(자주포)이 이미 도시에 있다 — 그게 없어지면 다음에 세운다
		_landmark_parked[key] = true
		var v := Vehicle.new()
		v.stats = t
		add_child(v)
		v.place(spot[0], spot[1])
		if spot.size() > 3:
			v.set_level(spot[3])   # 옥상(층 1)에 선 헬기
		v.landing_blocked.connect(func(): if hud: hud.notify("밑이 막혀 내려앉을 수 없다 — 빈 땅이나 도로 위로 옮긴다"))
		vehicles.append(v)


func _spawn_parked(spec: Array) -> Vehicle:
	var v := Vehicle.new()
	v.stats = VEHICLE_TYPES[spec[0]]
	v.has_driver = spec[5]
	add_child(v)
	if spec[1]:
		v.place(City.curb_vertical(spec[2], spec[3], spec[4]), 0.0)
	else:
		v.place(City.curb_horizontal(spec[2], spec[3], spec[4]), PI * 0.5)
	return v


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("view_toggle"):
		set_iso(not IsoView.enabled)
	if director.current_vehicle:
		for i in DEV_SWITCH_TYPES:
			if event.is_action_pressed("vehicle_%d" % (i + 1)):
				switch_vehicle(i)
	if event.is_action_pressed("reset"):
		if police.wanted.level > 0:
			hud.notify("수배 중에는 돌아갈 수 없다")
		elif missions.active():
			hud.notify("미션 중에는 돌아갈 수 없다")
		else:
			reset()


## 화면을 2.5D(사선)와 위에서 보기 사이에서 바꾼다. 물리·AI는 그대로다
func set_iso(on: bool) -> void:
	IsoView.enabled = on
	city.set_iso(on)
	Settings.values["iso"] = on
	hud.notify("2.5D 화면" if on else "위에서 보는 화면")


## 장을 바꾼다: 그 장까지의 구역이 열린다 (통제 바리케이드가 걷히고 길찾기가 새 길을 안다)
func set_chapter(n: int) -> void:
	chapter = clampi(n, 1, CityMap.LAST_CHAPTER)
	CityMap.set_chapter(chapter)
	RoadNav.clear_cache()
	city.refresh_locks()
	traffic.on_map_changed()
	pedestrians.on_map_changed()
	_spawn_landmark_parking()   # 새로 열린 구역의 랜드마크 차 (4장 부두 헬기)
	_update_goal()


func chapter_type() -> ChapterType:
	return CHAPTERS[chapter - 1]


## 캠핑카에서 내리면 그 자리에서 저장할 수 있다 (이동식 세이브 포인트, docs/03 §6)
func _on_control_changed(target: Node2D) -> void:
	if target is Vehicle:
		_last_vehicle = target
		return
	var v := _last_vehicle
	_last_vehicle = null
	if v and is_instance_valid(v) and v.stats.save_point and not v.wrecked and v.speed() < 20.0 and not _respawning:
		open_save_menu()


# ── 부업 ──────────────────────────────────────────────────

func _on_job_mastered(j: SideJobType) -> void:
	hud.banner(Locale.t("%s 부업 완료!") % Locale.t(j.display_name), "보너스: " + Locale.t(j.bonus_text), 4.0, Hud.GOLD)
	_apply_job_bonuses()


## 부업 보너스를 세상에 반영한다 (차 체력·불 피해)
func _apply_job_bonuses() -> void:
	var bonus := {}
	for id: StringName in SideJobs.DURABILITY_BONUS:
		if jobs.has_bonus(id):
			bonus[SideJobs.DURABILITY_BONUS[id]] = 1.5
	Vehicle.durability_bonus = bonus
	fires.player_scale = 0.5 if jobs.has_bonus(&"fire") else 1.0


# ── 장 진행 ───────────────────────────────────────────────

## 목표 금액을 모으면 다음 장을 연다 (마지막 장이면 엔딩). 장이 열리면 자동 저장한다.
func _check_chapter() -> void:
	if finished or _respawning or wallet.money < chapter_type().target:
		return
	if chapter >= CHAPTERS.size():
		finished = true
		_update_goal()
		hud.banner("엔딩", Locale.t("%s 모았다 — 서울은 이제 네 것이다") % ("₩" + Hud.won(chapter_type().target)), 6.0, Hud.GOLD)
		autosave()
		return
	set_chapter(chapter + 1)
	var names: Array[String] = []
	for d in CityMap.districts_of_chapter(chapter):
		names.append(d.display_name)
	hud.banner(Locale.t("%d장 · %s") % [chapter, chapter_type().title], "새 구역: " + " · ".join(names), 4.5, Hud.GOLD)
	hud.notify(chapter_type().intro)
	autosave()


func _update_goal() -> void:
	if hud == null:
		return
	if finished:
		hud.goal_text = Locale.t("엔딩 — 자유 플레이")
	else:
		hud.goal_text = Locale.t("%d장 %s · 목표 ₩%s") % [chapter, Locale.t(chapter_type().title), Hud.won(chapter_type().target)]


## 다른 구역에 들어서면 이름을 띄운다 (GTA2처럼)
func _check_district() -> void:
	var d := CityMap.district_at(director.controlled_target().global_position)
	if d == null or d == _district:
		return
	var first := _district == null
	_district = d
	if not first:
		hud.show_district(d.display_name, d.tagline, d.color)


## 운전 중인 차의 차종을 바꾼다 (개발용)
func switch_vehicle(index: int) -> void:
	var v := director.current_vehicle
	if v:
		v.apply_stats(VEHICLE_TYPES[index])
		v.motor.velocity = Vector2.ZERO


## 도보로 출발점에 돌아가고, 출발 차를 제자리에 둔다
func reset() -> void:
	director.exit_vehicle()
	start_vehicle.place(City.curb_vertical(3, 3, 0.5), 0.0)
	player.global_position = City.start_position()
	camera.snap()


## 붙잡혔다: 벌금을 내고 무기를 빼앗긴 채 경찰서 앞에서 다시 시작한다
func _on_busted(fine: int) -> void:
	if _respawning:
		return
	var paid := wallet.pay(fine / 2 if jobs.has_bonus(&"vigilante") else fine)
	missions.fail("체포")
	jobs.end("체포")
	rampages.abort()
	_respawn("체포!", "벌금 ₩%s · 무기 압수" % Hud.won(paid), City.nearest_police_station(director.controlled_target().global_position))


## 기절했다: 치료비를 내고 무기를 잃은 채 병원 앞에서 다시 시작한다
func _on_died() -> void:
	if _respawning:
		return
	var paid := wallet.pay(0 if jobs.has_bonus(&"ambulance") else HOSPITAL_FEE)
	missions.fail("기절")
	jobs.end("기절")
	rampages.abort()
	_respawn("기절!", "치료비 ₩%s · 무기 분실" % Hud.won(paid), City.nearest_hospital(director.controlled_target().global_position))


func _respawn(title: String, sub: String, at: Vector2) -> void:
	_respawning = true
	director.exit_vehicle()
	player.input_enabled = false
	police.freeze()
	hud.banner(title, sub)
	await get_tree().create_timer(BUST_DELAY, true, true).timeout
	police.reset()
	gangs.calm()
	player.arsenal.clear()
	player.revive()
	player.global_position = at
	player.facing = PI
	player.input_enabled = true
	camera.snap()
	_respawning = false


# ── 미션 ──────────────────────────────────────────────────

func _on_mission_started(m: MissionType) -> void:
	hud.banner(m.title, m.briefing, 3.5, Hud.GOLD)


func _on_mission_finished(m: MissionType, passed: bool, reason: String) -> void:
	if passed:
		var g := gangs.gang(m.gang)
		hud.banner("미션 성공!", Locale.t("₩%s · %s 존경도 +%d") % [Hud.won(m.reward), Locale.t(g.display_name), m.respect], 3.0, Hud.GOLD)
	elif _respawning or reason == "기절" or reason == "체포":
		hud.notify(Locale.t("미션 실패 — %s") % reason)
	else:
		hud.banner("미션 실패", reason)


# ── 저장 · 불러오기 ────────────────────────────────────────

func slot_path(slot: int) -> String:
	return SaveGame.slot_path(save_prefix, slot)


## 슬롯 1~3의 요약 (빈 슬롯은 "")
func slot_lines() -> Array[String]:
	var lines: Array[String] = []
	for slot in range(1, SaveGame.SLOTS + 1):
		var s := SaveGame.read(slot_path(slot))
		lines.append(s.summary(MissionSystem.MISSIONS.size()) if s else "")
	return lines


## 자동 저장 칸 요약 (없으면 "")
func auto_line() -> String:
	var s := SaveGame.read(slot_path(SaveGame.AUTO_SLOT))
	return s.summary(MissionSystem.MISSIONS.size()) if s else ""


## 은신처 발판을 밟았다. 아직 안 산 곳이면 살지 묻고, 내 것이면 저장 메뉴를 연다.
func _on_hideout_stepped(h: Hideout) -> void:
	if h.owned:
		current_hideout = h
		open_save_menu()
		return
	if wallet.money < h.type.price:
		hud.notify(Locale.t("%s — ₩%s 필요") % [Locale.t(h.type.display_name), Hud.won(h.type.price)])
		return
	_buying = h
	save_menu.open_confirm("%s — ₩%s에 살까?" % [h.type.display_name, Hud.won(h.type.price)], "산다", "그만둔다")


## 은신처를 산다 (돈이 모자라면 false)
func buy_hideout(h: Hideout) -> bool:
	if h.owned or wallet.money < h.type.price:
		return false
	wallet.pay(h.type.price)
	h.owned = true
	current_hideout = h
	hud.notify(Locale.t("%s을(를) 샀다 — 여기서 저장할 수 있다") % h.type.display_name)
	_stock_hideouts()
	return true


## 비밀 패키지로 푼 무기를 산 은신처마다 다시 생기는 상자로 놓는다
func _stock_hideouts() -> void:
	var doors := []
	for h in hideouts:
		if h.owned:
			doors.append([h.type.door, h.type.along])
	pickups.set_stock(doors, packages.unlocked())


func hideout_by_id(id: StringName) -> Hideout:
	for h in hideouts:
		if h.type.id == id:
			return h
	return null


## 은신처 발판을 밟았다: 저장할 슬롯을 고른다. 수배 중이거나 미션 중이면 열지 않는다.
func open_save_menu() -> void:
	if police.wanted.level > 0:
		hud.notify("수배 중에는 저장할 수 없다")
		return
	if missions.active():
		hud.notify("미션 중에는 저장할 수 없다")
		return
	save_menu.open_save(slot_lines())


func _on_slot_chosen(slot: int) -> void:
	match save_menu.mode:
		SaveMenu.Mode.SAVE:
			save_game(slot)
		SaveMenu.Mode.CONFIRM:
			if slot == 1 and _buying:
				buy_hideout(_buying)
			_buying = null
		_:
			if slot > 0:
				load_game(slot)


## 지금 상태를 슬롯에 저장한다. 수배 중이거나 미션 중이면 저장하지 않는다.
func save_game(slot: int) -> bool:
	if police.wanted.level > 0 or missions.active():
		return false
	if not _snapshot().write(slot_path(slot)):
		hud.notify("저장 실패")
		return false
	player.revive()
	hud.notify(Locale.t("슬롯 %d에 저장했다 — 체력 회복") % slot)
	return true


## 장이 열릴 때 자동 저장 칸에 저장한다 (수배·미션과 상관없이 — 불러오면 은신처에서 깨끗이 시작한다)
func autosave() -> bool:
	return _snapshot().write(slot_path(SaveGame.AUTO_SLOT))


func _snapshot() -> SaveGame:
	var s := SaveGame.new()
	s.money = wallet.money
	for id: StringName in respect.values:
		s.respect[String(id)] = respect.of(id)
	for id: StringName in missions.completed:
		s.completed.append(String(id))
	for w in player.arsenal.weapons:
		if w != player.arsenal.fist:
			s.weapons[w.resource_path] = player.arsenal.ammo_of(w)   # 방망이처럼 탄 없는 무기는 -1
	s.saved_at = Time.get_datetime_string_from_system(false, true)
	s.chapter = chapter
	s.finished = finished
	for id: StringName in jobs.best:
		s.jobs[String(id)] = jobs.best[id]
	for id: StringName in jobs.bonuses:
		s.job_bonuses.append(String(id))
	for i: int in packages.got:
		s.packages.append(i)
	for id: StringName in rampages.done:
		s.rampages.append(String(id))
	s.hideout = String(current_hideout.type.id)
	for h in hideouts:
		if h.owned and h.type.price > 0:
			s.hideouts.append(String(h.type.id))
	return s


## 슬롯에서 이어 한다: 돈·존경도·끝낸 미션·무기, 은신처 앞에서 시작. 비었으면 false
func load_game(slot: int) -> bool:
	var s := SaveGame.read(slot_path(slot))
	if s == null:
		return false
	wallet.money = s.money
	respect.values.clear()
	for id: String in s.respect:
		respect.set_value(StringName(id), s.respect[id])
	missions.completed.clear()
	for id in s.completed:
		missions.completed[StringName(id)] = true
	player.arsenal.clear()
	for path: String in s.weapons:
		if ResourceLoader.exists(path):
			player.arsenal.give(load(path), s.weapons[path])
	finished = s.finished
	set_chapter(s.chapter)
	jobs.end("불러오기")
	jobs.best.clear()
	jobs.bonuses.clear()
	for id: String in s.jobs:
		jobs.best[StringName(id)] = s.jobs[id]
	for id in s.job_bonuses:
		jobs.bonuses[StringName(id)] = true
	_apply_job_bonuses()
	for h in hideouts:
		h.owned = h.type.price == 0 or s.hideouts.has(String(h.type.id))
	packages.restore(s.packages)
	rampages.restore(s.rampages)
	_stock_hideouts()
	var at := hideout_by_id(StringName(s.hideout))
	current_hideout = at if at and at.owned else hideout
	director.exit_vehicle()
	police.reset()
	player.global_position = current_hideout.type.door + current_hideout.type.along
	player.facing = PI
	camera.snap()
	hud.notify(Locale.t("%s — %s에서 이어 한다") % ["자동 저장" if slot == SaveGame.AUTO_SLOT else "슬롯 %d" % slot,
		current_hideout.type.display_name])
	return true
