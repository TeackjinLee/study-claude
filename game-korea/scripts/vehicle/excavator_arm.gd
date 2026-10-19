class_name ExcavatorArm
extends RefCounted
## 굴삭기 팔(붐·암·버킷)의 순수 계산부 — 노드 없이 헤드리스 테스트에서 그대로 쓴다.
## 팔은 상부 회전축 앞의 붐 뿌리(pivot)에서 시작하는 두 마디 팔이다. 버킷 끝을 (앞 거리, 높이)에 두는 붐·암 각을
## 두 마디 역기구학으로 구한다 (팔꿈치가 위로 꺾인다 — 실제 굴삭기처럼 붐은 들리고 암은 아래로 접힌다).
## 각은 VehicleModel의 관절 각과 같은 기준: 0이면 앞(−y)으로 수평, +면 끝이 들린다. 암 각은 붐 기준이다.

const BOOM := 44.0          ## 붐 길이 (px)
const STICK := 34.0         ## 암 길이
const PIVOT_Y := -10.0      ## 붐 뿌리: 상부 회전축에서 앞으로 (차 기준 y, 회전축 기준)
const PIVOT_Z := 22.0       ## 붐 뿌리 높이
const DIG_TIME := 0.9       ## 한 번 퍼 올리는 데 걸리는 시간 (내려찍기 → 들어 올리기)
const CARRY_Z := 26.0       ## 버킷을 들고 있는 높이 (땅에서)
const DIG_Z := 1.0          ## 내려찍은 버킷 끝 높이


## 버킷 끝을 회전축에서 앞으로 reach, 땅에서 z 높이에 두는 [붐 각, 암 각]. 닿지 않으면 그 방향으로 쭉 편다
static func solve(reach: float, z: float) -> Vector2:
	var f := reach + PIVOT_Y      # 붐 뿌리에서 앞으로 (PIVOT_Y는 음수 = 앞)
	var u := z - PIVOT_Z
	var d2 := f * f + u * u
	var c := clampf((d2 - BOOM * BOOM - STICK * STICK) / (2.0 * BOOM * STICK), -1.0, 1.0)
	var elbow := -acos(c)          # 암은 아래로 접힌다
	var boom := atan2(u, f) - atan2(STICK * sin(elbow), BOOM + STICK * cos(elbow))
	return Vector2(boom, elbow)


## 붐·암 각에서 버킷 끝 (회전축에서 앞 거리, 높이) — solve의 검산·버킷 위치
static func tip(angles: Vector2) -> Vector2:
	var a := angles.x
	var b := angles.x + angles.y
	return Vector2(-PIVOT_Y + BOOM * cos(a) + STICK * cos(b), PIVOT_Z + BOOM * sin(a) + STICK * sin(b))


## 한 번 퍼 올리는 동안 버킷 끝 높이 (t 0 → 1: 들고 있다 → 내려찍기 → 다시 들어 올리기)
static func dig_height(t: float) -> float:
	return lerpf(CARRY_Z, DIG_Z, sin(clampf(t, 0.0, 1.0) * PI))


## 버킷 각 (암 기준): 내려찍을 때는 이를 세우고, 들어 올릴 때는 안으로 말아 담는다
static func bucket_angle(t: float, digging: bool) -> float:
	if not digging:
		return -1.4
	return lerpf(-0.4, -1.9, clampf((t - 0.45) / 0.4, 0.0, 1.0))
