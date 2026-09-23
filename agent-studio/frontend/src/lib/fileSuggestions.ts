/** 백엔드 FileSuggestionsController(/api/file-suggestions) 호출 — 입력창의 @파일 자동완성 */

const BACKEND_URL = process.env.NEXT_PUBLIC_BACKEND_URL ?? 'http://localhost:3000';

export interface FileSuggestion {
  /** 작업 폴더 기준 경로. 폴더는 끝에 / */
  path: string;
  dir: boolean;
}

export async function fetchFileSuggestions(q: string, signal?: AbortSignal): Promise<FileSuggestion[]> {
  const res = await fetch(`${BACKEND_URL}/api/file-suggestions?q=${encodeURIComponent(q)}`, { signal });
  if (!res.ok) throw new Error(`서버 오류 (${res.status})`);
  return ((await res.json()) as { items: FileSuggestion[] }).items;
}

/** 커서 바로 앞의 @검색어 (없으면 null). 이메일 같은 a@b는 빼려고 @ 앞은 공백이나 줄 처음이어야 한다 */
export function atQuery(text: string, caret: number): { start: number; query: string } | null {
  const m = /(^|\s)@([^\s@]*)$/.exec(text.slice(0, caret));
  return m ? { start: caret - m[2].length - 1, query: m[2] } : null;
}
