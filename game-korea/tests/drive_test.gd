extends Node
## M0 완료 기준 검증: 차종마다 최고속·가속·제동·선회·드리프트가 실제로 다르게 나오는가.
## 실행: godot --headless --path . res://tests/drive_test.tscn

const DT := 1.0 / 60.0
const VEHICLE_DIR := "res://data/vehicles/"

var _failures: Array[String] = []


func _ready() -> void:
	var results := {}
	for file in DirAccess.get_files_at(VEHICLE_DIR):
		if file.ends_with(".tres"):
			var t: VehicleType = load(VEHICLE_DIR + file)
			if t.enterable:   # 소방헬기처럼 탈 수 없는 연출용은 뺀다
				results[t.id] = measure(t)
				results[t.id].tracked = t.tracked
	_print_table(results)
	_check(results)
	if _failures.is_empty():
		print("drive_test: PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func measure(t: VehicleType) -> Dictionary:
	var r := {"name": t.display_name, "max": t.max_speed}
	var m := VehicleMotor.new(t)
	var time := 0.0
	var t95 := -1.0
	while time < 10.0:
		m.step(1.0, 0.0, false, DT)
		time += DT
		if t95 < 0.0 and m.forward_speed() >= t.max_speed * 0.95:
			t95 = time
	r.top = m.forward_speed()
	r.t95 = t95

	var dist := 0.0
	var bt := 0.0
	while m.forward_speed() > 5.0 and bt < 10.0:
		m.step(-1.0, 0.0, false, DT)
		dist += m.velocity.length() * DT
		bt += DT
	r.brake_dist = dist
	r.brake_time = bt

	var normal := _turn(t, false)
	var drift := _turn(t, true)
	r.turn = normal.rate
	r.drift_turn = drift.rate
	r.slip = normal.slip
	r.drift_slip = drift.slip
	return r


## 최고속의 70%에서 조향을 꺾고 0.2~0.6초 구간의 평균 회전율(°/s)과 최대 옆 미끄러짐(px/s)
func _turn(t: VehicleType, handbrake: bool) -> Dictionary:
	var m := VehicleMotor.new(t)
	m.velocity = Vector2.UP * t.max_speed * 0.7
	var time := 0.0
	var turned := 0.0
	var slip := 0.0
	while time < 0.6:
		var before := m.heading
		m.step(0.0 if handbrake else 1.0, 1.0, handbrake, DT)
		time += DT
		if time > 0.2:
			turned += angle_difference(before, m.heading)
			slip = maxf(slip, absf(m.lateral_speed()))
	return {"rate": rad_to_deg(turned) / 0.4, "slip": slip}


func _print_table(results: Dictionary) -> void:
	print("| 차종 | 최고속 | 0→95% | 제동거리 / 시간 | 선회 | 드리프트 선회 | 옆 미끄러짐 (일반→드리프트) |")
	print("|---|---|---|---|---|---|---|")
	for id in results:
		var r: Dictionary = results[id]
		print("| %s | %.0f | %.2fs | %.0fpx / %.2fs | %.0f°/s | %.0f°/s | %.0f → %.0f (%.1f배) |" % [
			r.name, r.top, r.t95, r.brake_dist, r.brake_time, r.turn, r.drift_turn,
			r.slip, r.drift_slip, r.drift_slip / maxf(r.slip, 1.0)])


func _check(results: Dictionary) -> void:
	for id in results:
		var r: Dictionary = results[id]
		_expect(absf(r.top - r.max) < r.max * 0.01, "%s 최고속 %.0f ≠ 설정 %.0f" % [id, r.top, r.max])
		_expect(r.t95 > 0.0 and r.t95 < 3.0, "%s 0→95%% %.2fs (0~3초여야 함)" % [id, r.t95])
		if r.tracked:
			continue   # 무한궤도(자주포)는 미끄러지지 않고 제자리에서 돈다 (tank_test)
		_expect(r.drift_turn > r.turn, "%s 드리프트 선회 %.0f ≤ 일반 %.0f" % [id, r.drift_turn, r.turn])
		_expect(r.drift_slip > r.slip * 1.5, "%s 드리프트 미끄러짐이 일반의 1.5배 미만" % id)

	if not (results.has(&"CAR_AVELA") and results.has(&"CAR_AVELA_R") and results.has(&"TRK_PORTA")):
		_failures.append("기준 3차종(CAR_AVELA, CAR_AVELA_R, TRK_PORTA)이 없음")
		return
	var sedan: Dictionary = results[&"CAR_AVELA"]
	var sport: Dictionary = results[&"CAR_AVELA_R"]
	var truck: Dictionary = results[&"TRK_PORTA"]
	_expect(sport.top > sedan.top and sedan.top > truck.top, "최고속 순서: 스포츠 > 세단 > 트럭")
	_expect(sport.t95 < truck.t95, "가속: 스포츠가 트럭보다 빨라야 함")
	_expect(truck.brake_dist < sedan.brake_dist and sedan.brake_dist < sport.brake_dist,
		"제동거리 순서: 트럭 < 세단 < 스포츠 (빠를수록 실수의 대가가 크다)")
	_expect(sport.turn > sedan.turn and sedan.turn > truck.turn, "선회 순서: 스포츠 > 세단 > 트럭")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
