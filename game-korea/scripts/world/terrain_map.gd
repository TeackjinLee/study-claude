class_name TerrainMap
extends Resource
## 서울 지형 높이 표. tools/prepare_terrain.py가 높이 그림(output/imagegen/terrain/seoul_height.png)에서 만든다 — 손으로 고치지 않는다.
## 높이 조절 값(max_height 아래부터)은 .tres에서 고친다 — 변환 도구가 다시 만들어도 지킨다. 계산은 Terrain이 한다.

## 첫 표본의 월드 좌표 (교차로 MIN의 북서 모서리)
@export var origin := Vector2.ZERO
## 표본 간격 (월드 px)
@export var cell := 192.0
## 표본 수 (가로, 세로)
@export var size := Vector2i.ZERO
## 밝기 0~1 (줄마다 가로로)
@export var values := PackedFloat32Array()
## 밝기 1의 높이 (2.5D 화면 px)
@export var max_height := 190.0
## 밝기를 이 거듭제곱으로 바꿔 높이로 쓴다 — 크면 산이 둘레 동네보다 도드라진다 (그림은 강북 전체를 밝게 칠했다)
@export var contrast := 1.8
## 한강 띠(북쪽 둑 도로 ~ 남쪽 둑 도로)에서 이 거리(월드 px)까지 높이를 0에서 부드럽게 올린다
@export var shore_fall := 700.0
## 고가차도 둘레를 평평하게 고르는 폭 (월드 px)
@export var flat_fall := 420.0
## 솟는 산 (x, y = 교차로 좌표 단위의 산 중심, z = 반지름(교차로 간격 단위)). 이 밖은 평지다 — 그림의 높이는 이 둘레에서만 쓴다
@export var hills: Array[Vector3] = []
## 건물 대신 숲(나무·흙길)이 서는 블록
@export var forests: Array[Vector2i] = []
## 비탈 그늘 세기 (기울기 1당 밝기 변화)
@export var shading := 2.0
