# Codex 작업 규칙 — 서울 거리 프로젝트

이 프로젝트는 Claude Code와 Codex가 같이 만든다. **작업 전에 `CLAUDE.md`를 끝까지 읽는다** — 프로젝트 규칙(테스트 목록, 2.5D 그리기 규칙, 성능 규칙, 상표 금지, 한국어 주석 등)은 Codex에게도 그대로 적용된다. 이 파일은 그 위에 더하는 "같이 일하는 규칙"이다.

## 1. 맡은 일만 한다
- 사용자가 준 작업 범위 안의 파일만 고친다. 시작할 때 고칠 파일 목록을 먼저 말한다.
- 범위 밖에서 버그를 보면 고치지 말고 보고만 한다 (파일:줄, 무엇이 문제인지).
- 관계없는 코드의 서식·이름·주석을 바꾸지 않는다. 다른 사람이 고친 변경을 되돌리지 않는다.

## 2. 작업 공간을 나눈다
- git 저장소 뿌리는 `/Users/itaegjin/study`(상위 폴더)이고, 다른 프로젝트 파일이 이미 스테이징돼 있다. **`game-korea/` 밖은 절대 건드리지 않는다.**
- 같은 폴더에서 Claude Code가 동시에 일할 수 있다. 사용자가 따로 말하지 않으면 별도 worktree·브랜치에서 일한다:
  ```bash
  git -C /Users/itaegjin/study worktree add /Users/itaegjin/study-codex-<작업이름> -b codex/<작업이름>
  cd /Users/itaegjin/study-codex-<작업이름>/game-korea      # 저장소 뿌리가 study라 게임은 그 안의 game-korea다
  godot --headless --path . --import                         # 새 worktree에는 .godot 캐시가 없다 — 처음에 꼭
  ```
- worktree는 마지막 커밋에서 시작한다. 커밋 안 된 변경은 보이지 않으니, 필요한 코드가 없어 보이면 추측해서 다시 만들지 말고 보고한다.
- `master`에 직접 커밋하지 않는다. push하지 않는다. `git reset --hard`·`git checkout -- <파일>`·`git clean`·`git stash`로 남의 변경을 지우지 않는다.
- 커밋은 `game-korea` 경로만: `git add -- game-korea/...` (또는 game-korea 안에서 `git add -- .`). `git add -A`·`git commit -a` 금지.
- `project.godot` 설정, `data/missions/*.tres`(생성기 `tools/gen_missions.py`로만), 테스트 기대값은 사용자가 요청할 때만 바꾼다.

## 3. Godot 함정 (실제로 터졌던 것)
- **새 `class_name` 파일을 만들면 반드시 먼저** `godot --headless --path . --import`. 안 하면 다른 스크립트가 그 클래스를 못 찾아 `city.gd`가 컴파일되지 않고, 본편이 `current_vehicle on Nil` 오류로 도배된다.
- 타입 추론이 안 되는 식(`var x := [..][k]`)은 타입을 적는다 (`var x: float = ...`). 파스 오류 하나면 그 스크립트를 쓰는 전부가 깨진다.
- 테스트에 문법 오류가 있으면 Godot가 끝나지 않고 멈춘다 — 출력의 `SCRIPT ERROR`부터 본다.
- 지워질 수 있는 노드(터진 차 잔해는 30초 뒤 치워진다 — `Combat._cleanup_wrecks`)를 변수에 들고 있으면 쓰기 전에 `is_instance_valid()`로 확인한다. 치워진 차에 메서드를 부르면 창 모드에서 엔진이 통째로 튕긴다(signal 11).
- `draw_colored_polygon`은 접힌·자기교차 다각형에서 `Invalid polygon`을 낸다. 점이 4개 이하면 `draw_primitive`.

## 4. 성능 규칙 (CLAUDE.md "성능" 절 요약 — 어기면 버벅인다)
- `queue_redraw()`는 `_process`에서만. `_physics_process`에서 부르지 않는다.
- 매 프레임 다시 그리는 것을 늘리지 않는다. 모습이 바뀔 때만 다시 그린다 (차 `Vehicle._look`, 보행자 `_drawn_key` 참고).
- 큰 원·반투명 원은 `FireFx.circle`, 벽 위 작은 사각형은 `_quad`(draw_primitive). `draw_circle`을 많이 겹치지 않는다.
- 그리기·매 프레임 계산을 늘렸으면 `godot --path . res://tools/perf_probe.tscn`으로 전후를 비교하고 숫자를 보고한다 (주행 평균·끊김 수, 폭발 평균·끊김 수).

## 5. 끝내기 전에 반드시 확인
1. `CLAUDE.md`의 "작업 후 반드시 실행" 12개를 전부 돌린다. 하나라도 FAIL이면 끝난 게 아니다.
2. 경찰·차 내구도·피해 수치를 고쳤으면 police_test의 ★3 도주 결과 줄(생존·체포 판 수)을 그대로 옮겨 적는다.
3. 교통 AI를 고쳤으면 `-- --seed=1`, `-- --seed=99`, `-- --seed=7 --chapter=4`로도 traffic_test를 돌린다.
4. 화면이 바뀌면 창 모드로 본다: `godot --path . res://tools/screenshot.tscn -- --only=iso` (출력에 `Invalid polygon`·`SCRIPT ERROR` 없어야 함). 해당 갤러리(건물·차량·사람·불)도 CLAUDE.md에 적힌 대로 본다.
5. 헤드리스 테스트는 렌더 버퍼 한도·창 모드 튕김을 못 잡는다 — 창 모드로 본편을 한 번 켠다: `godot --path . -- --chapter=3`.

## 6. 보고 형식 (작업 끝에 이대로)
```
## 한 일
- (무엇을 왜, 한두 줄씩)

## 바꾼 파일
- path/file.gd — 무엇을

## 확인
- 테스트 12개: 통과/실패 (실패면 출력 그대로)
- ★3 도주: (해당되면 그 줄)
- 창 모드·스크린샷: 무엇을 봤는지
- 성능: (해당되면 전후 숫자)

## 못 한 것·확인 못 한 것
- (솔직하게. 없으면 "없음")

## 범위 밖에서 본 문제
- (파일:줄 — 내용. 없으면 "없음")
```
- 돌리지 않은 테스트를 통과했다고 쓰지 않는다. 추측은 추측이라고 쓴다.
- 새로 알게 된 함정(다음 사람이 또 밟을 것)이 있으면 보고에 적는다. `CLAUDE.md`에 넣을지는 사용자가 정한다.
