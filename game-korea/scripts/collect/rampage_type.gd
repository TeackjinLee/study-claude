class_name RampageType
extends Resource
## 광란 모드 하나 (docs/05 §7). 거리의 빨간 해골 아이콘을 밟으면 무기를 받고, 제한 시간 안에 목표만큼 쓰러뜨린다.
## 데이터는 tools/gen_rampages.py가 만든다 — .tres를 손으로 고치지 말고 생성기를 고친다.

enum Target { ANYONE, GANG, CARS }

const CORNER_OFFSET := 70.0

@export var id: StringName
@export var block := Vector2i.ZERO       ## 아이콘이 서는 블록 (그 블록 인도 고리의 corner번째 모서리)
@export var corner := 0
@export var weapon: WeaponType           ## 하는 동안 탄이 떨어지지 않는다. 끝나면 원래 무기로 돌아간다
@export var target := Target.ANYONE
@export var gang: StringName             ## target == GANG일 때 그 조직 조직원만 센다
@export var count := 15
@export var time_limit := 60.0
@export var reward := 100000


## 모서리에서 조금 비켜 선다 (모서리에는 신호등 기둥·횡단보도 끝이 있다)
func position() -> Vector2:
	var loop := City.sidewalk_loop(block)
	var a := loop[corner]
	return a + (loop[(corner + 3) % 4] - a).normalized() * CORNER_OFFSET


## 알림·HUD 목표 글: "120초 안에 강남 조직원 15명"
func goal_text(gang_name := "") -> String:
	match target:
		Target.GANG:
			return Locale.t("%s 조직원 %d명 쓰러뜨리기") % [Locale.t(gang_name), count]
		Target.CARS:
			return Locale.t("차 %d대 터뜨리기") % count
	return Locale.t("%d명 쓰러뜨리기") % count
