서울 거리 프로젝트(/Users/itaegjin/study/game-korea, Godot 4.7 GDScript, 2.5D 사선 투영)를 이어서 작업해 줘.
먼저 CLAUDE.md를 끝까지 읽고 그 규칙을 따른다 (주석·UI 문구 한국어, 콘텐츠 수치는 data/ .tres, 작업 후 CLAUDE.md의 테스트 목록 실행, 요청할 때만 커밋, push 금지, 다른 세션 파일은 커밋하지 않기).

## 지금 상태 (2026-10-23)
- 브랜치 seoul-heli-army. git 저장소 루트는 상위 폴더(/Users/itaegjin/study)라 경로가 game-korea/…로 잡힌다.
- 최근 커밋:
  - c0ae1b4 사람은 죽지 않고 기절 — 구급차·구급대원 들것, 병원 옥상 구급헬기, 구급대원 기절 시 ★4, 배달원·조직원 드롭
  - 82eb7df (다른 세션) M6·M7 묶음
  - d4388b0 들것이 건물을 돌아 인도로 나옴(EmsDispatcher.carry_route·Paramedic.route), 주인공 발밑 진행 방향 원(HeadingRing),
    HUD 다시 디자인(왼쪽 아래 원형 미니맵·오른쪽 위 무기 칸 WeaponPanel·왼쪽 위 미션 상자·오른쪽 아래 라디오 상자), NPC 체력 막대·조직 색 삼각형을 머리 위로(Pedestrian._draw_head_tag·tag_color)
- 커밋 안 된 작업 (이번 세션 것, 테스트 통과): 미니맵 다시 디자인
  - scripts/ui/minimap.gd — 밝은 도로·블록 안 부지, 장소 그림 표(_icon), 목표까지 도로를 따라 노란 GPS 길(Minimap.route, RoadNav.next_cell)·핀·원 밖 화살, 이름표에 남은 거리(distance_text), 보는 쪽 부채꼴, 속도 따라 넓게(SCALE → SCALE_FAST)
  - tests/ui_test.gd — _test_minimap_route
  - CLAUDE.md — HUD 문단의 미니맵 설명
  → 사용자가 커밋을 원하면 이 세 파일만 골라 커밋한다.
- 추적 안 하는 image.png, tools/.scratch_tmp/, NEXT_SESSION_PROMPT.md(이 파일)는 커밋하지 않는다.
- HUD 참고 그림: ~/Desktop/스크린샷 2026-10-23 오전 8.58.48.png (원형 지도 왼쪽 아래, 무기 칸 오른쪽 위, 미션 상자 왼쪽 위, 무전 상자 오른쪽 아래, 차 밑 빨간 고리).

## 알아 둘 것
- police_test ★3 도주 6판 결과는 지금 "3분 생존 2, 체포 4"다. 82eb7df에서 바뀐 것이고(깨끗한 HEAD로 확인) 이번 작업 탓이 아니다. CLAUDE.md·기억에 남은 예전 기준 "생존 1, 체포 5"는 낡았다.
- 테스트 스크립트가 컴파일에 실패해도 "PASS"가 찍힐 수 있다 — 출력의 SCRIPT ERROR를 꼭 본다. 새 class_name을 만들면 먼저 `godot --headless --path . --import`.
- 이 프로젝트는 경고를 오류로 다룬다: 타입 추론 실패(:= 로 Variant), 내장 이름(len·name) 가리기를 피한다.
- 화면 확인: 창 모드 `godot --path . res://tools/screenshot.tscn -- --only=hud` → .screenshots/hud_foot.png·hud_drive.png (미션 상자·라디오 상자·미니맵·발밑 원·머리 위 막대). 구급대는 `--only=ems`.
- 걷기 입력 액션은 steer_left/steer_right/accelerate/brake (move_* 없음). macOS에는 timeout 명령이 없다.
- Stop 훅: 파일을 고친 턴의 마지막 답에는 한국어 커밋 메시지('feat : …' / 'fix : …')와 「다음 작업 추천」(우선순위 순 2~4개, 각각 이유 한 줄)을 넣는다.

## 다음 작업 후보 (우선순위)
1. 미니맵 작업 커밋 여부를 사용자에게 묻고, 원하면 위 세 파일만 커밋.
2. 직접 몰아 보며 미니맵 확대 속도·길 안내가 끊기지 않는지, 발밑 원·머리 위 막대·상자 크기 조정.
3. 일시정지 큰 지도(MapView)에도 같은 장소 그림·목표 길 안내 — 지금은 미니맵과 모양이 다르다.
4. CLAUDE.md의 ★3 기준을 "생존 2, 체포 4"로 고치기.
5. 미션 제목·목표 영어 번역(미션 상자 글이 한국어로만 나온다), 구급차 탈취를 구급 부업과 잇기.

먼저 `git status`와 `git log --oneline -5`로 위 상태가 맞는지 확인하고, 사용자에게 무엇부터 할지 물어봐 줘.
