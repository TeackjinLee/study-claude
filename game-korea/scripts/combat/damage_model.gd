class_name DamageModel
## 충돌·치임·폭발 피해 계산. 노드 없는 정적 함수와 상수.
## 체력 단위: 사람 20~100(주인공 100), 차는 VehicleType.durability(세단 120).

const CRASH_THRESHOLD := 400.0     ## 이보다 약한 충돌(벽에 박는 법선 속도 px/s 기준)은 흠집도 안 난다
const CRASH_SCALE := 0.08          ## 넘는 속도 1px/s당 피해
const RUN_OVER_SPEED := 80.0       ## 이보다 빠른 차에 치이면 다친다 (PedestrianManager.HIT_SPEED와 같다)
const RUN_OVER_SCALE := 0.1        ## 300px/s로 치면 시민(20)이 죽는다

const BURN_TIME := 3.0             ## 체력이 0이 된 차가 불타다 터지기까지 (내릴 시간)
const CHAIN_FUSE_MIN := 0.25       ## 폭발에 휘말린 차는 금방 터진다 — 연쇄가 눈에 보이게 약간 늦게
const CHAIN_FUSE_MAX := 0.6

const EXPLOSION_FULL := 60.0       ## 이 안은 최대 피해
const EXPLOSION_RADIUS := 200.0    ## 이 밖은 피해 없음
const EXPLOSION_VEHICLE_DAMAGE := 200.0
const EXPLOSION_PERSON_DAMAGE := 160.0
const EXPLOSION_IMPULSE := 520.0   ## px/s (질량 1 기준)


static func crash_damage(strength: float) -> float:
	return maxf(strength - CRASH_THRESHOLD, 0.0) * CRASH_SCALE


static func run_over_damage(speed: float) -> float:
	return maxf(speed - RUN_OVER_SPEED, 0.0) * RUN_OVER_SCALE


## 폭발 중심에서 dist 떨어진 곳의 피해 비율 (0~1)
## scale은 폭발 크기 배율 (유조차 3배 — 반경이 그만큼 커진다)
static func explosion_falloff(dist: float, scale := 1.0) -> float:
	if dist <= EXPLOSION_FULL * scale:
		return 1.0
	return clampf(1.0 - (dist - EXPLOSION_FULL * scale) / ((EXPLOSION_RADIUS - EXPLOSION_FULL) * scale), 0.0, 1.0)
