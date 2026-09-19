/**
 * 에이전트 id는 백엔드(data/agents.json, AgentRegistryService)의 id와 1:1로 맞춘다.
 * 사용자가 대시보드에서 에이전트를 추가/삭제/수정할 수 있으므로 고정 유니온이 아니라 문자열이다.
 */
export type AgentRole = string;

export type AgentStatus =
  | 'idle'
  | 'thinking'
  | 'working'
  | 'testing'
  | 'deploying'
  | 'completed'
  | 'error';

/** 참고 시안(workspace/agent_ad.png)과 같은 7개 방 */
export type RoomId = 'entrance' | 'lounge' | 'meeting' | 'dev' | 'test' | 'doc' | 'server';

export const ROOM_LABEL: Record<RoomId, string> = {
  meeting: '회의실',
  dev: '개발실',
  test: '테스트실',
  doc: '문서실',
  server: '서버실',
  lounge: '휴게실',
  entrance: '입구',
};

/** 에이전트를 배치할 수 있는 작업실 (휴게실/입구는 공용 공간) */
export const WORK_ROOMS: RoomId[] = ['meeting', 'dev', 'test', 'doc', 'server'];

export const AVAILABLE_TOOLS = ['Read', 'Glob', 'Grep', 'Edit', 'Write', 'Bash', 'WebSearch', 'WebFetch'] as const;
export type ToolName = (typeof AVAILABLE_TOOLS)[number];

export const TOOL_DESCRIPTION: Record<ToolName, string> = {
  Read: '파일 읽기',
  Glob: '파일 찾기',
  Grep: '내용 검색',
  Edit: '파일 수정',
  Write: '파일 생성',
  Bash: '명령 실행',
  WebSearch: '웹 검색',
  WebFetch: '웹 페이지 읽기',
};

/**
 * claude: Claude 서브에이전트 (총괄이 위임) / codex: OpenAI Codex 협업자 (총괄이 대화). 없으면 claude.
 */
export type AgentProvider = 'claude' | 'codex';
export const PROVIDER_LABEL: Record<AgentProvider, string> = { claude: 'Claude 서브에이전트', codex: 'OpenAI Codex' };
export const providerOf = (def: Pick<AgentDef, 'provider'>): AgentProvider => def.provider ?? 'claude';

/** 에이전트 정의. 백엔드 AgentConfig와 같은 모양이며 사용자가 편집한다. */
export interface AgentDef {
  id: AgentRole;
  provider?: AgentProvider;
  /** 총괄 에이전트가 서브에이전트를 부를 때 쓰는 이름 */
  sdkName: string;
  name: string;
  shortName: string;
  roleLabel: string;
  description: string;
  /** 작업 트리/진행 현황에 표시할 담당 작업명 */
  taskLabel: string;
  room: RoomId;
  color: string;
  /** PokeAPI 전국도감 번호 (캐릭터) */
  pokemonId: number;
  pokemonName: string;
  /** Claude 서브에이전트가 쓸 도구. Codex 에이전트는 빈 배열 */
  tools: ToolName[];
  /** 총괄 에이전트에게 보여주는 "언제 부르는지" 설명 */
  sdkDescription: string;
  /** 서브에이전트 시스템 프롬프트 (Codex면 역할 설명) */
  prompt: string;
}

export interface AgentState {
  id: AgentRole;
  status: AgentStatus;
  room: RoomId;
  message: string;
  progress?: number;
}

export interface LogEntry {
  id: string;
  at: number;
  agent: AgentRole | 'system';
  text: string;
  /** command: 슬래시 명령 응답 (여러 줄, 고정폭으로 표시) */
  kind?: 'command';
  /** 슬래시 명령 응답이 실패인지 */
  error?: boolean;
}

/** 명령 하나에 대해 각 에이전트가 맡은 작업의 진행 상태 (작업 진행 현황 / 작업 트리 패널용). */
export type TaskStatus = 'pending' | 'running' | 'done' | 'error';

export interface TaskState {
  status: TaskStatus;
  progress?: number;
}

export const STATUS_LABEL: Record<AgentStatus, string> = {
  idle: 'Idle',
  thinking: 'Thinking',
  working: 'Working',
  testing: 'Testing',
  deploying: 'Deploying',
  completed: 'Completed',
  error: 'Error',
};

export const STATUS_COLOR: Record<AgentStatus, string> = {
  idle: '#7c8db5',
  thinking: '#c084fc',
  working: '#4ade80',
  testing: '#38bdf8',
  deploying: '#fbbf24',
  completed: '#34d399',
  error: '#f87171',
};

export const TASK_STATUS_LABEL: Record<TaskStatus, string> = {
  pending: '대기 중',
  running: '진행 중',
  done: '완료',
  error: '실패',
};

export function defaultAgentState(role: AgentRole): AgentState {
  return { id: role, status: 'idle', room: 'lounge', message: '대기중' };
}

/** 백엔드 DEFAULT_AGENTS와 동일한 기본 8종(Claude 7 + Codex 1). Mock 모드의 초기값이자 "기본값으로 되돌리기"의 대상 */
export const DEFAULT_AGENTS: AgentDef[] = [
  {
    id: 'plan',
    provider: 'claude',
    sdkName: 'planner',
    name: 'Planner Agent',
    shortName: 'Planner',
    roleLabel: '기획 / 분석',
    description: '요구사항 분석 및 설계',
    taskLabel: '요구사항 분석',
    room: 'meeting',
    color: '#e879f9',
    pokemonId: 151,
    pokemonName: 'mew',
    tools: ['Read', 'Glob', 'Grep'],
    sdkDescription: '요구사항을 분석하고 작업을 구체적인 단계로 나눈다. 가장 먼저 호출한다. 파일을 수정하지 않는다.',
    prompt: '너는 기획 에이전트다.\n작업 폴더의 기존 파일을 살펴보고, 요청을 구현 가능한 단계로 나눠라.\n각 단계마다 담당(코드, 테스트, 문서, 리서치, 배포)과 완료 기준을 적어라.\n파일은 절대 수정하지 않는다. 결과는 한국어로 간결하게 보고한다.',
  },
  {
    id: 'research',
    provider: 'claude',
    sdkName: 'researcher',
    name: 'Research Agent',
    shortName: 'Research',
    roleLabel: '리서치 / 문서화',
    description: '기술 조사 및 문서 작성',
    taskLabel: '기술 조사',
    room: 'doc',
    color: '#c084fc',
    pokemonId: 53,
    pokemonName: 'persian',
    tools: ['Read', 'Glob', 'Grep', 'WebSearch', 'WebFetch'],
    sdkDescription: '라이브러리 사용법, 설정 방법, 참고 사례처럼 구현에 필요한 정보를 조사한다. 파일을 수정하지 않는다.',
    prompt: '너는 리서치 에이전트다.\n요청받은 주제를 조사하고, 코드 에이전트가 바로 쓸 수 있도록 핵심만 정리해라.\n가능하면 공식 문서를 우선하고, 참고한 출처 URL을 함께 적어라.\n파일은 수정하지 않는다. 결과는 한국어로 보고한다.',
  },
  {
    id: 'code',
    provider: 'claude',
    sdkName: 'coder',
    name: 'Backend Agent',
    shortName: 'Backend',
    roleLabel: '백엔드 개발',
    description: 'API 개발 및 서버 로직',
    taskLabel: 'API 개발',
    room: 'dev',
    color: '#fb923c',
    pokemonId: 6,
    pokemonName: 'charizard',
    tools: ['Read', 'Glob', 'Grep', 'Edit', 'Write', 'Bash'],
    sdkDescription: '작업 폴더 안에서 백엔드/서버 로직 코드를 작성하고 수정한다. UI 컴포넌트나 화면 작업은 frontend-agent에게 맡긴다.',
    prompt: '너는 백엔드 코드 에이전트다.\n전달받은 계획에 따라 작업 폴더 안에서만 서버 로직, API, 데이터 처리 코드를 작성하고 수정한다.\nUI 컴포넌트나 화면 관련 코드는 다루지 않는다 (frontend-agent 담당).\n기존 코드 스타일을 따르고, 필요한 의존성 설치나 빌드 명령은 실행해도 된다.\n끝나면 바꾼 파일 목록과 핵심 변경 내용을 한국어로 보고한다.',
  },
  {
    id: 'frontend',
    provider: 'claude',
    sdkName: 'frontend-agent',
    name: 'Frontend Agent',
    shortName: 'Frontend',
    roleLabel: '프론트엔드 개발',
    description: 'UI/UX 구현',
    taskLabel: 'UI 구현',
    room: 'dev',
    color: '#facc15',
    pokemonId: 25,
    pokemonName: 'pikachu',
    tools: ['Read', 'Glob', 'Grep', 'Edit', 'Write', 'Bash'],
    sdkDescription: '작업 폴더 안에서 UI 컴포넌트, 화면, 스타일 코드를 작성하고 수정한다. 서버/API 로직은 coder에게 맡긴다.',
    prompt: '너는 프론트엔드 코드 에이전트다.\n전달받은 계획에 따라 작업 폴더 안에서만 UI 컴포넌트, 화면, 스타일(CSS 등) 코드를 작성하고 수정한다.\n서버 로직이나 API 구현은 다루지 않는다 (coder 담당). 필요한 프런트엔드 의존성 설치나 빌드 명령은 실행해도 된다.\n끝나면 바꾼 파일 목록과 핵심 변경 내용을 한국어로 보고한다.',
  },
  {
    id: 'test',
    provider: 'claude',
    sdkName: 'tester',
    name: 'Tester Agent',
    shortName: 'Tester',
    roleLabel: '테스트 엔지니어',
    description: '테스트 코드 작성 및 실행',
    taskLabel: '테스트',
    room: 'test',
    color: '#38bdf8',
    pokemonId: 7,
    pokemonName: 'squirtle',
    tools: ['Read', 'Glob', 'Grep', 'Edit', 'Write', 'Bash'],
    sdkDescription: '테스트 코드를 작성하고 실행해 코드가 제대로 동작하는지 검증한다. 코드 작성이 끝난 뒤 호출한다.',
    prompt: '너는 테스트 에이전트다.\n구현된 코드에 대한 테스트를 작성하고 실제로 실행해라.\n실패하면 원인을 분석해 보고하고, 테스트 코드의 문제라면 직접 고쳐라. 제품 코드는 고치지 않는다.\n마지막에 통과/실패 개수와 실행한 명령을 한국어로 보고한다.',
  },
  {
    id: 'doc',
    provider: 'claude',
    sdkName: 'documenter',
    name: 'Documenter Agent',
    shortName: 'Docs',
    roleLabel: '기술 문서화',
    description: 'API 문서 및 가이드 작성',
    taskLabel: '문서화',
    room: 'doc',
    color: '#f472b6',
    pokemonId: 137,
    pokemonName: 'porygon',
    tools: ['Read', 'Glob', 'Grep', 'Edit', 'Write'],
    sdkDescription: '작업 결과를 README나 문서 파일(.md)로 정리한다. 구현과 테스트가 끝난 뒤 호출한다.',
    prompt: '너는 문서화 에이전트다.\n작업 폴더의 변경 내용을 읽고, 사용 방법과 변경사항을 Markdown 문서로 정리해라.\n문서는 docs/ 폴더나 README.md에 한국어로 작성한다.',
  },
  {
    id: 'deploy',
    provider: 'claude',
    sdkName: 'deployer',
    name: 'DevOps Agent',
    shortName: 'DevOps',
    roleLabel: '배포 / 인프라',
    description: '서버 배포 및 운영',
    taskLabel: '배포',
    room: 'server',
    color: '#a78bfa',
    pokemonId: 94,
    pokemonName: 'gengar',
    tools: ['Read', 'Glob', 'Grep', 'Bash'],
    sdkDescription: '빌드하고 로컬에서 실행해 정상 동작을 확인한다. 사용자가 배포나 실행 확인을 요청했을 때만 호출한다.',
    prompt: '너는 배포 에이전트다.\n프로젝트를 빌드하고 로컬에서 실행해 정상 동작(헬스체크)을 확인한다.\n원격 서버 배포, 클라우드 리소스 생성, 비밀 정보 사용은 절대 하지 않는다.\n실행한 서버 프로세스는 확인이 끝나면 종료한다. 결과는 한국어로 보고한다.',
  },
  {
    id: 'codex',
    provider: 'codex',
    sdkName: 'codex',
    name: 'Codex Agent',
    shortName: 'Codex',
    roleLabel: '시니어 엔지니어 (OpenAI Codex)',
    description: '설계 토론 · 코드 리뷰 · 구현 협업',
    taskLabel: '리뷰 / 협업',
    room: 'meeting',
    color: '#10a37f',
    pokemonId: 65,
    pokemonName: 'alakazam',
    tools: [],
    sdkDescription:
      '다른 모델(OpenAI Codex)의 시각으로 설계를 함께 토론하고, 작성된 코드를 솔직하게 리뷰하며, 요청하면 직접 구현한다. 설계를 확정하기 전이나 구현을 끝낸 뒤 교차 검증이 필요할 때 부른다.',
    prompt:
      '너는 Claude 총괄 에이전트와 짝을 이뤄 일하는 시니어 엔지니어다. 상대는 다른 AI 모델이고, 사용자는 두 모델의 대화를 대시보드에서 보고 있다.\n의견은 솔직하고 구체적으로 낸다. 동의하지 않으면 근거를 들어 반대하고, 더 나은 대안을 제시한다. 빈말이나 무조건적인 동의는 하지 않는다.\n토론(discuss)과 리뷰(review) 요청에서는 파일을 읽기만 하고 절대 수정하지 않는다. 구현(implement) 요청일 때만 필요한 최소 범위로 파일을 고치고, 무엇을 바꿨는지 파일 경로와 함께 보고한다.\n답은 한국어로, 핵심부터 간결하게 쓴다. 코드 리뷰는 심각도 순으로 문제 → 이유 → 고칠 방법 순서로 적는다.',
  },
];

/** 새 에이전트를 만들 때 폼의 초기값 */
export function newAgentTemplate(): AgentDef {
  return {
    id: '',
    provider: 'claude',
    sdkName: '',
    name: '',
    shortName: '',
    roleLabel: '',
    description: '',
    taskLabel: '',
    room: 'dev',
    color: '#60a5fa',
    pokemonId: 133,
    pokemonName: 'eevee',
    tools: ['Read', 'Glob', 'Grep'],
    sdkDescription: '',
    prompt: '',
  };
}
