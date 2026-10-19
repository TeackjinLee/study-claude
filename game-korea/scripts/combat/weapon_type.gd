class_name WeaponType
extends Resource
## 무기 한 종의 정의 (docs/05_게임플레이.md §3). 새 무기는 .tres만 추가한다.

@export var id: StringName
@export var display_name: String
@export var crate_label := ""          ## 무기 상자에 찍는 한 글자
@export var slot := 0                  ## 무기 순서 (0 = 주먹)

@export_group("Fire")
@export var melee := false             ## 근접 무기 (주먹): 앞쪽 부채꼴 안의 가장 가까운 사람 하나를 친다
@export var damage := 10.0             ## 한 발(산탄은 한 알) 피해. 사람 체력 20~100, 차 체력은 VehicleType.durability
@export var pellets := 1               ## 한 번에 나가는 알 수 (산탄총)
@export var spread := 0.03             ## 퍼짐 (rad). 산탄은 부채꼴 반각, 근접은 칠 수 있는 반각
@export var fire_interval := 0.35      ## 연사 간격 (초)
@export var max_range := 500.0            ## 사거리 px
@export var knockdown := false         ## 맞으면 넘어진다 (주먹)
@export var drive_by := true           ## 차 안에서 좌우로 쏠 수 있다
@export var pierce := 1                ## 한 발이 꿰뚫는 표적 수 (소총 2)

@export_group("Special")
## 던지거나 날아가는 탄: "" (즉시 맞는 총알) / "grenade" (수류탄) / "molotov" (화염병) / "rocket" (로켓)
@export var projectile: StringName = &""
@export var projectile_speed := 600.0  ## px/s
@export var fuse := 0.0                ## 수류탄: 이만큼 지나면 터진다 (0이면 닿으면 터진다)
@export var explosion_scale := 0.0     ## 터질 때 폭발 크기 (0이면 안 터진다)
@export var fire_radius := 0.0         ## 불이 붙는 범위 (화염병·화염방사기)
@export var flame := false             ## 화염방사기: 짧은 부채꼴에 불을 뿜는다
@export var water := false             ## 물대포: 사람·차를 밀고 불을 끈다 (피해 없음)
@export var push := 0.0                ## 물대포가 미는 힘 px/s
## 차에 달린 무기: 이 차종(id)을 몰면 쏘기 버튼이 늘 이 무기를 앞으로 쏜다 (소방차 물대포)
@export var mounted_on: Array[StringName] = []
@export var vehicle_only := false      ## 차 안에서만 쏜다 (차량 기관총)
@export var forward := false           ## 차 안에서 옆이 아니라 앞으로 쏜다

@export_group("Ammo")
@export var infinite := false
@export var pickup_ammo := 12          ## 무기 상자 하나에 든 탄
@export var max_ammo := 120

@export_group("Look")
@export var tracer_color := Color(1.0, 0.9, 0.5)
## 쏠 때 소리 (GunSynth.KINDS의 종류 — pistol·smg·rifle·shotgun·mg·rocket·cannon, ""면 소리 없음)
@export var sound: StringName = &""
