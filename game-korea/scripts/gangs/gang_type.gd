class_name GangType
extends Resource
## 갱 한 파의 정의 (docs/01 §3, docs/05 §5). 새 갱은 .tres만 추가한다.

@export var id: StringName
@export var display_name: String
@export var color := Color(0.1, 0.1, 0.1)       ## 상징색 (공중전화·조직원 옷)
@export var accent := Color(0.95, 0.75, 0.25)   ## 강조색 (간판·HUD)
@export var member: NpcType                     ## 조직원 NPC
@export var member_count := 0                   ## 구역을 돌아다니는 조직원 수 (0이면 미션에만 나온다)
@export var home_blocks: Array[Vector2i] = []   ## 조직원이 도는 블록 (잠긴 구역 블록에는 세우지 않는다)
## 라이벌 갱 id: 이 갱 미션에 성공하면 라이벌 존경도가 떨어지고(rival_share),
## 라이벌 조직원을 죽이면 이 갱 존경도가 오른다
@export var rival: StringName
@export var rival_share := 0.25
## 아지트 겉모습 (2.5D). 공중전화 묶음마다 가장 가까운 건물을 이 모양으로 그린다 (City.looks)
@export var base_look: BuildingType

@export_group("Respect")
@export var normal_respect := 20                ## 보통 미션 전화가 열리는 존경도
@export var hard_respect := 40                  ## 어려운 미션 전화가 열리는 존경도
@export var ally_respect := 40                  ## 이 이상이면 조직원이 아군 (때려도 참는다)
@export var hostile_respect := -40              ## 이 이하면 조직원이 보이는 대로 쏜다
@export var kill_penalty := 10                  ## 조직원 하나를 죽이면 깎이는 존경도
@export var mission_kill_penalty := 3           ## 미션 표적·경호원은 '일'이라 덜 깎인다

@export_group("Phones")
## 공중전화 위치. 셋씩 한 묶음 [쉬움, 보통, 어려움] — 묶음 k는 phones[3k .. 3k+2]이고
## MissionType.phone_set == k인 미션을 준다. 묶음마다 다른 구역에 두면 그 구역이 열려야 받을 수 있다.
@export var phones: PackedVector2Array = PackedVector2Array()
