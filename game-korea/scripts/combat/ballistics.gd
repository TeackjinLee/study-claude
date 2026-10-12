class_name Ballistics
## 탄 퍼짐·자동 조준·드라이브바이 방향. 노드 없는 정적 함수.

const AIM_CONE := 0.35             ## 바라보는 방향에서 이 각도(rad) 안의 표적을 자동으로 겨눈다


## 한 번 쏠 때 나가는 알들의 방향. 산탄은 부채꼴로 고르게 펼치고 약간 흔든다.
static func pellet_dirs(dir: Vector2, w: WeaponType, rng: RandomNumberGenerator, extra_spread := 0.0) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var s := w.spread + extra_spread
	if w.pellets <= 1:
		out.append(dir.rotated(rng.randf_range(-s, s)))
		return out
	for i in w.pellets:
		var t := lerpf(-s, s, float(i) / (w.pellets - 1))
		out.append(dir.rotated(t + rng.randf_range(-s, s) * 0.15))
	return out


## from에서 dir 쪽 cone 안, reach 안의 표적 중 가장 겨누기 쉬운 것(각도·거리 모두 작은 것)의 번호. 없으면 -1
static func pick_target(from: Vector2, dir: Vector2, targets: Array[Vector2], reach: float, cone := AIM_CONE) -> int:
	var best := -1
	var best_score := INF
	for k in targets.size():
		var rel := targets[k] - from
		var d := rel.length()
		if d > reach or d < 1.0:
			continue
		var angle := absf(dir.angle_to(rel))
		if angle > cone:
			continue
		var score := d * (1.0 + angle * 3.0)
		if score < best_score:
			best_score = score
			best = k
	return best


## 차 진행 방향 forward의 오른쪽(side=1) 또는 왼쪽(side=-1) — 드라이브바이는 옆으로 나간다
static func side_dir(forward: Vector2, side: float) -> Vector2:
	return forward.rotated(PI * 0.5) * side
