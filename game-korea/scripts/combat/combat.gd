class_name Combat
extends Node2D
## 사격·주먹·폭발과 그 효과(총알 궤적·총구 불꽃·폭발·그을음).
## 피해는 맞은 쪽에 넘긴다: 차는 Vehicle.take_damage, 사람은 PedestrianManager.damage, 주인공은 Player.take_damage.
## 차에 불이 붙으면 운전자를 내리게 하고, 터지면 주변에 폭발 피해를 준다 (그 피해로 옆 차가 또 터진다 — 연쇄).

signal gunfire(pos: Vector2, by_player: bool)
signal vehicle_attacked(vehicle: Vehicle, by_player: bool)   ## 총에 맞은 차 (충돌·폭발 피해는 빼고)
signal vehicle_exploded(vehicle: Vehicle, by_player: bool)

const SEED := 4404
## 총알 한 발은 짧은 빛줄기가 총구에서 맞은 곳까지 날아간다 (선 하나가 한 번에 그어지지 않는다).
## 맞히기는 쏘는 순간 정한다 — 그림만 날아간다
const BULLET_SPEED := 2600.0         ## 날아가는 빠르기 (px/s, 500px에 약 0.2초)
const BULLET_LEN := 30.0             ## 빛줄기 길이
const FLASH_TIME := 0.05             ## 총구 불꽃
const SPARK_TIME := 0.09             ## 맞은 곳 불똥
const BLAST_TIME := 1.8              ## 불덩이는 금방 사라지고 연기·불타는 파편이 조금 더 남는다
const SWING_TIME := 0.12
const SCARE_RADIUS := 320.0          ## 총소리에 겁먹는 거리
const BLAST_SCARE_RADIUS := 500.0
const BLAST_SPRITE_SIZE := 0.95     ## 폭발 넘김 그림 크기 (그림의 가장 큰 불덩이 반지름 ÷ 코드 불덩이 반지름 r)
const WRECK_TIME := 30.0             ## 잔해는 이만큼 지나고 화면 밖이면 치운다
const OFFSCREEN := 950.0
const MAX_SCORCH := 40
const EJECT_OFFSET := 16.0
const SHELL_ARC := 0.32              ## 포탄 궤적 꼭대기 높이 = 날아가는 거리 × 이 값 (곡사)
const MUZZLE_TIME := 0.35            ## 포구 불꽃·연기
const CRUSH_DPS := 160.0             ## 무한궤도에 깔린 차가 받는 초당 피해 (몇 초면 불이 난다)
const CRUSH_RATE := 1.5              ## 깔린 차가 납작해지는 빠르기 (1/s)
const CRUSH_PLAYER_DPS := 400.0      ## 무한궤도 밑에 깔린 주인공(도보)이 받는 초당 피해
const CRUSH_MOVING := 4.0
const GRAB_RADIUS := 26.0            ## 굴삭기 버킷이 이 안의 차를 집는다 (차 반 폭을 더한다)
const GRAB_DAMAGE := 25.0            ## 버킷에 찍혀 집힌 차가 받는 피해
const DIG_RADIUS := 22.0             ## 버킷이 찍은 곳에서 이 안의 사람은 넘어진다
const DIG_PERSON_DAMAGE := 40.0
const BLADE_DPS := 70.0              ## 내린 불도저 블레이드에 밀리는 차가 받는 초당 피해
const BLADE_PERSON_DAMAGE := 30.0    ## 블레이드에 밀린 사람 (넘어진다)
const BUMP_SOUND := 70.0            ## 이 세기(부딪힌 속도 px/s)부터 쿵 소리
const CRASH_SOUND := 260.0           ## 이 세기부터 쾅 (찌그러지는 쇳소리)
const DOWN_REACH := 60.0             ## 헬기에서 내려쏜 총알이 겨눈 곳 앞에서부터 맞히는 거리
const DOWN_MUZZLE := 4.0             ## 헬기에서 쏜 궤적이 나오는 높이 = 헬기 높이 − 이 값 (동체 아래)
const AIR_HIT_RADIUS := 0.5         ## 떠 있는 헬기를 맞히는 반경 = 길이 × 이 값 (아래에서 보면 날개까지 표적이다)
const ROCKET_SETTLE := 140.0         ## 로켓이 그림 속 탄두 자리에서 맞히는 길(가슴 높이)로 내려앉는 거리 (px)
const ROCKET_TUBE := 20.0            ## 발사관 뒤끝을 모를 때(차에서 쏘기·위에서 보기) 탄두 끝에서 뒤로 이만큼
const ROCKET_LEN := 11.0             ## 날아가는 로켓 그림 길이 (화면 px, 옆에서 볼 때)
const ROCKET_PUFF_EVERY := 3.5       ## 로켓 꼬리 연기 한 덩이마다 날아간 거리 (px)
const ROCKET_SMOKE_TIME := 1.3       ## 꼬리 연기가 퍼지며 사라지는 시간
const BACKBLAST_TIME := 1.1          ## 쏜 자리 앞 불꽃·뒤 후폭풍 연기
const DUST_TIME := 1.2            ## 이보다 빨리 움직이거나 돌 때만 깔아뭉갠다 (px/s)

var vehicles: Array[Vehicle] = []    ## 도시의 모든 차 (main과 공유)
var pedestrians: PedestrianManager
var player: Player
var director: Director
var traffic: TrafficSystem
var police: PoliceDispatcher
var fires: Fires                     ## 없으면 불이 붙지 않는다
const TANK_CANNON: WeaponType = preload("res://data/weapons/tank_cannon.tres")
var rng := RandomNumberGenerator.new()
var explosions := 0                  ## 지금까지 터진 차 수 (테스트용)

var _tracers: Array = []             ## 날아가는 총알 [from, to, color, age] — 나이는 늘 맨 끝
var _projectiles: Array[Dictionary] = []   ## 날아가는 수류탄·화염병·로켓 {pos, vel, w, by_player, age, travel, exclude, stopped}
var _flames: Array = []              ## 화염방사기·물대포 불꽃 [from, dir, w, age]
var _blasts: Array = []              ## [pos, 크기 배율, age]
var _swings: Array = []              ## [pos, dir, age]
var _shells: Array[Dictionary] = []  ## 곡사 포탄 {from, to, dur, t, w, by_player, shooter} — 건물 위로 날아가 겨눈 땅에 떨어진다
var _muzzles: Array = []             ## 포구 불꽃 [pos, dir, age]
var _dusts: Array = []               ## 굴삭기가 찍은 흙먼지 [pos, age]
var _backblasts: Array = []          ## 로켓을 쏜 자리 [탄두 끝, 발사관 뒤끝, 월드 방향, age] (그리는 자리 — 가슴 높이를 뺀 점)
var _rocket_smoke: Array = []        ## 로켓 꼬리 연기 [자리, seed, age]
var _under := {}                     ## 무한궤도 밑에 든 차 [무한궤도, 차] → true (그동안 둘의 충돌을 뺀다)
var _scorch: Array[Vector2] = []
var _decals: Node2D
var _watched := {}                   ## 신호를 연결한 차
var _wrecks := {}                    ## 잔해 → 터진 뒤 지난 시간


func _ready() -> void:
	rng.seed = SEED
	z_as_relative = false
	z_index = 5
	_decals = Node2D.new()
	_decals.z_as_relative = false
	_decals.z_index = -5
	_decals.draw.connect(_draw_decals)
	add_child(_decals)
	add_child(Sfx.new())


func _physics_process(delta: float) -> void:
	z_index = IsoView.Z_EFFECTS if IsoView.enabled else 5
	for v in vehicles:
		if not _watched.has(v):
			_watched[v] = true
			v.caught_fire.connect(_on_caught_fire.bind(v))
			v.exploded.connect(_on_exploded.bind(v))
			v.impacted.connect(_on_impacted.bind(v))
			if v.stats.arm_reach.y > 0.0:
				v.dug.connect(_on_dug.bind(v))
	_cleanup_wrecks(delta)
	_fly(delta)
	_fly_shells(delta)
	_crush(delta)
	_blades(delta)
	for pair: Array in _under.keys():
		if not is_instance_valid(pair[0]) or not is_instance_valid(pair[1]):
			_under.erase(pair)
	for list: Array in [_tracers, _blasts, _swings, _flames, _muzzles, _dusts, _backblasts, _rocket_smoke]:
		for e: Array in list:
			e[-1] += delta
	_flames = _flames.filter(func(e: Array): return e[3] < 0.25)
	_tracers = _tracers.filter(func(e: Array): return e[3] < _tracer_life(e))
	_blasts = _blasts.filter(func(e: Array): return e[2] < BLAST_TIME)
	_swings = _swings.filter(func(e: Array): return e[2] < SWING_TIME)
	_muzzles = _muzzles.filter(func(e: Array): return e[2] < MUZZLE_TIME)
	_dusts = _dusts.filter(func(e: Array): return e[1] < DUST_TIME)
	_backblasts = _backblasts.filter(func(e: Array): return e[3] < BACKBLAST_TIME)
	_rocket_smoke = _rocket_smoke.filter(func(e: Array): return e[2] < ROCKET_SMOKE_TIME)


## 그림은 화면 프레임마다 한 번 (물리 틱마다 부르면 느릴수록 한 프레임에 여러 번 그린다)
func _process(_delta: float) -> void:
	queue_redraw()


# ── 사격 ──────────────────────────────────────────────────

## from에서 dir 쪽으로 무기 w를 한 번 쏜다(친다). exclude는 맞지 않을 몸(쏜 사람, 탄 차).
## level은 쏜 사람의 고가차도 층 — 총알은 같은 층의 벽·차·사람만 맞는다 (-1이면 쏜 자리로 정한다).
## shown은 궤적을 그리기 시작할 점(전역, 그림 높이까지 올린 점 — 그림 속 총구, PersonRig.gun_muzzle). 맞히기는 from 그대로.
## rear는 로켓포 그림의 발사관 뒤끝(PersonRig.gun_breech) — 후폭풍이 나오는 곳
func fire(from: Vector2, dir: Vector2, w: WeaponType, by_player: bool, exclude: Array[RID] = [], extra_spread := 0.0,
		level := -1, shown: Variant = null, rear: Variant = null) -> void:
	var lv := level if level >= 0 else maxi(CityMap.level_zone(from), 0)
	if w.melee:
		_melee(from, dir, w, by_player, exclude)
		return
	if w.projectile != &"":
		_launch(from, dir, w, by_player, exclude, lv, shown, rear)
		return
	if w.flame or w.water:
		_spray(from, dir, w, by_player, exclude, lv)
		return
	var space := get_world_2d().direct_space_state
	for d in Ballistics.pellet_dirs(dir, w, rng, extra_spread):
		var to := from + d * w.max_range
		# 떠 있는 헬기는 충돌체가 없어 따로 잰다. 위로 쏘는 총알이라 건물 벽은 넘어가고, 그 앞의 사람·차에 먼저 맞으면 못 간다.
		# 주인공 총알은 경찰 헬기도 이렇게 잰다
		var air := _air_target(from, d, w.max_range, exclude, true, by_player)
		var air_at := from.distance_to(air[1]) if not air.is_empty() else INF
		# 관통: 맞은 몸을 빼고 다시 재서 pierce개까지 맞힌다 (벽에 닿으면 멈춘다)
		var skip := exclude.duplicate()
		for n in w.pierce:
			var q := PhysicsRayQueryParameters2D.create(from, from + d * w.max_range,
				Layers.at(Layers.WORLD | Layers.VEHICLES | Layers.PEOPLE, lv), skip)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				to = from + d * w.max_range
				break
			var wall: bool = not (hit.collider is CollisionObject2D) or hit.collider is StaticBody2D
			if not air.is_empty() and (wall or from.distance_to(hit.position) > air_at):
				break
			to = hit.position
			if wall:
				break
			_hit(hit.collider, d, w.damage, by_player)
			skip.append((hit.collider as CollisionObject2D).get_rid())
			if n == w.pierce - 1:
				air = []      # 꿰뚫을 힘을 땅에서 다 썼다
		if not air.is_empty():
			to = air[1]
			if air[0] is PoliceHeli:
				(air[0] as PoliceHeli).take_damage(w.damage, by_player)
			else:
				var heli: Vehicle = air[0]
				damage_vehicle(heli, w.damage * heli.ground_fire_factor(), by_player)
		var end := to
		if not air.is_empty() and IsoView.enabled:
			end = to + IsoView.lift(_air_height(air[0]) - 12.0)   # 궤적은 떠 있는 헬기 그림까지 올라간다
		elif IsoView.enabled:
			end = to + IsoView.lift(IsoView.ground(to, lv))       # 다리·고가·언덕 위에서는 그 땅 높이에서
		var start := from + (IsoView.lift(IsoView.ground(from, lv)) if IsoView.enabled else Vector2.ZERO)
		if shown is Vector2:
			start = to_local(shown) - IsoView.lift(12.0)   # _draw가 궤적을 가슴 높이(12)로 올려 그리므로 그만큼 뺀다 (그림 속 총구는 땅 높이를 담고 있다)
		_tracers.append([start, end, w.tracer_color, 0.0])
	Sfx.play(w.sound, from)
	gunfire.emit(from, by_player)
	pedestrians.scare(from, SCARE_RADIUS)


## 총알 길(from에서 d쪽으로 reach)에 걸리는 떠 있는 헬기 중 가장 가까운 것: [헬기, 맞은 점] (없으면 []).
## 땅에서 쏘면(from_ground) 땅 위 거리와 높이를 함께 따져 사거리 안이어야 한다. police면 경찰·군 헬기(PoliceHeli)도 본다
func _air_target(from: Vector2, d: Vector2, reach: float, exclude: Array[RID], from_ground := true, police_too := false) -> Array:
	var best: Array = []
	var best_t := INF
	for v in vehicles:
		if not is_instance_valid(v) or not v.stats.flies or not v.airborne() or v.wrecked or exclude.has(v.get_rid()):
			continue
		var t := (v.global_position - from).dot(d)
		if t <= 0.0 or t >= best_t:
			continue
		var point := from + d * t
		if point.distance_to(v.global_position) > v.stats.size.y * AIR_HIT_RADIUS:
			continue
		if Vector2(t, v.altitude if from_ground else 0.0).length() > reach:
			continue
		best = [v, point]
		best_t = t
	if police_too and police:
		for h in police.helis:
			if h.down:
				continue
			var t := (h.global_position - from).dot(d)
			if t <= 0.0 or t >= best_t:
				continue
			var point := from + d * t
			if point.distance_to(h.global_position) > h.hit_radius():
				continue
			if Vector2(t, h.altitude() if from_ground else 0.0).length() > reach:
				continue
			best = [h, point]
			best_t = t
	return best


## 떠 있는 헬기(Vehicle·PoliceHeli) 몸통이 그려지는 높이 (화면 px)
static func _air_height(h: Node2D) -> float:
	if h is PoliceHeli:
		return (h as PoliceHeli).altitude()
	var v := h as Vehicle
	return v.altitude + v.ground


## 공중(헬기)에서 땅의 at을 쏜다: at 바로 앞에서부터 광선을 재고, 궤적은 헬기에서 그린다
func fire_from_air(air: Vector2, at: Vector2, w: WeaponType) -> void:
	var space := get_world_2d().direct_space_state
	var d := (at - air).normalized().rotated(rng.randf_range(-w.spread, w.spread))
	var from := at - d * 60.0 + d.orthogonal() * rng.randf_range(-18.0, 18.0)
	var to := from + d * 120.0
	# 떠 있는 헬기를 겨눴으면 그 헬기가 맞는다 (같은 하늘이라 피해는 그대로)
	Sfx.play(w.sound, air)
	var target := _air_target(from, d, 120.0, [], false)
	if not target.is_empty():
		var heli: Vehicle = target[0]
		damage_vehicle(heli, w.damage, false)
		var end: Vector2 = target[1]
		if IsoView.enabled:
			end += IsoView.lift(heli.altitude + heli.ground - 12.0)
		_tracers.append([air, end, w.tracer_color, 0.0])
		return
	var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(from, to, Layers.VEHICLES | Layers.PEOPLE))
	if not hit.is_empty():
		to = hit.position
		_hit(hit.collider, d, w.damage, false)
	_tracers.append([air, to, w.tracer_color, 0.0])


## 주인공이 탄 떠 있는 헬기(shooter)에서 땅의 at 쪽으로 쏜다. 위에서 내려쏘니 사이의 건물에 막히지 않고,
## 겨눈 곳 둘레(앞 DOWN_REACH · 뒤 그 반)의 사람·차에 맞는다. 길에 다른 떠 있는 헬기가 있으면 그게 맞는다(같은 하늘, 피해 그대로).
## 궤적은 헬기 그림(높이)에서 땅으로 그린다
func fire_down(shooter: Vehicle, at: Vector2, w: WeaponType, by_player: bool) -> void:
	var space := get_world_2d().direct_space_state
	var base := shooter.global_position
	var muzzle := base + IsoView.lift(shooter.altitude + shooter.ground - DOWN_MUZZLE) if IsoView.enabled else base
	var exclude: Array[RID] = [shooter.get_rid()]
	if by_player:
		exclude.append(player.get_rid())
	var lv := maxi(CityMap.level_zone(at), 0)
	var dist := maxf(base.distance_to(at), 1.0)
	for d in Ballistics.pellet_dirs((at - base).normalized(), w, rng):
		var spot := base + d * dist
		var end := spot
		var air := _air_target(base, d, dist, exclude, false)
		if not air.is_empty():
			var heli: Vehicle = air[0]
			damage_vehicle(heli, w.damage, by_player)
			end = air[1]
			if IsoView.enabled:
				end += IsoView.lift(heli.altitude + heli.ground - 12.0)
		else:
			var q := PhysicsRayQueryParameters2D.create(spot - d * DOWN_REACH, spot + d * DOWN_REACH * 0.5,
				Layers.at(Layers.VEHICLES | Layers.PEOPLE, lv), exclude)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				end = hit.position
				_hit(hit.collider, d, w.damage, by_player)
			if IsoView.enabled:
				end += IsoView.lift(IsoView.ground(end, lv))
		if by_player and police:
			for h in police.helis:
				if h.hit_by(base, spot):
					h.take_damage(w.damage, true)
		_tracers.append([muzzle, end, w.tracer_color, 0.0])
	Sfx.play(w.sound, base)
	gunfire.emit(at, by_player)
	pedestrians.scare(at, SCARE_RADIUS)


# ── 던지는 무기 · 로켓 ─────────────────────────────────────

## shown·rear: 로켓포 그림의 탄두 끝·발사관 뒤끝 (전역, Combat.fire). 로켓은 그림 속 탄두 자리에서 나와 ROCKET_SETTLE을 날며
## 맞히는 길(가슴 높이)로 내려앉는다. 쏜 자리에는 앞 불꽃과 뒤로 뿜는 후폭풍(`_backblasts`)을 남긴다
func _launch(from: Vector2, dir: Vector2, w: WeaponType, by_player: bool, exclude: Array[RID], level := 0,
		shown: Variant = null, rear: Variant = null) -> void:
	var d := dir.rotated(rng.randf_range(-w.spread, w.spread))
	var p := {"pos": from, "vel": d * w.projectile_speed, "w": w, "by_player": by_player, "age": 0.0,
		"travel": 0.0, "exclude": exclude, "stopped": false, "level": level}
	_projectiles.append(p)
	Sfx.play(w.sound, from)
	if w.projectile == &"rocket":
		gunfire.emit(from, by_player)
		pedestrians.scare(from, SCARE_RADIUS)
		# 그리는 자리: _draw가 가슴 높이(12)로 올려 그리므로 그만큼 뺀 점 (총알 궤적과 같다)
		var tip: Vector2 = to_local(shown) - IsoView.lift(12.0) if shown is Vector2 else from
		var back: Vector2 = to_local(rear) - IsoView.lift(12.0) if rear is Vector2 else tip - d * ROCKET_TUBE
		p["off"] = tip - from - _ground_lift(from)    # 그림 속 탄두 자리는 땅 높이를 담고 있다 — 땅 높이는 _rocket_at이 다시 더한다
		p["puff_at"] = 0.0
		_backblasts.append([tip, back, d, 0.0])


func _fly(delta: float) -> void:
	var space := get_world_2d().direct_space_state
	for p: Dictionary in _projectiles.duplicate():
		var w: WeaponType = p.w
		p.age += delta
		if p.stopped:
			if p.age >= w.fuse:
				_detonate(p)
			continue
		var step: Vector2 = p.vel * delta
		var to: Vector2 = p.pos + step
		var drawn_from := _rocket_at(p)   # 꼬리 연기를 이번 틱에 그리는 자리가 지나간 길 위에 고르게 놓는다
		var mask := Layers.at(Layers.WORLD | Layers.VEHICLES | Layers.PEOPLE, p.get("level", 0))
		var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(p.pos, to, mask, p.exclude))
		if not hit.is_empty():
			p.pos = hit.position - step.normalized() * 4.0
			if w.fuse > 0.0:
				p.stopped = true      # 수류탄은 부딪히면 멈춰 있다가 터진다
			else:
				_detonate(p)
			continue
		p.pos = to
		p.travel += step.length()
		if w.projectile == &"rocket":
			# 꼬리 연기: 날아간 거리마다 한 덩이씩, 이번 틱에 그리는 자리가 지나간 길(그림 속 탄두에서 내려앉는 길) 위에 꼬리만큼 뒤로
			var drawn_to := _rocket_at(p)
			var tail := (p.vel as Vector2).normalized() * 5.0
			var len := step.length()
			while p.travel - float(p.get("puff_at", 0.0)) >= ROCKET_PUFF_EVERY:
				p["puff_at"] = float(p.get("puff_at", 0.0)) + ROCKET_PUFF_EVERY
				var f := clampf(1.0 - (float(p.travel) - float(p.puff_at)) / maxf(len, 0.001), 0.0, 1.0)
				_rocket_smoke.append([drawn_from.lerp(drawn_to, f) - tail, fmod(float(p.puff_at) * 0.37, TAU), 0.0])
		if p.travel >= w.max_range:
			if w.fuse > 0.0:
				p.stopped = true
			else:
				_detonate(p)
		elif w.fuse > 0.0 and p.age >= w.fuse:
			_detonate(p)


func _detonate(p: Dictionary) -> void:
	_projectiles.erase(p)
	var w: WeaponType = p.w
	if w.explosion_scale > 0.0:
		explode(p.pos, p.by_player, null, w.explosion_scale)
	if w.fire_radius > 0.0 and fires:
		fires.start(p.pos, w.fire_radius, p.by_player)
		pedestrians.scare(p.pos, SCARE_RADIUS)
		gunfire.emit(p.pos, p.by_player)


# ── 곡사포 (자주포) ───────────────────────────────────────

## 포구 from에서 땅의 to로 포탄을 쏜다. 곡사라 건물에 막히지 않고 포물선을 그리며 날아가 to에서 터진다.
## 쏜 곳에 포구 불꽃, 둘레 사람은 겁먹고 총소리처럼 경찰이 듣는다
func fire_shell(from: Vector2, to: Vector2, w: WeaponType, by_player: bool, shooter: Vehicle = null) -> void:
	var dist := from.distance_to(to)
	_shells.append({"from": from, "to": to, "dur": maxf(dist / w.projectile_speed, 0.3), "t": 0.0, "w": w,
		"by_player": by_player, "shooter": shooter, "arc": dist * SHELL_ARC})
	_muzzles.append([from, (to - from).normalized(), 0.0])
	Sfx.play(w.sound, from)
	gunfire.emit(from, by_player)
	pedestrians.scare(from, BLAST_SCARE_RADIUS)


## 날아가는 포탄 수 (테스트용)
func shells_in_flight() -> int:
	return _shells.size()


func _fly_shells(delta: float) -> void:
	for p: Dictionary in _shells.duplicate():
		p.t += delta
		if p.t >= p.dur:
			_shells.erase(p)
			var w: WeaponType = p.w
			explode(p.to, p.by_player, null, w.explosion_scale)


## 포탄의 지금 위치 (땅 평면)와 높이
static func shell_at(p: Dictionary) -> Array:
	var k: float = clampf(p.t / p.dur, 0.0, 1.0)
	return [(p.from as Vector2).lerp(p.to, k), 4.0 * p.arc * k * (1.0 - k)]


# ── 무한궤도 깔아뭉개기 ───────────────────────────────────

## 움직이는 무한궤도 밑에 든 차는 납작해지며 크게 다치고(곧 불이 난다), 무한궤도는 그 차 높이만큼 올라타 넘는다.
## 무한궤도는 차와 부딪히지 않으므로(Vehicle.apply_stats) 막히지 않고 지나간다. 밑에 든 사람은 PedestrianManager가 친다
func _crush(delta: float) -> void:
	for t in vehicles:
		if not t.stats.crusher or t.wrecked:
			continue
		var moving := t.speed() > CRUSH_MOVING or absf(t.motor.steer) > 0.2 and (t.controlled or t.has_driver)
		var half := t.stats.size * 0.5
		var goal := 0.0
		t.over_z = 0
		for v in vehicles:
			if v == t or v.stats.tracked or v.apart(t.global_position, t.level):
				continue
			var local := t.to_local(v.global_position)
			var r := minf(v.stats.size.x, v.stats.size.y) * 0.5
			var depth := minf(half.x + r - absf(local.x), half.y + v.stats.size.y * 0.5 - absf(local.y)) / r
			var pair := [t, v]
			if depth <= 0.0:
				if _under.has(pair) and depth < -0.3:
					# 다 지나갔다: 다시 부딪히게 한다
					_under.erase(pair)
					v.remove_collision_exception_with(t)
				continue
			if not _under.has(pair):
				# 밑에 든 차가 겹침을 풀려고 무한궤도 앞으로 밀려 나가지 않게 둘의 충돌을 뺀다
				_under[pair] = true
				v.add_collision_exception_with(t)
			depth = minf(depth, 1.0)
			if moving:
				v.crushed = move_toward(v.crushed, 1.0, CRUSH_RATE * depth * delta)
				v.motor.velocity = v.motor.velocity.move_toward(Vector2.ZERO, 900.0 * delta)
				if not v.wrecked:
					damage_vehicle(v, CRUSH_DPS * depth * delta, t.controlled)
					v.dent_at(v.global_position + (t.global_position - v.global_position).normalized() * r, CRUSH_DPS * delta)
			goal = maxf(goal, v.stats.height * (1.0 - VehicleModel.CRUSH_FLAT * v.crushed) * minf(depth * 1.6, 1.0))
			t.over_z = maxi(t.over_z, v.z_index + 1)   # 올라탄 차보다 위에 그린다
		t.climb_goal = goal
		if moving and player and player.visible and not player.is_dead() and not t.apart(player.global_position, player.level):
			var lp := t.to_local(player.global_position)
			if absf(lp.x) < half.x + Player.RADIUS and absf(lp.y) < half.y + Player.RADIUS:
				player.take_damage(CRUSH_PLAYER_DPS * delta)


# ── 중장비 (굴삭기 · 불도저) ──────────────────────────────

## 굴삭기 버킷이 땅을 찍었다: 들고 있던 차가 있으면 그 자리에 놓고, 없으면 찍은 곳의 차를 집는다(탄 사람은 내린다).
## 찍힌 곳의 사람은 넘어지고 흙먼지가 인다
func _on_dug(at: Vector2, ex: Vehicle) -> void:
	_dusts.append([at, 0.0])
	for p: Pedestrian in pedestrians.peds.duplicate():
		if not p.is_dead() and p.global_position.distance_to(at) < DIG_RADIUS + Pedestrian.RADIUS:
			pedestrians.damage(p, DIG_PERSON_DAMAGE, p.global_position - at, ex.controlled, true)
	if ex.carried:
		ex.release()
		return
	var best: Vehicle = null
	var best_d := INF
	for v in vehicles:
		if v == ex or v.stats.tracked or v.apart(ex.global_position, ex.level) or v.carried_by or v == director.current_vehicle:
			continue
		var d := v.global_position.distance_to(at) - minf(v.stats.size.x, v.stats.size.y) * 0.5
		if d < GRAB_RADIUS and d < best_d:
			best_d = d
			best = v
	if best == null:
		return
	damage_vehicle(best, GRAB_DAMAGE, ex.controlled)
	best.dent_at(at, GRAB_DAMAGE)
	if best.has_driver:
		_bail_out(best)
	if traffic:
		traffic.remove_ai(best)
	best.pursuit = null
	best.pick_up_by(ex)


## 굴삭기가 집은 차의 운전자는 뛰어내린다 (경찰은 내려서 쫓아온다)
func _bail_out(v: Vehicle) -> void:
	v.has_driver = false
	var door := v.door_position(false)
	var outward := (door - v.global_position).normalized()
	if police and police.owns(v):
		police.eject_crew(v, door + outward * EJECT_OFFSET)
	else:
		pedestrians.spawn_fleeing(door + outward * EJECT_OFFSET, outward, v.stats.driver_npc, v.level)


## 내린 불도저 블레이드: 앞으로 밀고 가는 동안 블레이드 앞의 차는 다치며 밀려 가고, 사람은 밀려 넘어진다
func _blades(delta: float) -> void:
	for d in vehicles:
		if not d.stats.blade or d.wrecked or d.blade_up or d.motor.forward_speed() < CRUSH_MOVING:
			continue
		var half := d.stats.size * 0.5
		for v in vehicles:
			if v == d or v.apart(d.global_position, d.level):
				continue
			var local := d.to_local(v.global_position)
			var r := minf(v.stats.size.x, v.stats.size.y) * 0.5
			if absf(local.x) < half.x + r and local.y < -half.y * 0.6 and local.y > -half.y - r - 6.0:
				damage_vehicle(v, BLADE_DPS * delta, d.controlled)
				# 옆으로 선 차는 바퀴 접지가 미끄러짐을 지워 버리므로, 불도저가 나아간 만큼 직접 밀어 옮긴다 (벽에는 막힌다)
				v.move_and_collide(d.motor.forward() * d.motor.forward_speed() * delta * 1.08)
				v.motor.velocity = v.motor.velocity.lerp(d.motor.velocity, minf(6.0 * delta, 1.0))
		for p: Pedestrian in pedestrians.peds.duplicate():
			if p.is_dead() or p.state == Pedestrian.State.KNOCKED:
				continue
			var lp := d.to_local(p.global_position)
			if absf(lp.x) < half.x + 4.0 and lp.y < -half.y * 0.6 and lp.y > -half.y - 10.0:
				pedestrians.damage(p, BLADE_PERSON_DAMAGE, d.motor.forward(), d.controlled, true)


# ── 화염방사기 · 물대포 ───────────────────────────────────

## 짧은 부채꼴: 불은 사람·차를 태우고 끝에 불을 놓는다. 물은 사람·차를 밀고 불을 끈다
func _spray(from: Vector2, dir: Vector2, w: WeaponType, by_player: bool, exclude: Array[RID], level := 0) -> void:
	var space := get_world_2d().direct_space_state
	# 벽에 막히면 거기까지만
	var reach := w.max_range
	var wall := space.intersect_ray(PhysicsRayQueryParameters2D.create(from, from + dir * reach, Layers.at(Layers.WORLD, level), exclude))
	if not wall.is_empty():
		reach = from.distance_to(wall.position)
	_flames.append([from, dir, w, 0.0])
	for p: Pedestrian in pedestrians.peds.duplicate():
		if p.is_dead() or exclude.has(p.get_rid()) or not _in_cone(from, dir, reach, w.spread, p.global_position):
			continue
		if w.water:
			p.knock_down(p.global_position - from)
		else:
			pedestrians.damage(p, w.damage, dir, by_player, false)
	for v in vehicles:
		if v.wrecked or exclude.has(v.get_rid()) or not _in_cone(from, dir, reach + v.stats.size.x * 0.5, w.spread, v.global_position):
			continue
		if w.water:
			v.motor.velocity += dir * w.push * get_physics_process_delta_time() * 6.0 / v.stats.mass
			if v.burning >= 0.0 or v.on_fire:   # 물을 뿌리면 불붙은 차가 꺼진다 (간신히 버틴다)
				v.burning = -1.0
				v.on_fire = false
				v.health = maxf(v.health, 1.0)
		else:
			damage_vehicle(v, w.damage, by_player)
	if not by_player and player.visible and _in_cone(from, dir, reach, w.spread, player.global_position):
		player.take_damage(w.damage)
	if fires:
		if w.water:
			# 물줄기 부채꼴에 걸린 불은 다 맞는다
			for f in fires.fires:
				if _in_cone(from, dir, reach + f.radius, w.spread + 0.2, f.pos):
					f.left = minf(f.left, Fires.DOUSED) - 0.25
		elif rng.randf() < 0.35:
			fires.start(from + dir * reach * 0.85, w.fire_radius, by_player, 4.0)
	if w.flame:
		gunfire.emit(from, by_player)


static func _in_cone(from: Vector2, dir: Vector2, reach: float, spread: float, at: Vector2) -> bool:
	var rel := at - from
	return rel.length() < reach and (rel.length() < 12.0 or absf(dir.angle_to(rel)) < spread)


func _hit(collider: Object, dir: Vector2, amount: float, by_player: bool) -> void:
	if collider is Vehicle:
		damage_vehicle(collider, amount, by_player)
	elif collider is Pedestrian:
		pedestrians.damage(collider, amount, dir, by_player, false)
	elif collider is Player:
		(collider as Player).take_damage(amount)


## 주먹: 앞쪽 부채꼴 안, 손이 닿는 가장 가까운 사람 하나 (NPC가 휘두르면 주인공도 맞는다)
func _melee(from: Vector2, dir: Vector2, w: WeaponType, by_player: bool, exclude: Array[RID]) -> void:
	_swings.append([from + dir * 12.0, dir, 0.0])
	var best: Pedestrian = null
	var best_d := w.max_range + Pedestrian.RADIUS
	for p in pedestrians.peds:
		if p.is_dead() or exclude.has(p.get_rid()):
			continue
		var rel := p.global_position - from
		var d := rel.length()
		if d < best_d and (d < Pedestrian.RADIUS or absf(dir.angle_to(rel)) < w.spread):
			best_d = d
			best = p
	if not by_player and player.visible and not exclude.has(player.get_rid()):
		var rel := player.global_position - from
		if rel.length() < best_d and (rel.length() < Player.RADIUS or absf(dir.angle_to(rel)) < w.spread):
			player.take_damage(w.damage)
			return
	if best:
		pedestrians.damage(best, w.damage, dir, by_player, w.knockdown)


func damage_vehicle(v: Vehicle, amount: float, by_player: bool) -> void:
	if v.wrecked:
		return
	v.take_damage(amount, by_player)
	vehicle_attacked.emit(v, by_player)


# ── 화재 · 폭발 ───────────────────────────────────────────

## 체력이 0이 된 차: 타고 있던 사람이 뛰어내린다 (경찰은 내려서 쫓아온다)
func _on_caught_fire(v: Vehicle) -> void:
	if traffic:
		traffic.remove_ai(v)
	if v.has_driver:
		v.has_driver = false
		var door := v.door_position(false)
		var out := (door - v.global_position).normalized()
		if police and police.owns(v):
			police.eject_crew(v, door + out * EJECT_OFFSET)
		else:
			pedestrians.spawn_fleeing(door + out * EJECT_OFFSET, out, v.stats.driver_npc, v.level)
	if police:
		police.abandon(v)


func _on_exploded(by_player: bool, v: Vehicle) -> void:
	explosions += 1
	_wrecks[v] = 0.0
	if v == director.current_vehicle:
		director.exit_vehicle()
		player.take_damage(player.health)
	explode(v.global_position, by_player, v)
	vehicle_exploded.emit(v, by_player)


## 차가 부딪혔다 (벽·차·내려앉기): 세기만큼 쿵 또는 쾅 — 차끼리는 양쪽이 다 알리지만 Sfx가 같은 곳 같은 소리를 한 번만 낸다
func _on_impacted(strength: float, v: Vehicle) -> void:
	if strength >= CRASH_SOUND:
		Sfx.play(&"crash", v.global_position, clampf(strength / CRASH_SOUND, 1.0, 1.6))
	elif strength >= BUMP_SOUND:
		Sfx.play(&"bump", v.global_position)


## pos에서 폭발: 가까운 차는 밀려나고 크게 다쳐 곧 터지고, 사람은 죽거나 넘어진다.
## scale이 0이면 터지는 차의 explosion_scale(없으면 1)을 쓴다
func explode(pos: Vector2, by_player: bool, source: Vehicle = null, scale := 0.0) -> void:
	if scale <= 0.0:
		scale = source.stats.explosion_scale if source else 1.0
	for v in vehicles:
		if v == source or v.wrecked:
			continue
		var k := DamageModel.explosion_falloff(v.global_position.distance_to(pos), scale)
		if k <= 0.0:
			continue
		v.motor.velocity += (v.global_position - pos).normalized() * DamageModel.EXPLOSION_IMPULSE * k / v.stats.mass
		v.take_damage(DamageModel.EXPLOSION_VEHICLE_DAMAGE * k, by_player,
			rng.randf_range(DamageModel.CHAIN_FUSE_MIN, DamageModel.CHAIN_FUSE_MAX))
	for p: Pedestrian in pedestrians.peds.duplicate():
		if p.is_dead():
			continue
		var k := DamageModel.explosion_falloff(p.global_position.distance_to(pos), scale)
		if k > 0.0:
			pedestrians.damage(p, DamageModel.EXPLOSION_PERSON_DAMAGE * k, p.global_position - pos, by_player, true)
	if player.visible:
		player.take_damage(DamageModel.EXPLOSION_PERSON_DAMAGE * DamageModel.explosion_falloff(player.global_position.distance_to(pos), scale))
	_blasts.append([pos, scale, 0.0])
	Sfx.play(&"explosion", pos, scale)
	_scorch.append(pos)
	if _scorch.size() > MAX_SCORCH:
		_scorch.remove_at(0)
	_decals.queue_redraw()
	pedestrians.scare(pos, BLAST_SCARE_RADIUS * sqrt(scale))
	gunfire.emit(pos, by_player)


func _cleanup_wrecks(delta: float) -> void:
	var camera := ChaseCamera.current_cam()
	for k in _wrecks.keys():
		if not is_instance_valid(k):
			_wrecks.erase(k)   # 다른 곳에서 치운 잔해
			continue
		var v: Vehicle = k
		_wrecks[v] += delta
		if _wrecks[v] < WRECK_TIME or camera == null or v.global_position.distance_to(camera.global_position) < OFFSCREEN:
			continue
		_wrecks.erase(v)
		_watched.erase(v)
		vehicles.erase(v)
		v.queue_free()


# ── 그리기 ────────────────────────────────────────────────

func _draw() -> void:
	# 2.5D: 총알·투사체·불길은 가슴 높이로 띄운다
	if IsoView.enabled:
		draw_set_transform(IsoView.lift(12.0), 0.0, Vector2.ONE)
	for e: Array in _tracers:
		_draw_bullet(e)
	_draw_rocket_fx()
	for p in _projectiles:
		var w: WeaponType = p.w
		var pos: Vector2 = p.pos
		if w.projectile != &"rocket" and IsoView.enabled:
			pos += IsoView.lift(IsoView.ground(pos))      # 다리·언덕 위에서 던진 것은 그 땅 높이에서
		match w.projectile:
			&"rocket":
				_draw_rocket(p)
			&"molotov":
				draw_circle(pos, 4.0, Color(0.45, 0.6, 0.3))
				draw_circle(pos + Vector2(0, -4), 3.0, Color(1.0, 0.6, 0.2))
			_:
				var blink: bool = w.fuse > 0.0 and p.stopped and int(p.age * 8.0) % 2 == 0
				draw_circle(pos, 5.0, Color(0.25, 0.3, 0.2))
				draw_circle(pos, 2.0, Color(1, 0.2, 0.2) if blink else Color(0.5, 0.55, 0.4))
	for e: Array in _flames:
		var w: WeaponType = e[2]
		var from: Vector2 = e[0]
		if IsoView.enabled:
			from += IsoView.lift(IsoView.ground(from))
		var dir: Vector2 = e[1]
		var k: float = e[3] / 0.25
		for i in 5:
			var t := (i + 1) / 5.0
			var p := from + dir.rotated(sin(i * 2.3 + e[3] * 30.0) * w.spread * 0.6) * w.max_range * t * (0.6 + 0.4 * k)
			var col := Color(0.6, 0.85, 1.0, 0.5 * (1.0 - k)) if w.water else Color(1.0, 0.5 - 0.3 * t, 0.1, 0.7 * (1.0 - k))
			draw_circle(p, 4.0 + t * 10.0, col)
	for e: Array in _swings:
		var k: float = 1.0 - e[2] / SWING_TIME
		var a: float = (e[1] as Vector2).angle()
		var at: Vector2 = e[0] + (IsoView.lift(IsoView.ground(e[0])) if IsoView.enabled else Vector2.ZERO)
		draw_arc(at, 10.0, a - 0.9, a + 0.9, 8, Color(1, 1, 1, 0.7 * k), 2.0)
	for e: Array in _blasts:
		_draw_blast(e[0] + IsoView.lift(IsoView.ground(e[0])), e[1], e[2])   # 다리 위 폭발은 상판 높이에서
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_cannon()


## 곡사포: 주인공이 모는 자주포의 조준점(떨어질 곳 원 + 장전 고리), 날아가는 포탄과 떨어질 곳 경고(적 포탄은 빨강), 포구 불꽃
## 총알이 날아가 맞고 불똥이 사그라질 때까지
static func _tracer_life(e: Array) -> float:
	return (e[0] as Vector2).distance_to(e[1]) / BULLET_SPEED + SPARK_TIME


## 총알 한 발: 총구 불꽃 → 짧은 빛줄기가 맞은 곳까지 날아감 → 맞은 곳 불똥
func _draw_bullet(e: Array) -> void:
	var from: Vector2 = e[0]
	var to: Vector2 = e[1]
	var c: Color = e[2]
	var age: float = e[3]
	var dist := from.distance_to(to)
	var dir := (to - from) / maxf(dist, 0.001)
	if age < FLASH_TIME:
		var k := 1.0 - age / FLASH_TIME
		draw_line(from, from + dir * 10.0 * k, Color(1.0, 0.95, 0.7, k), 4.0 * k)
		draw_circle(from, 3.5 * k, Color(1.0, 0.9, 0.55, k))
	var fly := dist / BULLET_SPEED
	if age < fly:
		var head := age * BULLET_SPEED
		var tail := maxf(head - BULLET_LEN, 0.0)
		draw_line(from + dir * tail, from + dir * head, Color(c, 0.75), 2.0)
		draw_line(from + dir * maxf(head - 8.0, tail), from + dir * head, Color(1.0, 1.0, 0.9, 0.95), 1.5)
	else:
		var k := 1.0 - (age - fly) / SPARK_TIME
		draw_circle(to, 2.5 * k, Color(1.0, 0.8, 0.4, k))
		draw_line(to, to - dir.rotated(0.6) * 6.0 * k, Color(1.0, 0.85, 0.5, k), 1.0)
		draw_line(to, to - dir.rotated(-0.6) * 6.0 * k, Color(1.0, 0.85, 0.5, k), 1.0)


func _draw_cannon() -> void:
	var v := director.current_vehicle if director else null
	if v and v.stats.cannon_max > 0.0 and not v.wrecked:
		var at := v.gun_target()
		var r := 34.0 * sqrt(TANK_CANNON.explosion_scale)
		var ready := 1.0 - v.gun_reload / TANK_CANNON.fire_interval
		var c := Color(1.0, 0.85, 0.3, 0.9) if ready >= 1.0 else Color(0.9, 0.9, 0.9, 0.55)
		draw_arc(at, r, 0.0, TAU, 32, c, 2.0)
		draw_arc(at, r * 0.45, -PI * 0.5, -PI * 0.5 + TAU * minf(ready, 1.0), 24, c, 3.0)
		for d in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
			draw_line(at + d * r * 0.7, at + d * r * 1.25, c, 2.0)
	if v and v.stats.arm_reach.y > 0.0 and not v.wrecked:
		var at := v.bucket_ground()
		var c := Color(1.0, 0.8, 0.25, 0.85) if v.carried == null else Color(0.5, 0.9, 1.0, 0.85)
		draw_arc(at, GRAB_RADIUS, 0.0, TAU, 24, c, 2.0)
		draw_line(at + Vector2(-8, 0), at + Vector2(8, 0), c, 2.0)
		draw_line(at + Vector2(0, -8), at + Vector2(0, 8), c, 2.0)
	for e: Array in _dusts:
		var k: float = e[1] / DUST_TIME
		for i in 5:
			var off := Vector2.RIGHT.rotated(i * TAU / 5.0 + 0.4) * (8.0 + 26.0 * k)
			var up := IsoView.lift(4.0 + 22.0 * k) if IsoView.enabled else Vector2.ZERO
			FireFx.circle(self, e[0] + off + up, 10.0 + 14.0 * k, Color(0.55, 0.45, 0.32, 0.55 * (1.0 - k)))
	var now := Time.get_ticks_msec() / 1000.0
	for p: Dictionary in _shells:
		var w: WeaponType = p.w
		var warn := Color(1.0, 0.25, 0.2, 0.55) if not p.by_player else Color(1.0, 0.85, 0.3, 0.35)
		var left: float = 1.0 - p.t / p.dur
		draw_arc(p.to, 30.0 * sqrt(w.explosion_scale) * (0.4 + 0.6 * left), 0.0, TAU, 28, warn, 2.0)
		var at: Array = shell_at(p)
		var pos: Vector2 = at[0]
		var h: float = at[1] if IsoView.enabled else 0.0
		var ahead: Array = shell_at({"from": p.from, "to": p.to, "t": maxf(p.t - 0.06, 0.0), "dur": p.dur, "arc": p.arc})
		var back: Vector2 = (ahead[0] as Vector2) + IsoView.lift(ahead[1] if IsoView.enabled else 0.0)
		var head := pos + IsoView.lift(h)
		draw_line(back, head, Color(0.85, 0.85, 0.8, 0.45), 3.0)
		draw_circle(head, 3.5, Color(0.25, 0.25, 0.22))
		FireFx.circle(self, head, 7.0, Color(1.0, 0.8, 0.4, 0.35 + 0.15 * sin(now * 30.0)))
	for e: Array in _muzzles:
		var k: float = e[2] / MUZZLE_TIME
		var lift := IsoView.lift(IsoView.ground(e[0]) + 22.0) if IsoView.enabled else Vector2.ZERO
		var pos: Vector2 = e[0] + lift
		FireFx.circle(self, pos + (e[1] as Vector2) * 8.0, 26.0 * (1.0 - k * 0.5), Color(1.0, 0.85, 0.45, 0.85 * (1.0 - k)))
		FireFx.circle(self, pos + (e[1] as Vector2) * (14.0 + 30.0 * k), 18.0 + 22.0 * k, Color(0.55, 0.55, 0.52, 0.5 * (1.0 - k)))


## 폭발 (참고 그림 순서): 하얀 섬광 → 부풀며 솟는 불덩이 → 사방으로 튀는 파편·불티 → 검은 연기와 바닥에 남은 불.
## 바닥 불빛·충격파 고리는 바닥에, 나머지는 화면 기준으로 세워 그린다
## 날아가는 로켓의 그리는 자리: 그림 속 탄두 자리(off)에서 ROCKET_SETTLE을 날며 맞히는 길로 내려앉는다
func _rocket_at(p: Dictionary) -> Vector2:
	return (p.pos as Vector2) + _ground_lift(p.pos) + (p.get("off", Vector2.ZERO) as Vector2) * maxf(0.0, 1.0 - float(p.travel) / ROCKET_SETTLE)


## 다리·고가·언덕 위 땅 높이만큼 (위에서 보기면 0)
static func _ground_lift(at: Vector2) -> Vector2:
	return IsoView.lift(IsoView.ground(at)) if IsoView.enabled else Vector2.ZERO


## 그리는 자리 at(가슴 높이를 뺀 점)에서 화면 px로 그리는 좌표계 — 연기·불꽃을 눕히지 않고 둥글게
func _screen_at(at: Vector2) -> void:
	if IsoView.enabled:
		draw_set_transform_matrix(IsoView.screen_frame(at, 12.0))
	else:
		draw_set_transform(at, 0.0, Vector2.ONE)


func _screen_dir(world: Vector2) -> Vector2:
	return IsoView.to_screen_dir(world) if IsoView.enabled else world


## 로켓 한 발: 국방색 탄두·검은 몸통·꼬리 날개, 꼬리에서 깜박이는 불꽃. 화면 쪽으로 날면 짧아 보인다
func _draw_rocket(p: Dictionary) -> void:
	var sd := _screen_dir((p.vel as Vector2).normalized())
	var u := sd.normalized()
	var n := Vector2(-u.y, u.x)
	var l := ROCKET_LEN * clampf(sd.length() / 0.78, 0.45, 1.1)
	var tip := u * l * 0.55
	var neck := u * l * 0.05
	var tail := -u * l * 0.45
	_screen_at(_rocket_at(p))
	var fl := l * (0.5 + 0.25 * sin(float(p.age) * 70.0))
	FireFx.circle(self, tail - u * 1.5, 3.4, Color(1.0, 0.75, 0.35, 0.35))
	draw_primitive(PackedVector2Array([tail + n * 1.7, tail - u * fl, tail - n * 1.7]),
		PackedColorArray([Color(1.0, 0.5, 0.12, 0.9), Color(1.0, 0.35, 0.05, 0.0), Color(1.0, 0.5, 0.12, 0.9)]), PackedVector2Array())
	draw_primitive(PackedVector2Array([tail + n * 0.9, tail - u * fl * 0.55, tail - n * 0.9]),
		PackedColorArray([Color(1.0, 0.97, 0.75), Color(1.0, 0.85, 0.4, 0.3), Color(1.0, 0.97, 0.75)]), PackedVector2Array())
	draw_line(tail + u * 1.2 + n * 2.3, tail + u * 2.8, Color(0.12, 0.12, 0.11), 1.0)
	draw_line(tail + u * 1.2 - n * 2.3, tail + u * 2.8, Color(0.12, 0.12, 0.11), 1.0)
	draw_line(tail, neck, Color(0.16, 0.17, 0.15), 2.2)
	var olive := Color(0.45, 0.48, 0.3)
	var mid := neck + u * l * 0.28
	draw_primitive(PackedVector2Array([neck + n * 1.5, mid + n * 1.9, mid - n * 1.9, neck - n * 1.5]),
		PackedColorArray([olive, olive, olive, olive]), PackedVector2Array())
	draw_primitive(PackedVector2Array([mid + n * 1.9, tip, mid - n * 1.9]),
		PackedColorArray([olive, olive.lightened(0.2), olive]), PackedVector2Array())
	_lifted()


## 로켓 꼬리 연기와 쏜 자리의 앞 불꽃·후폭풍
func _draw_rocket_fx() -> void:
	for e: Array in _rocket_smoke:
		var t: float = e[2] / ROCKET_SMOKE_TIME
		var seed: float = e[1]
		_screen_at(e[0])
		var r := 1.8 + 4.5 * sqrt(t)
		var a := 0.26 * pow(1.0 - t, 1.6) * minf(e[2] * 25.0, 1.0)
		var c := Color(1.0, 0.82, 0.6).lerp(Color(0.72, 0.72, 0.74), minf(t * 6.0, 1.0))
		FireFx.puff(self, Vector2(sin(seed) * 2.5 * t, -5.0 * t), r, Color(c, a))
	for e: Array in _backblasts:
		_draw_backblast(e[0], e[1], e[2], e[3])
	_lifted()


## 쏜 자리: 탄두 끝에 번쩍이는 불꽃, 발사관 뒤끝에서 뒤로 뿜는 불길과 부채꼴로 퍼지는 회색 후폭풍 연기
func _draw_backblast(tip: Vector2, back: Vector2, d: Vector2, age: float) -> void:
	var t := age / BACKBLAST_TIME
	var u := _screen_dir(d).normalized()
	var b := _screen_dir(back - tip)
	b = b.normalized() if b.length() > 1.0 else -u
	var n := Vector2(-b.y, b.x)
	# 뒤 연기 (뿜어 나갔다가 느려지며 부풀고 조금 떠오른다)
	_screen_at(back)
	for i in 9:
		var spread := (fmod(i * 0.618, 1.0) - 0.5) * 1.1
		var reach := (26.0 + 30.0 * fmod(i * 0.37, 1.0)) * (1.0 - pow(1.0 - minf(t * 1.6, 1.0), 3.0))
		var at := b.rotated(spread) * reach + Vector2(0, -9.0 * t * t)
		var r := (2.5 + 9.0 * t) * (0.7 + 0.5 * fmod(i * 0.29, 1.0))
		var a := 0.6 * pow(1.0 - t, 1.3) * minf(age * 18.0, 1.0)
		var c := Color(1.0, 0.72, 0.4).lerp(Color(0.74, 0.74, 0.76), minf(age * 7.0, 1.0))
		FireFx.puff(self, at, r, Color(c, a))
	# 뒤 불길 (짧게)
	if age < 0.18:
		var k := 1.0 - age / 0.18
		FireFx.puff(self, b * 6.0, 7.0 * k + 2.0, Color(1.0, 0.62, 0.25, 0.7 * k))
		draw_primitive(PackedVector2Array([n * 3.2, b * 26.0 * k, -n * 3.2]),
			PackedColorArray([Color(1.0, 0.6, 0.15, k), Color(1.0, 0.3, 0.05, 0.0), Color(1.0, 0.6, 0.15, k)]), PackedVector2Array())
		draw_primitive(PackedVector2Array([n * 1.6, b * 13.0 * k, -n * 1.6]),
			PackedColorArray([Color(1.0, 0.97, 0.8, k), Color(1.0, 0.8, 0.4, 0.0), Color(1.0, 0.97, 0.8, k)]), PackedVector2Array())
	# 앞 불꽃 (발사관 입구): 부드러운 빛 + 앞으로 뻗는 불꽃 + 옆으로 튀는 두 갈래
	if age < 0.12:
		var k := 1.0 - age / 0.12
		var m := Vector2(-u.y, u.x)
		_screen_at(tip)
		FireFx.puff(self, u * 3.0, 6.0 * k + 2.0, Color(1.0, 0.82, 0.5, 0.75 * k))
		draw_primitive(PackedVector2Array([m * 2.4, u * 14.0 * k, -m * 2.4]),
			PackedColorArray([Color(1.0, 0.9, 0.6, k), Color(1.0, 0.7, 0.3, 0.0), Color(1.0, 0.9, 0.6, k)]), PackedVector2Array())
		draw_line(Vector2.ZERO, (u + m * 0.9).normalized() * 6.0 * k, Color(1.0, 0.85, 0.5, k), 1.2)
		draw_line(Vector2.ZERO, (u - m * 0.9).normalized() * 6.0 * k, Color(1.0, 0.85, 0.5, k), 1.2)
	# 앞 연기 (작게)
	_screen_at(tip)
	for i in 3:
		var at := (u.rotated((i - 1) * 0.6) * (6.0 + 8.0 * minf(t * 2.0, 1.0))) + Vector2(0, -5.0 * t)
		FireFx.puff(self, at, 2.0 + 4.0 * t, Color(0.76, 0.76, 0.78, 0.4 * (1.0 - t) * minf(age * 18.0, 1.0)))


## _draw의 기본 좌표계로 되돌린다 (2.5D: 가슴 높이로 띄운 월드)
func _lifted() -> void:
	if IsoView.enabled:
		draw_set_transform(IsoView.lift(12.0), 0.0, Vector2.ONE)
	else:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_blast(pos: Vector2, scale: float, age: float) -> void:
	var t := age / BLAST_TIME
	var now := Time.get_ticks_msec() / 1000.0
	var seed := fmod(absf(pos.x * 0.013 + pos.y * 0.007), 10.0)
	var r := DamageModel.EXPLOSION_RADIUS * 0.4 * sqrt(scale)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	FireFx.glow(self, pos, r * (1.0 + 0.8 * minf(age * 4.0, 1.0)), 4.0 * pow(1.0 - t, 3.0), now, seed)
	if age < 0.35:
		var k := age / 0.35
		draw_arc(pos, r * 1.6 * k, 0.0, TAU, 40, Color(1.0, 0.85, 0.6, 0.45 * (1.0 - k)), 3.0)
	if IsoView.enabled:
		draw_set_transform_matrix(IsoView.screen_frame(pos))
	else:
		draw_set_transform(pos, 0.0, Vector2.ONE)
	var fire_sheet := FireFx.sheet("blast_fire")
	var smoke_sheet := FireFx.sheet("blast_smoke")
	var sprites := not fire_sheet.is_empty() and not smoke_sheet.is_empty()
	if sprites:
		_draw_blast_sheets(fire_sheet, smoke_sheet, r, age, seed)
	# 연기: 불덩이 뒤에서 피어올라 오래 남는다
	if age > 0.12 and not sprites:
		var k := (age - 0.12) / (BLAST_TIME - 0.12)
		for i in 7:
			var a := seed + i * 0.9
			var p := Vector2(cos(a) * r * (0.25 + 0.35 * k), -r * (0.35 + 0.9 * k) - sin(a * 1.7) * r * 0.2)
			var pr := r * (0.22 + 0.3 * k) * (0.8 + 0.3 * fmod(i * 0.61, 1.0))
			var c := Color(FireFx.SMOKE.lerp(Color(0.3, 0.28, 0.27), fmod(i * 0.37, 1.0)), 0.8 * minf(k * 5.0, 1.0) * (1.0 - k))
			FireFx.circle(self, p, pr, c)
			FireFx.circle(self, p + Vector2(-pr * 0.5, pr * 0.25), pr * 0.7, c)
	# 불덩이: 덩어리 여럿이 부풀었다가 붉게 식으며 꺼진다
	if age < 0.75 and not sprites:
		var f := age / 0.75
		var grow := sqrt(minf(age / 0.25, 1.0))
		var hot := clampf(1.0 - f * 1.4, 0.0, 1.0)
		var center := Vector2(0, -r * (0.3 + 0.35 * f))
		var layers := [[FireFx.OUTER, 1.0], [FireFx.MID, 0.78], [FireFx.INNER, 0.55 * (0.4 + 0.6 * hot)], [FireFx.CORE, 0.32 * hot]]
		for l: Array in layers:
			for i in 6:
				var a := seed + i * TAU / 6.0
				var p := center + Vector2(cos(a), sin(a) * 0.8) * r * 0.32 * grow
				var lr: float = r * (0.3 + 0.08 * fmod(i * 0.53, 1.0)) * grow * l[1] * (1.0 - f * 0.35)
				if lr > 0.5:
					FireFx.circle(self, p, lr, Color(l[0], 1.0 - f * f))
			var cr: float = r * 0.4 * grow * l[1]
			if cr > 0.5:
				FireFx.circle(self, center, cr, Color(l[0], 1.0 - f * f))
	# 섬광
	if age < 0.12 and not sprites:
		var k := age / 0.12
		FireFx.circle(self, Vector2(0, -r * 0.3), r * (0.35 + 0.45 * k), Color(1.0, 0.95, 0.75, 0.7 * (1.0 - k)))
	# 파편(검은 조각)과 불티(노란 줄): 위로 튀었다 떨어진다
	if age < 1.1:
		for i in 14:
			var a := seed * 0.7 + i * 2.39996
			var v := r * (2.0 + 1.6 * fmod(i * 0.618, 1.0))
			var vel := Vector2(cos(a) * v, -absf(sin(a)) * v * 0.9 - r * 1.2)
			var p := vel * age + Vector2(0, r * 4.5 * age * age)
			var fade := 1.0 - age / 1.1
			if i % 2 == 0:
				var s := 2.0 + fmod(i * 0.29, 1.0) * 2.5
				draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s * 0.7)), Color(0.08, 0.07, 0.06, fade))
			else:
				var dir := (vel + Vector2(0, r * 9.0 * age)).normalized()
				draw_line(p, p - dir * 6.0, Color(FireFx.INNER, fade), 1.5)
	# 바닥에 떨어진 파편이 잠깐 더 탄다
	if age > 0.3:
		FireFx.ground_fire(self, Vector2.ZERO, r * 0.45, now, seed, clampf((BLAST_TIME - age) / 0.6, 0.0, 1.0))


## 폭발 넘김 그림 (assets/fx): 연기 16장(BLAST_TIME 동안, 장 사이를 섞어 넘긴다)을 뒤에, 불덩이 16장(섬광 → 부풀기 → 식기)을 앞에.
## 화면 기준 좌표, 원점이 폭발한 바닥. 그림의 가장 큰 불덩이(반지름 칸 104px)가 r × BLAST_SPRITE_SIZE가 되게 줄인다
func _draw_blast_sheets(fire: Dictionary, smoke: Dictionary, r: float, age: float, seed: float) -> void:
	var k := r * BLAST_SPRITE_SIZE / 104.0
	var flip := posmod(int(seed * 3.0), 2) == 1
	var n: int = smoke.frames
	var sp := age / float(smoke.get("seconds", BLAST_TIME)) * n
	var si := int(sp)
	if si < n:
		FireFx.frame(self, smoke, si, Vector2.ZERO, k, Color.WHITE, flip)
		if si + 1 < n:
			FireFx.frame(self, smoke, si + 1, Vector2.ZERO, k, Color(1, 1, 1, sp - si), flip)
	var fi := int(age / float(fire.get("seconds", 0.75)) * int(fire.frames))
	if fi < int(fire.frames):
		FireFx.frame(self, fire, fi, Vector2.ZERO, k, Color.WHITE, flip)


func _draw_decals() -> void:
	for pos in _scorch:
		FireFx.char_patch(_decals, pos, 44.0, fmod(absf(pos.x * 0.013 + pos.y * 0.007), 10.0))
