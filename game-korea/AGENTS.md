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
1. `CLAUDE.md`의 "작업 후 반드시 실행" 13개를 전부 돌린다. 하나라도 FAIL이면 끝난 게 아니다.
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

## 7. 참고 이미지 · 설계도 경로 (Claude Code · Codex 공용)

사용자가 제공·생성한 분야별 참고 시안과 파츠 명세는 아래 경로에 정리돼 있다. 작업 전에 해당 폴더의 `README.md`와 `manifest.json`을 먼저 읽는다.

### 7.1 성인 NPC 12종 설계도 · 사방 보행 스프라이트 시트 (`output/imagegen/characters/`)
- **명세 문서**: `output/imagegen/characters/README.md`, `docs/17_성인_NPC_능력치_설계.md`, `data/codex/adult_roster.json`
- **통합 시트 및 사방 보행 시트 (`output/imagegen/characters/`)**:
  - `npc_walk_sheet_1_to_6.png` — 1~6번(`civ_f`, `office`, `delivery`, `merchant`, `gang_f`, `boss`) 6프레임 사방 보행·달리기 시트 (앞모습 정지·왼발·오른발 + 뒷모습 정지·왼발·달리기)
  - `npc_walk_sheet_7_to_12.png` — 7~12번(`thug`, `thief`, `police`, `swat`, `firefighter`, `assassin`) 6프레임 사방 보행·달리기 시트
  - `npc_12_turnaround_v1.png` — 12종 2.5D 기립 전신 앞모습(우하단)·뒷모습(우상단) 한 쌍 설계도 시트
  - `npc_parts_spec_v1.png` — `PersonDrawer` 높이 기준(`y = 0` 발끝 ~ `y = -31` 모자), 4방향·걷기(`stride`)·쓰러짐(`knocked`), `NpcType` 파츠 모듈(`outfit`, `hat`, `face`, `prop`) 기준표
  - `adult_roster_v1.png` — 성인 캐릭터 대표 12종 도감 포스터 (원본)
- **1인씩 잘라 둔 개별 PNG 12종 (`output/imagegen/characters/parts/`)**:
  - `01_civ_f.png` (일반 시민), `02_office.png` (직장인), `03_delivery.png` (배달원), `04_merchant.png` (상인), `05_gang_f.png` (조직원), `06_boss.png` (조직 보스), `07_thug.png` (폭력배), `08_thief.png` (도둑), `09_police.png` (경찰), `10_swat.png` (특공대), `11_firefighter.png` (소방관), `12_assassin.png` (암살자)
- **관련 코드·검증**: `scripts/actors/person_drawer.gd`, `scripts/actors/person_rig.gd`, `data/npc/*.tres`, `scenes/ui/adult_codex.tscn`, `godot --path . res://tools/person_gallery.tscn -- --shot` (`.screenshots/person_gallery.png`)

### 7.2 첫 진입 메인 타이틀 화면 및 개별 파츠 (`output/imagegen/title_screen/`)
- **명세 문서**: `output/imagegen/title_screen/README.md`, `output/imagegen/title_screen/parts/manifest.json`
- **통합 설계도 경로**:
  - `output/imagegen/title_screen/title_master_v1.png` — 메인 타이틀 화면 완성 시안 (16:9, 1280×720)
  - `output/imagegen/title_screen/parts_sheet_1_bg_fx.png` ~ `parts_sheet_3_ui_logo.png` — 배경·인물·차량·UI 파츠 분리 시트 3종
- **개별 PNG 파츠 경로 (`output/imagegen/title_screen/parts/`)**:
  - 배경 레이어: `01_bg_skyline.png` (원경 밤하늘·남산타워·한강 다리), `02_bg_neon_street.png` (중경 네온 상가·전경 젖은 아스팔트 노면)
  - 전경 인물 컷아웃: `03_char_protagonist.png` (주인공), `04_char_boss.png` (조직 보스), `05_char_police.png` (경찰관)
  - 추격 차량·헬기: `06_veh_striker.png` (스포츠카 스트라이커), `07_veh_police_front.png` (경찰차 전방), `08_veh_police_rear.png` (경찰차 후방), `09_veh_swat_van.png` (특공대 장갑차), `10_veh_police_heli.png` (경찰 헬기 + 탐조등)
  - 타이틀 로고·UI 스킨: `11_ui_title_logo.png` (「서울 거리」 로고 + 슬로건 배너), `12_ui_menu_skins.png` (네온 메뉴 프레임 + 버튼 선택/기본/비활성 3상태 무지 스킨)
- **연동 시 주의**: 본편 진입(`scripts/main.gd` · `scripts/ui/save_menu.gd`)에 타이틀 메뉴를 연결할 때, 헤드리스 테스트나 자식 노드 마운트(`get_parent() != get_tree().root`), `--chapter=N` 실행 인자에서는 기존 `load_on_start` 조건을 유지해 자동 테스트 12개가 멈추지 않게 한다.

### 7.3 전체 건물 39종 + 공통 파츠 1:1 개별 PNG 경로 (`output/imagegen/buildings_blueprints/README.md`)
- **전체 매핑 문서**: `output/imagegen/buildings_blueprints/README.md`, `output/imagegen/buildings_blueprints/subdivided/manifest.json`
- **① 기본 주거·상업·산업 건물 15종 개별 PNG (`scripts/world/building_model.gd`)**:
  - 앞면 15개: `assets/buildings/assembled_v1/buildings/01_house.png` ~ `15_campsite.png` (`01_house`, `02_villa`, `03_officetel`, `04_apartment`, `05_rowhouse`, `06_gosiwon`, `07_oneroom`, `08_mixed_use`, `09_commercial`, `10_office`, `11_warehouse`, `12_factory`, `13_hanok`, `14_jjokbang`, `15_campsite`)
  - 뒷면 15개: `assets/buildings/assembled_v1/rear/01_house_rear.png` ~ `15_campsite_rear.png`
- **② 기능(특수) 건물 8종 개별 PNG (`scripts/world/special_building.gd` · `special_decor.gd`)**:
  - 폴더: `assets/buildings/special_concepts_v1/parts/`
  - 파일: `01_police.png` (경찰서), `02_hospital.png` (병원), `03_gang_tower.png` (강남 사옥), `04_gang_office.png` (건달파 사무실), `05_gang_dock.png` (밀수단 거점), `06_car_center.png` (정비소), `07_sauna.png` (24시 사우나), `08_convenience.png` (편의점 GO25)
- **③ 랜드마크 6종 및 구성 모듈 9종 개별 PNG (`scripts/world/landmark_building.gd` · `landmark_decor.gd`)**:
  - 전체 부지 6개: `assets/buildings/landmarks_concepts_v1/parts/01_landmark_tower.png` (서울 타워 공원), `02_terminal.png` (고속터미널), `03_market.png` (재래시장), `04_industrial_dock.png` (공단 부두), `05_broadcast.png` (여의도 방송국), `06_checkpoint.png` (다리 검문소)
  - 모듈 앞면 9개: `assets/buildings/landmark_modules_v1/parts_front/01_landmark_tower.png` ~ `09_barrier.png` (`01_landmark_tower`, `02_terminal`, `03_market`, `04_dock_crane`, `05_broadcast`, `06_checkpoint`, `07_container`, `08_dock_warehouse`, `09_barrier`)
  - 모듈 뒷면 9개: `assets/buildings/landmark_modules_v1/parts_rear/01_landmark_tower_rear.png` ~ `09_barrier_rear.png`
- **④ 서울 거리 특수 건물 10종 개별 PNG (`scripts/world/street_building.gd` · `street_decor.gd`)**:
  - 앞·뒤·평면 설계보드 10개: `output/imagegen/street_buildings/parts_modeling/01_church.png` (교회), `02_motel.png` (모텔), `03_gas_station.png` (주유소), `04_nightlife.png` (유흥 건물), `05_parking_tower.png` (주차타워), `06_school.png` (학교), `07_subway.png` (지하철 출입구), `08_fire_station.png` (소방서), `09_finance_tower.png` (금융타워), `10_print_alley.png` (인쇄·공구 골목)
  - 뒷면 시안 10개: `output/imagegen/street_buildings/parts_rear/01_church_rear.png` ~ `10_print_alley_rear.png`
  - 현재 코드 렌더 캡처 10개: `.screenshots/one_CHURCH.png` ~ `.screenshots/one_SUBWAY.png`
- **⑤ 건물 공통 모듈 파츠 16종 개별 PNG (`scripts/world/building_view.gd`)**:
  - 폴더: `assets/buildings/modular_v1/parts/` (`01_wall_brick_windows.png` ~ `16_water_tank.png`)
- **검증 명령**:
  - 기본 15종: `godot --path . res://tools/building_gallery.tscn -- --shot` (개별 비교 시 `--ids=HOUSE,HANOK` 등)
  - 기능 8종: `godot --path . res://tools/building_gallery.tscn -- --shot --set=special`
  - 랜드마크: `godot --path . res://tools/building_gallery.tscn -- --shot --set=landmarks`
  - 거리 10종: `godot --path . res://tools/building_gallery.tscn -- --shot --set=street`

### 7.4 기타 월드 · 차량 · 도로 참고 이미지 경로
- **차량 27종**: `docs/12_차량_이미지.md`, `docs/images/vehicles/`, `assets/vehicles/reference_v1/`
- **도로 재질**: `output/imagegen/roads/road_design_v1.png`
