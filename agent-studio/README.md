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
2. 총괄 에이전트는 `Agent` 도구로 서브에이전트(기획, 리서치, 코드, 테스트, 문서화, 배포)에게 일을 나눠줍니다.
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
- **명령 실행(Bash)은 항상 화면에서 승인**해야 하며, "항상 허용" 선택지도 제공하지 않습니다.
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

## 에이전트 바꾸기

1. `src/agent/agents.config.ts`의 `AGENTS` 배열에서 설명(`description`), 지시문(`prompt`), 사용할 도구(`tools`)를 수정합니다. 총괄 에이전트는 `description`을 보고 누구에게 일을 맡길지 정하므로, 언제 호출해야 하는지를 분명히 적는 것이 중요합니다.
2. 에이전트를 추가했다면 `public/index.html`의 `AGENTS` 배열에도 같은 `id`로 추가합니다.

## 채팅 / Cowork 모드

명령 입력창 위의 토글로 고릅니다 (브라우저에 기억).

- **Cowork** (기본): 총괄이 할 일 목록을 만들고 서브에이전트·Codex에게 나눠 실제로 파일을 만들고 명령을 실행합니다.
- **채팅**: Claude와 대화만 합니다. 작업 폴더의 파일은 읽기·검색만 가능하고 수정·명령 실행·서브에이전트·Codex 호출은 꺼집니다. 이전 채팅을 이어가며(`resume`), `/clear`나 작업 폴더 변경, 서버 재시작 시 새 대화로 시작합니다. 실제 작업을 요청하면 Cowork로 바꾸라고 안내합니다.

입력창 아래에는 작업 폴더 · 모델 · 추론 노력 · 권한 모드 드롭다운이 있고(각각 `/workspace`, `/model`, `/effort`, `/permission-mode`와 같음), Chrome 계열에서는 **음성** 버튼으로 한국어 음성 입력을 할 수 있습니다. 헤더 오른쪽의 Claude/Codex 토글은 명령을 받는 쪽을 정합니다(`/codex` 접두어와 동기화).

## Codex 협업 (Claude ↔ OpenAI Codex)

Claude 총괄 에이전트가 OpenAI Codex와 대화하며 협업할 수 있습니다. Codex는 서브에이전트가 아니라 "동료 개발자"로, 총괄이 MCP 도구(`ask_<sdkName>`)로 메시지를 보내면 답이 돌아옵니다.

1. **로그인**: 헤더의 `Codex 로그인` 칩 → 링크를 열어 ChatGPT 계정으로 로그인하면 자동으로 완료됩니다 (`codex login`, localhost:1455 콜백). 브라우저를 다른 기기에서 쓰는 경우 등에는 "기기 코드" 방식(`codex login --device-auth`)으로 바꿔 화면의 일회용 코드를 입력합니다. 기기 코드에서 "잘못된 요청"이 뜨면 ChatGPT 워크스페이스에서 기기 코드 로그인이 꺼진 것이니 브라우저 로그인을 쓰세요. 자격증명은 `~/.codex/auth.json`에 저장됩니다. `.env`에 `CODEX_API_KEY`를 넣어도 됩니다.
2. **에이전트**: 기본 목록에 `Codex Agent`(회의실)가 있습니다. 에이전트 추가/편집에서 제공자를 `OpenAI Codex`로 고르면 리뷰어·구현자처럼 역할이 다른 Codex 에이전트를 여러 개 둘 수 있습니다. 예전 `data/agents.json`에는 없으니 편집기에서 추가하거나 "기본 8종으로 되돌리기"를 하세요.
3. **실행 중 대화**: 총괄은 설계 전에 `discuss`, 구현 뒤 `review`, 필요하면 `implement`로 Codex를 부릅니다. 로그에 `총괄 → codex [리뷰]: …`와 Codex의 답이 차례로 보이고, 사무실에서 Codex 캐릭터가 움직입니다. 같은 실행 안에서 Codex는 앞 대화를 기억합니다.
4. **직접 대화**: 명령창에 `/codex <메시지>`(토론), `/codex review <메시지>`, `/codex implement <메시지>`, `/codex image [>저장경로] <프롬프트>`(이미지 생성), `/codex @<에이전트> <메시지>`, `/codex reset`. 실행 중에는 쓸 수 없습니다.
5. **이미지 생성**: Claude는 그림을 잘 못 그리므로, 아이콘·로고·일러스트 등이 필요하면 총괄이 영어 프롬프트만 쓰고 Codex에게 `image` 모드로 생성을 맡기도록 지시되어 있습니다(Codex의 내장 이미지 생성 도구 사용). 만들어진 파일은 결과 미리보기의 **이미지** 탭에 표시됩니다(`GET /api/workspace-files/<경로>`, 작업 폴더 안 이미지만).
6. **권한**: `discuss`/`review`는 Codex가 읽기 전용 샌드박스에서 돌아 자동 허용됩니다. `implement`/`image`는 `workspace-write` 샌드박스(파일 수정 + 샌드박스 안 명령 실행)라, 권한 모드가 `default`면 승인 배너가 뜹니다.
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
