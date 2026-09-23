/** 백엔드 FileSuggestionsController(/api/file-suggestions) 호출 — 입력창의 @파일 자동완성 */

import { apiFetch } from '@/lib/backend';

export interface FileSuggestion {
  /** 작업 폴더 기준 경로. 폴더는 끝에 / */
  path: string;
  dir: boolean;
}

export async function fetchFileSuggestions(q: string, signal?: AbortSignal): Promise<FileSuggestion[]> {
  const res = await apiFetch(`/api/file-suggestions?q=${encodeURIComponent(q)}`, { signal });
  if (!res.ok) throw new Error(`서버 오류 (${res.status})`);
  return ((await res.json()) as { items: FileSuggestion[] }).items;
}
