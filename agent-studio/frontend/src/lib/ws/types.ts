import type { AgentDef, AgentRole, AgentStatus, RoomId } from '@/types/agent';
import type { Attachment } from '@/lib/uploads';

/** 결과 미리보기 탭 종류. 백엔드 ArtifactKind(code/test/doc/image) + 최종 요약 */
export type ArtifactKind = 'code' | 'test' | 'doc' | 'image';

export interface Artifact {
  key: string;
  kind: ArtifactKind;
  title: string;
  lang: string;
  text: string;
  /** image 종류: 파일을 받아 볼 백엔드 상대 주소 (/api/workspace-files/…) */
  url?: string;
  at: number;
}

export interface PermissionRequest {
  id: string;
  agent: AgentRole | 'system';
  tool: string;
  title: string;
  detail: string;
  canAlwaysAllow: boolean;
}

/** 대화 화면에서 펼쳐 볼 도구 입력 (백엔드 ToolDetail과 같은 모양) */
export type ToolDetail =
  | { kind: 'bash'; command: string; description?: string }
  | { kind: 'edit'; path: string; edits: { oldText: string; newText: string }[] }
  | { kind: 'write'; path: string; content: string }
  | { kind: 'read'; path: string }
  | { kind: 'search'; pattern: string; path?: string }
  | { kind: 'other'; input: string };

/** 실행 하나가 바꾼 파일 (작업 폴더 기준 경로) */
export type CheckpointFile = { path: string; status: 'added' | 'modified' | 'deleted' };

/** 실행 되돌리기 결과 */
export interface UndoResult {
  ok: boolean;
  error?: string;
  restored: string[];
  skipped: { path: string; reason: string }[];
  complete: boolean;
}

/** 에이전트 id 또는 'main'(총괄/코드 모드의 Claude) */
export type TxAgent = AgentRole | 'main';

/** 대화 화면(Claude Code처럼 글·도구 호출이 이어지는 화면)을 그리는 이벤트 */
export type TxEvent =
  | { t: 'text'; agent: TxAgent; text: string }
  /** 쓰는 중인 글의 새 조각. 블록이 끝나면 전체 글(text)이 와서 대체한다 */
  | { t: 'text_delta'; agent: TxAgent; text: string }
  | { t: 'tool_start'; id: string; agent: TxAgent; tool: string; label: string; detail?: ToolDetail }
  | { t: 'tool_done'; id: string; ok: boolean; output?: string }
  | { t: 'agent_start'; id: string; agent: AgentRole; task: string }
  | { t: 'agent_done'; id: string; ok: boolean; summary: string }
  | { t: 'plan'; items: { text: string; status: 'pending' | 'in_progress' | 'completed' }[] }
  /** 사무실에서 에이전트에게 직접 한 말 (/talk, /codex) */
  | { t: 'user_to'; agent: AgentRole; text: string }
  /** 실행이 파일을 바꿨음 → "이 실행 되돌리기" */
  | { t: 'checkpoint'; id: string; files: CheckpointFile[] }
  | { t: 'checkpoint_undone'; id: string; restored: string[]; skipped: { path: string; reason: string }[]; complete: boolean };

/** 명령 종류: code=Claude Code처럼 혼자 직접 코딩(기본, 이전 대화 이어감) / chat=대화만(읽기 전용) / cowork=총괄+서브에이전트+Codex로 팀 작업 */
export type RunMode = 'code' | 'chat' | 'cowork';
export const RUN_MODES: readonly RunMode[] = ['code', 'chat', 'cowork'];

/** /model 등으로 바꾸는 서버 실행 설정 (백엔드 RunSettings와 같은 모양) */
export interface RunSettings {
  model?: string;
  /** Codex 협업자가 쓸 모델. 없으면 ~/.codex/config.toml 값 */
  codexModel?: string;
  /** 에이전트가 파일을 읽고 쓰는 작업 폴더 (절대 경로). /workspace 로 바꾼다 */
  workspaceDir: string;
  permissionMode: 'acceptEdits' | 'default';
  effort?: 'low' | 'medium' | 'high' | 'xhigh' | 'max';
  maxTurns: number;
  maxBudgetUsd: number;
}

/** /model 처럼 인자 없이 부르면 고를 수 있는 선택지 */
export interface CommandChoice {
  value: string;
  label: string;
  description?: string;
  current?: boolean;
}
export interface CommandChoices {
  command: string;
  title: string;
  options: CommandChoice[];
}

/** 명령 입력창 자동완성용 슬래시 명령 정보 */
export interface CommandInfo {
  name: string;
  description: string;
  argumentHint: string;
  source: 'builtin' | 'sdk';
  /** codex: 입력창이 Codex 대상(/codex ...)일 때만 뜨는 하위 명령 (`/codex /<name>`) */
  scope?: 'codex';
  /** 인자를 메뉴에서 고를 수 있는 명령의 선택지 (/model, /codex /model, /effort ...) */
  choices?: CommandChoice[];
}

export interface RunResult {
  ok: boolean;
  result: string;
  costUsd?: number;
  turns?: number;
  durationMs?: number;
  /** 총괄이 제안한 다음 추천 명령 (명령 입력창 버튼) */
  suggestions?: string[];
}

/**
 * 실행 엔진(Mock 데모 / 실제 NestJS 게이트웨이)이 무엇이든 상관없이
 * 스토어와 Phaser 씬이 동일하게 소비하는 정규화된 이벤트.
 */
export type AgentSimEvent =
  | { type: 'connection'; status: 'connected' | 'connecting' | 'disconnected' }
  /** 서버(또는 다른 화면)에서 에이전트 목록이 바뀌었을 때 */
  | { type: 'agents_changed'; agents: AgentDef[] }
  | { type: 'session'; model: string }
  /** continued: 같은 모드의 이전 대화를 이어서 실행 / planFirst: 계획을 먼저 승인받고 수정 */
  | { type: 'run_start'; command: string; workspace?: string; attachments?: Attachment[]; mode?: RunMode; continued?: boolean; planFirst?: boolean }
  /** 실행 도중 사용자가 끼워 넣은 추가 지시 */
  | { type: 'follow_up'; text: string }
  /** 코드·채팅의 이어갈 대화가 생기거나(active) 새 대화로 비워짐. all은 접속 직후 전체 상태 */
  | { type: 'conversation'; mode: RunMode; active: boolean; id?: string; title?: string }
  | { type: 'conversations'; all: Partial<Record<RunMode, boolean>>; titles?: Partial<Record<RunMode, { id: string; title: string }>> }
  /** 지난 대화를 열었음 (기록 재생이 끝난 뒤 온다) */
  | { type: 'conversation_loaded'; mode: RunMode; id: string; title: string }
  /** room: 'work'는 "그 에이전트의 담당 작업실"(에이전트 정의의 room)로, 스토어가 실제 방으로 바꾼다 */
  | { type: 'agent_status'; agent: AgentRole; status: AgentStatus; room?: RoomId | 'work'; message?: string; progress?: number }
  | { type: 'log'; agent: AgentRole | 'system'; text: string }
  /** 슬래시 명령(/model 등)에 대한 서버 응답 */
  | { type: 'command_result'; command: string; ok: boolean; text: string; choices?: CommandChoices }
  | { type: 'settings'; settings: RunSettings }
  /** /clear: 로그/결과 비우기 */
  | { type: 'cleared' }
  | { type: 'artifact'; artifact: Omit<Artifact, 'at'> }
  | { type: 'permission_request'; request: PermissionRequest }
  | { type: 'permission_resolved'; id: string; allowed: boolean }
  | { type: 'run_done'; result: RunResult }
  | { type: 'run_error'; message: string }
  | { type: 'run_aborted' }
  /** /codex 직접 대화 진행 중 (실행이 아니어도 중지 버튼을 보여준다) */
  | { type: 'codex_direct'; active: boolean }
  /** 사용자(Master)가 에이전트에게 한 말 — 사무실에서 Master 말풍선으로 보여준다 */
  | { type: 'master_say'; to: AgentRole; text: string }
  /** 대화 화면 */
  | { type: 'tx'; event: TxEvent };

/** Mock/실제 소스가 공통으로 구현하는 추상화 인터페이스. */
export interface AgentEventSource {
  connect(onEvent: (evt: AgentSimEvent) => void): void;
  disconnect(): void;
  /** agents: 현재 등록된 에이전트 목록 (Mock이 사용자 정의 에이전트도 움직이게 하려고 받는다) */
  sendCommand(prompt: string, agents: AgentDef[], attachments?: Attachment[], mode?: RunMode, opts?: { planFirst?: boolean }): void;
  /** 실행 도중 추가 지시 (다음 도구 호출 사이에 끼워 넣는다) */
  followUp(prompt: string): void;
  /** 코드·채팅의 이어갈 대화를 비우고 새로 시작. mode가 없으면 모두 */
  newConversation(mode?: RunMode): void;
  /** 실행 되돌리기. force면 실행 뒤에 다시 바뀐 파일도 덮어쓴다 */
  undoCheckpoint(id: string, force?: boolean): Promise<UndoResult>;
  /** 실행 중인 작업 중단 */
  interrupt(): void;
  /** 승인 요청에 응답 (always = 이번 세션 동안 같은 요청은 자동 허용) */
  /** always: true=이 도구를 이번 실행 동안 허용, 'all'=모든 도구를 이번 실행 동안 허용 */
  replyPermission(id: string, allowed: boolean, always: boolean | 'all'): void;
  /** 자동완성용 슬래시 명령 목록 */
  listCommands(): Promise<CommandInfo[]>;
}
