/** 백엔드 ConversationsController(/api/conversations) 호출 — 지난 대화 목록 */
import type { RunMode } from '@/lib/ws';

const BACKEND_URL = process.env.NEXT_PUBLIC_BACKEND_URL ?? 'http://localhost:3000';

export interface ConversationMeta {
  id: string;
  mode: RunMode;
  workspaceDir: string;
  title: string;
  sessionId?: string;
  createdAt: number;
  updatedAt: number;
  runs: number;
  costUsd: number;
}

type Result = { ok: boolean; error?: string };

async function call<T>(path: string, method = 'GET'): Promise<T> {
  const res = await fetch(`${BACKEND_URL}/api/conversations${path}`, { method });
  if (!res.ok) throw new Error(`서버 오류 (${res.status})`);
  return res.json() as Promise<T>;
}

export const conversationsApi = {
  list: () => call<{ workspace: string; conversations: ConversationMeta[] }>(''),
  /** 열면 서버가 소켓으로 기록을 보내 대화 화면이 다시 그려진다 */
  open: (id: string) => call<Result>(`/${encodeURIComponent(id)}/open`, 'POST'),
  remove: (id: string) => call<Result>(`/${encodeURIComponent(id)}`, 'DELETE'),
};
