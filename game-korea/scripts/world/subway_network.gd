class_name SubwayNetwork
extends Resource
## 지하철 빠른 이동 (사용자 요청 2026-10-24): 걸어서 역 출입구 앞에서 F → 열린 역을 골라 요금을 내고 그 역 출입구로 옮긴다.
## 노드 없이 타도 되는지만 정한다 — 출입구 자리·그림·옮기기는 Subway가 한다.

@export var stations: Array[SubwayStation] = []
@export var fare := 1500
## 이 별 수보다 높으면 못 탄다 (경찰이 개찰구를 지킨다)
@export var max_wanted := 0


## 역이 선 구역이 열렸나
func is_open(i: int) -> bool:
	return CityMap.is_open_block(stations[i].block)


## 못 타는 까닭 ("" = 탈 수 있다). busy = 미션·부업·광란 중
func refusal(wanted: int, busy: bool, money: int) -> String:
	if wanted > max_wanted:
		return "수배 중에는 지하철을 탈 수 없다"
	if busy:
		return "미션 중에는 지하철을 탈 수 없다"
	if money < fare:
		return "교통비가 모자란다"
	return ""
