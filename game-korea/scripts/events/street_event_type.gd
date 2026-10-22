class_name StreetEventType
extends Resource
## 랜덤 거리 이벤트 한 종 (docs/02 §랜덤 거리 이벤트). 새 종은 .tres를 만들고 StreetEvents.EVENTS에 넣는다.
## 대사는 data/dialogue/lines.csv의 범인 npc 줄(snatch·threat·escape·caught)과 * 줄(robbed·held·thanks)을 쓴다.

@export var id: StringName
@export var display_name := ""
@export var npc: NpcType                 ## 범인 (도둑·강도). 무기가 있으면 들킨 뒤 주인공을 쏜다
@export var act_time := 0.0              ## 저지르는 시간 (0 = 낚아채고 바로 달아난다, 강도는 이만큼 위협한다)
@export var victim_situation: StringName = &"robbed"   ## 피해자가 하는 말 (lines.csv 상황)
@export var flee_speed := 175.0          ## 달아나는 빠르기 (주인공 달리기 Player.RUN_SPEED 190보다 조금 느리게)
@export var alert_range := 160.0         ## 저지르는 중 주인공이 이만큼 다가오면 들켜 바로 달아난다
@export var give_up_distance := 700.0    ## 주인공과 이만큼 멀어지면 놓친다
@export var escape_time := 45.0          ## 달아난 뒤 이만큼 지나면 놓친다
@export var reward := 30000              ## 산 채로 붙잡으면 주는 돈 (원)
@export_range(0.0, 1.0) var kill_reward_scale := 0.5   ## 기절시켜 막으면 보상 배율 (넘어뜨려 붙잡으면 전부)
@export var wanted_relief := 1           ## 막으면 떼 주는 수배 별 (정의 구현 보너스)
@export var weight := 1.0                ## 고를 비중
@export var start_text := ""             ## 저지를 때 알림
