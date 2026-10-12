class_name DistrictType
extends Resource
## 구역 하나의 정의 (docs/01 §2). 블록 범위·해금 장·지배 갱·건물 비중을 담는다.
## 새 구역은 .tres를 만들고 CityMap.DISTRICTS에 한 줄 더한다.

@export var id: StringName
@export var display_name: String
## 이 장(Chapter)부터 들어갈 수 있다
@export var chapter := 1
## 지배 갱 id (없으면 비워 둔다)
@export var gang: StringName
## 블록 좌표 범위 (City.block_rect 기준). 구역끼리 겹치지 않는다
@export var blocks := Rect2i()
## 지도·이름표 색
@export var color := Color(0.6, 0.65, 0.8)
## 인도 색 (구역 분위기)
@export var sidewalk := Color(0.33, 0.34, 0.40)
## 건물 종류 id → 출현 비중. 비어 있으면 BuildingType.weight를 그대로 쓴다
@export var building_weights := {}
## 건물 없는 블록 (공원·주차장)
@export var plazas: Array[Vector2i] = []
## 경찰서·병원 블록 (블록 통째). 체포·사망하면 가장 가까운 곳에서 다시 시작한다
@export var police_stations: Array[Vector2i] = []
@export var hospitals: Array[Vector2i] = []
## 들어서면 화면에 띄우는 한 줄 소개
@export var tagline := ""


func has_block(b: Vector2i) -> bool:
	return blocks.has_point(b)
