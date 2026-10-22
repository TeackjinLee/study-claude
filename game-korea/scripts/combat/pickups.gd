class_name Pickups
extends Node2D
## 무기 상자·구급상자. 맵 고정 위치에 있고, 먹으면 RESPAWN초 뒤 다시 생긴다.
## 걸어서든 차로든 지나가면 먹는다 (GTA2처럼).
## 기절한 사람도 떨어뜨린다 (한 번 먹으면 사라진다): 군인은 소총, 배달원은 상자 속 무엇이든(NpcType.ko_loot),
## 조직원은 총알 상자(ko_ammo)·드물게 총(ko_gun_chance). 무작위는 자기 rng만 쓴다.

signal picked(label: String)

const RESPAWN := 30.0
const REACH_FOOT := 20.0
const REACH_CAR := 34.0
const PISTOL: WeaponType = preload("res://data/weapons/pistol.tres")
const SMG: WeaponType = preload("res://data/weapons/smg.tres")
const SHOTGUN: WeaponType = preload("res://data/weapons/shotgun.tres")
const BAT: WeaponType = preload("res://data/weapons/bat.tres")
const MOLOTOV: WeaponType = preload("res://data/weapons/molotov.tres")
const GRENADE: WeaponType = preload("res://data/weapons/grenade.tres")
const ROCKET: WeaponType = preload("res://data/weapons/rocket.tres")
const FLAMETHROWER: WeaponType = preload("res://data/weapons/flamethrower.tres")
const CAR_MG: WeaponType = preload("res://data/weapons/car_mg.tres")
const RIFLE: WeaponType = preload("res://data/weapons/rifle.tres")
const SOLDIER: NpcType = preload("res://data/npc/soldier.tres")
const SIZE := 18.0
const LOOT_SEED := 20261024

var director: Director
var player: Player
var pedestrians: PedestrianManager
## {pos, weapon(null이면 구급상자), wait, once(먹으면 사라짐), ammo(총알 상자면 탄 수 — 아니면 0)}
var crates: Array[Dictionary] = []
var loot_rng := RandomNumberGenerator.new()   ## 떨어뜨릴 것 고르기 전용 (다른 rng를 뽑으면 다른 결과가 바뀐다)


func _ready() -> void:
	z_index = -1
	material = Terrain.material()   # 바닥 그림을 지형 높이만큼 올린다
	_ready_drops()
	# 출발점 바로 위 인도에 권총 — 처음 몇 걸음 안에 찾게
	_add(City.start_position() + Vector2(0, -140), PISTOL)
	_add(City.sidewalk_loop(Vector2i(2, 3))[1], SMG)
	_add(City.sidewalk_loop(Vector2i(4, 4))[0], SHOTGUN)
	_add(City.sidewalk_loop(Vector2i(0, 0))[2], PISTOL)
	_add(City.sidewalk_loop(Vector2i(5, 1))[3], SMG)
	_add(City.sidewalk_loop(Vector2i(1, 2))[2], SHOTGUN)
	_add(City.hospital_position() + Vector2(-80, 0), null)
	_add(City.sidewalk_loop(Vector2i(3, 1))[0], null)
	_add(City.sidewalk_loop(Vector2i(0, 4))[1], BAT)
	# M6 구역들: 종로 방망이·화염병, 홍대 화염병, 공단 수류탄·로켓, 여의도 차량 기관총, 변두리·한강 비밀 상자
	_add(City.sidewalk_loop(Vector2i(2, -6))[0], BAT)
	_add(City.sidewalk_loop(Vector2i(4, -8))[3], MOLOTOV)
	_add(City.sidewalk_loop(Vector2i(-4, -6))[1], MOLOTOV)
	_add(City.sidewalk_loop(Vector2i(-2, -8))[2], SMG)
	_add(City.sidewalk_loop(Vector2i(-4, 2))[0], GRENADE)
	_add(City.sidewalk_loop(Vector2i(-1, 4))[2], ROCKET)
	_add(City.sidewalk_loop(Vector2i(-2, -2))[3], CAR_MG)
	_add(City.sidewalk_loop(Vector2i(-5, -11))[0], ROCKET)          # 지도 북서쪽 끝 — 비밀 상자
	_add(City.sidewalk_loop(Vector2i(5, -5))[2], FLAMETHROWER)       # 한강공원 동쪽 끝 — 비밀 상자
	_add(City.sidewalk_loop(Vector2i(3, -10))[1] + Vector2(0, 60), null)
	_add(City.sidewalk_loop(Vector2i(-2, 4))[1], null)


func _add(pos: Vector2, weapon: WeaponType, once := false, ammo := 0) -> void:
	crates.append({"pos": pos, "weapon": weapon, "wait": 0.0, "once": once, "ammo": ammo})


## 기절한 사람이 떨어뜨린다 (한 번 먹으면 사라진다). weapon이 null이면 구급상자, ammo > 0이면 그 무기의 총알 상자
func drop(pos: Vector2, weapon: WeaponType, ammo := 0) -> void:
	_add(pos, weapon, true, ammo)
	queue_redraw()


func _ready_drops() -> void:
	loot_rng.seed = LOOT_SEED
	if pedestrians:
		pedestrians.person_hurt.connect(func(p: Pedestrian, _by: bool, killed: bool):
			if killed:
				drop_loot(p))


## 기절한 사람이 가진 것을 떨어뜨린다 (docs/05 §3: 소총은 군인 드롭)
func drop_loot(p: Pedestrian) -> void:
	var pos := p.global_position
	var npc := p.npc
	if npc == SOLDIER:
		drop(pos, RIFLE)
	if not npc.ko_loot.is_empty():
		# 배달 상자: 실은 것 중 하나 (구급상자도)
		var n := npc.ko_loot.size() + (1 if npc.ko_loot_medkit else 0)
		var k := loot_rng.randi() % n
		drop(pos + Vector2(10, 0), npc.ko_loot[k] if k < npc.ko_loot.size() else null)
	if npc.ko_ammo > 0 and npc.ko_ammo_weapon:
		if loot_rng.randf() < npc.ko_gun_chance:
			drop(pos, npc.ko_ammo_weapon)                  # 드물게 총 자체
		else:
			drop(pos, npc.ko_ammo_weapon, npc.ko_ammo)     # 총알


func _physics_process(delta: float) -> void:
	var v := director.current_vehicle
	var pos := v.global_position if v else player.global_position
	var reach := REACH_CAR if v else REACH_FOOT
	var can_take := (v != null and not v.airborne()) or (v == null and player.visible and not player.is_dead())
	var redraw := false
	for c in crates:
		if c.wait > 0.0:
			c.wait -= delta
			redraw = redraw or c.wait <= 0.0
			continue
		if can_take and pos.distance_to(c.pos) < reach and take(c):
			c.wait = RESPAWN
			redraw = true
			if c.once:
				crates.erase(c)
				break
	if redraw:
		queue_redraw()


## 상자를 연다. 구급상자는 체력이 깎였을 때만 먹는다.
func take(c: Dictionary) -> bool:
	var w: WeaponType = c.weapon
	if c.get("ammo", 0) > 0:
		# 총알 상자: 그 무기가 있으면 거기, 없으면 지금 든(또는 가진) 총에 넣는다. 총이 없으면 못 먹는다
		var gun := w if player.arsenal.has(w) else _ammo_target()
		if gun == null or player.arsenal.ammo_of(gun) >= gun.max_ammo:
			return false
		player.arsenal.give(gun, c.ammo)
		picked.emit("%s 총알 +%d" % [gun.display_name, c.ammo])
		return true
	if w == null:
		if player.health >= Player.MAX_HEALTH:
			return false
		player.revive()
		picked.emit("체력 회복")
		return true
	if w.infinite and player.arsenal.has(w):
		return false
	player.arsenal.give(w, w.pickup_ammo)
	picked.emit(w.display_name if w.infinite else "%s +%d" % [w.display_name, w.pickup_ammo])
	return true


## 총알을 넣을 총: 지금 든 총, 아니면 가진 총 중 맨 앞 (주먹·방망이·무한 무기는 빼고)
func _ammo_target() -> WeaponType:
	var held := player.arsenal.current()
	if not held.melee and not held.infinite:
		return held
	for w in player.arsenal.weapons:
		if not w.melee and not w.infinite:
			return w
	return null


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for c in crates:
		if c.wait > 0.0:
			continue
		var r := Rect2(c.pos - Vector2(SIZE, SIZE) * 0.5, Vector2(SIZE, SIZE))
		draw_rect(Rect2(r.position + Vector2(3, 3), r.size), Color(0, 0, 0, 0.35))
		var w: WeaponType = c.weapon
		if w == null:
			draw_rect(r, Color(0.95, 0.95, 0.95))
			draw_rect(Rect2(c.pos - Vector2(2.5, 7), Vector2(5, 14)), Color(0.9, 0.1, 0.12))
			draw_rect(Rect2(c.pos - Vector2(7, 2.5), Vector2(14, 5)), Color(0.9, 0.1, 0.12))
		elif c.get("ammo", 0) > 0:
			# 총알 상자: 짙은 국방색 탄통에 노란 탄 세 알
			var box := Rect2(c.pos - Vector2(8, 6), Vector2(16, 12))
			draw_rect(box, Color(0.3, 0.34, 0.22))
			draw_rect(box, Color(0.75, 0.7, 0.4), false, 1.5)
			for i in 3:
				draw_rect(Rect2(c.pos + Vector2(-5.5 + i * 4.0, -4), Vector2(2.5, 7)), Color(0.95, 0.78, 0.3))
		else:
			draw_rect(r, Color(0.55, 0.38, 0.18))
			draw_rect(r, Color(0.95, 0.75, 0.3), false, 2.0)
			draw_string(font, Vector2(r.position.x, r.end.y - 4), w.crate_label,
				HORIZONTAL_ALIGNMENT_CENTER, SIZE, 13, Color(1.0, 0.95, 0.8))
