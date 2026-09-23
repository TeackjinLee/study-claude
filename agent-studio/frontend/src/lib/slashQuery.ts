/** 입력창의 슬래시 명령 파싱 (SlashCommandMenu가 쓰고, 테스트하기 쉽게 따로 둔다) */

/**
 * 슬래시 명령을 고를 수 있는지 (아직 인자를 입력하기 전).
 * `/xxx` → 일반 명령, `/codex /xxx` → Codex 하위 명령(모드, 모델, 상태 등)
 */
export function slashQuery(value: string): { query: string; scope: 'codex' | null; arg?: string } | null {
  const codex = /^\/codex\s+\/([\w-]*)$/i.exec(value);
  if (codex) return { query: codex[1].toLowerCase(), scope: 'codex' };
  const m = /^\/([\w-]*)$/.exec(value);
  if (m) return { query: m[1].toLowerCase(), scope: null };
  // 명령 뒤에 인자를 한 토큰 치는 중 (`/model op`, `/codex /model gpt`) → 그 명령에 선택지가 있으면 인자 메뉴
  const codexArg = /^\/codex\s+\/([\w-]+)\s+(\S*)$/i.exec(value);
  if (codexArg) return { query: codexArg[1].toLowerCase(), scope: 'codex', arg: codexArg[2] };
  const a = /^\/([\w-]+)\s+(\S*)$/.exec(value);
  return a ? { query: a[1].toLowerCase(), scope: null, arg: a[2] } : null;
}
