class_name BuildingType
extends Resource
## 건물 한 종의 정의 (docs/04_건물_주거.md). 새 건물 종은 .tres만 추가하고, 모양(style)이 새로우면 BuildingDrawer에 한 줄 더한다.

@export var id: StringName
@export var display_name: String
## 그리는 모양: commercial / mixed / office / officetel / apt / villa / gosiwon / warehouse
## / house / rowhouse / oneroom / factory / hanok / jjokbang / campsite / park
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
## 2.5D 화면의 외벽 색
@export var wall_color := Color(0.45, 0.45, 0.5)
## false면 충돌체가 없다 (공원처럼 걸어서·차로 지나갈 수 있는 부지)
@export var solid := true
