class_name PackageSet
extends Resource
## 비밀 패키지 묶음 (docs/05 §7 수집 요소). 자리는 tools/gen_packages.gd가 도시 배치에서 골라 적는다 —
## 손으로 고치지 말고 생성기를 고친다. 모은 수가 milestones에 닿으면 unlocks의 같은 번째 무기를 준다
## (그 무기는 산 은신처마다 다시 생기는 상자로도 남는다).

@export var spots := PackedVector2Array()        ## 월드 좌표 (골목·마당·공터 — 걸어서 닿는 곳)
@export var reward := 10000                      ## 하나 주울 때마다 (원)
@export var milestones: Array[int] = [10, 20, 30, 40, 50]
@export var unlocks: Array[WeaponType] = []      ## milestones와 같은 순서
@export var final_reward := 1000000              ## 모두 모으면 더 주는 돈
