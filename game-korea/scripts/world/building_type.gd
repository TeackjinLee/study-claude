class_name BuildingType
extends Resource
## 건물 한 종의 정의 (docs/04_건물_주거.md). 새 건물 종은 .tres만 추가하고, 모양(style)이 새로우면 BuildingDrawer(위에서 보기)와 BuildingModel(2.5D)에 더한다.

@export var id: StringName
@export var display_name: String
## 그리는 모양: commercial / mixed / office / officetel / apt / villa / gosiwon / warehouse
## / house / rowhouse / oneroom / factory / hanok / jjokbang / campsite / park
## 기능 건물(2.5D 겉모습, SpecialBuilding): police / hospital / gang_tower / gang_office / gang_dock / car_center / sauna / convenience
@export var style: StringName = &"commercial"
## 놓일 수 있는 부지: 0 블록 통째 · 1 블록 절반 · 2 블록 1/4
@export var footprints: Array[int] = [0, 1, 2]
## 같은 부지 후보끼리의 출현 비중 (0이면 자동 배치 안 함 — 본부·창고처럼 정해 둔 곳에만)
@export var weight := 1.0
@export var roof_colors: Array[Color] = [Color(0.36, 0.3, 0.3)]
## 간판 문구 후보 (모양마다 쓰임이 다르다: 상호·건물 이름·동 번호 앞자리 등)
@export var signs: PackedStringArray = PackedStringArray()
@export var accent := Color(1.0, 0.82, 0.23)
## 2.5D 화면의 층수 (한 층 = IsoView.FLOOR_HEIGHT px). 0이면 바닥에 납작하게 그린다
@export var floors := 4
## 시각 층고 배율. 층수·충돌은 유지하며 2.5D 덩어리 높이만 바꾼다.
@export var visual_floor_scale := 1.0
## 재질 얼룩·처마 음영·돌출 테두리의 추가 표현.
@export var surface_detail := false
## 2.5D 화면의 외벽 색
@export var wall_color := Color(0.45, 0.45, 0.5)
## 2.5D 평지붕(옥상) 색. 투명이면 roof_colors를 쓴다 (빌라·원룸·아파트의 초록 방수 옥상처럼 위에서 보기와 다를 때)
@export var top_color := Color(0, 0, 0, 0)
## 기능 건물(사우나·편의점)의 흩뿌리기: 자동 배치된 replaces(종류 id) 부지를 scatter 확률로 이 겉모습으로 그린다.
## 충돌·위에서 보기는 원래 종류 그대로다 (City.looks)
@export var replaces: Array[StringName] = []
@export var scatter := 0.0
## false면 충돌체가 없다 (공원처럼 걸어서·차로 지나갈 수 있는 부지)
@export var solid := true
