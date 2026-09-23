/** git 출력 파싱 (GitService가 쓰고, 테스트하기 쉽게 순수 함수로 둔다) */

export type ChangeStatus = 'modified' | 'added' | 'deleted' | 'renamed' | 'untracked' | 'conflicted';

export interface StatusEntry {
  /** 저장소 루트 기준 경로 */
  path: string;
  /** 이름이 바뀐 경우 원래 경로 */
  from?: string;
  /** git status의 두 글자 (X=스테이지, Y=작업 트리) */
  code: string;
  status: ChangeStatus;
}

function statusOf(code: string): ChangeStatus {
  if (code === '??') return 'untracked';
  if (code.includes('U') || code === 'AA' || code === 'DD') return 'conflicted';
  if (code.includes('R') || code.includes('C')) return 'renamed';
  if (code.includes('D')) return 'deleted';
  if (code[0] === 'A') return 'added';
  return 'modified';
}

/** `git status --porcelain=v1 -z` 출력. 이름 바꿈(R/C)은 "새 경로\0원래 경로" 순서로 온다 */
export function parsePorcelainZ(out: string): StatusEntry[] {
  const parts = out.split('\0');
  const entries: StatusEntry[] = [];
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i];
    if (part.length < 4) continue;
    const code = part.slice(0, 2);
    const path = part.slice(3);
    const status = statusOf(code);
    if (status === 'renamed') {
      entries.push({ path, from: parts[i + 1], code, status });
      i++;
    } else {
      entries.push({ path, code, status });
    }
  }
  return entries;
}

/** unified diff에서 추가/삭제 줄 수 (파일 머리글 +++/--- 는 뺀다) */
export function countDiff(diff: string): { additions: number; deletions: number } {
  let additions = 0;
  let deletions = 0;
  let inHunk = false;
  for (const line of diff.split('\n')) {
    if (line.startsWith('@@')) inHunk = true;
    else if (line.startsWith('diff --git')) inHunk = false;
    else if (!inHunk) continue;
    else if (line.startsWith('+')) additions++;
    else if (line.startsWith('-')) deletions++;
  }
  return { additions, deletions };
}

/** 새 파일(추적 안 됨)의 내용을 diff 모양으로 */
export function newFileDiff(path: string, text: string): string {
  const lines = text.replace(/\n$/, '').split('\n');
  return [`diff --git a/${path} b/${path}`, 'new file', '--- /dev/null', `+++ b/${path}`, `@@ -0,0 +1,${lines.length} @@`, ...lines.map((l) => `+${l}`)].join('\n');
}

/** 저장소 루트 기준 경로 → 작업 폴더 기준 경로 (prefix는 `git rev-parse --show-prefix`, 끝에 / 포함 또는 빈 문자열) */
export const stripPrefix = (path: string, prefix: string) => (prefix && path.startsWith(prefix) ? path.slice(prefix.length) : path);

/** 브랜치 이름으로 쓸 수 있는지 (최종 판단은 git check-ref-format, 여기서는 명백히 위험한 값을 거른다) */
export const looksLikeBranchName = (name: string) => /^[\w./-]{1,100}$/.test(name) && !name.startsWith('-') && !name.includes('..');

export interface NumstatEntry {
  path: string;
  from?: string;
  additions: number;
  deletions: number;
  binary: boolean;
}

/**
 * `git diff --numstat -z` 출력. 한 줄은 "추가\t삭제\t경로\0", 이름 바꿈은 "추가\t삭제\t\0원래\0새경로\0".
 * 바이너리 파일은 추가·삭제가 "-"로 온다.
 */
export function parseNumstatZ(out: string): NumstatEntry[] {
  const parts = out.split('\0');
  const entries: NumstatEntry[] = [];
  for (let i = 0; i < parts.length; i++) {
    const m = /^(-|\d+)\t(-|\d+)\t(.*)$/s.exec(parts[i]);
    if (!m) continue;
    const binary = m[1] === '-';
    const counts = { additions: binary ? 0 : Number(m[1]), deletions: binary ? 0 : Number(m[2]), binary };
    if (m[3] === '') {
      entries.push({ from: parts[i + 1], path: parts[i + 2], ...counts });
      i += 2;
    } else {
      entries.push({ path: m[3], ...counts });
    }
  }
  return entries;
}

/** 새 파일(추적 안 됨)의 줄 수. 끝의 줄바꿈 하나는 줄로 세지 않는다 */
export const countLines = (text: string) => (text ? text.replace(/\n$/, '').split('\n').length : 0);
