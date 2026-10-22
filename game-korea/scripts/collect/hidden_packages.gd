class_name HiddenPackages
extends Node2D
## 비밀 패키지 50개 (docs/05 §7). 골목·마당·랜드마크 공터처럼 인도에서 안쪽으로 들어가야 보이는 곳에 있다.
## 걸어서든 차로든 지나가면 줍는다 — 하나마다 SET.reward, 모은 수가 SET.milestones에 닿으면 그 무기를 준다.
## 모은 번호는 저장된다(SaveGame.packages). 자리는 tools/gen_packages.gd가 정한다 (spot_in_block).

signal collected(count: int, total: int, reward: int)
signal milestone(weapon: WeaponType, count: int)
signal completed(reward: int)

const SET: PackageSet = preload("res://data/collect/packages.tres")
const REACH_FOOT := 18.0
const REACH_CAR := 30.0
## 생성기·검사: 걸어서 닿는지 재는 격자 간격과 사람이 지나갈 틈 (주인공 반지름 7 + 여유)
const GRID := 8.0
const CLEARANCE := 10.0          ## 격자 번짐 (마당·공터)
const ALLEY_CLEARANCE := 7.5     ## 곧은 골목 (부지 사이 18px — 주인공 반지름 7이 지나간다)
const COVER_MARGIN := 4.0        ## 지붕·처마 밑은 위에서 안 보여 빼고, 가장자리에서 조금 더 띄운다
const SCAN := 3.0                ## 자리 후보 간격
const MIN_DEPTH := 36.0          ## 인도 가장자리에서 적어도 이만큼 안쪽 (숨어 있어야 한다)

var director: Director
var player: Player
var wallet: Wallet
var got := {}                    ## 주운 번호 → true


func _ready() -> void:
	_make_views()


func count() -> int:
	return got.size()


func total() -> int:
	return SET.spots.size()


## 모은 수까지 풀린 무기 (은신처 상자·불러오기용)
func unlocked() -> Array[WeaponType]:
	var out: Array[WeaponType] = []
	for k in mini(SET.milestones.size(), SET.unlocks.size()):
		if count() >= SET.milestones[k]:
			out.append(SET.unlocks[k])
	return out


## 불러오기: 모은 번호를 되돌린다 (보상은 다시 주지 않는다)
func restore(ids: Array) -> void:
	got.clear()
	for i in ids:
		if int(i) >= 0 and int(i) < total():
			got[int(i)] = true
	_make_views()


func _physics_process(_delta: float) -> void:
	if director == null or player == null:
		return
	var v := director.current_vehicle
	if v == null and (not player.visible or player.is_dead()):
		return
	if v and v.airborne():
		return
	var pos := v.global_position if v else player.global_position
	var reach := REACH_CAR if v else REACH_FOOT
	for i in SET.spots.size():
		if not got.has(i) and pos.distance_to(SET.spots[i]) < reach:
			take(i)


func take(i: int) -> void:
	if got.has(i):
		return
	got[i] = true
	if wallet:
		wallet.earn(SET.reward)
	collected.emit(count(), total(), SET.reward)
	for k in mini(SET.milestones.size(), SET.unlocks.size()):
		if count() == SET.milestones[k]:
			var w := SET.unlocks[k]
			if player and w:
				player.arsenal.give(w, w.max_ammo)
			milestone.emit(w, count())
	if count() == total():
		if wallet:
			wallet.earn(SET.final_reward)
		completed.emit(SET.final_reward)
	_make_views()


## 패키지마다 서 있는 작은 소포 상자 — 사람처럼 깊이 정렬해(z_of) 처마·차양 밑에 묻히지 않고, 앞 건물이 가리면 그 건물이 흐려질 때 보인다
class PackageView extends Node2D:
	const SIZE := 6.0         ## 반 변 (월드 px)
	const HEIGHT := 9.0
	var pos := Vector2.ZERO
	var _t := 0.0

	func _ready() -> void:
		z_as_relative = false
		z_index = IsoView.z_of(pos)
		position = pos

	func _process(delta: float) -> void:
		_t += delta
		var cam := ChaseCamera.current_cam()
		visible = cam == null or pos.distance_squared_to(cam.global_position) < 1400.0 * 1400.0
		if visible:
			queue_redraw()

	func _draw() -> void:
		var g := IsoView.lift(IsoView.ground(pos)) if IsoView.enabled else Vector2.ZERO
		var glow := 0.5 + 0.5 * sin(_t * 3.0)
		FireFx.circle(self, g, 15.0 + glow * 3.0, Color(1.0, 0.82, 0.3, 0.14 + glow * 0.12))
		var r := Rect2(-SIZE, -SIZE, SIZE * 2.0, SIZE * 2.0)
		var h := HEIGHT if IsoView.enabled else 0.0
		var top := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		for k in top.size():
			top[k] += g + IsoView.lift(h)
		var brown := Color(0.62, 0.45, 0.25)
		if h > 0.0:
			draw_colored_polygon(IsoView.wall(Vector2(r.position.x, r.end.y) + g, r.end + g, 0.0, h), brown.darkened(IsoView.face_shade(Vector2.DOWN)))
			draw_colored_polygon(IsoView.wall(r.end + g, Vector2(r.end.x, r.position.y) + g, 0.0, h), brown.darkened(IsoView.face_shade(Vector2.RIGHT)))
		draw_colored_polygon(top, brown.lightened(0.12))
		var tape := Color(0.92, 0.85, 0.6)
		draw_line((top[0] + top[1]) * 0.5, (top[2] + top[3]) * 0.5, tape, 1.6)
		draw_line((top[1] + top[2]) * 0.5, (top[3] + top[0]) * 0.5, tape, 1.6)
		top.append(top[0])
		draw_polyline(top, Color(0.32, 0.2, 0.1), 1.0)


var _views := {}                 ## 번호 → PackageView


func _make_views() -> void:
	for i in SET.spots.size():
		if not got.has(i) and not _views.has(i):
			var v := PackageView.new()
			v.pos = SET.spots[i]
			add_child(v)
			_views[i] = v
	for i in _views.keys():
		if got.has(i):
			_views[i].queue_free()
			_views.erase(i)


# ── 자리 고르기 (생성기·검사) ────────────────────────────

## 블록 안에서 인도로부터 걸어서 닿고 지붕에 덮이지 않은 가장 깊은 빈 자리(골목·마당·공터). 없으면 Vector2.INF.
## obstacles = City.obstacle_rects() + 강물, cover = City.cover_rects()
static func spot_in_block(block: Vector2i, obstacles: Array[Rect2], cover: Array[Rect2]) -> Vector2:
	var area := City.block_rect(block.x, block.y)
	var walls := _near(area, obstacles, CLEARANCE)
	var thin := _near(area, obstacles, ALLEY_CLEARANCE)
	var roofs := _near(area, cover, COVER_MARGIN)
	var flood := reachable(area, walls)
	var best := Vector2.INF
	var best_depth := MIN_DEPTH
	var y := area.position.y + City.SIDEWALK + MIN_DEPTH
	while y < area.end.y - City.SIDEWALK - MIN_DEPTH:
		var x := area.position.x + City.SIDEWALK + MIN_DEPTH
		while x < area.end.x - City.SIDEWALK - MIN_DEPTH:
			var p := Vector2(x, y)
			var depth := _depth(area, p)
			if depth > best_depth and not _inside(p, thin) and not _inside(p, roofs) \
					and (flood.has(_cell(area, p)) and not _inside(p, walls) or _straight_out(area, p, thin)):
				best_depth = depth
				best = p
			x += SCAN
		y += SCAN
	return best


## 이 자리가 그 블록 인도에서 걸어서 닿는가 (검사용)
static func is_reachable(p: Vector2, obstacles: Array[Rect2]) -> bool:
	var block := CityMap.block_at(p)
	var area := City.block_rect(block.x, block.y)
	if not area.has_point(p):
		return false
	var walls := _near(area, obstacles, CLEARANCE)
	var thin := _near(area, obstacles, ALLEY_CLEARANCE)
	if _inside(p, thin):
		return false
	return (reachable(area, walls).has(_cell(area, p)) and not _inside(p, walls)) or _straight_out(area, p, thin)


## 블록 격자 칸 중 인도 띠에서 막히지 않고 번져 닿는 칸 (near = 이미 틈만큼 넓힌 장애물)
static func reachable(area: Rect2, near: Array[Rect2]) -> Dictionary:
	var n := Vector2i(int(area.size.x / GRID), int(area.size.y / GRID))
	var seen := {}
	var queue: Array[Vector2i] = []
	var ring := int(City.SIDEWALK * 0.5 / GRID)
	for y in n.y:
		for x in n.x:
			var c := Vector2i(x, y)
			if (x <= ring or y <= ring or x >= n.x - 1 - ring or y >= n.y - 1 - ring) and not _inside(_center(area, c), near):
				seen[c] = true
				queue.append(c)
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var m: Vector2i = c + d
			if m.x < 0 or m.y < 0 or m.x >= n.x or m.y >= n.y or seen.has(m):
				continue
			if not _inside(_center(area, m), near):
				seen[m] = true
				queue.append(m)
	return seen


## 동서남북 어느 한쪽으로 곧장 인도 띠까지 막힘이 없다 (부지 사이 좁은 골목은 격자 번짐으로 못 찾는다)
static func _straight_out(area: Rect2, p: Vector2, thin: Array[Rect2]) -> bool:
	for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var q := p
		var clear := true
		while _depth(area, q) > 0.0:
			if _inside(q, thin):
				clear = false
				break
			q += d * 3.0
		if clear:
			return true
	return false


static func _near(area: Rect2, rects: Array[Rect2], grow: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r in rects:
		var g := r.grow(grow)
		if g.intersects(area):
			out.append(g)
	return out


static func _inside(p: Vector2, rects: Array[Rect2]) -> bool:
	for r in rects:
		if r.has_point(p):
			return true
	return false


## 인도 안쪽 가장자리에서 잰 깊이 (인도 위면 0 이하)
static func _depth(area: Rect2, p: Vector2) -> float:
	return minf(minf(p.x - area.position.x, area.end.x - p.x), minf(p.y - area.position.y, area.end.y - p.y)) - City.SIDEWALK


static func _cell(area: Rect2, p: Vector2) -> Vector2i:
	return Vector2i(int((p.x - area.position.x) / GRID), int((p.y - area.position.y) / GRID))


static func _center(area: Rect2, c: Vector2i) -> Vector2:
	return area.position + (Vector2(c) + Vector2(0.5, 0.5)) * GRID
