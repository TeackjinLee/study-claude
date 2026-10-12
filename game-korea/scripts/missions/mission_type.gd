class_name MissionType
extends Resource
## 갱 미션 하나 (docs/05 §5.3). 단계(MissionStep)를 차례로 끝내면 성공. 새 미션은 .tres만 추가한다.

enum Tier { EASY, NORMAL, HARD }

@export var id: StringName
@export var gang: StringName                 ## 미션을 주는 갱 (GangType.id)
@export var tier := Tier.EASY                ## 어느 공중전화에서 받는지
@export var phone_set := 0                   ## 그 갱의 몇 번째 공중전화 묶음에서 받는지 (GangType.phones)
@export var order := 0                       ## 같은 전화 안에서의 순서
@export var title := ""
@export_multiline var briefing := ""
@export var reward := 30000                  ## 성공 보상 (원)
@export var respect := 8                     ## 성공 시 오르는 존경도
@export var time_limit := 0.0                ## 전체 제한 시간 (초). 0이면 없음
@export var steps: Array[MissionStep] = []
