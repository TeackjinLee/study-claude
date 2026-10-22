class_name AudioSetup
extends RefCounted
## 소리 묶음(버스): 효과음(총·폭발·차·사람) · 음악(차 라디오) · 배경음(도시·비·강). 설정 화면의 크기 막대가 이 버스를 바꾼다.
## 버스는 프로젝트 파일에 두지 않고 켤 때 만든다 (ensure — Main·타이틀이 부른다). 크기는 Settings가 저장한다.

const SFX := &"Sfx"
const MUSIC := &"Music"
const AMBIENCE := &"Ambience"
const BUSES: Array[StringName] = [SFX, MUSIC, AMBIENCE]


static func ensure() -> void:
	for name in BUSES:
		if AudioServer.get_bus_index(name) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, name)
			AudioServer.set_bus_send(i, &"Master")


## 버스 크기 0..1 (0이면 끈다). bus가 &"Master"면 전체
static func set_volume(bus: StringName, linear: float) -> void:
	ensure()
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, linear <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.001)))


static func volume(bus: StringName) -> float:
	var i := AudioServer.get_bus_index(bus)
	if i < 0 or AudioServer.is_bus_mute(i):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(i))
