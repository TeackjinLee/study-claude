class_name NpcType
extends Resource
## NPC 한 종의 정의 (docs/02_캐릭터_NPC.md). 새 종은 .tres만 추가한다.

@export var id: StringName
@export var display_name: String
@export var walk_speed_min := 50.0
@export var walk_speed_max := 72.0
@export var run_speed := 170.0
## 인도 모퉁이에서 잠깐 멈춰 설 확률
@export var idle_chance := 0.25
## 차 회피 반응 거리 배율 (어르신 < 1 < 학생)
@export var reaction := 1.0
@export var spawn_weight := 1.0
@export var health := 20.0
## 들고 다니는 무기 (경찰 등). 없으면 null
@export var weapon: WeaponType
## 소속 갱 (GangType.id). 시민·경찰은 비어 있다
@export var gang: StringName
## 몸 크기 배율 (아이 0.7)
@export var body_scale := 1.0
## 다치지 않는다 — 차·총·폭발 모두 (아이: docs/02 등급·윤리 규칙)
@export var protected := false
## 겁먹지 않는다 (노숙자: 직접 맞기 전엔 무시)
@export var fearless := false
## 플레이어가 곁에 서 있으면 하는 말 (docs/02 §5.3)
@export var lines: PackedStringArray = PackedStringArray()
## 이 구역에서만 걷는다 (DistrictType.id). 비우면 어디서나
@export var districts: Array[StringName] = []
## 이 시각(게임 시각, 0~24시) 사이에만 나온다. x > y면 밤을 넘긴다 (예: 20 → 4)
@export var hours := Vector2i(0, 24)
@export var shirt_colors: Array[Color] = [Color(0.5, 0.5, 0.5)]
@export var pants_colors: Array[Color] = [Color(0.2, 0.22, 0.3)]
@export var hair_colors: Array[Color] = [Color(0.08, 0.07, 0.07)]
