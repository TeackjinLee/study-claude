class_name NpcType
extends Resource
## NPC 한 종의 정의 (docs/02_캐릭터_NPC.md). 새 종은 .tres만 추가한다.

@export var id: StringName
@export var display_name: String
## 0은 기존 종의 수치를 유지한다. 성인 설계도 12종은 1~10을 데이터로 지정한다.
@export_range(0, 10) var stat_health := 0
@export_range(0, 10) var stat_speed := 0
@export_range(0, 10) var stat_power := 0
@export var walk_speed_min := 50.0:
	get: return (35.0 + stat_speed * 3.0 if stat_speed > 0 else walk_speed_min) * walk_scale
@export var walk_speed_max := 72.0:
	get: return (57.0 + stat_speed * 3.0 if stat_speed > 0 else walk_speed_max) * walk_scale
## 걷는 속도 배율 (일반 시민 0.9 — 거리를 느긋하게 걷게). 달리기(도망)는 그대로
@export var walk_scale := 1.0
@export var run_speed := 170.0:
	get: return 110.0 + stat_speed * 12.0 if stat_speed > 0 else run_speed
## 인도 모퉁이에서 잠깐 멈춰 설 확률
@export var idle_chance := 0.25
## 차 회피 반응 거리 배율 (어르신 < 1 < 학생)
@export var reaction := 1.0
@export var spawn_weight := 1.0
@export var health := 20.0:
	get: return 10.0 + stat_health * 2.5 if stat_health > 0 else health
## 들고 다니는 무기 (경찰 등). 없으면 null
@export var weapon: WeaponType
## 기절시키면 이 중 하나를 떨어뜨린다 (배달원 상자 — Pickups). 비우면 없다
@export var ko_loot: Array[WeaponType] = []
## ko_loot 고르기에 구급상자도 넣는다
@export var ko_loot_medkit := false
## 기절시키면 이 무기의 총알 상자를 떨어뜨린다 (조직원 — 주인공이 가진 그 무기·든 총에 들어간다). 0이면 없다
@export var ko_ammo := 0
## 기절시키면 이 확률(0~1)로 총알 대신 총 자체(ko_ammo_weapon)를 떨어뜨린다
@export var ko_gun_chance := 0.0
## 떨어뜨리는 총알·총의 무기 (조직원 권총은 NPC용이라 주인공 권총으로 준다)
@export var ko_ammo_weapon: WeaponType
## 소속 갱 (GangType.id). 시민·경찰은 비어 있다
@export var gang: StringName
## 몸 크기 배율 (아이 0.7)
@export var body_scale := 1.0
## 다치지 않는다 — 차·총·폭발 모두 (아이: docs/02 등급·윤리 규칙)
@export var protected := false
## 겁먹지 않는다 (노숙자: 직접 맞기 전엔 무시)
@export var fearless := false
## 이 구역에서만 걷는다 (DistrictType.id). 비우면 어디서나
@export var districts: Array[StringName] = []
## 한자리에 서 있는 사람: &"shop" 가게(상가·상가주택·편의점·시장) 앞 인도에서 길 쪽을 보고 호객 · &"street" 블록 둘레 인도에서 길 쪽을 보고 공연.
## 서 있는 동안 대기 그림(assets/characters/<id>_idle_dir8.png)을 되풀이한다. 비우면 늘 걷는다
@export var station: StringName = &""
## 새로 나올 때 station 자리에 설 몫 (0~1, 나머지는 걷는다)
@export var station_share := 0.0
## 이 시각(게임 시각, 0~24시) 사이에만 나온다. x > y면 밤을 넘긴다 (예: 20 → 4)
@export var hours := Vector2i(0, 24)
@export var shirt_colors: Array[Color] = [Color(0.5, 0.5, 0.5)]
@export var pants_colors: Array[Color] = [Color(0.2, 0.22, 0.3)]
@export var hair_colors: Array[Color] = [Color(0.08, 0.07, 0.07)]

@export_group("모습")
## 옷 모양 (PersonDrawer가 그린다). plain 셔츠 · jacket 앞이 열린 겉옷 · coat 긴 코트 · suit 정장·넥타이 ·
## tank 민소매·문신 · tracksuit 줄무늬 운동복 · dress 원피스 · vest 조끼(형광·방탄) · stripes 반사띠 제복 ·
## camo 얼룩무늬 · apron 앞치마 · hanbok 한복 홍보복 · rags 해진 겉옷 · pinstripe 줄무늬 정장 · armor 전술복
@export var outfit: StringName = &"plain"
## 안에 받친 옷·넥타이·줄무늬·조끼·반사띠 색
@export var trim_color := Color(0.92, 0.92, 0.9)
## 모자: cap 야구모자 · flatcap 헌팅캡 · beanie 비니 · police 경찰 모자 · helmet 안전모·방탄모 ·
## fire_helmet 소방 헬멧 · hood 두건 · visor 챙 모자 · headband 머리띠 · ponytail 묶은 머리. 비우면 맨머리
@export var hat: StringName = &""
@export var hat_color := Color(0.2, 0.2, 0.22)
## 모자를 쓴 사람 비율 (0~1). 사람마다 정해진다
@export var hat_chance := 1.0
## 얼굴: sunglasses 선글라스 · glasses 안경 · balaclava 복면 · mask 마스크 · beard 수염 · goggles 보안경
@export var face: StringName = &""
## 긴 머리 (어깨까지)
@export var long_hair := false
## 든 것: briefcase 서류가방 · handbag 핸드백 · backpack 배낭 · sack 자루 · cane 지팡이 · box 배달 상자 ·
## guitar 기타 · headphones 헤드폰 · flyers 전단지 · baton 경광봉 · phone 휴대폰 · delivery 배낭+상자 ·
## satchel 크로스백 · air_tank 공기통 · rifle 도감용 소총 · blades 단검
@export var prop: StringName = &""
@export var prop_color := Color(0.25, 0.18, 0.12)
## 든 것을 가진 사람 비율 (0~1)
@export var prop_chance := 1.0

## 총기에는 적용하지 않는다. 공유 무기 리소스의 피해량을 바꾸지 않는다.
func melee_multiplier() -> float:
	return 0.55 + stat_power * 0.15 if stat_power > 0 else 1.0
