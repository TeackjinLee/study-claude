/**
 * 명령 모드별 실행 방식. 러너가 query 옵션을 만들 때 이 표만 보고 결정한다.
 *   code   Claude Code처럼 혼자 직접 코딩 (기본). 서브에이전트·Codex 없이 수정·실행, 이전 대화를 이어간다
 *   chat   대화만. 읽기/검색/웹 도구만 남기고 이전 대화를 이어간다
 *   cowork 총괄이 서브에이전트·Codex에게 나눠 맡기는 팀 작업. 매번 새 세션
 */
import { RUN_MODES, type RunMode } from './ui-events.js';

export interface RunModeProfile {
  /** 같은 작업 폴더의 이전 세션을 이어가는지 */
  resumable: boolean;
  /** 등록된 서브에이전트를 붙이는지 */
  subagents: boolean;
  /** Codex 협업자를 MCP 도구로 붙이는지 */
  codex: boolean;
  /** "계획 먼저"(plan 권한 모드)를 쓸 수 있는지 — 수정할 수 있는 모드만 의미가 있다 */
  canPlan: boolean;
  disallowedTools?: string[];
}

/** 채팅 모드에서 빼는 도구: 파일 쓰기, 명령 실행, 서브에이전트, 할 일 목록. 읽기/검색/웹만 남긴다 */
export const CHAT_DISALLOWED_TOOLS = [
  'Write', 'Edit', 'MultiEdit', 'NotebookEdit', 'Bash', 'BashOutput', 'KillShell',
  'Agent', 'Task', 'TodoWrite', 'TaskCreate', 'TaskUpdate', 'TaskList', 'TaskGet', 'TaskOutput', 'TaskStop',
  'Skill', 'EnterPlanMode', 'ExitPlanMode',
];

/** 코드 모드에서 빼는 도구: 서브에이전트 호출만 막고 파일 수정·명령 실행은 그대로 둔다 (Claude Code 단독 작업) */
export const CODE_DISALLOWED_TOOLS = ['Agent', 'Task', 'TaskOutput', 'TaskStop'];

const PROFILES: Record<RunMode, RunModeProfile> = {
  code: { resumable: true, subagents: false, codex: false, canPlan: true, disallowedTools: CODE_DISALLOWED_TOOLS },
  chat: { resumable: true, subagents: false, codex: false, canPlan: false, disallowedTools: CHAT_DISALLOWED_TOOLS },
  cowork: { resumable: false, subagents: true, codex: true, canPlan: true },
};

export const runModeProfile = (mode: RunMode): RunModeProfile => PROFILES[mode];

/** 화면에서 온 값을 모드로. 모르는 값이면 기본인 코드 모드 */
export const parseRunMode = (v: unknown): RunMode => RUN_MODES.find((m) => m === v) ?? 'code';
