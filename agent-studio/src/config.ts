import { resolve } from 'node:path';
import type { PermissionMode } from '@anthropic-ai/claude-agent-sdk';

const toInt = (value: string | undefined, fallback: number) => {
  const n = Number.parseInt(value ?? '', 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
};

const toIntOrZero = (value: string | undefined, fallback: number) => {
  const n = Number.parseInt(value ?? '', 10);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
};

const toFloat = (value: string | undefined, fallback: number) => {
  const n = Number.parseFloat(value ?? '');
  return Number.isFinite(n) && n > 0 ? n : fallback;
};

const permissionMode = (process.env.PERMISSION_MODE ?? 'acceptEdits') as PermissionMode;
if (permissionMode !== 'acceptEdits' && permissionMode !== 'default') {
  throw new Error(
    `PERMISSION_MODE는 acceptEdits 또는 default만 사용할 수 있습니다. (현재 값: ${permissionMode})`,
  );
}

export const config = {
  port: toInt(process.env.PORT, 3000),
  workspaceDir: resolve(process.env.WORKSPACE_DIR ?? './workspace'),
  /** 대시보드에서 편집하는 에이전트 목록 저장 파일 */
  agentsFile: resolve(process.env.AGENTS_FILE ?? './data/agents.json'),
  /** /model 등으로 바꾼 실행 설정 저장 파일 */
  settingsFile: resolve(process.env.SETTINGS_FILE ?? './data/settings.json'),
  /** 실행 비용/토큰 누적 기록 (/cost) */
  costFile: resolve(process.env.COST_FILE ?? './data/cost.json'),
  /** 명령 첨부 업로드 보관 일수. 0이면 자동 정리 안 함 */
  uploadRetentionDays: toIntOrZero(process.env.UPLOAD_RETENTION_DAYS, 7),
  /** 자동 정리 검사 주기 */
  uploadCleanupIntervalMs: 60 * 60 * 1000,
  permissionMode,
  /**
   * 휴대폰 등 같은 네트워크의 다른 기기에서 접속할 때 쓰는 비밀번호. 설정하면(8자 이상) 서버를 네트워크에 열고,
   * 이 컴퓨터가 아닌 곳에서 오는 요청은 로그인해야 쓸 수 있다. 비우면 지금처럼 이 컴퓨터에서만 접속된다.
   */
  accessPassword: process.env.ACCESS_PASSWORD?.trim() || undefined,
  model: process.env.MODEL?.trim() || undefined,
  maxTurns: toInt(process.env.MAX_TURNS, 60),
  maxBudgetUsd: toFloat(process.env.MAX_BUDGET_USD, 2),
  /** 로그인으로 토큰을 받으면 재시작 없이 바로 반영되도록, 값이 아니라 매번 확인하는 함수 */
  hasAuth: () => Boolean(process.env.ANTHROPIC_API_KEY || process.env.CLAUDE_CODE_OAUTH_TOKEN),
  /** 어떤 방식으로 인증됐는지. API 키가 있으면 SDK가 그것을 우선 쓰므로 api_key로 본다 */
  authMethod: (): AuthMethod =>
    process.env.ANTHROPIC_API_KEY ? 'api_key' : process.env.CLAUDE_CODE_OAUTH_TOKEN ? 'oauth' : null,
};

export type AuthMethod = 'api_key' | 'oauth' | null;
