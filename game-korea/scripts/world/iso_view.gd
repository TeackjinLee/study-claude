class_name IsoView
## 2.5D 사선 화면의 공통 수식. 물리·AI는 원래 XY 평면 그대로이고, 화면에 비출 때만 사선으로 눕힌다.
## 화면 = 원점 + 줌 × BASIS × (월드 − 카메라) − (0, 높이 × 줌)
## 높이는 화면 픽셀(줌 1) 단위다. 월드에서는 LIFT 방향으로 그만큼 옮겨 그리면 같은 자리에 보인다.
## 이 수식 덕분에 각 노드는 자기 _draw 안에서 높이를 더해 그릴 수 있다 (매 프레임 다시 그리지 않아도 된다).
## 모양의 기준은 tools/isometric_sample (Codex 2.5D 샘플)이다.

## 월드 +x는 화면 오른쪽 아래, 월드 +y는 화면 왼쪽 아래로 눕는다
const BASIS := Transform2D(Vector2(0.78, 0.39), Vector2(-0.78, 0.39), Vector2.ZERO)
## 화면 위로 1px 올라가는 월드 방향 (= BASIS⁻¹ × (0, -1))
const LIFT := Vector2(-1.2820513, -1.2820513)
## 깊이 정렬: 월드 x+y가 클수록 화면 앞쪽이다. 이 값을 z_index로 바꾼다
const Z_MIN := 100
const Z_MAX := 4000
const DEPTH_MIN := -12600.0
const DEPTH_STEP := 6.0
## 정렬 위에 덮이는 효과 (폭발·탄환 / 헬기)
const Z_EFFECTS := 4050
const Z_AIR := 4080
## 사람 키 (화면 px)
const PERSON_HEIGHT := 26.0
const FLOOR_HEIGHT := 18.0

## false면 예전 위에서 보는 화면 (F9로 바꾼다)
static var enabled := true


## 높이 h(화면 px)를 월드 오프셋으로
static func lift(h: float) -> Vector2:
	return LIFT * h


## 그 자리 땅 높이 (다리 위). 위에서 보기(F9)면 0
static func ground(pos: Vector2) -> float:
	return CityMap.ground_height(pos) if enabled else 0.0


## 회전한 노드 안에서 쓸 높이 오프셋
static func lift_local(h: float, rotation: float) -> Vector2:
	return (LIFT * h).rotated(-rotation)


## 화면 기준으로 그리는 좌표계 (회전 없는 노드에서 draw_set_transform_matrix에 넘긴다).
## 이 안에서 (x, y)는 화면 픽셀이다 — 서 있는 사람·말풍선·글자를 눕히지 않고 세워 그린다.
static func screen_frame(at := Vector2.ZERO, h := 0.0) -> Transform2D:
	var inv := BASIS.affine_inverse()
	return Transform2D(inv.x, inv.y, at + lift(h))


## 월드 방향 → 화면 방향 (정규화하지 않는다)
static func to_screen_dir(world_dir: Vector2) -> Vector2:
	return BASIS.basis_xform(world_dir)


## 화면 기준 입력(W=화면 위) → 월드 이동 방향. 길이는 입력 세기를 유지한다
static func walk_dir(screen_dir: Vector2) -> Vector2:
	if screen_dir == Vector2.ZERO:
		return Vector2.ZERO
	return BASIS.affine_inverse().basis_xform(screen_dir).normalized() * minf(screen_dir.length(), 1.0)


static func z_of(pos: Vector2) -> int:
	return clampi(Z_MIN + int((pos.x + pos.y - DEPTH_MIN) / DEPTH_STEP), Z_MIN, Z_MAX)


## 카메라 위치·줌 → 캔버스 변환
static func canvas(view_size: Vector2, cam: Vector2, zoom: float) -> Transform2D:
	var t := BASIS.scaled(Vector2(zoom, zoom))
	t.origin = view_size * Vector2(0.5, 0.56) - t.basis_xform(cam)
	return t


## 벽 한 면: 바닥 선분 a→b를 높이 h0~h1로 세운 사각형
static func wall(a: Vector2, b: Vector2, h0: float, h1: float) -> PackedVector2Array:
	return PackedVector2Array([a + lift(h0), b + lift(h0), b + lift(h1), a + lift(h1)])


## 월드 법선 n인 벽이 화면에서 보이는가 (앞으로 향한 면)
static func faces_viewer(n: Vector2) -> bool:
	return n.x + n.y > 0.001


## 보이는 면을 밝기로 구분한다 (오른쪽 면은 덜, 왼쪽 면은 더 어둡게)
static func face_shade(n: Vector2) -> float:
	return 0.3 if n.x > n.y else 0.48
