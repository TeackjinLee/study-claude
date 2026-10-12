class_name VehicleType
extends Resource
## 차종 하나의 성능·외형 정의.
## 새 차종은 이 리소스(.tres) 하나만 추가한다 — 차량 코드는 고치지 않는다.

@export var id: StringName
@export var display_name: String
## 그리는 모양: sedan / sport / suv / light / taxi / truck / bus / police / ambulance / swat / bike
## / tanker / garbage / mixer / fire / tow / bicycle / camper / bigtruck / heli
@export var category: StringName = &"sedan"
## 빼앗으면 끌려 나오는 운전자 (비우면 일반 시민)
@export var driver_npc: NpcType

@export_group("Engine")
@export var max_speed := 720.0        ## px/s
@export var acceleration := 520.0     ## px/s²
@export var reverse_speed := 240.0    ## px/s
@export var brake_force := 900.0      ## px/s²
@export var coast_drag := 120.0       ## 가속 페달을 뗐을 때 감속 px/s²

@export_group("Handling")
@export var turn_rate := 2.6          ## rad/s, 최대 조향·충분한 속도에서
@export var turn_speed_ref := 220.0   ## 이 속도 이상이면 조향이 100% 먹는다 (px/s)
@export var steer_response := 7.0     ## 조향 입력이 목표까지 가는 속도 (1/s)
@export var grip := 1600.0            ## 옆 미끄러짐을 잡는 힘 px/s²
@export var handbrake_grip := 0.22    ## 핸드브레이크 시 grip 배율
@export var handbrake_decel := 420.0  ## 핸드브레이크 감속 px/s²
@export var drift_turn_boost := 1.35  ## 핸드브레이크 시 회전 배율

@export_group("Body")
@export var mass := 1.0
@export var durability := 120.0     ## 체력. 총알·충돌·폭발 피해를 받아 0이 되면 불이 붙는다
@export var size := Vector2(28, 56)   ## 폭 × 길이 px (차는 화면 위쪽을 향한다)
@export var body_color := Color.WHITE
@export var roof_color := Color(0.85, 0.85, 0.88)
## 2.5D 화면에서 차체 높이 (화면 px, 줌 1). 그림에만 쓰고 물리에는 영향 없다
@export var height := 14.0

@export_group("Special")
## 타고 있으면 주인공 체력이 초당 이만큼 찬다 (구급차)
@export var heal_rate := 0.0
## 터질 때 폭발 반경 배율 (유조차 3배)
@export var explosion_scale := 1.0
## false면 탈 수 없다 (소방헬기 — 연출용)
@export var enterable := true
## 빼앗아도 신고가 안 들어온다 (자전거 — 조용하다)
@export var silent := false
## 이동식 세이브 포인트 (캠핑카: 세워 두고 내리면 저장 메뉴)
@export var save_point := false
## 일반 교통으로 이 구역에서만 나온다 (DistrictType.id). 비우면 어디서나
@export var districts: Array[StringName] = []
