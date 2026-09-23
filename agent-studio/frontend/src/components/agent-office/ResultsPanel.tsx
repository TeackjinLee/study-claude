'use client';

import { useEffect, useMemo, useState } from 'react';
import { useAgentStore, type ResultTab } from '@/store/agentStore';
import type { Artifact } from '@/lib/ws';
import { CheckIcon } from './StatusBadge';
import { formatTime } from '@/lib/format';
import { AttachmentChips } from './AttachmentChips';
import { LogFilterSelect, LogList, type LogFilter } from './LogList';
import { ChangesPanel } from './ChangesPanel';
import { BACKEND_URL } from '@/lib/backend';


/** 결과물 탭 + 작업 폴더의 git 변경사항 + 사이드 패널의 실시간 로그를 넓게 보는 탭 */
type PanelTab = ResultTab | 'changes' | 'log';

const TABS: { id: PanelTab; label: string }[] = [
  { id: 'changes', label: '변경사항' },
  { id: 'code', label: '코드' },
  { id: 'test', label: '테스트 결과' },
  { id: 'doc', label: '문서' },
  { id: 'image', label: '이미지' },
  { id: 'summary', label: '최종 요약' },
  { id: 'log', label: '실시간 로그' },
];

const EMPTY: Record<ResultTab, string> = {
  code: '에이전트가 파일을 만들거나 고치면 여기에 표시됩니다.',
  test: '테스트를 실행하면 결과가 여기에 표시됩니다.',
  doc: 'Markdown 문서가 만들어지면 여기에 표시됩니다.',
  image: 'Codex가 이미지를 만들면 여기에 표시됩니다. (총괄이 프롬프트를 쓰고 Codex가 그립니다 — /codex image <프롬프트> 로 직접 요청할 수도 있습니다)',
  summary: '작업이 끝나면 최종 요약이 여기에 표시됩니다. 이어지는 대화(코드·채팅)는 명령마다 한 항목씩 쌓입니다.',
};

const RUN_STATUS = {
  running: { label: '실행 중', color: '#60a5fa' },
  done: { label: '완료', color: '#4ade80' },
  error: { label: '실패', color: '#f87171' },
  aborted: { label: '중단됨', color: '#fbbf24' },
} as const;

function formatDuration(ms: number) {
  const s = Math.max(0, Math.round(ms / 1000));
  if (s < 60) return `${s}초`;
  return `${Math.floor(s / 60)}분 ${s % 60}초`;
}

/** 실행 중에는 1초마다 경과 시간을 다시 계산한다. */
function useElapsed(startedAt?: number, endedAt?: number) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!startedAt || endedAt) return;
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [startedAt, endedAt]);
  if (!startedAt) return null;
  return (endedAt ?? now) - startedAt;
}

/**
 * 기존 대시보드(localhost:3000)의 "결과 미리보기"에 해당하는 화면.
 * 실행 메타(상태/시작/소요/비용/모델) + 코드·테스트·문서·최종 요약 탭 + 파일 목록 + 본문.
 */
export function ResultsPanel() {
  const run = useAgentStore((s) => s.run);
  const thread = useAgentStore((s) => s.thread);
  const artifacts = useAgentStore((s) => s.artifacts);
  const fresh = useAgentStore((s) => s.freshResults);
  const markSeen = useAgentStore((s) => s.markResultsSeen);
  const logCount = useAgentStore((s) => s.logs.length);
  const [tab, setTab] = useState<PanelTab>('changes');
  const [logFilter, setLogFilter] = useState<LogFilter>('all');
  const [picked, setPicked] = useState<Partial<Record<ResultTab, string>>>({});

  const elapsed = useElapsed(run?.startedAt, run?.endedAt);

  const items = useMemo<Artifact[]>(() => {
    if (tab === 'log' || tab === 'changes') return [];
    if (tab === 'summary') {
      // 이어지는 대화면 앞의 명령들까지 한 항목씩 (명령 → 추가 지시 → 답)
      return [...thread, ...(run ? [run] : [])]
        .filter((r) => r.result || r.errorMessage)
        .map((r, i, all) => ({
          kind: 'doc' as const,
          key: `summary-${r.startedAt}`,
          title: all.length > 1 ? `${i + 1}. ${r.command}` : '최종 요약',
          lang: r.status === 'error' ? '실패' : '결과',
          text: [`▶ ${r.command}`, ...r.followUps.map((f) => `▶ (추가 지시) ${f}`), '', r.result?.result || r.errorMessage || '(요약 없음)'].join('\n'),
          at: r.endedAt ?? 0,
        }));
    }
    return Object.values(artifacts[tab]).sort((a, b) => a.at - b.at);
  }, [tab, artifacts, run, thread]);

  // 탭을 열면 "새 결과" 표시를 지우고, 새 결과물이 들어오면 자동으로 최신 항목을 고른다
  useEffect(() => {
    if (tab !== 'log' && tab !== 'changes') markSeen(tab);
  }, [tab, items.length, markSeen]);

  const current = tab === 'log' || tab === 'changes' ? undefined : (items.find((a) => a.key === picked[tab]) ?? items[items.length - 1]);

  // 실행 시작 시 이전 선택 초기화
  useEffect(() => {
    setPicked({});
  }, [run?.startedAt]);

  const status = run ? RUN_STATUS[run.status] : null;
  const summaryCount = [...thread, run].filter((r) => r?.result || r?.errorMessage).length;

  return (
    <section className="panel flex h-full min-h-0 flex-col overflow-hidden">
      <div className="flex flex-wrap items-center gap-x-5 gap-y-2 border-b border-line px-4 py-2.5">
        <div className="flex min-w-0 items-center gap-2.5">
          {status ? (
            <span
              className="inline-flex shrink-0 items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-[11px] font-semibold"
              style={{
                color: status.color,
                borderColor: `${status.color}66`,
                backgroundColor: `${status.color}1a`,
              }}
            >
              <span className={`h-1.5 w-1.5 rounded-full ${run?.status === 'running' ? 'pulse-dot' : ''}`} style={{ backgroundColor: status.color }} />
              {status.label}
            </span>
          ) : (
            <span className="rounded-full border border-line px-2.5 py-0.5 text-[11px] font-semibold text-muted">대기</span>
          )}
          {run && (
            <span className="shrink-0 rounded border border-line px-1.5 py-0.5 text-[10px] font-semibold text-slate-300" title={run.mode === 'chat' ? '채팅: 대화만' : run.mode === 'cowork' ? 'Cowork: 팀 작업' : '코드: 직접 코딩'}>
              {run.mode === 'chat' ? '채팅' : run.mode === 'cowork' ? 'Cowork' : '코드'}
              {run.continued && <span className="text-emerald-300"> · 이어서 {thread.length + 1}번째</span>}
              {run.planFirst && <span className="text-amber-200"> · 계획 먼저</span>}
            </span>
          )}
          <span className="truncate text-[13px] font-bold text-white">{run?.command ?? '아직 실행한 명령이 없습니다'}</span>
        </div>
        <dl className="ml-auto flex items-center gap-4 text-[11px] text-muted">
          <Meta label="시작" value={run ? formatTime(run.startedAt) : '--:--'} />
          <Meta label="소요" value={elapsed !== null ? formatDuration(elapsed) : '-'} />
          <Meta label="비용" value={run?.result?.costUsd !== undefined ? `$${run.result.costUsd.toFixed(4)}` : '-'} />
          <Meta label="턴" value={run?.result?.turns !== undefined ? String(run.result.turns) : '-'} />
          <Meta label="모델" value={run?.model ?? '-'} className="hidden lg:flex" />
        </dl>
      </div>

      {run && run.attachments.length > 0 && (
        <div className="border-b border-line px-4 py-2">
          <AttachmentChips items={run.attachments} size="sm" />
        </div>
      )}

      {run?.errorMessage && <p className="border-b border-red-500/30 bg-red-500/10 px-4 py-2 text-[12px] text-red-300">{run.errorMessage}</p>}

      <div className="flex gap-1 border-b border-line px-3 pt-2" role="tablist" aria-label="결과 종류">
        {TABS.map((t) => {
          const count = t.id === 'log' ? logCount : t.id === 'changes' ? 0 : t.id === 'summary' ? summaryCount : Object.keys(artifacts[t.id]).length;
          const active = tab === t.id;
          return (
            <button
              key={t.id}
              role="tab"
              type="button"
              aria-selected={active}
              onClick={() => setTab(t.id)}
              className={`relative -mb-px flex items-center gap-1.5 rounded-t-lg border border-b-0 px-3 py-1.5 text-[12px] font-semibold transition ${
                active ? 'border-line bg-[#08101f] text-white' : 'border-transparent text-muted hover:text-slate-200'
              }`}
            >
              {t.label}
              {count > 0 && <span className={`rounded-full px-1.5 text-[10px] ${active ? 'bg-accent/30 text-blue-200' : 'bg-white/10 text-slate-300'}`}>{count}</span>}
              {t.id !== 'log' && t.id !== 'changes' && fresh[t.id] && !active && <span className="absolute right-1 top-1 h-1.5 w-1.5 rounded-full bg-emerald-400" />}
            </button>
          );
        })}
      </div>

      {tab === 'changes' ? (
        <ChangesPanel />
      ) : tab === 'log' ? (
        <div className="flex min-h-0 flex-1 flex-col bg-[#08101f]">
          <div className="flex items-center justify-between gap-3 border-b border-line px-3 py-1.5">
            <span className="text-[12px] text-muted">사이드 패널의 실시간 로그와 같은 내용입니다. 에이전트별로 걸러 볼 수 있습니다.</span>
            <LogFilterSelect value={logFilter} onChange={setLogFilter} />
          </div>
          <LogList filter={logFilter} large />
        </div>
      ) : (
        <div className="grid min-h-0 flex-1 bg-[#08101f] md:grid-cols-[220px_minmax(0,1fr)]">
          <ul className="hidden min-h-0 overflow-y-auto border-r border-line py-2 md:block">
            {items.length === 0 && <li className="px-3 py-2 text-[12px] text-slate-500">결과물 없음</li>}
            {items.map((a) => {
              const active = a.key === current?.key;
              return (
                <li key={a.key}>
                  <button
                    type="button"
                    onClick={() => setPicked((p) => ({ ...p, [tab]: a.key }))}
                    className={`flex w-full items-center gap-2 px-3 py-1.5 text-left text-[12px] ${
                      active ? 'bg-accent/15 text-white' : 'text-slate-300 hover:bg-white/[0.04]'
                    }`}
                  >
                    <span className="flex h-4 w-4 shrink-0 items-center justify-center rounded bg-emerald-500/15 text-emerald-400">
                      <CheckIcon className="h-3 w-3" />
                    </span>
                    <span className="truncate font-mono">{a.title}</span>
                  </button>
                </li>
              );
            })}
          </ul>

          <div className="flex min-h-0 flex-col">
            {items.length > 0 && (
              <div className="flex items-center justify-between border-b border-line px-3 py-1.5 md:hidden">
                <select
                  value={current?.key}
                  onChange={(e) => setPicked((p) => ({ ...p, [tab]: e.target.value }))}
                  className="w-full rounded-md border border-line bg-panel-2 px-2 py-1 text-[12px] text-slate-200"
                >
                  {items.map((a) => (
                    <option key={a.key} value={a.key}>
                      {a.title}
                    </option>
                  ))}
                </select>
              </div>
            )}
            {current ? (
              <ArtifactView artifact={current} prose={tab === 'doc' || tab === 'summary'} />
            ) : (
              <p className="flex flex-1 items-center justify-center px-6 text-center text-[13px] text-slate-500">{EMPTY[tab]}</p>
            )}
          </div>
        </div>
      )}
    </section>
  );
}

function Meta({ label, value, className = '' }: { label: string; value: string; className?: string }) {
  return (
    <div className={`flex items-center gap-1.5 ${className}`}>
      <dt>{label}</dt>
      <dd className="font-semibold tabular-nums text-slate-200">{value}</dd>
    </div>
  );
}

function ArtifactView({ artifact, prose }: { artifact: Artifact; prose: boolean }) {
  const lines = useMemo(() => artifact.text.replace(/\n$/, '').split('\n'), [artifact.text]);
  // 이미지는 작업 폴더 파일을 백엔드에서 받아 그대로 보여준다. at을 쿼리로 붙여 같은 경로에 다시 만들어도 새로 받는다
  const imageSrc = artifact.kind === 'image' && artifact.url ? `${BACKEND_URL}${artifact.url}?v=${artifact.at}` : null;
  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="flex items-center justify-between gap-3 border-b border-line px-3 py-1.5">
        <span className="truncate font-mono text-[12px] text-slate-200">{artifact.title}</span>
        <span className="shrink-0 rounded bg-white/10 px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-slate-300">{artifact.lang}</span>
      </div>
      <div className="min-h-0 flex-1 overflow-auto">
        {imageSrc ? (
          <div className="flex min-h-full flex-col items-center justify-center gap-3 p-4">
            {/* eslint-disable-next-line @next/next/no-img-element -- 작업 폴더의 동적 파일이라 next/image 최적화 대상이 아니다 */}
            <img src={imageSrc} alt={artifact.title} className="max-h-[70vh] max-w-full rounded-lg border border-line bg-[#0b1020] object-contain" />
            <a href={imageSrc} target="_blank" rel="noreferrer" className="font-mono text-[11px] text-muted underline-offset-2 hover:text-slate-200 hover:underline">
              {artifact.text} · 새 탭에서 열기
            </a>
          </div>
        ) : prose ? (
          <pre className="whitespace-pre-wrap px-4 py-3 font-sans text-[13px] leading-relaxed text-slate-200">{artifact.text}</pre>
        ) : (
          <table className="w-full border-collapse font-mono text-[12px] leading-5">
            <tbody>
              {lines.map((line, i) => (
                <tr key={i} className="hover:bg-white/[0.03]">
                  <td className="w-10 select-none border-r border-line pr-2 text-right align-top text-[11px] text-slate-600">{i + 1}</td>
                  <td className="whitespace-pre px-3 text-slate-200">{line || ' '}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
