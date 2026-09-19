'use client';

import { useEffect, useRef } from 'react';
import { useAgentStore } from '@/store/agentStore';
import type { AgentRole } from '@/types/agent';
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
        <option value="system">System</option>
      </select>
      <ChevronDownIcon className="pointer-events-none absolute right-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted" />
    </label>
  );
}

/**
 * 실시간 로그 목록. large=true면 결과 미리보기처럼 넓은 영역용으로 글자와 여백을 키운다.
 * 새 로그가 오면 맨 아래로 따라가되, 사용자가 위로 올려 읽는 중이면 방해하지 않는다.
 */
export function LogList({ filter, large = false }: { filter: LogFilter; large?: boolean }) {
  const logs = useAgentStore((s) => s.logs);
  const defsById = useAgentStore((s) => s.defsById);
  const listRef = useRef<HTMLDivElement | null>(null);

  const visible = filter === 'all' ? logs : logs.filter((l) => l.agent === filter);

  useEffect(() => {
    const el = listRef.current;
    if (!el) return;
    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 80;
    if (nearBottom) el.scrollTop = el.scrollHeight;
  }, [visible.length]);

  const text = large ? 'text-[13.5px]' : 'text-[12px]';
  const time = large ? 'w-14 text-[12.5px]' : 'w-10 text-[12px]';
  const pad = large ? 'px-5 py-3' : 'px-3.5 py-2.5';
  const avatar = large ? 34 : 28;

  return (
    <div ref={listRef} className="min-h-0 flex-1 overflow-y-auto">
      {visible.length === 0 && (
        <p className={`px-4 py-6 text-center text-slate-500 ${text}`}>아직 로그가 없습니다. 아래에서 명령을 입력해보세요.</p>
      )}
      <ul>
        {visible.map((log) => {
          const meta = log.agent === 'system' ? null : (defsById[log.agent] ?? null);
          if (log.kind === 'command') {
            const [cmd, ...rest] = log.text.split('\n');
            return (
              <li key={log.id} className={`border-b border-line/60 ${pad}`}>
                <div className="flex items-center gap-2">
                  <span className={`shrink-0 tabular-nums text-muted ${time}`}>{formatTime(log.at)}</span>
                  <code className={`rounded px-1.5 py-0.5 font-mono font-semibold ${text} ${log.error ? 'bg-red-500/15 text-red-300' : 'bg-accent/15 text-blue-200'}`}>{cmd}</code>
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
              {log.agent === 'system' || !meta ? (
                <span
                  className="flex shrink-0 items-center justify-center rounded-lg border border-line bg-panel-2 text-[10px] font-bold text-slate-300"
                  style={{ width: avatar, height: avatar }}
                >
                  SYS
                </span>
              ) : (
                <AgentAvatar role={log.agent} size={avatar} />
              )}
              <div className="min-w-0 flex-1">
                <span className={`font-bold ${text}`} style={{ color: meta?.color ?? '#cbd5e1' }}>
                  {meta?.shortName ?? (log.agent === 'system' ? 'System' : log.agent)}
                </span>
                <p className={`leading-snug text-slate-300 ${text} ${large ? 'mt-0.5' : ''}`}>{log.text}</p>
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
