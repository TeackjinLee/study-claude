class_name Combat
extends Node2D
## 사격·주먹·폭발과 그 효과(총알 궤적·총구 불꽃·폭발·그을음).
## 피해는 맞은 쪽에 넘긴다: 차는 Vehicle.take_damage, 사람은 PedestrianManager.damage, 주인공은 Player.take_damage.
## 차에 불이 붙으면 운전자를 내리게 하고, 터지면 주변에 폭발 피해를 준다 (그 피해로 옆 차가 또 터진다 — 연쇄).

signal gunfire(pos: Vector2, by_player: bool)
signal vehicle_attacked(vehicle: Vehicle, by_player: bool)   ## 총에 맞은 차 (충돌·폭발 피해는 빼고)
signal vehicle_exploded(vehicle: Vehicle, by_player: bool)

const SEED := 4404
const TRACER_TIME := 0.08
const BLAST_TIME := 1.8              ## 불덩이는 금방 사라지고 연기·불타는 파편이 조금 더 남는다
const SWING_TIME := 0.12
const SCARE_RADIUS := 320.0          ## 총소리에 겁먹는 거리
const BLAST_SCARE_RADIUS := 500.0
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

var _tracers: Array = []             ## [from, to, color, age] — 나이는 늘 맨 끝
var _projectiles: Array[Dictionary] = []   ## 날아가는 수류탄·화염병·로켓 {pos, vel, w, by_player, age, travel, exclude, stopped}
var _flames: Array = []              ## 화염방사기·물대포 불꽃 [from, dir, w, age]
var _blasts: Array = []              ## [pos, 크기 배율, age]
var _swings: Array = []              ## [pos, dir, age]
var _shells: Array[Dictionary] = []  ## 곡사 포탄 {from, to, dur, t, w, by_player, shooter} — 건물 위로 날아가 겨눈 땅에 떨어진다
var _muzzles: Array = []             ## 포구 불꽃 [pos, dir, age]
var _dusts: Array = []               ## 굴삭기가 찍은 흙먼지 [pos, age]
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


func _physics_process(delta: float) -> void:
	z_index = IsoView.Z_EFFECTS if IsoView.enabled else 5
	for v in vehicles:
		if not _watched.has(v):
			_watched[v] = true
			v.caught_fire.connect(_on_caught_fire.bind(v))
			v.exploded.connect(_on_exploded.bind(v))
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
	for list: Array in [_tracers, _blasts, _swings, _flames, _muzzles, _dusts]:
		for e: Array in list:
			e[-1] += delta
	_flames = _flames.filter(func(e: Array): return e[3] < 0.25)
	_tracers = _tracers.filter(func(e: Array): return e[3] < TRACER_TIME)
	_blasts = _blasts.filter(func(e: Array): return e[2] < BLAST_TIME)
	_swings = _swings.filter(func(e: Array): return e[2] < SWING_TIME)
	_muzzles = _muzzles.filter(func(e: Array): return e[2] < MUZZLE_TIME)
	_dusts = _dusts.filter(func(e: Array): return e[1] < DUST_TIME)


## 그림은 화면 프레임마다 한 번 (물리 틱마다 부르면 느릴수록 한 프레임에 여러 번 그린다)
func _process(_delta: float) -> void:
	queue_redraw()


# ── 사격 ──────────────────────────────────────────────────

## from에서 dir 쪽으로 무기 w를 한 번 쏜다(친다). exclude는 맞지 않을 몸(쏜 사람, 탄 차).
func fire(from: Vector2, dir: Vector2, w: WeaponType, by_player: bool, exclude: Array[RID] = [], extra_spread := 0.0) -> void:
	if w.melee:
		_melee(from, dir, w, by_player, exclude)
		return
	if w.projectile != &"":
		_launch(from, dir, w, by_player, exclude)
		return
	if w.flame or w.water:
		_spray(from, dir, w, by_player, exclude)
		return
	var space := get_world_2d().direct_space_state
	for d in Ballistics.pellet_dirs(dir, w, rng, extra_spread):
		var to := from + d * w.max_range
		# 관통: 맞은 몸을 빼고 다시 재서 pierce개까지 맞힌다 (벽에 닿으면 멈춘다)
		var skip := exclude.duplicate()
		for n in w.pierce:
			var q := PhysicsRayQueryParameters2D.create(from, from + d * w.max_range, Layers.WORLD | Layers.VEHICLES | Layers.PEOPLE, skip)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				to = from + d * w.max_range
				break
			to = hit.position
			if not (hit.collider is CollisionObject2D) or hit.collider is StaticBody2D:
				break
			_hit(hit.collider, d, w.damage, by_player)
			skip.append((hit.collider as CollisionObject2D).get_rid())
		# 주인공 총알은 지나는 길의 헬기도 맞힌다 (공중이라 충돌체가 없다)
		if by_player and police:
			for h in police.helis:
				if h.hit_by(from, to):
					h.take_damage(w.damage, true)
		_tracers.append([from, to, w.tracer_color, 0.0])
	gunfire.emit(from, by_player)
	pedestrians.scare(from, SCARE_RADIUS)


## 공중(헬기)에서 땅의 at을 쏜다: at 바로 앞에서부터 광선을 재고, 궤적은 헬기에서 그린다
func fire_from_air(air: Vector2, at: Vector2, w: WeaponType) -> void:
	var space := get_world_2d().direct_space_state
	var d := (at - air).normalized().rotated(rng.randf_range(-w.spread, w.spread))
	var from := at - d * 60.0 + d.orthogonal() * rng.randf_range(-18.0, 18.0)
	var to := from + d * 120.0
	var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(from, to, Layers.VEHICLES | Layers.PEOPLE))
	if not hit.is_empty():
		to = hit.position
		_hit(hit.collider, d, w.damage, false)
	_tracers.append([air, to, w.tracer_color, 0.0])


# ── 던지는 무기 · 로켓 ─────────────────────────────────────

func _launch(from: Vector2, dir: Vector2, w: WeaponType, by_player: bool, exclude: Array[RID]) -> void:
	var d := dir.rotated(rng.randf_range(-w.spread, w.spread))
	_projectiles.append({"pos": from, "vel": d * w.projectile_speed, "w": w, "by_player": by_player, "age": 0.0,
		"travel": 0.0, "exclude": exclude, "stopped": false})
	if w.projectile == &"rocket":
		gunfire.emit(from, by_player)
		pedestrians.scare(from, SCARE_RADIUS)


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
		var mask := Layers.WORLD | Layers.VEHICLES | Layers.PEOPLE
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
			if v == t or v.stats.tracked or v.airborne():
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
		if moving and player and player.visible and not player.is_dead():
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
		if v == ex or v.stats.tracked or v.airborne() or v.carried_by or v == director.current_vehicle:
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
		pedestrians.spawn_fleeing(door + outward * EJECT_OFFSET, outward, v.stats.driver_npc)


## 내린 불도저 블레이드: 앞으로 밀고 가는 동안 블레이드 앞의 차는 다치며 밀려 가고, 사람은 밀려 넘어진다
func _blades(delta: float) -> void:
	for d in vehicles:
		if not d.stats.blade or d.wrecked or d.blade_up or d.motor.forward_speed() < CRUSH_MOVING:
			continue
		var half := d.stats.size * 0.5
		for v in vehicles:
			if v == d or v.airborne():
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
func _spray(from: Vector2, dir: Vector2, w: WeaponType, by_player: bool, exclude: Array[RID]) -> void:
	var space := get_world_2d().direct_space_state
	# 벽에 막히면 거기까지만
	var reach := w.max_range
	var wall := space.intersect_ray(PhysicsRayQueryParameters2D.create(from, from + dir * reach, Layers.WORLD, exclude))
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
			pedestrians.spawn_fleeing(door + out * EJECT_OFFSET, out, v.stats.driver_npc)
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
	_scorch.append(pos)
	if _scorch.size() > MAX_SCORCH:
		_scorch.remove_at(0)
	_decals.queue_redraw()
	pedestrians.scare(pos, BLAST_SCARE_RADIUS * sqrt(scale))
	gunfire.emit(pos, by_player)


func _cleanup_wrecks(delta: float) -> void:
	var camera := ChaseCamera.current_cam()
	for v: Vehicle in _wrecks.keys():
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
		var k: float = 1.0 - e[3] / TRACER_TIME
		var c: Color = e[2]
		draw_line(e[0], e[1], Color(c, 0.85 * k), 2.0)
		draw_circle(e[0], 5.0 * k, Color(1.0, 0.95, 0.6, k))
		draw_circle(e[1], 2.5 * k, Color(1.0, 0.8, 0.4, k))
	for p in _projectiles:
		var w: WeaponType = p.w
		var pos: Vector2 = p.pos
		match w.projectile:
			&"rocket":
				var back: Vector2 = -(p.vel as Vector2).normalized()
				draw_line(pos, pos + back * 26.0, Color(1.0, 0.85, 0.5, 0.6), 4.0)
				draw_circle(pos + back * 30.0, 6.0, Color(0.6, 0.6, 0.6, 0.4))
				draw_circle(pos, 4.0, Color(0.3, 0.32, 0.3))
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
		draw_arc(e[0], 10.0, a - 0.9, a + 0.9, 8, Color(1, 1, 1, 0.7 * k), 2.0)
	for e: Array in _blasts:
		_draw_blast(e[0] + IsoView.lift(IsoView.ground(e[0])), e[1], e[2])   # 다리 위 폭발은 상판 높이에서
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_cannon()


## 곡사포: 주인공이 모는 자주포의 조준점(떨어질 곳 원 + 장전 고리), 날아가는 포탄과 떨어질 곳 경고(적 포탄은 빨강), 포구 불꽃
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
	# 연기: 불덩이 뒤에서 피어올라 오래 남는다
	if age > 0.12:
		var k := (age - 0.12) / (BLAST_TIME - 0.12)
		for i in 7:
			var a := seed + i * 0.9
			var p := Vector2(cos(a) * r * (0.25 + 0.35 * k), -r * (0.35 + 0.9 * k) - sin(a * 1.7) * r * 0.2)
			var pr := r * (0.22 + 0.3 * k) * (0.8 + 0.3 * fmod(i * 0.61, 1.0))
			var c := Color(FireFx.SMOKE.lerp(Color(0.3, 0.28, 0.27), fmod(i * 0.37, 1.0)), 0.8 * minf(k * 5.0, 1.0) * (1.0 - k))
			FireFx.circle(self, p, pr, c)
			FireFx.circle(self, p + Vector2(-pr * 0.5, pr * 0.25), pr * 0.7, c)
	# 불덩이: 덩어리 여럿이 부풀었다가 붉게 식으며 꺼진다
	if age < 0.75:
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
	if age < 0.12:
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


func _draw_decals() -> void:
	for pos in _scorch:
		FireFx.char_patch(_decals, pos, 44.0, fmod(absf(pos.x * 0.013 + pos.y * 0.007), 10.0))
