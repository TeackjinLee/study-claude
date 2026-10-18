# 서울 거리 프로젝트 (임시 작업명) — 작업 규칙

Godot 4.7 / GDScript / 2D 탑다운. 기획은 `docs/`, 단계 계획은 `docs/08_로드맵.md`.

## Codex 작업 인계 (2026-10-11)

Codex에게 맡길 때의 규칙(작업 범위·worktree 분리·끝내기 전 확인·보고 형식)은 `AGENTS.md`에 있다. Codex가 넘긴 결과는 그 보고 형식대로 받아, 테스트를 다시 돌려 확인한 뒤 합친다.

사용자 요청으로 별도 2.5D 사선 투영 샘플을 추가했다. 본편 물리는 기존 2D 그대로이며 진입점은 `tools/isometric_sample.tscn`이다. 변경 구조·진행 상태·표시 미연결 항목·확인 범위는 `docs/11_Claude_인계_2.5D.md`를 참고한다. M6 완료나 최종 아트 완료로 취급하지 않는다.

- 에셋 파일 없이 코드로 그린다 (M7 아트 단계 전까지). 예외: 타이틀 화면(`assets/title/`)과 인물 스프라이트(`assets/characters/`)는 사용자가 준 그림을 쓴다.
- 차종·NPC·무기 등 콘텐츠 수치는 `data/` 리소스(.tres)에 둔다. 코드에 하드코딩하지 않는다.
- 물리·AI 계산은 노드 없는 클래스(예: `VehicleMotor`)로 분리해 헤드리스 테스트가 가능하게 한다.
- 실존 상표(현대·기아·GS25 등)는 쓰지 않는다 → `docs/09_법적_리스크.md`의 가칭 사용.
- 주석·UI 문구는 한국어.
- 정식 제목은 미정. 문서와 새 작업물의 작업명은 ‘서울 거리 프로젝트’이며, GTA2·한국판 GTA2를 제품명으로 쓰지 않는다. 참고 이미지별 사용 범위와 M7 제작 기준은 `docs/10_비주얼_제작기준.md`를 따른다.
- M6 콘텐츠 확장은 Claude Code가 구현했다(현황은 `docs/08_로드맵.md` M6 절). 다리·고가 높이 레이어는 아직 없고, M5 외부 플레이테스트 게이트도 통과 기록이 없다. M7 비주얼 기준 문서 작성은 에셋 구현 완료나 M6 완료를 의미하지 않는다.

## 작업 후 반드시 실행

```bash
godot --headless --path . --import
godot --headless --path . res://tests/drive_test.tscn
godot --headless --path . res://tests/smoke_test.tscn
godot --headless --path . res://tests/m1_test.tscn
godot --headless --fixed-fps 60 --path . res://tests/traffic_test.tscn   # 약 2분 30초 걸린다. --fixed-fps 60 필수
godot --headless --fixed-fps 60 --path . res://tests/police_test.tscn    # 약 1분 30초
godot --headless --fixed-fps 60 --path . res://tests/weapon_test.tscn
godot --headless --fixed-fps 60 --path . res://tests/vehicle_damage_test.tscn
godot --headless --fixed-fps 60 --path . res://tests/mission_test.tscn   # 약 30초
godot --headless --fixed-fps 60 --path . res://tests/mvp_test.tscn
godot --headless --fixed-fps 60 --path . res://tests/m6_test.tscn
godot --headless --fixed-fps 60 --path . res://tests/iso_test.tscn
godot --headless --fixed-fps 60 --path . res://tests/title_test.tscn
```

본편 화면은 2.5D 사선 투영이다 (물리는 2D 그대로). 수식은 `scripts/world/iso_view.gd` 한 곳에 있다.
- 카메라(`ChaseCamera`)는 Camera2D가 아니다 — 화면 변환을 직접 정한다. 화면 가운데가 필요하면 `ChaseCamera.current_cam()`을 쓴다 (`get_camera_2d()`는 null).
- 노드가 높이를 그리려면 `IsoView.lift(h)`(월드 오프셋)만큼 옮겨 그린다. 글자·서 있는 사람은 `IsoView.screen_frame()` 안에서 그린다.
- 다리 위는 땅이 떠 있다: 바닥에 서는 것을 새로 그리면 `IsoView.ground(위치)`만큼 더 올린다 (물리는 평면 그대로).
- 그리는 순서는 `z_index = IsoView.z_of(위치)` (z_as_relative = false). 바닥 것(도로·자국·표시)은 z 100 미만에 둔다.
- 새로 그리는 것은 `IsoView.enabled`가 false(F9, 위에서 보기)일 때도 깨지지 않게 한다.
- 도보 테스트에서 월드 방향으로 걸어야 하면 `player.screen_walk = false`.

테스트 스크립트에 문법 오류가 있으면 Godot가 끝나지 않고 멈춘다 — 오래 걸리면 출력의 `SCRIPT ERROR`부터 본다.

지도(구역·강·다리)는 `scripts/world/city_map.gd`와 `data/districts/*.tres`가 정한다. 블록·교차로 좌표에 음수가 있다 —
"교차로 없음"은 `(-1, -1)`이 아니라 `RoadNav.INVALID`로 나타낸다. 장(Chapter)마다 열린 구역이 다르니
도로가 이어졌는지는 `LaneGraph.connected(cell, d)`(열린 도로)로 본다.

미션은 `tools/gen_missions.py`가 만든다(`python3 tools/gen_missions.py data/missions`). .tres를 손으로 고치지 말고 생성기를 고친다.

미션 .tres의 지점은 월드 좌표다. 지점을 바꾸면 mission_test가 건물 안·강물·맵 밖·그 장에 잠긴 구역인지 검사한다. 운전 미션의 제한 시간은 mission_test의 봇 기록 출력을 보고 정한다(봇이 제한의 65% 안에 끝내야 한다).
기본 실행은 대표 운전 미션 6개만 봇이 몬다 — 미션을 고쳤으면 `-- --all-drives`로 운전 미션 전부(23개)를 돌린다.

경찰·추격·차 내구도·피해 수치를 고쳤으면 police_test의 ★3 도주 결과(생존·체포 판 수)가 "가능하되 쉽지 않다"에서 벗어나지 않았는지 본다.
경찰 결정에 쓰는 `rng`는 추격·봉쇄 전용이다. 발포처럼 자주 뽑는 무작위는 따로 둔다 — 같은 rng를 쓰면 도주 결과가 나비효과로 통째로 바뀐다.

교통 AI를 고쳤으면 시드 몇 개로도 돌린다 (`-- --seed=1`, `--seed=99` …). 시드 하나만 통과하는 건 우연일 수 있다.
모든 구역이 열린 4장에서도 한 번 돌린다 (`-- --seed=7 --chapter=4`). 길이 80px 넘는 차는 일반 교통에 넣지 않는다(회전할 때 뒤꽁무니가 휘어 정지선 차를 친다).
(zsh에서 `a="-- --seed=1"; godot ... $a`처럼 변수로 넘기면 한 덩어리로 넘어가 시드가 무시된다 — 인자를 직접 쓴다.)

본편을 특정 장부터 해 보려면 `godot --path . -- --chapter=N`이다. 그 장까지 열린 구역으로 시작하고 저장 불러오기는 띄우지 않는다. 다리는 2장부터 동쪽 둘, 4장에 서쪽까지 열린다. 이 인자는 Main이 루트에 붙은 본편 실행에서만 읽는다(테스트의 `--chapter`와 따로).

화면이 바뀌는 작업이면 `godot --path . res://tools/screenshot.tscn` 후 `.screenshots/*.png`를 확인한다. 2.5D만 빨리 보려면 `-- --only=iso`.
건물 모양(`building_model.gd`·`building_view.gd`·`special_building.gd`·`special_decor.gd`)을 고쳤으면 `godot --path . res://tools/building_gallery.tscn -- --shot`으로 15종을, `-- --shot --set=special`로 기능 건물 8종을 본다. 새 그림에서 `Invalid polygon` 오류가 나지 않는지 출력도 본다. 벽 위 작은 사각형은 `_quad`(draw_primitive)로 그린다 — 도시 전체에서 `draw_colored_polygon`을 수만 번 부르면 렌더 버퍼 한도를 넘어 창 모드 실행이 멈춘다(헤드리스 테스트로는 안 잡힌다. 창 모드 `screenshot.tscn -- --only=iso`로 본다).
켜질 창과 간판은 같은 조각을 한 번 더 세운 불빛 조각(`BuildingView.lights`)이 그린다. 밤에도 밝게 남고, 창은 시각에 따라 하나둘 켜진다(`DayNight.lights_on`). 본 조각은 창을 모두 꺼진 유리로 그린다. 창·간판을 고쳤으면 `iso_intersection`(밤)·`iso_day`·`iso_dusk`로 본다(docs/11). 간판은 `BuildingView._board`(금속판·글씨, 색은 `SIGN_STYLES`)로 그린다. `assets/signs` 그림은 쓰지 않는다.
랜드마크(`landmark_building.gd`·`landmark_decor.gd`, docs/15)는 부지 전체가 아니라 바닥에 선 덩어리만 막는다 — 공터(잔디·골목·승강장)는 바닥 그림이고 사람·차가 다닌다. 덩어리를 더하면 `iso_test`의 랜드마크 공터 검사(보행 길이 막히지 않는가)를 본다. 공중 덩어리는 h0 > 0으로 두면 막지 않는다. 등·전구의 밤 불빛은 불빛 조각이 `LandmarkDecor.glow`로 그린다 — `landmark_city_preview.tscn -- --night`로 본다.
거리 건물 10종(`street_building.gd`·`street_decor.gd`, docs/16)은 `building_gallery.tscn -- --shot --set=street`(한 종씩 `--ids=MOTEL`)로 본다. 밑의 덩어리를 덮는 캐노피·내민 윗층은 `Piece.z_at_end = true`, 긴 담은 토막으로 나눈다 — 아니면 그리는 순서가 꼬여 옆 지붕 위로 올라온다. 바닥 무늬 점을 `hash01`로 x·y 이어 뽑으면 대각선 줄이 된다(`StreetBuilding._h`).
사람 모습(`person_drawer.gd`·`data/npc`의 outfit·hat·face·prop)을 고쳤으면 `godot --path . res://tools/person_gallery.tscn -- --shot`으로 전 종 앞·뒤를 크게 본다. 설계도 그림과 맞춰 볼 때는 `--ids=office,boss`로 몇 종만 더 크게 본다. 모습 값은 데이터에 두고, 보행자 rng를 더 뽑지 않는다(`look_seed`).
인물(2.5D 화면)은 `PersonRig`가 그린다. `assets/characters/<id>.png`(4열 서 있기·걷기 A·걷기 B·달리기 × 2행 앞↘·뒤↗, 칸 96×112, 발끝 (48,108))가 있으면 그 그림을, 없으면 관절 그림(몸 기준 3차원 관절 점을 보는 방향으로 돌려 찍는다)을 쓴다. 그림 원본은 제미나이가 그린 `output/imagegen/characters/NN_<id>.png`이고 `python3 tools/prepare_character_sprites.py [--debug]`로 다시 뽑는다(테두리 플러드필로만 배경을 지워 검은 옷이 뚫리지 않게, 시트 안에서 같은 배율·같은 발끝). 새 그림 요청 규칙은 `output/imagegen/characters/GEMINI_PROMPT_v2.md`. `person_gallery.tscn -- --sheet`(성인 12종 앞·뒤), `-- --rig [--ids=...]`(8방향 걷기·달리기·쓰러짐), `--code-rig`면 그림 대신 관절 그림. 그림을 줄여 그리므로 사람 노드는 `texture_filter = LINEAR`. 그림은 8열(0 서 있기·1 걷기 A·2 걷기 B·3 달리기·4 걷기 모음·5 달리기 A·6 달리기 B·7 달리기 모음)이다. 걷기는 [1·4·2·4], 달리기는 [5·7·6·7]을 돈다 — 제미나이 그림의 A·B가 같은 다리인 경우가 많아, 다리를 모은 칸을 사이에 넣어 다리가 벌어졌다 모이게 한다. 모음 칸은 다듬기 도구가 걷기 A·달리기 A의 팔·다리를 몸 가운데로 모아 만든다(팔이 흔들렸다 붙는다)(서 있기 칸은 다른 그림에서 와서 방향·옷이 달라 쓰지 않는다). 걷기·달리기 두 장을 `NN_<id>_walk.png`·`NN_<id>_run.png`(2열×2행)로 따로 받으면 그것으로 바꾼다.
걷기·달리기 한 바퀴 8장(`NN_<id>_walk_front/back.png`·`_run_front/back.png`, 각 4열×2행)을 받으면 시트 9~16열(걷기)·17~24열(달리기)에 붙고, 게임은 모음 칸 대신 8장을 차례로 넘긴다. 코덱스 요청은 `output/imagegen/characters/CODEX_WALK8_LEGS_PROMPT.md` — 생성기가 "반대 다리"를 못 지켜서, 인물 오른쪽 발목에 초록(#00FF00) 띠를 그리게 하고 `prepare_character_sprites.py --check-legs`로 1번 칸 앞·5번 칸 뒤인지 검사한다(띠는 다듬을 때 신발 색으로 지운다. 두 다리가 같은 색이라 어느 다리가 나갔는지 안 보여서, 띠가 없는 먼 다리를 어둡게 칠한다 — `shade_far_leg`). 주인공이 이 방식으로 통과했다. 한 바퀴 원본은 4×2(8장)·4×4(16장) 모두 받고(캔버스 비율로 판단), 게임 시트에는 16장씩 들어간다(걷기 8~23열, 달리기 24~39열). 자세·방향이 튀는 칸은 같은 이름의 `.skip.txt`(예: `00_player_run_front.skip.txt`에 `2 3 9`)에 적으면 빼고 남은 장으로 채운다. 정방향 4방향 걷기(`NN_<id>_walk_dir4.png`, 8열×4행 앞·뒤·오른쪽·왼쪽, 줄마다 `_walk_dir4_<s|n|e>.png` 4×4 16장으로 바꿔 끼울 수 있다, 투명 PNG는 그 투명도를 그대로 쓴다) 또는 12장 한 바퀴 `NN_<id>_walk12_dir4.png`(12열×4행 앞·왼쪽·오른쪽·뒤, 있으면 앞·뒤·옆 걷기를 모두 이걸로 — 팔·다리 틈의 어두운 마젠타까지 그림 전체에서 배경색 섞임을 푼다 `unmix_key`)를 받으면 `assets/characters/<id>_dir4.png`(앞·뒤·옆 3행, 0열 서 있기 + 걷기 24장 [+ `_run_dir4` 달리기 24장], 12장 원본은 두 번씩·8장 원본은 세 번씩 고르게)가 생기고, 게임은 서 있기·걷기·달리기를 이걸로 그린다(`PersonRig._draw_dir4`, 쓰러짐만 예전 시트). 왼쪽 줄은 생성 그림이 얼굴만 돌아간 경우가 있어 오른쪽 줄을 뒤집어 쓴다. 방향은 화면 진행 각도로 고르고 직전 방향을 14° 더 봐 준다(`DIR4_HOLD`) — 사선 3/4 그림은 칸마다 보는 방향이 달라 뒤로 걸을 때 좌우로 휙휙 돌아 보였다. 지금은 주인공만 있다.
8방향 걷기(`NN_<id>_walk8_<방향>.png`, 방향 e·se·s·sw·w·nw·n·ne, 각 4열×4행 16장)를 받으면 `assets/characters/<id>_dir8.png`(8행, 0열 서 있기 + 걷기 16장, 칸 128×112) + `.json`(받은 방향 목록)이 생기고, 게임은 4방향보다 먼저 이걸 쓴다(`PersonRig._draw_dir8`). 없는 방향은 좌우 짝을 뒤집고(↙ ← ↘), 그것도 없으면(↓·↑) 가장 가까운 방향을 쓴다. 경계에서는 직전 방향을 12° 더 지킨다. 한 장짜리 8방향 시트 `NN_<id>_walk<N>_dir8.png`(N열×5행 ↓·↙·←·↖·↑, 줄마다 한 바퀴 N장 — walk24·walk12, 초록·마젠타 배경은 `unmix_key`로 그림 전체에서 섞임을 푼다)도 받는다 — 있으면 방향별 시트를 덮어쓰고, `.json`의 `frames`(N)를 게임이 읽는다(없으면 16). 옷이 배경과 같은 계열인 인물(초록 배경에 국방색 재킷 civ_f·카키 바지 merchant·형광 반사띠 firefighter·초록 티셔츠 foreigner·형광 조끼 traffic_cop·얼룩무늬 soldier·올리브 조끼 police_heli)은 `KEEP_TINT`에 넣어 배경 가장자리와 짙은 틈만 푼다. 지금은 player(walk24)·civ_f·office·delivery·merchant·gang_f·boss·thug·robber·police·swat·firefighter·assassin(walk12)가 한 장 시트다(↘·→·↗는 뒤집기). civ_m·thief·homeless·foreigner·gang_oldtown·paramedic·police_heli는 walk8 8행 시트로 8방향을 모두 그림대로 쓴다(gang_smuggler·traffic_cop·soldier·flyer는 줄이 한 칸씩 밀려 `.rows.txt`로 방향을 다시 적고 ↗(flyer는 →)는 뒤집기)(코덱스 요청은 `CODEX_WALK8_DIR8_MOTION_PROMPT.md` — 참고 동작 `reference/walk8_motion_ref.png`의 관절 움직임 + `reference/npc_ref/` 인물 그림). 달리기 시트 `NN_<id>_run<M>_dir8.png`가 있으면 걷기 다음 칸에 붙고(`.json`의 `run_dirs`·`run_frames`, 크기는 머리 폭으로 걷기에 맞춘다) 게임이 달리기를 그것으로 그린다 — 한 장 시트 13종 모두와 walk8 인물 11종(civ_m·thief·homeless·foreigner·gang_oldtown·gang_smuggler·traffic_cop·paramedic·soldier·flyer·police_heli)(8방향 모두 8장, 8행 시트 ↓ ↘ → ↗ ↑ ↖ ← ↙, `.rows.txt`로 줄 방향을 적는다. paramedic은 구급 가방이 빠진 칸을 `.rows.txt`에서 뺐다). 생성 그림은 ↓ 줄을 20%쯤 작게 그리곤 해서 달리기는 줄마다 키를 시트 가운데값에 맞춘다(`RUN_ROW_K`). gang_gangnam(20)·bus_driver(27)는 달리기 시트만 있다 — 걷기 시트가 오면 붙는다. 칸을 꽉 채워 그려 모자가 윗줄로 넘어간 시트(줄 간격이 고르지 않다 — 그대로 자르면 머리가 잘린다)는 `python3 tools/regrid_sheet.py 원본 결과 열 줄`로 덩어리마다 칸을 다시 정해 고른 160×240 칸으로 옮긴다(civ_m 달리기, 원본은 `reference/raw/`). `KEEP_TINT` 인물의 달리기는 다리 틈에 남는 짙은 초록을 한 번 더 걷는다(`_despill`, 형광 반사띠가 있는 `NEON`(firefighter)은 뺀다). 줄 수는 `.rows.txt` 줄 수를 따르고(없으면 5행), 머리를 크게 그린 그림은 몸이 작아지므로 달리기 키를 걷기 키의 85~92%(`RUN_H_RANGE`) 안으로 당긴다. 넘어짐 시트 `NN_<id>_fall<K>_dir8.png`(8행 × K장, 서 있기 → 엎드림)가 있으면 달리기 다음 칸에 붙고(`.json`의 `fall_dirs`·`fall_frames`·`fall_col`, 누운 자세는 옆 칸까지 길게 그려져 좌우로 넉넉히 읽고 덩어리 가운데를 칸 가운데에 맞춘다) 주인공이 쓰러지면 `DIR8_FALL_FRAME`(0.09초)마다 넘기다 마지막 칸에서 멈춘다(`_draw_dir8_fall`, 보행자는 예전처럼 눕힌 그림). 그림자는 누울수록 그 칸 그림이 차지한 폭·깊이에 맞춘 부드러운 타원(`_soft_shadow`)과 몸 둘레 그늘이다. `person_gallery.tscn -- --rig --fall`로 본다. 주먹 콤보 시트 `NN_<id>_combo<P>_dir8.png`(8행 × 12장: 싸움 자세 · 잽 · 스트레이트 · 훅 · 싸움 자세)가 있으면 넘어짐 다음 칸에 붙고(`.json`의 `punch_dirs`·`punch_frames`·`punch_col`, 크기는 걷기 키의 `PUNCH_H`배, 가로는 몸통 가운데) 주인공이 주먹을 지를 때마다(`Player.punch`, `COMBO_GAP` 0.7초 안에 이어 지르면) 잽 → 스트레이트 → 훅 토막(`PersonRig.PUNCH_SEGS`)을 `PUNCH_FRAME`(0.07초)마다 넘긴다. `-- --rig --punch`로 본다. `.rows.txt` 줄 끝에 `>방향 칸`(예: `s 1-7 >se 8-12`)을 붙이면 그 칸은 도는 장면(`.json`의 `turns`)이다. 주인공은 보이는 방향을 목표까지 45°씩 `DIR8_TURN_STEP`(0.07초)마다 돌리고, 달리며 도는 장면이 있는 두 방향 사이를 오가면 그 장면을 넘긴다(`_dir8_turn`, 지금 주인공 시트에는 도는 장면이 없다 — 예전 12장 시트는 `output/imagegen/characters/reference/old_player_run12/`). 보행자는 걸음 박자가 바뀔 때만 다시 그려 중간 방향에서 멈출 수 있어 바로 바꾼다. 줄 배치가 다르거나 튀는 칸이 있으면 같은 이름의 `.rows.txt`에 줄마다 `방향 [칸]`(예: `s 1-7`, `n 1-12,14`, 안 쓰는 줄은 `-`)을 적는다. 달리기 그림이 없으면 정방향 4방향 그림의 달리기를(`_dir4_has_run`), 그것도 없으면 걷기를 빠르게 넘긴다. 4방향·8방향 칸(128px)과 기본 시트 칸(96px)을 섞지 않는다.
인물 모션 편집기 `tools/motion_editor.html`(브라우저로 파일을 바로 연다)는 그림을 넣어 칸으로 자르고, 방향·동작(서 있기·걷기·달리기)마다 장면 순서를 넣고·빼고·바꾸며 방향키(Shift 달리기)로 미리 본다. 다듬기 규칙(배경·초록 띠·시트마다 같은 배율·발끝·몸통 무게중심)은 `prepare_character_sprites.py`와 같고, "게임 8방향 내보내기"는 `<id>_dir8.png`+`.json`을 같은 형식으로 낸다(assets/characters/에 넣는다). 작업은 브라우저 저장소에 남고 "작업 저장"은 그림까지 담은 .json이다. 장면 줄·칸 모음에서 Shift(사이를 모두)·⌘(하나씩)로 여러 장을 골라 한꺼번에 옮기기·뒤집기·복제·빼기·넣기를 한다. "게임 그림 보기" 탭(`motion_editor.html#game`)은 `assets/characters/*_dir8.png`를 게임과 같은 규칙(방향 고르기·뒤집기·걸음 박자·주인공 45° 돌기·넘어짐·주먹 콤보·`body_scale`)으로 돌린다 — 목록은 `tools/motion_game_index.js`(`python3 tools/gen_motion_index.py`, 그림을 다시 뽑으면 같이 만든다. 파일로 연 페이지는 .json을 못 읽어서 스크립트로 둔다).
(몸 조각 방식 `PersonRig.draw_parts`·`tools/prepare_character_rig.py`도 남아 있지만 이질적이라 쓰지 않는다 — 조각 그림이 없으면 건너뛴다.)
조준: 쏘기 키(Ctrl·J)·패드는 바라보는 쪽 부채꼴 자동 조준, 마우스를 움직이거나 누르면 커서 쪽으로 정확히 쏜다(`PlayerWeapons.mouse_aim`·`screen_dir`). 2.5D에서는 서 있는 사람이 위로 그려져 몸을 누르면 바닥 점이 그 사람 뒤라, 커서가 사람 그림(발끝~머리) `AIM_PICK` 안이면 그 사람을 겨눈다. 마우스로 겨누면 `AIM_HOLD`(0.35초) 동안 걸어도 커서 쪽을 본다(`Player.face`), 드라이브바이는 커서가 있는 옆으로 `DRIVE_BY_SPREAD`까지 튼다. 일반 시민 8종은 `walk_scale` 0.9로 조금 느리게 걷는다(도망은 그대로).
차는 부딪힌 곳이 찌그러진다(`Vehicle.dents`, 그림만 — 충돌 모양은 그대로). 모형 꼭짓점은 모서리에만 있어 면 가운데는 팬 자국으로 그린다. 체력이 20% 아래면 불이 나고(`on_fire`, 아직 탈 수 있다) 체력이 타들어가 0이 되면 `burning` → 폭발이다(수치는 `DamageModel`).
불꽃·연기·불씨·불빛·그을음은 `FireFx`(scripts/fx/fire_fx.gd) 한 곳에서 그린다 — 차 화재 단계(`Vehicle._draw_damage`, 잔해 `wreck_age`), 폭발(`Combat._draw_blast`), 땅 불(`Fires`)이 같이 쓴다. 고쳤으면 `godot --path . res://tools/fire_gallery.tscn -- --shot`으로 단계별로 본다.
타이틀 화면(`title_screen.gd`·`title_backdrop.gd`, 시안은 `output/imagegen/title_screen`)이 `run/main_scene`이다 — 켜면 타이틀이 먼저 나오고, 헤드리스·`--chapter=N` 실행은 타이틀 없이 바로 본편이다(`TitleScreen.auto_skip`). 고르면 `Main.entry`("new"·"load")·`entry_slot`에 적고 본편 장면으로 넘어가며, Main이 `_ready` 끝에서 읽어 불러온다(읽으면 비운다 — 타이틀을 거치지 않은 직접 실행·테스트는 예전 `load_on_start` 그대로). 배경·차·인물·로고·메뉴 스킨은 `assets/title/`의 그림이다 — 원본(`output/.../parts`)을 고치면 `python3 tools/prepare_title_assets.py`로 다시 뽑는다(검은 배경 투명화·오려내기·줄이기). 글자·간판 깜박임·경광등·빗줄기는 코드(`TitleBackdrop`). `tools/title_preview.tscn`로 본다(`-- --fake-saves`, `--modal=slots`·`codex`). 경광등 교차 주기는 0.25초(`Vehicle._siren_phase`, `TitleBackdrop.SIREN_MS`).
성능: 그리는 것·매 프레임 도는 것을 늘렸으면 `godot --path . res://tools/perf_probe.tscn`(봇이 차를 몰고 근처 차를 태워 터뜨린다)으로 주행·폭발 프레임 시간과 끊김 수를 본다. `-- --uncapped`는 프레임 제한 없이 일의 양, `--ablate`·`--burn-ablate`는 종류별로 꺼 보며 몫, `--profile`은 스크립트별 시간, `--census`는 그리기 호출·도형 수.
- 본편은 화면을 물리(60틱)에 맞춰 60프레임으로 묶고, 늦은 프레임에 물리를 3틱까지만 몰아 돈다(`Main.limit_frame_rate`, 헤드리스 테스트는 그대로).
- queue_redraw는 `_process`에서 부른다. `_physics_process`에서 부르면 틱마다 그려, 느려질수록 한 프레임에 여러 번 그리는 악순환이 된다.
- 차 모형(약 0.8ms)은 모습(`Vehicle._look`, 방향은 `ROT_STEP`마다)이 바뀔 때만 다시 그리고, 불·연기는 위층(`Vehicle._fx`)이 따로 매 프레임 그린다. 보행자도 걸음 24단계(그림 한 칸이 바뀌는 박자보다 촘촘하게)·방향이 바뀔 때만 그린다.
- 큰 원·반투명 원은 `FireFx.circle`(원 그림 한 장)로 그린다 — `draw_circle`은 수십 각형이라 많이 겹치면 불난 차 한 대에 2ms가 넘는다.
- 바닥 청크는 블록 하나씩(`City.CHUNK = 1`) 세 겹(아스팔트·인도·차선)이다 — 청크가 크면 화면에 조금만 걸쳐도 화면 밖 블록까지 매 프레임 그린다.
차량 모형(`vehicle_model.gd`)을 고쳤으면 `godot --path . res://tools/vehicle_gallery.tscn -- --shot`으로 28종 앞·뒤를 크게 본다. 부품이 늘면 traffic_test 시간도 본다(모습이 바뀔 때만 다시 그리지만, 도는 차는 매 프레임 그린다).
