/** 명령 입력창의 입력 기록(↑/↓)과 쓰던 초안. 브라우저에만 저장한다 */

const HISTORY_KEY = 'agent-studio.inputHistory';
const DRAFT_KEY = 'agent-studio.inputDraft';
export const MAX_HISTORY = 100;

/** 보낸 명령을 기록 끝에 넣는다. 빈 글은 넣지 않고, 바로 앞과 같으면 한 번만 (오래된 것부터 버린다) */
export function addToHistory(list: string[], text: string, max = MAX_HISTORY): string[] {
  const t = text.trim();
  if (!t || list[list.length - 1] === t) return list;
  return [...list, t].slice(-max);
}

/**
 * ↑/↓로 기록을 오갈 때 다음 위치. index는 뒤에서부터 센 번호(-1 = 기록을 보고 있지 않음, 0 = 가장 최근).
 * 끝을 넘어가면 그대로 둔다. -1로 돌아오면 쓰던 초안을 되살린다.
 */
export function stepHistory(length: number, index: number, dir: 'up' | 'down'): number {
  if (dir === 'up') return length === 0 ? -1 : Math.min(index + 1, length - 1);
  return Math.max(index - 1, -1);
}

/** 커서가 첫 줄에 있는지 (↑가 줄 이동 대신 기록을 불러오는 조건) */
export const onFirstLine = (text: string, caret: number) => !text.slice(0, caret).includes('\n');
/** 커서가 마지막 줄에 있는지 (↓ 조건) */
export const onLastLine = (text: string, caret: number) => !text.slice(caret).includes('\n');

function read(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function write(key: string, value: string | null) {
  try {
    if (value === null) localStorage.removeItem(key);
    else localStorage.setItem(key, value);
  } catch {
    // 저장할 수 없으면(사생활 보호 모드 등) 이번 화면에서만 유지
  }
}

export function loadHistory(): string[] {
  try {
    const raw = JSON.parse(read(HISTORY_KEY) ?? '[]') as unknown;
    return Array.isArray(raw) ? raw.filter((v): v is string => typeof v === 'string').slice(-MAX_HISTORY) : [];
  } catch {
    return [];
  }
}

export const saveHistory = (list: string[]) => write(HISTORY_KEY, JSON.stringify(list));
export const loadDraft = () => read(DRAFT_KEY) ?? '';
export const saveDraft = (text: string) => write(DRAFT_KEY, text ? text : null);
