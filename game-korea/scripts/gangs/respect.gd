class_name Respect
extends RefCounted
## 갱별 존경도 (−100 ~ +100). 노드 없는 순수 계산 — 미션 성공은 올리고 조직원 살해는 깎는다.

signal changed(gang: StringName, value: int, delta: int)

const MIN := -100
const MAX := 100

var values := {}   ## gang id → 존경도


func of(gang: StringName) -> int:
	return values.get(gang, 0)


func change(gang: StringName, amount: int) -> void:
	var before := of(gang)
	var after := clampi(before + amount, MIN, MAX)
	values[gang] = after
	if after != before:
		changed.emit(gang, after, after - before)


func set_value(gang: StringName, value: int) -> void:
	values[gang] = clampi(value, MIN, MAX)
	changed.emit(gang, values[gang], 0)


## tier(0 쉬움 · 1 보통 · 2 어려움) 미션 전화가 열렸는지
func tier_open(g: GangType, tier: int) -> bool:
	return of(g.id) >= required(g, tier)


static func required(g: GangType, tier: int) -> int:
	match tier:
		1: return g.normal_respect
		2: return g.hard_respect
	return MIN


func is_hostile(g: GangType) -> bool:
	return of(g.id) <= g.hostile_respect


func is_ally(g: GangType) -> bool:
	return of(g.id) >= g.ally_respect
