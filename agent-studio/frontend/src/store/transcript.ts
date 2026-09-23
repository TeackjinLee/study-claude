import type { AgentRole } from '@/types/agent';
import type { CheckpointFile, RunMode, RunResult, ToolDetail, TxAgent, TxEvent } from '@/lib/ws';

/**
 * 대화 화면(Claude Code처럼 명령 → 글 → 도구 호출 → 결과가 이어지는 화면)의 항목.
 * 같은 대화를 이어가는 동안(코드·채팅) 쌓이고, 새 대화·/clear·이어가지 않는 실행에서 비운다.
 */
export type TxItem =
  | { kind: 'user'; id: string; text: string; mode?: RunMode; followUp?: boolean; to?: AgentRole; attachments?: number; at: number }
  /** draft: 지금 쓰는 중인 글 (실시간으로 이어 붙고, 완성된 글이 오면 text로 옮긴다) */
  | { kind: 'text'; id: string; agent: TxAgent; text: string; draft?: string }
  | { kind: 'tool'; id: string; agent: TxAgent; tool: string; label: string; detail?: ToolDetail; status: 'running' | 'ok' | 'error'; output?: string }
  | { kind: 'agent'; id: string; agent: AgentRole; task: string; status: 'running' | 'ok' | 'error'; summary?: string }
  | { kind: 'plan'; id: string; items: { text: string; status: 'pending' | 'in_progress' | 'completed' }[] }
  | { kind: 'result'; id: string; ok: boolean; costUsd?: number; turns?: number; durationMs?: number; text?: string }
  | { kind: 'notice'; id: string; tone: 'error' | 'warn'; text: string }
  /** 실행이 바꾼 파일과 되돌리기 상태 (restored가 files 전부면 되돌림 완료) */
  | { kind: 'checkpoint'; id: string; files: CheckpointFile[]; restored: string[]; skipped: { path: string; reason: string }[]; complete: boolean }
  /** 대화 압축 경계. 이 위의 내용은 Claude가 요약본으로만 기억한다 */
  | { kind: 'compact'; id: string; trigger: 'manual' | 'auto'; preTokens: number; postTokens?: number };

const MAX_ITEMS = 1500;
let seq = 0;
const nextId = (p: string) => `${p}-${Date.now().toString(36)}-${seq++}`;

const cap = (items: TxItem[]) => (items.length > MAX_ITEMS ? items.slice(-MAX_ITEMS) : items);

export function txUser(items: TxItem[], text: string, opts: { mode?: RunMode; followUp?: boolean; attachments?: number; reset?: boolean } = {}): TxItem[] {
  const base = opts.reset ? [] : items;
  return cap([...base, { kind: 'user', id: nextId('u'), text, mode: opts.mode, followUp: opts.followUp, attachments: opts.attachments, at: Date.now() }]);
}

/** 실행 결과. 성공이면 요약 글은 바로 앞의 마지막 글과 같으므로 통계만, 실패면 사유도 */
export function txResult(items: TxItem[], result: RunResult): TxItem[] {
  const lastText = [...items].reverse().find((i) => i.kind === 'text' || i.kind === 'user');
  const duplicate = lastText?.kind === 'text' && result.result && lastText.text.trim() === result.result.trim();
  return cap([
    ...settleRunning(items, result.ok),
    { kind: 'result', id: nextId('r'), ok: result.ok, costUsd: result.costUsd, turns: result.turns, durationMs: result.durationMs, text: duplicate ? undefined : result.result || undefined },
  ]);
}

export function txNotice(items: TxItem[], tone: 'error' | 'warn', text: string): TxItem[] {
  return cap([...settleRunning(items, false), { kind: 'notice', id: nextId('n'), tone, text }]);
}

/** 실행이 끝났는데 결과를 못 받은 도구·에이전트 호출은 멈춘 것으로, 쓰다 만 글은 받은 데까지 글로 남긴다 */
function settleRunning(items: TxItem[], ok: boolean): TxItem[] {
  const unsettled = (i: TxItem) => ((i.kind === 'tool' || i.kind === 'agent') && i.status === 'running') || (i.kind === 'text' && i.draft !== undefined);
  if (!items.some(unsettled)) return items;
  return items
    .map((i): TxItem => {
      if (!unsettled(i)) return i;
      if (i.kind === 'text') return { ...i, text: joinText(i.text, i.draft?.trim() ?? ''), draft: undefined };
      return { ...i, status: ok ? 'ok' : 'error' } as TxItem;
    })
    .filter((i) => i.kind !== 'text' || i.text !== '');
}

const joinText = (a: string, b: string) => (a && b ? `${a}\n\n${b}` : a || b);

export function applyTx(items: TxItem[], e: TxEvent): TxItem[] {
  switch (e.t) {
    case 'text_delta': {
      // 쓰는 중인 글은 마지막 글 항목의 draft에 이어 붙인다
      const last = items[items.length - 1];
      if (last?.kind === 'text' && last.agent === e.agent) return [...items.slice(0, -1), { ...last, draft: (last.draft ?? '') + e.text }];
      return cap([...items, { kind: 'text', id: nextId('t'), agent: e.agent, text: '', draft: e.text }]);
    }
    case 'text': {
      // 블록 하나가 완성됐다. 쓰던 글(draft)을 완성된 글로 바꾸고, 같은 주인의 글이 연달아 오면 한 덩어리로 붙인다
      const last = items[items.length - 1];
      if (last?.kind === 'text' && last.agent === e.agent) return [...items.slice(0, -1), { ...last, text: joinText(last.text, e.text), draft: undefined }];
      return cap([...items, { kind: 'text', id: nextId('t'), agent: e.agent, text: e.text }]);
    }
    case 'tool_start':
      if (items.some((i) => i.kind === 'tool' && i.id === e.id)) return items;
      return cap([...items, { kind: 'tool', id: e.id, agent: e.agent, tool: e.tool, label: e.label, detail: e.detail, status: 'running' }]);
    case 'tool_done':
      return items.map((i) => (i.kind === 'tool' && i.id === e.id ? { ...i, status: e.ok ? 'ok' : 'error', output: e.output } : i));
    case 'agent_start':
      if (items.some((i) => i.kind === 'agent' && i.id === e.id)) return items;
      return cap([...items, { kind: 'agent', id: e.id, agent: e.agent, task: e.task, status: 'running' }]);
    case 'agent_done':
      return items.map((i) => (i.kind === 'agent' && i.id === e.id ? { ...i, status: e.ok ? 'ok' : 'error', summary: e.summary } : i));
    case 'plan': {
      // 할 일 목록은 한 실행에 하나. 이번 실행(마지막 사용자 입력 뒤)의 목록이 있으면 그 자리에서 갱신한다
      const lastUser = items.map((i) => i.kind).lastIndexOf('user');
      const idx = items.findIndex((i, n) => n > lastUser && i.kind === 'plan');
      if (idx >= 0) return items.map((i, n) => (n === idx ? { ...(i as Extract<TxItem, { kind: 'plan' }>), items: e.items } : i));
      return cap([...items, { kind: 'plan', id: nextId('p'), items: e.items }]);
    }
    case 'checkpoint':
      if (items.some((i) => i.kind === 'checkpoint' && i.id === e.id)) return items;
      return cap([...items, { kind: 'checkpoint', id: e.id, files: e.files, restored: [], skipped: [], complete: false }]);
    case 'checkpoint_undone':
      return items.map((i) =>
        i.kind === 'checkpoint' && i.id === e.id ? { ...i, restored: [...new Set([...i.restored, ...e.restored])], skipped: e.skipped, complete: e.complete } : i,
      );
    case 'compacted':
      return cap([...items, { kind: 'compact', id: nextId('c'), trigger: e.trigger, preTokens: e.preTokens, postTokens: e.postTokens }]);
    case 'user_to':
      return cap([...items, { kind: 'user', id: nextId('u'), text: e.text, to: e.agent, at: Date.now() }]);
  }
}
