class_name WantedSystem
extends RefCounted
## 수배 단계(★). 노드 없는 순수 계산 — 목격된 범죄와 "경찰 눈에 보이는지"만 받아 별을 올리고 내린다.
##
## 범죄마다 열기(heat)가 쌓이고, 열기가 문턱을 넘으면 별이 오른다. 무거운 범죄는 최소 별도 정한다.
## 경찰 눈에 띈 채 도망치는 동안에도 열기가 조금씩 오른다(체포 불응).
## 경찰 시야에서 LOSE_TIME 동안 벗어나 있으면 별이 하나 내려간다. ★4부터는 저절로 내려가지 않는다(카센터 도색으로 뗀다).
## ★5(LOCK_LEVEL)부터는 어떻게도 떨어지지 않는다 — 카센터 도색·거리 이벤트 보상(lower)·자경단 부업도 못 뗀다.
## 체포·기절(clear)로 추격이 끝나야 풀린다.
## 범죄마다 올릴 수 있는 별의 상한이 있다: 가벼운 범죄와 추격 중 쌓이는 열기는 ★3, 시민·경찰을 기절시키면 ★4(사람은 죽지 않고 기절한다), 구급대원은 바로 ★4,
## 특공대원 기절은 ★5(특공대 사상 → 헬기), 그 뒤 군인 기절·헬기 격추는 ★6(군 투입)까지 (docs/05 §4).

signal level_changed(level: int, previous: int)
signal escaped                                           ## 시야 밖에서 버텨 ★0이 됐다 (체포로 지운 건 아님)

enum Crime { CAR_THEFT, HIT_PEDESTRIAN, RAM_POLICE, HIT_OFFICER, STEAL_POLICE_CAR,
	GUNFIRE, KILL_PEDESTRIAN, KILL_OFFICER, ATTACK_POLICE_CAR, KILL_SWAT, KILL_SOLDIER, DOWN_HELI, KO_PARAMEDIC }

const MAX_LEVEL := 6
const HEAT_LEVEL_CAP := 3                                ## 가벼운 범죄·추격 열기로는 이 별까지만
const LOCK_LEVEL := 5                                    ## 이 별부터는 떨어지지 않는다 (clear만 푼다)
const LEVEL_HEAT: Array[float] = [0.0, 1.0, 4.0, 9.0, 24.0, 40.0, 64.0]   ## 별마다 필요한 누적 열기
const LETHAL := [Crime.KILL_PEDESTRIAN, Crime.KILL_OFFICER, Crime.KILL_SWAT, Crime.KILL_SOLDIER, Crime.DOWN_HELI, Crime.KO_PARAMEDIC]
## 범죄별 [열기, 최소 별, 알림 문구, 이 범죄로 오를 수 있는 최고 별]
const CRIMES := {
	Crime.CAR_THEFT: [1.0, 1, "차량 탈취", 3],
	Crime.HIT_PEDESTRIAN: [1.0, 1, "시민을 침", 3],
	Crime.RAM_POLICE: [1.0, 1, "경찰차 들이받기", 3],
	Crime.HIT_OFFICER: [3.0, 2, "경찰관을 침", 3],
	Crime.STEAL_POLICE_CAR: [3.0, 2, "경찰차 탈취", 3],
	Crime.GUNFIRE: [0.5, 1, "총기 발사", 3],
	Crime.KILL_PEDESTRIAN: [3.0, 2, "시민 기절시킴", 4],
	Crime.KILL_OFFICER: [6.0, 3, "경찰관 기절시킴", 4],
	Crime.ATTACK_POLICE_CAR: [2.0, 2, "경찰차 공격", 3],
	Crime.KILL_SWAT: [8.0, 4, "특공대원 기절시킴", 5],
	Crime.KILL_SOLDIER: [10.0, 5, "군인 기절시킴", 6],
	Crime.DOWN_HELI: [20.0, 6, "헬기 격추", 6],
	Crime.KO_PARAMEDIC: [24.0, 4, "구급대원 기절시킴", 4],   # 구급대원을 기절시키면 바로 ★4
}
## 별마다 시야 밖에서 버텨야 하는 시간(초). ★4부터는 안 내려간다
const LOSE_TIME: Array[float] = [0.0, 10.0, 14.0, 18.0, INF, INF, INF]
const CHASE_HEAT_RATE := 0.04                            ## 수배 중 경찰 눈에 띈 1초마다 쌓이는 열기

var level := 0
var heat := 0.0
var unseen_time := 0.0


static func crime_name(crime: Crime) -> String:
	return CRIMES[crime][2]


## 목격된 범죄 하나. 별이 올랐으면 true
func report(crime: Crime) -> bool:
	heat += CRIMES[crime][0]
	unseen_time = 0.0
	var from_heat := mini(level_for(heat), CRIMES[crime][3])
	return _raise(maxi(CRIMES[crime][1], from_heat))


func update(delta: float, seen: bool) -> void:
	if level == 0:
		return
	if seen:
		unseen_time = 0.0
		heat += CHASE_HEAT_RATE * delta
		_raise(mini(level_for(heat), HEAT_LEVEL_CAP))
		return
	unseen_time += delta
	if unseen_time >= LOSE_TIME[level]:
		var previous := level
		level -= 1
		heat = LEVEL_HEAT[level]
		unseen_time = 0.0
		level_changed.emit(level, previous)
		if level == 0:
			escaped.emit()


## 범죄 없이 별을 붙인다 (미션의 "경찰에 제보가 들어갔다" 등). 이미 더 높으면 그대로
func raise_to(to: int) -> void:
	unseen_time = 0.0
	_raise(to)


## 카센터 도색 등: 별을 n개 뗀다 (★5부터는 못 뗀다)
func lower(n: int) -> void:
	if level == 0 or locked():
		return
	var previous := level
	level = maxi(level - n, 0)
	heat = LEVEL_HEAT[level]
	unseen_time = 0.0
	level_changed.emit(level, previous)
	if level == 0:
		escaped.emit()


## ★5부터: 도색·보상·자경단으로 별을 뗄 수 없다
func locked() -> bool:
	return level >= LOCK_LEVEL


func clear() -> void:
	var previous := level
	level = 0
	heat = 0.0
	unseen_time = 0.0
	if previous != 0:
		level_changed.emit(0, previous)


## 별이 하나 내려가기까지 시야 밖에서 버틴 비율 (0~1, HUD 깜빡임용)
func lose_progress() -> float:
	return unseen_time / LOSE_TIME[level] if level > 0 and LOSE_TIME[level] < INF else 0.0


static func level_for(h: float) -> int:
	var l := 0
	for k in LEVEL_HEAT.size():
		if h >= LEVEL_HEAT[k]:
			l = k
	return mini(l, MAX_LEVEL)


func _raise(to: int) -> bool:
	to = mini(to, MAX_LEVEL)
	if to <= level:
		return false
	var previous := level
	level = to
	heat = maxf(heat, LEVEL_HEAT[level])
	level_changed.emit(level, previous)
	return true
