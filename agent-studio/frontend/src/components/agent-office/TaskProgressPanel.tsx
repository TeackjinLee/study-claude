'use client';

import { useAgentStore } from '@/store/agentStore';
import { ListChecksIcon } from '@/components/ui/icons';
import { AgentAvatar } from './AgentAvatar';
import { TaskStatusBadge } from './StatusBadge';

/** 시안의 "작업 진행 현황": 에이전트별 담당 작업과 진행률 막대 */
export function TaskProgressPanel() {
  const tasks = useAgentStore((s) => s.tasks);
  const defs = useAgentStore((s) => s.defs);

  return (
    <section className="panel shrink-0">
      <div className="panel-header">
        <h2 className="panel-title">
          <ListChecksIcon className="h-4 w-4 text-blue-300" />
          작업 진행 현황
        </h2>
      </div>
      <ul className="px-3 py-1.5">
        {defs.map((meta) => {
          const role = meta.id;
          const task = tasks[role] ?? { status: 'pending' as const };
          const pct = task.status === 'done' ? 100 : (task.progress ?? 0);
          return (
            <li key={role} className="flex items-center gap-2.5 border-b border-line/60 py-2 last:border-0">
              <AgentAvatar role={role} size={28} />
              <div className="min-w-0 flex-1">
                <div className="flex items-center justify-between gap-2">
                  <span className="truncate text-[12px] font-semibold text-slate-100">
                    {meta.taskLabel} <span className="font-normal text-muted">({meta.shortName})</span>
                  </span>
                  <TaskStatusBadge status={task.status} percent={task.status === 'running' ? task.progress : undefined} />
                </div>
                {task.status === 'running' && (
                  <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-[#1a2a4a]">
                    <div className="h-full rounded-full bg-gradient-to-r from-blue-500 to-sky-400 transition-[width] duration-500" style={{ width: `${pct}%` }} />
                  </div>
                )}
              </div>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
