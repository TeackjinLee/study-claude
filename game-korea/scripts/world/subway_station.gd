class_name SubwayStation
extends Resource
## 지하철역 하나. 블록 아래(남쪽) 인도에 출입구가 선다 — 그 블록에 지하철 랜드마크가 있으면 그 계단 앞 (Subway).
## 역이 선 블록의 구역이 열려야 탈 수 있다.

@export var id: StringName
@export var display_name := ""
@export var line := 2                    ## 호선 (간판 숫자)
@export var line_color := Color("1f9a55")
@export var block := Vector2i.ZERO
