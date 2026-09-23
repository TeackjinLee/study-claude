/** 백엔드 GitController(/api/git) 호출 — 결과 미리보기의 "변경사항" 탭이 쓴다 */
const BACKEND_URL = process.env.NEXT_PUBLIC_BACKEND_URL ?? 'http://localhost:3000';

export type ChangeStatus = 'modified' | 'added' | 'deleted' | 'renamed' | 'untracked' | 'conflicted';

/** 변경 목록의 파일 하나 (diff 본문은 gitApi.diff로 따로 받는다) */
export interface FileChange {
  path: string;
  from?: string;
  status: ChangeStatus;
  additions: number;
  deletions: number;
  binary: boolean;
}

export interface FileDiff {
  ok: boolean;
  error?: string;
  diff: string;
  truncated: boolean;
}

export type ChangesResult =
  | { repo: false; workspace: string; message: string }
  | { repo: true; workspace: string; branch: string; hasHead: boolean; files: FileChange[]; omitted: number };

export type GitResult = { ok: boolean; error?: string };

async function call<T>(path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${BACKEND_URL}/api/git/${path}`, {
    method: body === undefined ? 'GET' : 'POST',
    headers: body === undefined ? undefined : { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`서버 오류 (${res.status})`);
  return res.json() as Promise<T>;
}

export const gitApi = {
  changes: () => call<ChangesResult>('changes'),
  diff: (path: string) => call<FileDiff>(`diff?path=${encodeURIComponent(path)}`),
  revert: (path: string) => call<GitResult>('revert', { path }),
  commit: (message: string, opts: { branch?: string; paths?: string[] } = {}) => call<GitResult & { hash?: string; branch?: string }>('commit', { message, ...opts }),
  suggestMessage: () => call<GitResult & { message?: string }>('commit-message', {}),
};
