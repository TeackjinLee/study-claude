extends Resource
## 비주얼 샘플의 색·밀도·간판. 게임 플레이 수치는 기존 리소스를 사용한다.

@export var asphalt := Color("202733")
@export var pavement := Color("555765")
@export var roof := Color("354248")
@export var warm := Color("ffc879")
@export var cyan := Color("62dbea")
@export var pink := Color("f267a9")
@export var signs: PackedStringArray
@export var shop_vertical := PackedStringArray(["노래방", "PC방", "약국", "치킨"])
@export var texture_seed := 7021
@export var rain_drops := 90
