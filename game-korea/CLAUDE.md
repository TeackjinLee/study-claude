# 서울 거리 프로젝트 (임시 작업명) — 작업 규칙

Godot 4.7 / GDScript / 2D 탑다운. 기획은 `docs/`, 단계 계획은 `docs/08_로드맵.md`.

## Codex 작업 인계 (2026-10-11)

사용자 요청으로 별도 2.5D 사선 투영 샘플을 추가했다. 본편 물리는 기존 2D 그대로이며 진입점은 `tools/isometric_sample.tscn`이다. 변경 구조·진행 상태·표시 미연결 항목·확인 범위는 `docs/11_Claude_인계_2.5D.md`를 참고한다. M6 완료나 최종 아트 완료로 취급하지 않는다.

- 에셋 파일 없이 코드로 그린다 (M7 아트 단계 전까지).
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
랜드마크(`landmark_building.gd`·`landmark_decor.gd`, docs/15)는 부지 전체가 아니라 바닥에 선 덩어리만 막는다 — 공터(잔디·골목·승강장)는 바닥 그림이고 사람·차가 다닌다. 덩어리를 더하면 `iso_test`의 랜드마크 공터 검사(보행 길이 막히지 않는가)를 본다. 공중 덩어리는 h0 > 0으로 두면 막지 않는다.
사람 모습(`person_drawer.gd`·`data/npc`의 outfit·hat·face·prop)을 고쳤으면 `godot --path . res://tools/person_gallery.tscn -- --shot`으로 전 종 앞·뒤를 크게 본다. 모습 값은 데이터에 두고, 보행자 rng를 더 뽑지 않는다(`look_seed`).
차량 모형(`vehicle_model.gd`)을 고쳤으면 `godot --path . res://tools/vehicle_gallery.tscn -- --shot`으로 28종 앞·뒤를 크게 본다. 부품이 늘면 traffic_test 시간도 본다(모습이 바뀔 때만 다시 그리지만, 도는 차는 매 프레임 그린다).
