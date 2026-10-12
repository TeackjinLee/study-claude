class_name ChapterType
extends Resource
## 장(Chapter) 하나 (docs/05 §1). 목표 금액을 모으면 다음 장이 열리고 새 구역이 풀린다.
## 어느 구역이 열리는지는 DistrictType.chapter가 정한다.

@export var number := 1
@export var title := ""
## 이 장을 끝내는 목표 금액 (원). 마지막 장은 이걸 모으면 엔딩
@export var target := 1000000
@export_multiline var intro := ""
