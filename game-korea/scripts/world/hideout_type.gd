class_name HideoutType
extends Resource
## 은신처 하나 (docs/04 §2). 문 앞 발판을 밟으면 저장한다. 값이 있으면 처음 밟을 때 산다.
## 새 은신처는 .tres만 추가하고 main.HIDEOUTS에 한 줄 더한다.

@export var id: StringName
@export var display_name := ""
## 문 앞 인도의 발판 위치 (월드 좌표)
@export var door := Vector2.ZERO
## 불러오면 발판에서 이만큼 비켜 선다 (인도를 따라)
@export var along := Vector2(0, 30)
## 사는 값 (0이면 처음부터 내 것)
@export var price := 0
