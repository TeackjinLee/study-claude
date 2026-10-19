class_name Layers
## 물리 충돌 레이어. 비트 값이다.

const WORLD := 1      ## 건물·외벽
const VEHICLES := 2
const PEOPLE := 4     ## 플레이어(도보)·보행자
## 고가차도 위(층 1)의 같은 것들 — 위아래가 서로 부딪히지 않게 비트를 따로 쓴다 (at으로 옮긴다)
const DECK := 8       ## 고가 난간
const DECK_VEHICLES := 16
const DECK_PEOPLE := 32
const LEVEL_SHIFT := 3


## 땅 기준 비트를 층 level의 비트로 옮긴다
static func at(bits: int, level: int) -> int:
	return bits << LEVEL_SHIFT if level == 1 else bits
