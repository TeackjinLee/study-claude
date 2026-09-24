/**
 * 서버 → 대시보드로 보내는 이벤트.
 * 화면은 이 이벤트만 보고 그려지므로, SDK 메시지 형식이 바뀌어도 message-mapper.ts만 고치면 된다.
 */
import type { Attachment } from './attachments.js';
import type { RunSettings } from './settings.service.js';
import type { CommandChoices } from './slash-commands.service.js';

/** 대시보드에서 편집 가능한 에이전트 id (AgentRegistryService). */
export type UiAgentId = string;
/** 'main'은 서브에이전트에게 일을 나눠주는 총괄 에이전트 */
export type AgentRef = UiAgentId | 'main';

export type PlanItem = { text: string; status: 'pending' | 'in_progress' | 'completed' };

/** code=Claude Code처럼 혼자 직접 코딩(기본) / chat=대화만 / cowork=총괄+서브에이전트+Codex 팀 작업 */
export type RunMode = 'code' | 'chat' | 'cowork';
export const RUN_MODES: readonly RunMode[] = ['code', 'chat', 'cowork'];

export type ArtifactKind = 'code' | 'test' | 'doc' | 'image';

/** 실행 하나가 바꾼 파일 (작업 폴더 기준 경로) */
export type CheckpointFile = { path: string; status: 'added' | 'modified' | 'deleted' };

/** 대화 화면에서 도구 호출을 펼쳐 볼 때 쓰는 입력 요약 (길면 잘림) */
export type ToolDetail =
  | { kind: 'bash'; command: string; description?: string }
  | { kind: 'edit'; path: string; edits: { oldText: string; newText: string }[] }
  | { kind: 'write'; path: string; content: string }
  | { kind: 'read'; path: string }
  | { kind: 'search'; pattern: string; path?: string }
  | { kind: 'other'; input: string };
/** Codex 협업자에게 보내는 요청 종류. discuss/review는 읽기 전용, implement만 파일 수정 가능 */
/** image: 총괄이 쓴 프롬프트로 Codex가 내장 이미지 생성 도구를 써서 그림 파일을 만든다 */
export type CodexMode = 'discuss' | 'review' | 'implement' | 'image';

export type UiEventBody =
  /** mode: code=혼자 직접 코딩(기본, 세션 이어감) / chat=대화만(읽기 전용, 세션 이어감) / cowork=총괄+서브에이전트+Codex로 실제 작업 */
  /** continued: 같은 모드의 이전 대화(세션)를 이어서 실행 / planFirst: 계획을 먼저 세우고 승인받은 뒤 수정 */
  | { type: 'run_start'; command: string; workspace: string; attachments?: Attachment[]; mode?: RunMode; continued?: boolean; planFirst?: boolean }
  /** 실행 도중 사용자가 끼워 넣은 추가 지시 */
  | { type: 'follow_up'; text: string }
  /** 코드·채팅 모드의 이어갈 대화(세션)가 생기거나(active) 새 대화로 비워짐 */
  | { type: 'conversation'; mode: RunMode; active: boolean; id?: string; title?: string }
  /** 이어가는 대화의 컨텍스트 사용량 (실행이 끝날 때 잰다) */
  | { type: 'context_usage'; mode: RunMode; conversationId: string; context: ContextInfo }
  /** 대화를 압축했음 (/compact 또는 컨텍스트가 차서 자동). 토큰 수는 압축 전·후 */
  | { type: 'compacted'; trigger: 'manual' | 'auto'; preTokens: number; postTokens?: number }
  /** 지난 대화를 열었음: 화면을 비우고 events로 대화 화면을 다시 그린다 (이 이벤트 자체는 기록하지 않음) */
  | { type: 'conversation_loaded'; mode: RunMode; conversationId: string; title: string; events: UiEvent[]; context?: ContextInfo }
  /** 슬래시 명령(/model 등)을 서버가 처리한 결과 */
  | { type: 'command_result'; command: string; ok: boolean; text: string; choices?: CommandChoices }
  /** 실행 설정이 바뀜 (/model, /effort ...) */
  | { type: 'settings'; settings: RunSettings }
  /** /clear: 화면의 로그/결과를 비우라는 신호 */
  | { type: 'cleared' }
  | { type: 'session'; sessionId: string; model: string }
  | { type: 'plan'; items: PlanItem[] }
  | { type: 'main_note'; text: string }
  | { type: 'api_retry'; attempt: number; maxRetries: number; delayMs: number; reason: string }
  | { type: 'api_error'; reason: string }
  | { type: 'agent_start'; agent: UiAgentId; callId: string; task: string }
  | { type: 'agent_progress'; agent: UiAgentId; callId: string; text: string }
  | { type: 'agent_note'; agent: UiAgentId; text: string }
  | { type: 'agent_done'; agent: UiAgentId; callId: string; ok: boolean; summary: string }
  /** 에이전트 사이의 대화 한 마디 (총괄→Codex, Codex→총괄, 사용자(/codex)→Codex) */
  | { type: 'agent_message'; from: AgentRef | 'user'; to: AgentRef; mode: CodexMode; text: string }
  /** /codex 직접 대화 시작/끝 — 실행(run)이 아니어도 화면에 중지 버튼을 보여주기 위해 */
  | { type: 'codex_direct'; active: boolean }
  /** /talk — 사용자(Master)가 사무실에서 Claude 서브에이전트에게 직접 말을 걸어 대화 중 */
  | { type: 'direct_talk'; active: boolean; agent: UiAgentId }
  | { type: 'action_start'; agent: AgentRef; actionId: string; tool: string; label: string; detail?: ToolDetail }
  /** output: 도구 결과 텍스트 (파일 읽기 결과는 보내지 않음, 길면 잘림) */
  | { type: 'action_done'; agent: AgentRef; actionId: string; ok: boolean; output?: string }
  /** 에이전트가 쓴 글 전체 (대화 화면용. main_note/agent_note는 로그용 한 줄 요약) */
  | { type: 'assistant_text'; agent: AgentRef; text: string }
  /** 쓰는 중인 글의 새 조각 (실시간 표시용, 기록·저장하지 않는다). 블록이 끝나면 전체 글이 assistant_text로 온다 */
  | { type: 'assistant_delta'; agent: AgentRef; text: string }
  /** image 종류는 text가 작업 폴더 기준 경로이고 url로 파일을 받아 볼 수 있다 */
  | { type: 'artifact'; kind: ArtifactKind; key: string; title: string; lang: string; text: string; url?: string }
  /** image: 함께 보여 줄 이미지 URL (레퍼런스 확인) */
  | { type: 'permission_request'; id: string; agent: AgentRef; tool: string; title: string; detail: string; canAlwaysAllow: boolean; image?: string }
  | { type: 'permission_resolved'; id: string; allowed: boolean }
  /** suggestions: 총괄이 요약 끝에 붙인 다음 추천 명령 (명령 입력창의 버튼으로 표시) */
  | { type: 'run_done'; ok: boolean; result: string; costUsd: number; turns: number; durationMs: number; suggestions?: string[] }
  | { type: 'run_error'; message: string }
  /** 실행을 끝내지는 않지만 사용자가 바로 알아야 할 문제 (예: Codex 모델 설정 오류) */
  | { type: 'notice'; tone: 'error' | 'warn'; text: string }
  /** 실행이 끝났고 파일이 바뀌었음 → "이 실행 되돌리기" 버튼 (id로 되돌린다) */
  | { type: 'checkpoint'; id: string; files: CheckpointFile[] }
  /** 되돌리기 결과. complete면 이 실행의 변경을 전부 되돌렸다 */
  | { type: 'checkpoint_undone'; id: string; restored: string[]; skipped: { path: string; reason: string }[]; complete: boolean }
  | { type: 'run_aborted' };

export type UiEvent = UiEventBody & { at: number };

/** 대화의 컨텍스트 창 사용량 */
export interface ContextInfo {
  tokens: number;
  max: number;
  /** 0~100 */
  pct: number;
  at: number;
}
