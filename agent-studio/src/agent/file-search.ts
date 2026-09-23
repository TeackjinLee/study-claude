/** @파일 자동완성 순위 매기기 (FileIndexService가 쓰고, 테스트하기 쉽게 순수 함수로 둔다) */

export interface FileSuggestion {
  /** 작업 폴더 기준 경로. 폴더는 끝에 / */
  path: string;
  dir: boolean;
}

/** 파일 목록에서 그 파일들이 들어 있는 폴더도 뽑아 후보에 넣는다 */
export function withDirs(files: string[]): FileSuggestion[] {
  const dirs = new Set<string>();
  for (const f of files) {
    let i = f.indexOf('/');
    while (i > 0) {
      dirs.add(f.slice(0, i + 1));
      i = f.indexOf('/', i + 1);
    }
  }
  return [...[...dirs].map((path) => ({ path, dir: true })), ...files.map((path) => ({ path, dir: false }))];
}

const baseName = (p: string) => {
  const trimmed = p.endsWith('/') ? p.slice(0, -1) : p;
  return trimmed.slice(trimmed.lastIndexOf('/') + 1);
};

/** 글자가 순서대로 다 들어 있는지 (vdrc → vehicle_driver_controller) */
function isSubsequence(q: string, s: string) {
  let i = 0;
  for (let j = 0; j < s.length && i < q.length; j++) if (s[j] === q[i]) i++;
  return i === q.length;
}

/**
 * 순위: 이름이 검색어로 시작 → 이름에 포함 → 경로에 포함 → 글자 순서만 일치. 같으면 얕고 짧은 경로가 먼저.
 * 검색어가 비었으면 맨 위 폴더의 항목만 보여준다. 검색어에 /가 있으면 그 경로 아래를 찾는다.
 */
export function rankFiles(candidates: FileSuggestion[], rawQuery: string, limit = 30): FileSuggestion[] {
  const q = rawQuery.toLowerCase();
  const depth = (p: string) => p.replace(/\/$/, '').split('/').length;
  const byPath = (a: FileSuggestion, b: FileSuggestion) => depth(a.path) - depth(b.path) || a.path.length - b.path.length || a.path.localeCompare(b.path);
  if (!q) return candidates.filter((c) => depth(c.path) === 1).sort((a, b) => Number(b.dir) - Number(a.dir) || a.path.localeCompare(b.path)).slice(0, limit);

  const scored: { c: FileSuggestion; score: number }[] = [];
  for (const c of candidates) {
    const path = c.path.toLowerCase();
    const name = baseName(path);
    let score = -1;
    // 이미 다 친 폴더(scripts/)는 다시 보여주지 않고 그 안의 항목만
    if (path === q) continue;
    if (q.includes('/')) {
      if (path.startsWith(q)) score = 0;
      else if (path.includes(q)) score = 2;
      else if (isSubsequence(q, path)) score = 3;
    } else if (name.startsWith(q)) score = 0;
    else if (name.includes(q)) score = 1;
    else if (path.includes(q)) score = 2;
    else if (isSubsequence(q, name)) score = 3;
    if (score >= 0) scored.push({ c, score });
  }
  return scored
    .sort((a, b) => a.score - b.score || byPath(a.c, b.c))
    .slice(0, limit)
    .map((s) => s.c);
}
