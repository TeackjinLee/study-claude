class_name SideJobType
extends Resource
## 부업 하나 (docs/05 §5.4). 정해진 차를 몰고 B를 누르면 시작한다. 10단계를 한 번에 끝내면 영구 보너스.
## 새 부업은 .tres를 만들고 main.SIDE_JOBS에 한 줄 더한다 (진행 방식 kind가 새로우면 SideJobs에 더한다).

enum Kind { TAXI, BUS, DELIVERY, AMBULANCE, FIRE, VIGILANTE }

@export var id: StringName
@export var display_name := ""
@export var kind := Kind.TAXI
## 이 차종(VehicleType.id)을 몰고 있으면 시작할 수 있다
@export var vehicles: Array[StringName] = []
@export var levels := 10
@export var base_reward := 5000          ## 1단계 보상 (원)
@export var reward_step := 2000          ## 단계마다 늘어나는 보상
@export var time_base := 60.0            ## 1단계 제한 시간 (초)
@export var time_step := 3.0             ## 단계마다 줄어드는 시간
@export var min_time := 25.0
@export var stops := 1                   ## 단계마다 들를 곳 (버스 정류장 3)
@export var intro := ""                  ## 시작할 때 띄우는 한 줄
@export var bonus_text := ""             ## 10단계를 다 끝내면 얻는 것


func reward(level: int) -> int:
	return base_reward + reward_step * level


func time_limit(level: int) -> float:
	return maxf(time_base - time_step * level, min_time)
