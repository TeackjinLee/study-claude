'use client';

import { useAgentStore } from '@/store/agentStore';
import { STATUS_COLOR, STATUS_LABEL, type AgentStatus } from '@/types/agent';
import { ActivityIcon } from '@/components/ui/icons';

/** 시안의 "전체 상태" 카드. Thinking/Completed는 Working/Idle로 묶어 시안과 같은 5줄로 보여준다. */
const ROWS: { label: string; statuses: AgentStatus[]; color: string }[] = [
  { label: 'Working', statuses: ['working', 'thinking'], color: STATUS_COLOR.working },
  { label: 'Testing', statuses: ['testing'], color: STATUS_COLOR.testing },
  { label: 'Deploying', statuses: ['deploying'], color: STATUS_COLOR.deploying },
  { label: 'Idle', statuses: ['idle', 'completed'], color: STATUS_COLOR.idle },
  { label: 'Error', statuses: ['error'], color: STATUS_COLOR.error },
];

export function StatusSummaryPanel() {
  const agents = useAgentStore((s) => s.agents);
  const counts: Partial<Record<AgentStatus, number>> = {};
  for (const state of Object.values(agents)) {
    counts[state.status] = (counts[state.status] ?? 0) + 1;
  }

  return (
    <section className="panel shrink-0">
      <div className="panel-header">
        <h2 className="panel-title">
          <ActivityIcon className="h-4 w-4 text-blue-300" />
          전체 상태
        </h2>
      </div>
      <ul className="px-4 py-2">
        {ROWS.map((row) => {
          const n = row.statuses.reduce((acc, s) => acc + (counts[s] ?? 0), 0);
          return (
            <li key={row.label} className="flex items-center justify-between border-b border-line/60 py-2 text-[13px] last:border-0">
              <span className="flex items-center gap-2.5 text-slate-200">
                <span className="inline-block h-3 w-3 rounded-full" style={{ backgroundColor: row.color, boxShadow: `0 0 8px ${row.color}88` }} />
                {row.label}
                <span className="sr-only">({row.statuses.map((s) => STATUS_LABEL[s]).join(', ')})</span>
              </span>
              <span className="font-bold tabular-nums" style={{ color: n > 0 ? row.color : '#6b7a9e' }}>
                {n}
              </span>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
