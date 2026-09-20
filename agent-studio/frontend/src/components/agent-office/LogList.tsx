'use client';

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { useAgentStore } from '@/store/agentStore';
import { MASTER_ID, type AgentRole } from '@/types/agent';
import { ChevronDownIcon } from '@/components/ui/icons';
import { AgentAvatar } from './AgentAvatar';
import { formatTime } from '@/lib/format';

export type LogFilter = 'all' | AgentRole | 'system';

/** 에이전트별 로그 필터 드롭다운 (사이드 패널과 결과 미리보기의 로그 탭이 같이 쓴다) */
export function LogFilterSelect({ value, onChange }: { value: LogFilter; onChange: (next: LogFilter) => void }) {
  const defs = useAgentStore((s) => s.defs);
  return (
    <label className="relative">
      <select
        value={value}
        onChange={(e) => onChange(e.target.value as LogFilter)}
        className="appearance-none rounded-md border border-line bg-panel-2 py-1 pl-2.5 pr-7 text-[12px] text-slate-200 outline-none focus:border-accent/60"
      >
        <option value="all">전체</option>
        {defs.map((d) => (
          <option key={d.id} value={d.id}>
            {d.shortName}
          </option>
        ))}
        <option value="system">Master</option>
      </select>
      <ChevronDownIcon className="pointer-events-none absolute right-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted" />
    </label>
  );
}

/** 이 거리(px) 안이면 "맨 아래에 있다"고 본다 */
const STICK_THRESHOLD = 40;

/**
 * 실시간 로그 목록. large=true면 결과 미리보기처럼 넓은 영역용으로 글자와 여백을 키운다.
 * 항상 가장 최근 로그가 보이도록 맨 아래에 붙어 있고(처음 열 때·필터 바꿀 때·새 로그·아바타 로딩으로 높이가 변할 때),
 * 사용자가 위로 올려 읽는 중이면 따라가지 않고 "새 로그 N" 버튼만 띄운다.
 */
export function LogList({ filter, large = false }: { filter: LogFilter; large?: boolean }) {
  const logs = useAgentStore((s) => s.logs);
  const defsById = useAgentStore((s) => s.defsById);
  const master = useAgentStore((s) => s.master);
  const listRef = useRef<HTMLDivElement | null>(null);
  const innerRef = useRef<HTMLUListElement | null>(null);
  /** 맨 아래에 붙어서 따라갈지. 사용자가 위로 스크롤하면 풀리고, 다시 아래로 내리면 붙는다 */
  const stickRef = useRef(true);
  const [unread, setUnread] = useState(0);

  const visible = filter === 'all' ? logs : logs.filter((l) => l.agent === filter);

  const scrollToBottom = useCallback(() => {
    const el = listRef.current;
    if (!el) return;
    el.scrollTop = el.scrollHeight;
    stickRef.current = true;
    setUnread(0);
  }, []);

  const onScroll = () => {
    const el = listRef.current;
    if (!el) return;
    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < STICK_THRESHOLD;
    stickRef.current = nearBottom;
    if (nearBottom) setUnread(0);
  };

  // 필터를 바꾸거나 처음 열면 무조건 맨 아래(가장 최근)로
  useLayoutEffect(() => {
    scrollToBottom();
  }, [filter, scrollToBottom]);

  // 새 로그: 붙어 있으면 따라가고, 아니면 안 읽은 개수만 올린다
  const prevCount = useRef(visible.length);
  useLayoutEffect(() => {
    const added = visible.length - prevCount.current;
    prevCount.current = visible.length;
    if (stickRef.current) scrollToBottom();
    else if (added > 0) setUnread((n) => n + added);
  }, [visible.length, scrollToBottom]);

  // 아바타 이미지 로딩·줄바꿈으로 내용 높이가 늦게 바뀌어도 맨 아래를 유지한다
  useEffect(() => {
    const inner = innerRef.current;
    if (!inner || typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(() => {
      if (stickRef.current) {
        const el = listRef.current;
        if (el) el.scrollTop = el.scrollHeight;
      }
    });
    ro.observe(inner);
    return () => ro.disconnect();
  }, []);

  const text = large ? 'text-[13.5px]' : 'text-[12px]';
  const time = large ? 'w-14 text-[12.5px]' : 'w-10 text-[12px]';
  const pad = large ? 'px-5 py-3' : 'px-3.5 py-2.5';
  const avatar = large ? 34 : 28;

  return (
    <div className="relative flex min-h-0 flex-1 flex-col">
      <div ref={listRef} onScroll={onScroll} className="min-h-0 flex-1 overflow-y-auto">
        {visible.length === 0 && <p className={`px-4 py-6 text-center text-slate-500 ${text}`}>아직 로그가 없습니다. 아래에서 명령을 입력해보세요.</p>}
        <ul ref={innerRef}>
          {visible.map((log) => {
            const meta = log.agent === 'system' ? null : (defsById[log.agent] ?? null);
            if (log.kind === 'command') {
              const [cmd, ...rest] = log.text.split('\n');
              return (
                <li key={log.id} className={`border-b border-line/60 ${pad}`}>
                  <div className="flex items-center gap-2">
                    <span className={`shrink-0 tabular-nums text-muted ${time}`}>{formatTime(log.at)}</span>
                    <code className={`rounded px-1.5 py-0.5 font-mono font-semibold ${text} ${log.error ? 'bg-red-500/15 text-red-300' : 'bg-accent/15 text-blue-200'}`}>
                      {cmd}
                    </code>
                  </div>
                  <pre
                    className={`mt-1.5 whitespace-pre-wrap rounded-lg border border-line bg-[#08101f]/70 px-3 py-2 font-mono leading-relaxed ${
                      large ? 'ml-16 text-[12.5px]' : 'ml-12 text-[11.5px]'
                    } ${log.error ? 'text-red-200' : 'text-slate-200'}`}
                  >
                    {rest.join('\n')}
                  </pre>
                </li>
              );
            }
            return (
              <li key={log.id} className={`flex items-start gap-2.5 border-b border-line/60 ${pad}`}>
                <span className={`shrink-0 pt-0.5 tabular-nums text-muted ${time}`}>{formatTime(log.at)}</span>
                {log.agent === 'system' ? (
                  // 시스템 줄(명령 접수, Master → 에이전트 말)은 사용자 자신(Master)의 캐릭터로 보여준다
                  <AgentAvatar role={MASTER_ID} size={avatar} />
                ) : !meta ? (
                  <span
                    className="flex shrink-0 items-center justify-center rounded-lg border border-line bg-panel-2 text-[10px] font-bold text-slate-300"
                    style={{ width: avatar, height: avatar }}
                  >
                    ?
                  </span>
                ) : (
                  <AgentAvatar role={log.agent} size={avatar} />
                )}
                <div className="min-w-0 flex-1">
                  <span className={`font-bold ${text}`} style={{ color: log.agent === 'system' ? master.color : (meta?.color ?? '#cbd5e1') }}>
                    {log.agent === 'system' ? master.name : (meta?.shortName ?? log.agent)}
                  </span>
                  <p className={`leading-snug text-slate-300 ${text} ${large ? 'mt-0.5' : ''}`}>{log.text}</p>
                </div>
              </li>
            );
          })}
        </ul>
      </div>
      {unread > 0 && (
        <button
          type="button"
          onClick={scrollToBottom}
          className="absolute bottom-3 left-1/2 inline-flex -translate-x-1/2 items-center gap-1 rounded-full border border-accent/50 bg-[#0a1428]/95 px-3 py-1 text-[11px] font-semibold text-blue-200 shadow-[0_6px_20px_rgba(0,0,0,0.5)] hover:bg-accent/20"
        >
          <ChevronDownIcon className="h-3.5 w-3.5" />새 로그 {unread}개 · 맨 아래로
        </button>
      )}
    </div>
  );
}
