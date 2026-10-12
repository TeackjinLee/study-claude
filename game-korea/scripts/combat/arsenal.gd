class_name Arsenal
extends RefCounted
## 가진 무기와 탄약, 연사 대기. 노드 없는 순수 계산 — 쏠 수 있는지와 탄 소모만 정한다.
## 주먹은 늘 갖고 있다. 탄이 떨어진 무기는 목록에서 빠지고 주먹으로 돌아간다.

signal changed

var fist: WeaponType
var weapons: Array[WeaponType] = []   ## 무기 순서(slot)대로, 맨 앞은 주먹
var ammo := {}                        ## WeaponType → 남은 탄
var index := 0
var cooldown := 0.0


func _init(p_fist: WeaponType) -> void:
	fist = p_fist
	weapons = [fist]


func current() -> WeaponType:
	return weapons[index]


## 남은 탄. 무한이면 -1
func ammo_of(w: WeaponType) -> int:
	return -1 if w.infinite else ammo.get(w, 0)


func has(w: WeaponType) -> bool:
	return weapons.has(w)


## 무기 상자 등으로 탄을 얻는다. 새 무기이고 지금 주먹이면 바로 든다.
## 탄이 없는 무기(야구방망이)는 한 번 얻으면 계속 갖는다.
func give(w: WeaponType, amount: int) -> void:
	if w.infinite and weapons.has(w):
		return
	if not weapons.has(w):
		var at := weapons.size()
		for k in weapons.size():
			if weapons[k].slot > w.slot:
				at = k
				break
		var held := current()
		weapons.insert(at, w)
		index = weapons.find(held)
		if held == fist:
			index = at
	if not w.infinite:
		ammo[w] = mini(ammo.get(w, 0) + amount, w.max_ammo)
	changed.emit()


func update(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)


func can_fire() -> bool:
	return cooldown <= 0.0


## 한 번 쏜다(친다). 연사 대기 중이면 false. 마지막 탄을 쏘면 그 무기는 빠진다.
func fire() -> bool:
	if not can_fire():
		return false
	var w := current()
	cooldown = w.fire_interval
	if not w.infinite:
		ammo[w] -= 1
		if ammo[w] <= 0:
			ammo.erase(w)
			weapons.remove_at(index)
			index = 0
		changed.emit()
	return true


## step = +1 다음 무기, -1 이전 무기
func cycle(step: int) -> void:
	index = wrapi(index + step, 0, weapons.size())
	cooldown = maxf(cooldown, 0.15)
	changed.emit()


## 체포·사망: 무기 압수 (주먹만 남는다)
func clear() -> void:
	weapons = [fist]
	ammo.clear()
	index = 0
	cooldown = 0.0
	changed.emit()
