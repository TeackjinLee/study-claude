class_name Wallet
extends RefCounted
## 주인공의 돈. 벌금·보상이 모두 여기를 거친다.

signal changed(money: int)

const START_MONEY := 500000

var money := START_MONEY


## 돈을 낸다. 모자라면 있는 만큼만 낸다. 실제로 낸 금액을 돌려준다.
func pay(amount: int) -> int:
	var paid := mini(amount, money)
	money -= paid
	changed.emit(money)
	return paid


func earn(amount: int) -> void:
	money += amount
	changed.emit(money)
