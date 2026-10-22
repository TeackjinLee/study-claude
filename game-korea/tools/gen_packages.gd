extends SceneTree
## 비밀 패키지 자리 생성기 → data/collect/packages.tres
## 구역마다 정한 수만큼, 블록 안에서 인도로부터 걸어서 닿는 가장 깊은 빈 자리(골목·마당·공터)를 고른다
## 지붕·처마·나무 밑은 뺀다 (HiddenPackages.spot_in_block). 블록은 번호 해시 순서로 고르고, 이미 고른 블록과 붙은 블록은 뒤로 미룬다.
## 도시 배치(City._build_layout)가 바뀌면 다시 돌린다 — collect_test가 자리를 다시 검사한다.
## 실행: godot --headless --path . -s res://tools/gen_packages.gd

const OUT := "res://data/collect/packages.tres"
## 구역 → 패키지 수 (합 50)
const QUOTA := {&"gangnam": 10, &"jongno": 7, &"hongdae": 7, &"riverside": 5, &"yeouido": 5,
	&"outskirts": 8, &"industrial": 8}
const UNLOCKS := ["smg", "shotgun", "rifle", "rocket", "flamethrower"]


func _init() -> void:
	var city := City.new()
	city._build_layout()
	var obstacles := city.obstacle_rects()
	obstacles.append_array(City.water_rects())
	var cover := city.cover_rects()
	var by_district := {}
	for j in range(CityMap.MIN.y, CityMap.MAX.y + 1):
		for i in range(CityMap.MIN.x, CityMap.MAX.x + 1):
			var cell := Vector2i(i, j)
			var d := CityMap.district_of(cell)
			if d == null or not CityMap.is_land(cell):
				continue
			var p := HiddenPackages.spot_in_block(cell, obstacles, cover)
			if p == Vector2.INF:
				continue
			if not by_district.has(d.id):
				by_district[d.id] = []
			by_district[d.id].append([cell, p])
	var spots := PackedVector2Array()
	for id: StringName in QUOTA:
		var cands: Array = by_district.get(id, [])
		cands.sort_custom(func(a, b): return _hash(a[0]) < _hash(b[0]))
		var chosen: Array = []
		for pass_ in 2:
			for c in cands:
				if chosen.size() >= QUOTA[id] or chosen.has(c):
					continue
				var touching := chosen.any(func(o): return absi(o[0].x - c[0].x) <= 1 and absi(o[0].y - c[0].y) <= 1)
				if pass_ == 1 or not touching:
					chosen.append(c)
		if chosen.size() < QUOTA[id]:
			printerr("%s: 자리가 %d곳뿐 (필요 %d)" % [id, chosen.size(), QUOTA[id]])
		for c in chosen:
			spots.append(c[1])
		print("%s: %d곳 %s" % [id, chosen.size(), chosen.map(func(c): return c[0])])
	var set := PackageSet.new()
	set.spots = spots
	for w in UNLOCKS:
		set.unlocks.append(load("res://data/weapons/%s.tres" % w))
	var err := ResourceSaver.save(set, OUT)
	print("패키지 %d개 → %s (%s)" % [spots.size(), OUT, error_string(err)])
	city.free()
	quit(0 if err == OK and spots.size() == 50 else 1)


static func _hash(c: Vector2i) -> int:
	return posmod(c.x * 73856093 ^ c.y * 19349663, 1000003)
