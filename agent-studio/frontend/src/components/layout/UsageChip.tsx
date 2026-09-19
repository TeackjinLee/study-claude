'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { useAgentStore } from '@/store/agentStore';
import { ActivityIcon, ChevronDownIcon } from '@/components/ui/icons';

const BACKEND_URL = process.env.NEXT_PUBLIC_BACKEND_URL ?? 'http://localhost:3000';
const REFRESH_MS = 5 * 60_000;

type Totals = { runs: number; costUsd: number; turns: number; durationMs: number };
type ModelTotals = { model: string; costUsd: number; inputTokens: number; outputTokens: number; cacheReadTokens: number; cacheWriteTokens: number };
type UsageWindow = { label: string; utilization: number | null; resetsAt: string | null };

/** GET /api/usage 응답 — 비용 누적(/cost)과 Claude 구독 한도(/usage) */
type Usage = {
  cost: {
    last: { at: number; command: string; ok: boolean; costUsd: number; turns: number; durationMs: number } | null;
    today: Totals;
    total: Totals;
    byModel: ModelTotals[];
  };
  plan: { available: boolean; subscription: string | null; windows: UsageWindow[]; extra: { used: number; limit: number | null; currency: string; utilization: number | null } | null } | null;
  planError?: string;
  /** Codex(ChatGPT) 구독 한도. 로그인 안 돼 있으면 null */
  codex: { plan: string | null; windows: UsageWindow[]; resetCredits: number | null; blocked: boolean } | null;
  fetchedAt: number;
};

const money = (n: number) => (n >= 1 ? `$${n.toFixed(2)}` : `$${n.toFixed(3)}`);
const tok = (n: number) => (n >= 1_000_000 ? `${(n / 1_000_000).toFixed(1)}M` : n >= 1000 ? `${(n / 1000).toFixed(n >= 10000 ? 0 : 1)}k` : String(n));
const pct = (n: number | null) => (n === null ? '-' : `${Math.round(n)}%`);

/** 소진율에 따라 초록 → 노랑 → 빨강 */
function colorFor(n: number | null) {
  if (n === null) return '#94a3b8';
  if (n >= 80) return '#f87171';
  if (n >= 50) return '#fbbf24';
  return '#4ade80';
}

function resetIn(iso: string | null) {
  if (!iso) return '';
  const ms = new Date(iso).getTime() - Date.now();
  if (!Number.isFinite(ms) || ms <= 0) return '곧 초기화';
  const d = Math.floor(ms / 86400000);
  const h = Math.floor((ms % 86400000) / 3600000);
  const m = Math.floor((ms % 3600000) / 60000);
  if (d) return `${d}일 ${h}시간 뒤 초기화`;
  if (h) return `${h}시간 ${m}분 뒤 초기화`;
  return `${m}분 뒤 초기화`;
}

function fmtTime(at: number) {
  const d = new Date(at);
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

/**
 * 헤더의 사용량 칩. Claude·Codex 구독의 5시간 한도 소진율과 오늘 Claude 비용을 보여주고, 누르면 /usage + /cost + Codex 한도를 한 번에 본다.
 * 실행이 끝날 때마다, 그리고 5분마다 다시 읽는다.
 */
export function UsageChip() {
  const runEndedAt = useAgentStore((s) => s.run?.endedAt);
  const [usage, setUsage] = useState<Usage | null>(null);
  const [loading, setLoading] = useState(false);
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);

  const load = useCallback(async (refresh = false) => {
    setLoading(true);
    try {
      const res = await fetch(`${BACKEND_URL}/api/usage${refresh ? '?refresh=1' : ''}`);
      if (res.ok) setUsage((await res.json()) as Usage);
    } catch {
      // 서버가 잠깐 없으면 이전 값을 그대로 둔다
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
    const id = setInterval(() => void load(), REFRESH_MS);
    return () => clearInterval(id);
  }, [load]);

  // 실행이 끝나면 비용과 한도가 바뀌므로 바로 다시 읽는다 (한도는 서버 캐시를 건너뛴다)
  useEffect(() => {
    if (runEndedAt) void load(true);
  }, [runEndedAt, load]);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (!rootRef.current?.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    document.addEventListener('mousedown', onDown);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('mousedown', onDown);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  const primary = usage?.plan?.available ? usage.plan.windows[0] : undefined;
  const primaryColor = colorFor(primary?.utilization ?? null);
  const codexPrimary = usage?.codex?.windows[0];
  const codexColor = colorFor(codexPrimary?.utilization ?? null);
  const todayCost = usage?.cost.today.costUsd ?? 0;
  const tooltip = [
    primary ? `Claude ${primary.label} ${pct(primary.utilization)} 사용 · ${resetIn(primary.resetsAt)}` : null,
    codexPrimary ? `Codex ${codexPrimary.label} ${pct(codexPrimary.utilization)} 사용 · ${resetIn(codexPrimary.resetsAt)}` : null,
    `오늘 Claude 비용 ${money(todayCost)} (API 환산)`,
  ]
    .filter(Boolean)
    .join('\n');

  return (
    <div ref={rootRef} className="relative hidden md:block">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-haspopup="dialog"
        aria-expanded={open}
        className="inline-flex items-center gap-1.5 rounded-full border border-line bg-panel px-3 py-1 text-[12px] text-slate-300 hover:border-line-strong hover:text-white"
        title={tooltip}
      >
        <ActivityIcon className="h-3.5 w-3.5 shrink-0" style={{ color: primary ? primaryColor : undefined }} />
        {primary && (
          <>
            <span className="text-muted">Claude</span>
            <span className="font-semibold tabular-nums" style={{ color: primaryColor }}>
              {pct(primary.utilization)}
            </span>
          </>
        )}
        {codexPrimary && (
          <>
            {primary && <span className="text-muted">·</span>}
            <span className="text-muted">Codex</span>
            <span className="font-semibold tabular-nums" style={{ color: codexColor }}>
              {pct(codexPrimary.utilization)}
            </span>
          </>
        )}
        {primary || codexPrimary ? <span className="text-muted">·</span> : <span className="text-muted">오늘</span>}
        <span className="font-semibold tabular-nums text-white">{usage ? money(todayCost) : '…'}</span>
        <ChevronDownIcon className={`h-3.5 w-3.5 shrink-0 text-muted transition-transform ${open ? 'rotate-180' : ''}`} />
      </button>

      {open && (
        <div
          role="dialog"
          aria-label="사용량"
          className="absolute right-0 top-[calc(100%+6px)] z-40 w-[380px] max-w-[calc(100vw-32px)] rounded-lg border border-line bg-[#0a1428] p-3 shadow-[0_10px_30px_rgba(0,0,0,0.5)]"
        >
          <div className="flex items-center justify-between">
            <p className="text-[12px] font-semibold text-white">사용량</p>
            <button
              type="button"
              onClick={() => void load(true)}
              disabled={loading}
              className="text-[11px] text-muted underline-offset-2 hover:text-slate-200 hover:underline disabled:opacity-50"
            >
              {loading ? '읽는 중…' : '새로고침'}
            </button>
          </div>

          {!usage ? (
            <p className="mt-2 text-[12px] text-muted">아직 불러오지 못했습니다.</p>
          ) : (
            <>
              <section className="mt-2.5">
                <SectionTitle title="Claude 구독 한도" plan={usage.plan?.subscription ?? null} />
                {usage.plan?.available ? (
                  <WindowBars windows={usage.plan.windows}>
                    {usage.plan.extra && (
                      <li className="text-[11px] text-muted">
                        추가 사용량: {usage.plan.extra.used}/{usage.plan.extra.limit ?? '-'} {usage.plan.extra.currency} ({pct(usage.plan.extra.utilization)})
                      </li>
                    )}
                  </WindowBars>
                ) : (
                  <p className="mt-1 text-[11px] leading-snug text-muted">
                    {usage.planError ? `한도를 가져오지 못했습니다: ${usage.planError}` : 'API 키 방식이거나 구독 정보를 읽을 수 없어 한도가 표시되지 않습니다.'}
                  </p>
                )}
              </section>

              <section className="mt-3 border-t border-line pt-2.5">
                <SectionTitle title="Codex 구독 한도" plan={usage.codex?.plan ?? null} />
                {usage.codex ? (
                  <WindowBars windows={usage.codex.windows}>
                    {usage.codex.blocked && <li className="text-[11px] font-semibold text-red-300">한도에 도달해 Codex를 지금은 쓸 수 없습니다.</li>}
                    {usage.codex.resetCredits !== null && usage.codex.resetCredits > 0 && (
                      <li className="text-[11px] text-muted">초기화 크레딧 {usage.codex.resetCredits}개 남음</li>
                    )}
                  </WindowBars>
                ) : (
                  <p className="mt-1 text-[11px] leading-snug text-muted">Codex에 ChatGPT 계정으로 로그인하면 한도가 표시됩니다.</p>
                )}
              </section>

              <section className="mt-3 border-t border-line pt-2.5">
                <p className="text-[11px] font-semibold uppercase tracking-wide text-muted">실행 비용 (API 환산)</p>
                <dl className="mt-1.5 grid grid-cols-3 gap-2 text-center">
                  <CostCell label="마지막 실행" value={usage.cost.last ? money(usage.cost.last.costUsd) : '-'} sub={usage.cost.last ? `${usage.cost.last.turns}턴` : ''} />
                  <CostCell label="오늘" value={money(usage.cost.today.costUsd)} sub={`${usage.cost.today.runs}회 실행`} />
                  <CostCell label="전체" value={money(usage.cost.total.costUsd)} sub={`${usage.cost.total.runs}회 실행`} />
                </dl>
                {usage.cost.byModel.length > 0 && (
                  <ul className="mt-2 space-y-0.5 text-[11px]">
                    {usage.cost.byModel.slice(0, 4).map((m) => (
                      <li key={m.model} className="flex items-center justify-between gap-2">
                        <span className="truncate font-mono text-slate-300">{m.model}</span>
                        <span className="shrink-0 tabular-nums text-muted">
                          {money(m.costUsd)} · 출력 {tok(m.outputTokens)} · 캐시 {tok(m.cacheReadTokens)}
                        </span>
                      </li>
                    ))}
                  </ul>
                )}
              </section>

              <p className="mt-2.5 text-[10.5px] leading-snug text-slate-500">
                비용은 Claude 실행만 집계하며, 구독 계정 실행은 실제 청구가 아닌 API 요금 환산치입니다. Codex는 ChatGPT 구독 한도만 표시됩니다. {fmtTime(usage.fetchedAt)} 기준 · 자세히는 /usage, /cost
              </p>
            </>
          )}
        </div>
      )}
    </div>
  );
}

function SectionTitle({ title, plan }: { title: string; plan: string | null }) {
  return (
    <p className="text-[11px] font-semibold uppercase tracking-wide text-muted">
      {title}
      {plan && <span className="ml-1 normal-case tracking-normal text-slate-300">({plan})</span>}
    </p>
  );
}

/** 한도 창들을 소진율 막대로. children은 목록 끝에 붙는 부가 정보 */
function WindowBars({ windows, children }: { windows: UsageWindow[]; children?: React.ReactNode }) {
  return (
    <ul className="mt-1.5 space-y-2">
      {windows.length === 0 && <li className="text-[11px] text-muted">한도 정보 없음</li>}
      {windows.map((w) => (
        <li key={w.label}>
          <div className="flex items-baseline justify-between text-[12px]">
            <span className="text-slate-200">{w.label}</span>
            <span className="tabular-nums">
              <span className="font-semibold" style={{ color: colorFor(w.utilization) }}>
                {pct(w.utilization)}
              </span>
              {w.resetsAt && <span className="ml-1.5 text-[11px] text-muted">{resetIn(w.resetsAt)}</span>}
            </span>
          </div>
          <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-white/10">
            <div
              className="h-full rounded-full transition-[width]"
              style={{ width: `${Math.max(0, Math.min(100, w.utilization ?? 0))}%`, backgroundColor: colorFor(w.utilization) }}
            />
          </div>
        </li>
      ))}
      {children}
    </ul>
  );
}

function CostCell({ label, value, sub }: { label: string; value: string; sub: string }) {
  return (
    <div className="rounded-md border border-line bg-panel px-2 py-1.5">
      <dt className="text-[10.5px] text-muted">{label}</dt>
      <dd className="text-[13px] font-bold tabular-nums text-white">{value}</dd>
      {sub && <dd className="text-[10.5px] text-muted">{sub}</dd>}
    </div>
  );
}
