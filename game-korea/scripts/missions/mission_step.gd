class_name MissionStep
extends Resource
## 미션의 한 단계. 종류(kind)에 따라 쓰는 칸이 다르다.
##  GOTO        points[0]에 간다 (need_vehicle이면 미션 차를 타고)
##  ENTER       points[0]에 vehicle을 세워 두고, 거기 타면 끝 (driver면 운전자가 타고 있어 빼앗아야 한다)
##  DELIVER     지금 미션 차를 points[0]에 세운다 (min_health 밑으로 부서지면 실패)
##  KILL        npc를 npc_points마다 세우고, 모두 죽으면 끝
##  DESTROY     vehicle을 points마다 세우고(moving이면 도로를 달린다), 모두 부서지면 끝. npc는 지키는 조직원
##  LOSE_WANTED 수배가 0이 되면 끝 (wanted로 단계 시작 때 별을 붙인다)

enum Kind { GOTO, ENTER, DELIVER, KILL, DESTROY, LOSE_WANTED }

@export var kind := Kind.GOTO
@export var text := ""                                   ## HUD 목표 문구
@export var points: PackedVector2Array = PackedVector2Array()
@export var headings: PackedFloat32Array = PackedFloat32Array()   ## points마다 차 방향 (rad, 0 = 위)
@export var radius := 50.0                               ## GOTO·DELIVER 도착 판정 거리
@export var need_vehicle := false                        ## GOTO를 미션 차로 가야 한다 (경주 체크포인트)
@export var vehicle: VehicleType
@export var driver := false
@export var moving := false
@export var npc: NpcType
@export var npc_points: PackedVector2Array = PackedVector2Array()
@export var min_health := 0.0                            ## DELIVER: 차 체력 비율이 이보다 낮아지면 실패
@export var wanted := 0                                  ## 단계 시작 때 붙는 수배 별
