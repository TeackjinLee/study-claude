'use client';

import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { useAgentStore } from '@/store/agentStore';
import type { TxItem } from '@/store/transcript';
import type { ToolDetail, TxAgent } from '@/lib/ws';
import { lineDiff } from '@/lib/lineDiff';
import { ChatIcon, ChevronDownIcon, ClaudeMarkIcon, RetryIcon, UserIcon } from '@/components/ui/icons';
import { CopyButton } from '@/components/ui/CopyButton';
import { AgentAvatar } from './AgentAvatar';
import { Markdown } from './Markdown';
import { ConversationHistoryMenu } from './ConversationHistoryMenu';
import { PermissionCard } from './PermissionBanner';

const MODE_LABEL = { code: '코드', chat: '채팅', cowork: 'Cowork' } as const;

function formatDuration(ms?: number) {
  if (ms === undefined) return '';
  const s = Math.max(0, Math.round(ms / 1000));
  return s < 60 ? `${s}초` : `${Math.floor(s / 60)}분 ${s % 60}초`;
}

/**
 * 대화 화면 — Claude Code 터미널처럼 한 줄기로 이어지는 기록.
 * 내 명령 → Claude의 글 → 도구 호출(펼치면 명령·수정 diff·출력) → 결과. 이어지는 대화(코드·채팅)는 계속 쌓인다.
 */
export function ConversationPanel() {
  const items = useAgentStore((s) => s.transcript);
  const running = useAgentStore((s) => s.running);
  const run = useAgentStore((s) => s.run);
  const title = useAgentStore((s) => {
    const mode = s.run?.mode ?? s.commandMode;
    return s.conversations[mode] ? s.conversationTitles[mode]?.title : undefined;
  });
  const scroller = useRef<HTMLDivElement | null>(null);
  /** 사용자가 위로 스크롤해 읽는 중이면 새 항목이 와도 끌어내리지 않는다 */
  const stick = useRef(true);

  // 새 승인 요청은 위로 올려 읽는 중이어도 보이게 끌어내린다 (답해야 실행이 이어진다)
  const pendingCount = useAgentStore((s) => s.permissions.length);
  const lastPending = useRef(0);
  /** 위로 올려 읽는 동안 새 글이 왔는지 → "새 메시지" 버튼 */
  const [unseen, setUnseen] = useState(false);
  const toBottom = () => {
    const el = scroller.current;
    stick.current = true;
    setUnseen(false);
    el?.scrollTo({ top: el.scrollHeight, behavior: 'smooth' });
  };
  const lastItems = useRef(items);
  useLayoutEffect(() => {
    const el = scroller.current;
    if (pendingCount > lastPending.current) stick.current = true;
    lastPending.current = pendingCount;
    const changed = lastItems.current !== items;
    lastItems.current = items;
    if (el && stick.current) el.scrollTop = el.scrollHeight;
    else if (changed && items.length > 0) setUnseen(true);
  }, [items, running, pendingCount]);

  const totals = useMemo(() => {
    let cost = 0;
    let turns = 0;
    for (const i of items) {
      if (i.kind === 'result') {
        cost += i.costUsd ?? 0;
        turns += i.turns ?? 0;
      }
    }
    return { cost, turns, runs: items.filter((i) => i.kind === 'user' && !i.followUp && !i.to).length };
  }, [items]);

  const last = items[items.length - 1];
  const retry = useAgentStore((s) => s.retryLastRun);
  /** 마지막 명령이 실패·중단으로 끝났으면 "다시 시도" (결과 뒤의 되돌리기 기록은 건너뛰고 본다) */
  const canRetry = useMemo(() => {
    if (running || !run) return false;
    for (let i = items.length - 1; i >= 0; i--) {
      const it = items[i];
      if (it.kind === 'result') return !it.ok;
      if (it.kind === 'notice') return true;
      if (it.kind === 'user') return false;
    }
    return false;
  }, [items, running, run]);
  const waiting = running && pendingCount === 0 && !(last?.kind === 'tool' && last.status === 'running') && !(last?.kind === 'agent' && last.status === 'running');

  return (
    <section className="panel relative flex h-full min-h-0 flex-col overflow-hidden">
      <div className="flex items-center gap-2 border-b border-line px-4 py-2.5 text-[12px]">
        <ChatIcon className="h-4 w-4 shrink-0 text-blue-300" />
        <span className="shrink-0 font-bold text-white">대화</span>
        {run?.mode && <span className="shrink-0 rounded border border-line px-1.5 py-0.5 text-[10px] font-semibold text-slate-300">{MODE_LABEL[run.mode]}</span>}
        {title && (
          <span className="min-w-0 truncate text-[12px] text-slate-400" title={title}>
            {title}
          </span>
        )}
        {running && (
          <span className="inline-flex shrink-0 items-center gap-1 text-[11px] font-semibold text-blue-300">
            <span className="pulse-dot h-1.5 w-1.5 rounded-full bg-blue-400" />
            실행 중
          </span>
        )}
        <div className="ml-auto flex shrink-0 items-center gap-2">
          {totals.runs > 0 && (
            <span className="hidden text-[11px] text-muted sm:inline">
              명령 {totals.runs}개 · {totals.turns}턴 · ${totals.cost.toFixed(4)}
            </span>
          )}
          <ContextMeter />
          <ConversationHistoryMenu />
        </div>
      </div>

      <div
        ref={scroller}
        onScroll={(e) => {
          const el = e.currentTarget;
          stick.current = el.scrollHeight - el.scrollTop - el.clientHeight < 60;
          if (stick.current) setUnseen(false);
        }}
        className="min-h-0 flex-1 overflow-y-auto bg-[#08101f] px-4 py-3"
      >
        {items.length === 0 ? (
          <div className="flex h-full flex-col items-center justify-center gap-2 text-center">
            <ClaudeMarkIcon className="h-8 w-8 text-[#d97757]" />
            <p className="text-[13px] font-semibold text-slate-200">아래 명령 입력에서 Claude에게 일을 시켜 보세요</p>
            <p className="max-w-md text-[12px] leading-relaxed text-slate-500">
              코드 모드에서는 Claude가 직접 파일을 읽고 고치고 명령을 실행합니다. 그 과정이 여기에 차례로 쌓이고, 도구 줄을 누르면 실행한 명령·수정한 내용·출력을 볼 수 있습니다.
            </p>
          </div>
        ) : (
          <ol className="flex flex-col gap-3">
            {items.map((item) => (
              <li key={item.id}>
                <TxRow item={item} />
              </li>
            ))}
            {waiting && (
              <li className="flex items-center gap-2 pl-8 text-[12px] text-slate-500">
                <span className="pulse-dot h-1.5 w-1.5 rounded-full bg-[#d97757]" />
                생각하는 중…
              </li>
            )}
            {canRetry && run && (
              <li className="pl-8">
                <button
                  type="button"
                  onClick={retry}
                  title={`같은 명령을 다시 실행합니다${run.attachments.length ? ` (첨부 ${run.attachments.length}개 포함)` : ''}: ${run.command}`}
                  className="inline-flex items-center gap-1.5 rounded-md border border-line px-2.5 py-1 text-[12px] font-semibold text-slate-200 hover:border-accent/60 hover:text-white"
                >
                  <RetryIcon className="h-3.5 w-3.5" />
                  다시 시도
                </button>
              </li>
            )}
          </ol>
        )}
      </div>
      {unseen && (
        <button
          type="button"
          onClick={toBottom}
          className="absolute bottom-3 left-1/2 z-10 -translate-x-1/2 rounded-full border border-accent/60 bg-[#0a1428]/95 px-3 py-1 text-[11px] font-semibold text-blue-100 shadow-[0_6px_18px_rgba(0,0,0,0.5)] hover:bg-accent/20"
        >
          ↓ 새 메시지
        </button>
      )}
    </section>
  );
}

function Who({ agent }: { agent: TxAgent }) {
  const def = useAgentStore((s) => (agent === 'main' ? undefined : s.defsById[agent]));
  if (agent === 'main') {
    return (
      <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-md bg-[#d97757]/15">
        <ClaudeMarkIcon className="h-4 w-4 text-[#d97757]" />
      </span>
    );
  }
  return <AgentAvatar role={agent} def={def} size={24} />;
}

function whoName(agent: TxAgent, names: Record<string, string>) {
  return agent === 'main' ? 'Claude' : (names[agent] ?? agent);
}

function TxRow({ item }: { item: TxItem }) {
  const defsById = useAgentStore((s) => s.defsById);
  const names = useMemo(() => Object.fromEntries(Object.values(defsById).map((d) => [d.id, d.shortName])), [defsById]);

  switch (item.kind) {
    case 'user':
      return (
        <div className="flex items-start gap-2">
          <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-md bg-accent/20 text-blue-200">
            <UserIcon className="h-3.5 w-3.5" />
          </span>
          <div className="min-w-0 flex-1 rounded-lg border border-accent/30 bg-accent/10 px-3 py-2">
            {(item.followUp || item.to || !!item.attachments) && (
              <p className="mb-0.5 text-[10px] font-semibold text-blue-300">
                {item.followUp ? '추가 지시' : item.to ? `→ ${names[item.to] ?? item.to}에게` : ''}
                {item.attachments ? `${item.followUp || item.to ? ' · ' : ''}첨부 ${item.attachments}개` : ''}
              </p>
            )}
            <p className="whitespace-pre-wrap break-words text-[13px] text-white">{item.text}</p>
          </div>
        </div>
      );

    case 'text':
      return (
        <div className="group/text relative flex items-start gap-2">
          {item.draft === undefined && item.text && (
            <CopyButton text={item.text} className="absolute right-0 top-0 z-[1] opacity-0 focus:opacity-100 group-hover/text:opacity-100" />
          )}
          <Who agent={item.agent} />
          <div className="min-w-0 flex-1 pt-0.5">
            {item.agent !== 'main' && <p className="mb-0.5 text-[11px] font-semibold text-slate-400">{whoName(item.agent, names)}</p>}
            {item.text && <Markdown text={item.text} />}
            {item.draft !== undefined && (
              // 쓰는 중: 마지막 줄 끝에 깜빡이는 커서
              <Markdown
                text={item.draft || ' '}
                className={`${item.text ? 'mt-2' : ''} [&>*:last-child]:after:ml-0.5 [&>*:last-child]:after:animate-pulse [&>*:last-child]:after:text-blue-300 [&>*:last-child]:after:content-['▍']`}
              />
            )}
          </div>
        </div>
      );

    case 'tool':
      return <ToolRow item={item} name={item.agent === 'main' ? null : whoName(item.agent, names)} />;

    case 'agent':
      return <AgentRow item={item} name={names[item.agent] ?? item.agent} />;

    case 'plan':
      return (
        <div className="ml-8 rounded-lg border border-line bg-panel/60 px-3 py-2">
          <p className="mb-1 text-[11px] font-semibold text-slate-400">할 일</p>
          <ul className="flex flex-col gap-0.5 text-[12px]">
            {item.items.map((p, n) => (
              <li key={n} className={`flex items-start gap-1.5 ${p.status === 'completed' ? 'text-slate-500 line-through' : p.status === 'in_progress' ? 'text-white' : 'text-slate-300'}`}>
                <span className="mt-px w-3 shrink-0 text-center">{p.status === 'completed' ? '✓' : p.status === 'in_progress' ? '▸' : '○'}</span>
                {p.text}
              </li>
            ))}
          </ul>
        </div>
      );

    case 'result':
      return (
        <div className="ml-8 flex flex-col gap-1">
          {item.text && <p className={`whitespace-pre-wrap text-[12px] ${item.ok ? 'text-slate-300' : 'text-red-300'}`}>{item.text}</p>}
          <p className={`text-[11px] ${item.ok ? 'text-emerald-400/80' : 'text-red-300'}`}>
            {item.ok ? '✓ 완료' : '✕ 실패'}
            {item.turns !== undefined && ` · ${item.turns}턴`}
            {item.costUsd !== undefined && ` · $${item.costUsd.toFixed(4)}`}
            {item.durationMs !== undefined && ` · ${formatDuration(item.durationMs)}`}
          </p>
        </div>
      );

    case 'notice':
      return <p className={`ml-8 text-[12px] ${item.tone === 'error' ? 'text-red-300' : 'text-amber-300'}`}>{item.text}</p>;

    case 'checkpoint':
      return <CheckpointRow item={item} />;

    case 'permission':
      return <PermissionRow item={item} />;

    case 'compact':
      return (
        <div className="flex items-center gap-2 py-1 text-[11px] text-slate-500" title="이 위의 대화는 Claude가 요약본으로만 기억합니다">
          <span className="h-px flex-1 bg-line" />
          <span className="shrink-0">
            {item.trigger === 'auto' ? '컨텍스트가 차서 자동으로 압축했습니다' : '대화를 압축했습니다'}
            {item.preTokens > 0 && ` · ${formatTokens(item.preTokens)}${item.postTokens ? ` → ${formatTokens(item.postTokens)}` : ''} 토큰`}
          </span>
          <span className="h-px flex-1 bg-line" />
        </div>
      );
  }
}

const PERMISSION_DONE = {
  allowed: { mark: '✓', text: '허용함', cls: 'text-emerald-300' },
  denied: { mark: '✕', text: '거부함', cls: 'text-red-300' },
  expired: { mark: '–', text: '답하지 않고 끝남', cls: 'text-slate-500' },
} as const;

/** 승인 요청: 기다리는 중이면 대화 안에서 바로 답하는 카드, 답했으면 한 줄 기록 */
function PermissionRow({ item }: { item: Extract<TxItem, { kind: 'permission' }> }) {
  const request = useAgentStore((s) => (item.status === 'pending' ? s.permissions.find((p) => p.id === item.id) : undefined));
  if (request) return <PermissionCard request={request} />;
  const done = PERMISSION_DONE[item.status === 'pending' ? 'expired' : item.status];
  const plan = item.tool === 'ExitPlanMode';
  return (
    <p className="ml-8 flex min-w-0 items-center gap-1.5 text-[11px] text-slate-500">
      <span className={`shrink-0 font-semibold ${done.cls}`}>
        {done.mark} {plan ? (item.status === 'allowed' ? '계획 승인' : item.status === 'denied' ? '계획 거절' : '계획 승인 안 함') : done.text}
      </span>
      <span className="min-w-0 truncate" title={item.title}>
        · {item.title}
      </span>
    </p>
  );
}

function formatTokens(n: number) {
  return n >= 1000 ? `${(n / 1000).toFixed(n >= 100_000 ? 0 : 1)}k` : String(n);
}

/** 컨텍스트가 이만큼 차면 압축을 권한다 (Claude Code는 가득 차기 직전에 자동으로 압축한다) */
const CONTEXT_WARN_PCT = 70;

/**
 * 이어가는 대화의 컨텍스트 게이지와 압축 버튼.
 * 사용량은 실행이 끝날 때마다 서버가 재서 알려준다. 압축하면 지난 대화를 요약해 컨텍스트를 비우고 같은 대화를 이어간다.
 */
function ContextMeter() {
  const mode = useAgentStore((s) => s.run?.mode ?? s.commandMode);
  const info = useAgentStore((s) => (s.conversations[mode] ? s.conversationTitles[mode] : undefined));
  const running = useAgentStore((s) => s.running);
  const sendCommand = useAgentStore((s) => s.sendCommand);
  if (mode === 'cowork' || !info) return null;
  const ctx = info.context;
  const warn = !!ctx && ctx.pct >= CONTEXT_WARN_PCT;
  const tone = !ctx ? 'bg-slate-500' : ctx.pct >= 85 ? 'bg-red-400' : warn ? 'bg-amber-400' : 'bg-blue-400';
  const compact = () => {
    if (window.confirm('지금까지의 대화를 요약해 컨텍스트를 비울까요?\n같은 대화를 이어가지만 Claude는 앞부분을 요약본으로만 기억합니다.')) sendCommand('/compact', [], mode);
  };
  return (
    <div className="flex items-center gap-1.5">
      {ctx && (
        <span
          className="hidden items-center gap-1.5 text-[11px] text-muted md:inline-flex"
          title={`컨텍스트 ${ctx.tokens.toLocaleString()} / ${ctx.max.toLocaleString()} 토큰 (마지막 실행 기준). 가득 차면 자동으로 압축됩니다.`}
        >
          <span className="relative h-1.5 w-12 overflow-hidden rounded-full bg-white/10">
            <span className={`absolute inset-y-0 left-0 rounded-full ${tone}`} style={{ width: `${Math.max(2, ctx.pct)}%` }} />
          </span>
          <span className={warn ? 'font-semibold text-amber-300' : undefined}>{ctx.pct}%</span>
        </span>
      )}
      <button
        type="button"
        onClick={compact}
        disabled={running}
        title={running ? '실행이 끝난 뒤 압축할 수 있습니다' : '대화 압축 (/compact) — 지난 대화를 요약해 컨텍스트를 비웁니다'}
        className={`rounded-md border px-2 py-0.5 text-[11px] font-semibold transition disabled:cursor-not-allowed disabled:opacity-40 ${
          warn ? 'border-amber-400/60 bg-amber-400/10 text-amber-200 hover:bg-amber-400/20' : 'border-line text-slate-300 hover:border-accent/60 hover:text-white'
        }`}
      >
        압축
      </button>
    </div>
  );
}

const STATUS_DOT = {
  running: 'bg-blue-400 pulse-dot',
  ok: 'bg-emerald-400',
  error: 'bg-red-400',
} as const;

function ToolRow({ item, name }: { item: Extract<TxItem, { kind: 'tool' }>; name: string | null }) {
  // 파일 수정은 기본으로 펼쳐 diff를 보여주고, 실패한 도구도 펼친다
  const autoOpen = item.detail?.kind === 'edit' || item.detail?.kind === 'write' || item.status === 'error';
  const [open, setOpen] = useState<boolean | null>(null);
  const expanded = open ?? autoOpen;
  // 읽기·검색은 대상만 보면 충분하다. 출력이 있으면(실패 등) 펼칠 수 있다
  const hasBody = (!!item.detail && item.detail.kind !== 'read' && item.detail.kind !== 'search') || !!item.output;

  return (
    <div className="ml-8">
      <button
        type="button"
        onClick={() => hasBody && setOpen(!expanded)}
        className={`flex w-full min-w-0 items-center gap-2 rounded-md px-1.5 py-1 text-left ${hasBody ? 'hover:bg-white/[0.04]' : 'cursor-default'}`}
        aria-expanded={hasBody ? expanded : undefined}
      >
        <span className={`h-1.5 w-1.5 shrink-0 rounded-full ${STATUS_DOT[item.status]}`} />
        <span className="shrink-0 font-mono text-[12px] font-semibold text-slate-200">{item.tool}</span>
        <span className="min-w-0 flex-1 truncate font-mono text-[12px] text-slate-400">
          {name && <span className="text-slate-500">{name} · </span>}
          {toolSubject(item.detail) ?? item.label}
        </span>
        {hasBody && <ChevronDownIcon className={`h-3.5 w-3.5 shrink-0 text-slate-500 transition ${expanded ? 'rotate-180' : ''}`} />}
      </button>
      {expanded && hasBody && (
        <div className="mt-1 overflow-hidden rounded-lg border border-line bg-[#060d1a]">
          <ToolBody detail={item.detail} output={item.output} error={item.status === 'error'} />
        </div>
      )}
    </div>
  );
}

/** 도구 줄에 보일 대상 (명령, 파일 경로 등) */
function toolSubject(d?: ToolDetail): string | null {
  if (!d) return null;
  switch (d.kind) {
    case 'bash':
      return d.description ? `${d.command.split('\n')[0]}  — ${d.description}` : d.command.split('\n')[0];
    case 'edit':
    case 'write':
    case 'read':
      return d.path;
    case 'search':
      return d.path ? `${d.pattern}  (${d.path})` : d.pattern;
    default:
      return null;
  }
}

function ToolBody({ detail, output, error }: { detail?: ToolDetail; output?: string; error: boolean }) {
  return (
    <div className="max-h-80 overflow-auto font-mono text-[12px] leading-5">
      {detail?.kind === 'bash' && <pre className="whitespace-pre-wrap break-all border-b border-line px-3 py-1.5 text-sky-200">$ {detail.command}</pre>}
      {detail?.kind === 'edit' && detail.edits.map((e, n) => <DiffBlock key={n} oldText={e.oldText} newText={e.newText} />)}
      {detail?.kind === 'write' && <DiffBlock oldText="" newText={detail.content} />}
      {detail?.kind === 'other' && <pre className="whitespace-pre-wrap break-all border-b border-line px-3 py-1.5 text-slate-400">{detail.input}</pre>}
      {output && <pre className={`whitespace-pre-wrap break-all px-3 py-1.5 ${error ? 'text-red-300' : 'text-slate-300'}`}>{output}</pre>}
    </div>
  );
}

function DiffBlock({ oldText, newText }: { oldText: string; newText: string }) {
  const lines = useMemo(() => lineDiff(oldText, newText), [oldText, newText]);
  return (
    <div className="min-w-max border-b border-line py-1 last:border-b-0">
      {lines.map((l, i) => (
        <div
          key={i}
          className={`whitespace-pre px-3 ${l.op === '+' ? 'bg-emerald-500/10 text-emerald-200' : l.op === '-' ? 'bg-red-500/10 text-red-200' : 'text-slate-400'}`}
        >
          <span className="mr-2 select-none text-slate-600">{l.op}</span>
          {l.text || ' '}
        </div>
      ))}
    </div>
  );
}

function AgentRow({ item, name }: { item: Extract<TxItem, { kind: 'agent' }>; name: string }) {
  const [open, setOpen] = useState(false);
  // 끝났을 때 요약이 있으면 한 번 펼쳐서 보여준다
  useEffect(() => {
    if (item.status !== 'running' && item.summary) setOpen(true);
  }, [item.status, item.summary]);
  return (
    <div className="ml-8 rounded-lg border border-line bg-panel/60">
      <button type="button" onClick={() => setOpen(!open)} className="flex w-full min-w-0 items-center gap-2 px-2.5 py-1.5 text-left">
        <AgentAvatar role={item.agent} size={20} />
        <span className="shrink-0 text-[12px] font-semibold text-white">{name}</span>
        <span className="min-w-0 flex-1 truncate text-[12px] text-slate-400">{item.task}</span>
        <span className={`h-1.5 w-1.5 shrink-0 rounded-full ${STATUS_DOT[item.status]}`} />
        {item.summary && <ChevronDownIcon className={`h-3.5 w-3.5 shrink-0 text-slate-500 transition ${open ? 'rotate-180' : ''}`} />}
      </button>
      {open && item.summary && (
        <div className="max-h-64 overflow-auto border-t border-line px-3 py-2">
          <Markdown text={item.summary} className="text-[12px]" />
        </div>
      )}
    </div>
  );
}

const FILE_STATUS = {
  added: { letter: 'A', color: '#4ade80', label: '새 파일' },
  modified: { letter: 'M', color: '#fbbf24', label: '수정' },
  deleted: { letter: 'D', color: '#f87171', label: '삭제' },
} as const;

/** 실행이 바꾼 파일 목록과 "이 실행 되돌리기" */
function CheckpointRow({ item }: { item: Extract<TxItem, { kind: 'checkpoint' }> }) {
  const running = useAgentStore((s) => s.running);
  const undo = useAgentStore((s) => s.undoCheckpoint);
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const restored = new Set(item.restored);
  const left = item.files.filter((f) => !restored.has(f.path));

  const run = async (force: boolean) => {
    const what = force
      ? `실행 뒤에 다시 바뀐 파일 ${item.skipped.length}개도 실행 전 내용으로 덮어씁니다. 그 뒤의 수정은 사라집니다. 계속할까요?`
      : `이 실행이 바꾼 파일 ${left.length}개를 실행 전으로 되돌립니다. 새로 만든 파일은 지워집니다. 계속할까요?`;
    if (!window.confirm(what)) return;
    setBusy(true);
    setError(null);
    const res = await undo(item.id, force);
    setBusy(false);
    if (!res.ok) setError(res.error ?? '되돌리지 못했습니다.');
  };

  return (
    <div className="ml-8 rounded-lg border border-line bg-panel/60">
      <div className="flex flex-wrap items-center gap-x-2 gap-y-1 px-2.5 py-1.5 text-[12px]">
        <button type="button" onClick={() => setOpen(!open)} className="inline-flex min-w-0 items-center gap-1 text-slate-300 hover:text-white" aria-expanded={open}>
          <ChevronDownIcon className={`h-3.5 w-3.5 shrink-0 transition ${open ? 'rotate-180' : ''}`} />
          {item.complete ? (
            <span className="text-emerald-300">↺ 되돌림 완료 · 파일 {item.files.length}개</span>
          ) : (
            <span>
              이 실행에서 바뀐 파일 {item.files.length}개
              {item.restored.length > 0 && <span className="text-emerald-300"> · {item.restored.length}개 되돌림</span>}
            </span>
          )}
        </button>
        {!item.complete && (
          <span className="ml-auto flex items-center gap-1.5">
            {item.skipped.length > 0 && (
              <button
                type="button"
                disabled={busy || running}
                onClick={() => void run(true)}
                className="rounded-md border border-red-400/40 px-2 py-0.5 text-[11px] font-semibold text-red-300 hover:bg-red-500/10 disabled:opacity-50"
              >
                건너뛴 {item.skipped.length}개도 되돌리기
              </button>
            )}
            {item.skipped.length === 0 && (
              <button
                type="button"
                disabled={busy || running}
                onClick={() => void run(false)}
                title={running ? '실행이 끝난 뒤 되돌릴 수 있습니다' : '이 실행이 바꾼 파일만 실행 전으로 되돌립니다'}
                className="rounded-md border border-line px-2 py-0.5 text-[11px] font-semibold text-slate-200 hover:border-amber-400/60 hover:text-amber-100 disabled:opacity-50"
              >
                {busy ? '되돌리는 중…' : '↺ 이 실행 되돌리기'}
              </button>
            )}
          </span>
        )}
      </div>
      {error && <p className="border-t border-line px-3 py-1.5 text-[12px] text-red-300">{error}</p>}
      {item.skipped.length > 0 && !item.complete && (
        <div className="border-t border-line px-3 py-1.5 text-[11px] text-amber-200">
          실행 뒤에 다시 바뀐 파일은 덮어쓰지 않고 건너뛰었습니다:
          <ul className="mt-0.5 font-mono text-amber-100/90">
            {item.skipped.map((s) => (
              <li key={s.path}>
                {s.path} <span className="font-sans text-amber-200/70">— {s.reason}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
      {open && (
        <ul className="max-h-48 overflow-y-auto border-t border-line py-1 font-mono text-[12px]">
          {item.files.map((f) => {
            const st = FILE_STATUS[f.status];
            return (
              <li key={f.path} className={`flex items-center gap-2 px-3 ${restored.has(f.path) ? 'text-slate-500 line-through' : 'text-slate-300'}`}>
                <span className="w-3 shrink-0 text-center font-bold" style={{ color: st.color }} title={st.label}>
                  {st.letter}
                </span>
                <span className="truncate">{f.path}</span>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
