class_name DamageModel
## 충돌·치임·폭발 피해 계산. 노드 없는 정적 함수와 상수.
## 체력 단위: 사람 20~100(주인공 100), 차는 VehicleType.durability(세단 120).

const CRASH_THRESHOLD := 400.0     ## 이보다 약한 충돌(벽에 박는 법선 속도 px/s 기준)은 흠집도 안 난다
const CRASH_SCALE := 0.08          ## 넘는 속도 1px/s당 피해
const RUN_OVER_SPEED := 80.0       ## 이보다 빠른 차에 치이면 다친다 (PedestrianManager.HIT_SPEED와 같다)
const RUN_OVER_SCALE := 0.1        ## 300px/s로 치면 시민(20)이 죽는다

const BURN_TIME := 3.0             ## 체력이 0이 된 차가 불타다 터지기까지 (내릴 시간)
const FIRE_HEALTH := 0.2           ## 체력이 이 비율 아래로 떨어지면 차에 불이 난다
const FIRE_TIME := 8.0             ## 불난 차의 남은 체력(20%)이 다 타서 0이 되기까지 초 — 그 뒤 BURN_TIME 뒤 터진다

const DENT_PER_DAMAGE := 0.15      ## 충돌 피해 1당 찌그러지는 깊이 px (그림만, 충돌 모양은 그대로)
const DENT_MAX := 5.0              ## 한 곳이 찌그러지는 최대 깊이 px
const DENT_RADIUS := 20.0          ## 찌그러짐이 퍼지는 반경 px. 이 안에 또 부딪히면 같은 곳이 더 들어간다
const MAX_DENTS := 8               ## 차 한 대에 남기는 찌그러진 곳 수 (넘으면 얕은 곳부터 지운다)
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
