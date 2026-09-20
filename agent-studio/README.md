# AI Agent Studio

명령을 입력하면 여러 Claude 에이전트가 역할을 나눠 일하고, 그 과정을 브라우저에서 실시간으로 볼 수 있는 대시보드입니다.

- **백엔드:** NestJS 12 (ESM) + Socket.IO
- **에이전트:** Claude Agent SDK (`@anthropic-ai/claude-agent-sdk`)
- **화면:** `public/index.html` 한 파일 (빌드 없음)

## 실행 방법

Node.js 22 이상이 필요합니다.

```bash
npm install
cp .env.example .env      # ANTHROPIC_API_KEY 입력
npm run dev               # 개발 모드 (코드 수정 시 자동 재시작)
```

브라우저에서 http://localhost:3000 을 엽니다.

API 키는 [Claude Console](https://platform.claude.com)에서 발급합니다. API 사용량은 Claude 구독(Pro/Max)과 별도로 과금되니, Console에서 사용 한도를 먼저 설정해 두세요.

## 동작 방식

```
브라우저 ──command──▶ AgentGateway ──▶ AgentRunnerService ──query()──▶ Claude Agent SDK
   ▲                                                                        │
   └──────── agent-event ◀── MessageMapper ◀──── SDK 메시지 스트림 ◀─────────┘
```

1. 화면에서 명령을 보내면 서버가 `query()`로 **총괄 에이전트**를 실행합니다.
2. 총괄 에이전트는 `Agent` 도구로 서브에이전트(게임 기획, 게임플레이, 월드, 그래픽/사운드, QA, 문서, 리서치)에게 일을 나눠줍니다.
3. SDK가 보내는 메시지를 `MessageMapper`가 화면용 이벤트로 바꿔 Socket.IO로 보냅니다.
   - 서브에이전트 호출(`Agent` 도구) → 카드 상태 변경
   - `parent_tool_use_id` → 어느 서브에이전트의 도구 사용인지 구분
   - `TodoWrite` / `TaskCreate` → 작업 계획과 전체 진행률
   - `Write` / `Edit` / 테스트 명령 → 결과 미리보기
   - `result` 메시지 → 최종 요약, 비용, 턴 수
4. 새로고침하거나 재접속하면 서버에 쌓인 이벤트로 화면을 복원합니다.

## 권한과 안전장치

에이전트는 **이 컴퓨터에서 실제로 파일을 쓰고 명령을 실행**합니다. 그래서 다음 장치를 두었습니다.

- 서버는 `127.0.0.1`에만 열립니다. 같은 네트워크의 다른 기기에서는 접속할 수 없습니다.
- 모든 작업은 작업 폴더(기본 `WORKSPACE_DIR` = `./workspace`)에서 시작합니다. 대시보드 상단의 폴더 칩을 누르거나 `/workspace <경로>`로 다른 폴더를 지정할 수 있습니다 (`/workspace default`로 되돌림).
- 읽기, 검색, 웹 조사, 서브에이전트 호출은 자동으로 허용합니다.
- `PERMISSION_MODE=acceptEdits`(기본값)이면 작업 폴더 안의 파일 수정은 자동 허용합니다. `default`로 바꾸면 파일 수정도 매번 확인합니다.
- **명령 실행(Bash)은 화면에서 승인**해야 합니다. 승인 배너의 `<도구> 계속 허용`은 그 도구를, `이번 실행 모두 허용`은 모든 도구를 **이번 명령이 끝날 때까지만** 자동 허용하고, 다음 명령에서는 다시 묻습니다.
- 명령 하나당 비용 한도(`MAX_BUDGET_USD`, 기본 2달러)를 넘으면 자동으로 멈춥니다.
- 중지하기를 누르면 대기 중인 승인 요청은 모두 거부 처리됩니다.
- 배포 에이전트는 로컬 빌드와 실행 확인만 하도록 지시되어 있습니다.

그래도 처음에는 중요한 파일이 없는 빈 폴더를 작업 폴더로 쓰는 것을 권장합니다.

## 폴더 구조

```
src/
  main.ts                        서버 시작 (로컬 주소에만 열기)
  config.ts                      .env 설정 읽기
  app.module.ts                  정적 파일(public) + AgentModule
  agent/
    agents.config.ts             서브에이전트 정의와 총괄 에이전트 지시문  ← 역할 바꿀 때 여기
    agent-runner.service.ts      query() 실행, 중지, 승인 대기
    message-mapper.ts            SDK 메시지 → 화면 이벤트 변환
    agent.gateway.ts             Socket.IO 입출력
    ui-events.ts                 화면 이벤트 타입
public/index.html                대시보드
workspace/                       에이전트 작업 폴더
```

## 기본 에이전트 (GTA2 게임 프로젝트용)

기본 팀은 Godot 4 / GDScript 2D 탑다운 게임 **GTA2** 프로젝트(에셋 파일 없이 전부 코드로 그리는 제약)에 맞춰 구성돼 있습니다.
공통 규칙(건드리지 말 것, 헤드리스 검증 명령 등)의 원본은 작업 폴더의 `AGENTS.md`이고, 총괄은 시작할 때 이 파일을 읽어 서브에이전트에게 전달합니다.

| id | SDK 이름 | 역할 | 방 | 담당 |
|---|---|---|---|---|
| `plan` | `game-designer` | 게임 디자이너 | 회의실 | 조작감 기준으로 요구 정의, 담당·완료 기준(어떤 헤드리스 테스트로 확인할지) 분해. 파일 수정 없음 |
| `gameplay` | `gameplay-coder` | 게임플레이 | 개발실 | `car.gd`·`player.gd`·`director.gd`·카메라·입력·`data/*.tres`. 차종은 `.tres`로만, `_apply_grip()` 수정 금지 |
| `world` | `world-builder` | 월드/레벨 | 개발실 | `city.gd`·`map_*.gd`·맵 에디터/마커·스폰. `default_map.tres`는 bake로만 갱신 |
| `visual` | `visual-audio` | 테크 아트/사운드 | 개발실 | `_draw()` 그래픽, 스키드/이펙트, `engine_audio.gd` 합성음, HUD 표현. 물리 수치는 안 건드림 |
| `test` | `qa` | QA | 테스트실 | 헤드리스 검증 4종(+`map_data_test`) 실행·판정, `tests/` 추가, 튜닝 전후 수치 비교. 제품 코드 수정 없음 |
| `doc` | `documenter` | 문서 | 문서실 | `README.md`·`AGENTS.md`(새 함정/규칙 추가)·차종 비교표 |
| `research` | `godot-researcher` | 리서치 | 문서실 | Godot 4 공식 문서(프로젝트 버전 기준), GTA류 메커닉 참고 사례. 파일 수정 없음 |
| `codex` | `codex` | 시니어 게임 엔지니어 (Codex) | 회의실 | 설계 토론, GDScript 리뷰, 구현 협업, 컨셉/목업 이미지(참고용, `.gdignore` 폴더) |

## 에이전트 바꾸기

- 대시보드의 에이전트 편집기에서 추가/수정/삭제하면 `data/agents.json`에 저장됩니다. "기본 8종으로 되돌리기"는 `src/agent/agents.config.ts`의 `DEFAULT_AGENTS`로 초기화합니다 (`POST /api/agents/reset`).
- 다른 프로젝트용 팀으로 바꾸려면 `DEFAULT_AGENTS`의 `sdkDescription`(총괄이 언제 부를지 판단하는 근거), `prompt`, `tools`를 고치고 되돌리기를 누르세요. `frontend/src/types/agent.ts`의 `DEFAULT_AGENTS`는 Mock 모드 초기값이라 같은 내용으로 맞춥니다.

## 채팅 / Cowork 모드

명령 입력창 위의 토글로 고릅니다 (브라우저에 기억).

- **Cowork** (기본): 총괄이 할 일 목록을 만들고 서브에이전트·Codex에게 나눠 실제로 파일을 만들고 명령을 실행합니다.
- **채팅**: Claude와 대화만 합니다. 작업 폴더의 파일은 읽기·검색만 가능하고 수정·명령 실행·서브에이전트·Codex 호출은 꺼집니다. 이전 채팅을 이어가며(`resume`), `/clear`나 작업 폴더 변경, 서버 재시작 시 새 대화로 시작합니다. 실제 작업을 요청하면 Cowork로 바꾸라고 안내합니다.

실행이 끝나면 총괄이 요약 끝에 붙인 **다음 추천 작업** 3~4개가 입력창 아래 버튼으로 뜹니다(누르면 입력창에 채워지고, 고쳐서 보낼 수 있음). 실행 전에는 예시 명령이 보입니다.

입력창 아래에는 작업 폴더 · 모델 · 추론 노력 · 권한 모드 드롭다운이 있고(각각 `/workspace`, `/model`, `/effort`, `/permission-mode`와 같음), Chrome 계열에서는 **음성** 버튼으로 한국어 음성 입력을 할 수 있습니다. 헤더 오른쪽의 Claude/Codex 토글은 명령을 받는 쪽을 정합니다(`/codex` 접두어와 동기화).

## Master — 사무실에서 직접 움직이며 에이전트에게 말 걸기

사용자 자신도 사무실에 캐릭터(**Master**, 기본 피카츄)로 서 있습니다. 에이전트 목록 맨 위 "나" 카드에서 이름·캐릭터·색을 바꿀 수 있고(브라우저에 저장), 실시간 로그의 시스템 줄(명령 접수, 내가 한 말)도 이 캐릭터로 표시됩니다.

- **이동**: 방향키 / `WASD` (입력창에 타이핑 중이면 움직이지 않음), 바닥 클릭으로 걸어가기. 벽은 통과하지 않고 문과 복도를 거쳐 갑니다.
- **말 걸기**: 에이전트 옆(약 100px)에 가면 발밑에 색 링과 `E · <이름>에게 말하기` 힌트가 뜹니다. `E`나 `Enter`를 누르거나 **에이전트를 클릭**하면 Master가 옆으로 걸어가고, 명령 입력이 그 에이전트 대상으로 바뀝니다(입력창 테두리가 에이전트 색, 헤더에 `<이름>에게 말하기` 칩). 빈 입력에서 `Esc` 또는 칩의 ✕로 해제하면 다시 총괄에게 갑니다.
- **대화**: 그 상태로 보낸 말은 `/talk @<sdkName> <메시지>`로 전달됩니다. Claude 서브에이전트는 자기 프롬프트·도구로 한 번 실행되어(총괄 없이) 답하고, 사무실에서는 Master 말풍선 → 에이전트 말풍선으로 보입니다. 에이전트별로 세션을 이어가서 이전 대화를 기억합니다(`/clear`로 초기화). Codex 에이전트에게 말하면 `/codex @…`로 넘어갑니다. 실행(Cowork) 중에는 말할 수 없고, 답하는 동안 중지 버튼으로 끊을 수 있습니다.
- 직접 입력도 됩니다: `/talk @gameplay-coder 트럭 그립이 너무 낮지 않아?`, `/talk`(에이전트 목록).

## Codex 협업 (Claude ↔ OpenAI Codex)

Claude 총괄 에이전트가 OpenAI Codex와 대화하며 협업할 수 있습니다. Codex는 서브에이전트가 아니라 "동료 개발자"로, 총괄이 MCP 도구(`ask_<sdkName>`)로 메시지를 보내면 답이 돌아옵니다.

1. **로그인**: 헤더의 `Codex 로그인` 칩 → 링크를 열어 ChatGPT 계정으로 로그인하면 자동으로 완료됩니다 (`codex login`, localhost:1455 콜백). 브라우저를 다른 기기에서 쓰는 경우 등에는 "기기 코드" 방식(`codex login --device-auth`)으로 바꿔 화면의 일회용 코드를 입력합니다. 기기 코드에서 "잘못된 요청"이 뜨면 ChatGPT 워크스페이스에서 기기 코드 로그인이 꺼진 것이니 브라우저 로그인을 쓰세요. 자격증명은 `~/.codex/auth.json`에 저장됩니다. `.env`에 `CODEX_API_KEY`를 넣어도 됩니다.
2. **에이전트**: 기본 목록에 `Codex Agent`(회의실)가 있습니다. 에이전트 추가/편집에서 제공자를 `OpenAI Codex`로 고르면 리뷰어·구현자처럼 역할이 다른 Codex 에이전트를 여러 개 둘 수 있습니다. 예전 `data/agents.json`에는 없으니 편집기에서 추가하거나 "기본 8종으로 되돌리기"를 하세요.
3. **실행 중 대화**: 총괄은 설계 전에 `discuss`, 구현 뒤 `review`, 필요하면 `implement`로 Codex를 부릅니다. 로그에 `총괄 → codex [리뷰]: …`와 Codex의 답이 차례로 보이고, 사무실에서 Codex 캐릭터가 움직입니다. 같은 실행 안에서 Codex는 앞 대화를 기억합니다.
4. **직접 대화**: 명령창에 `/codex <메시지>`(대화·작업 요청, 파일 수정 가능), `/codex review <메시지>`, `/codex implement <메시지>`, `/codex image [>저장경로] <프롬프트>`(이미지 생성), `/codex @<에이전트> <메시지>`, `/codex reset`. 입력창 대상이 Codex일 때(`/codex ` 뒤에서) `/`를 치면 Codex 하위 명령 메뉴가 뜹니다: `/codex /model [이름]`, `/codex /status`(로그인·모델·구독 한도), `/codex /reset`, `/codex /help`, `/codex /review …` 등. 실행 중에는 쓸 수 없습니다.
5. **이미지 생성**: Claude는 그림을 잘 못 그리므로, 아이콘·로고·일러스트 등이 필요하면 총괄이 영어 프롬프트만 쓰고 Codex에게 `image` 모드로 생성을 맡기도록 지시되어 있습니다(Codex의 내장 이미지 생성 도구 사용). 만들어진 파일은 결과 미리보기의 **이미지** 탭에 표시됩니다(`GET /api/workspace-files/<경로>`, 작업 폴더 안 이미지만).
6. **권한**: `review`만 읽기 전용 샌드박스라 항상 자동 허용됩니다. `discuss`(기본)/`implement`/`image`는 `workspace-write` 샌드박스(파일 수정 + 샌드박스 안 명령 실행)라 Codex가 요청받은 파일을 직접 고칠 수 있고, 권한 모드가 `default`면 승인 배너가 뜹니다(`acceptEdits`면 자동). `/codex`로 직접 말할 때는 승인 없이 바로 고칩니다.
7. **제한**: Codex 사용량은 `/cost`에 포함되지 않습니다(ChatGPT 구독 한도 사용). Codex 모델은 `/codex-model <이름>`으로 바꿉니다. 로그인되지 않은 상태로 실행하면 Codex는 제외되고 Claude만 진행합니다.

## 설정 (.env)

| 이름 | 기본값 | 설명 |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | (필수) | Claude API 키 |
| `CODEX_API_KEY` | (선택) | Codex 협업자용 OpenAI API 키. 보통은 대시보드 로그인 사용 |
| `PORT` | `3000` | 서버 포트 |
| `WORKSPACE_DIR` | `./workspace` | 에이전트 작업 폴더 기본값 (대시보드/`/workspace`로 변경 가능) |
| `PERMISSION_MODE` | `acceptEdits` | `acceptEdits` 또는 `default` |
| `MODEL` | (기본 모델) | 총괄 에이전트 모델 |
| `MAX_TURNS` | `60` | 명령 하나당 최대 턴 수 |
| `MAX_BUDGET_USD` | `2` | 명령 하나당 최대 비용(달러), 넘으면 중단 |

## 소켓 이벤트

| 방향 | 이름 | 내용 |
| --- | --- | --- |
| 화면 → 서버 | `command` | `{ prompt }`, 응답으로 `{ ok, error? }` |
| 화면 → 서버 | `interrupt` | 실행 중인 작업 중지 |
| 화면 → 서버 | `permission-reply` | `{ id, allowed, always }` |
| 서버 → 화면 | `hello` | 접속 직후 상태와 지금까지의 이벤트 |
| 서버 → 화면 | `agent-event` | `ui-events.ts`의 `UiEvent` |

## 다음에 해볼 만한 것

- 이어서 명령하기: `result`의 `session_id`를 저장해 두고 `options.resume`으로 대화 이어가기
- 작업 기록: 이벤트를 SQLite 등에 저장해 사이드바의 "작업 기록" 메뉴 구현
- MCP 연결: `options.mcpServers`로 GitHub, Notion 등을 붙여 PR 생성이나 문서 업로드까지 자동화
