'use client';

import { useAgentStore } from '@/store/agentStore';
import type { TaskStatus } from '@/types/agent';
import { BranchIcon } from '@/components/ui/icons';
import { TaskStatusBadge } from './StatusBadge';

const NODE_COLOR: Record<TaskStatus, string> = {
  pending: '#4b5b7f',
  running: '#3b82f6',
  done: '#22c55e',
  error: '#ef4444',
};

/**
 * 시안의 "작업 트리 (Task Graph)": 명령 → 에이전트별 작업 → 진행 중인 에이전트의 최근 로그(하위 단계) 트리.
 * 실제 의존 그래프를 서버에서 받는 대신 스토어의 작업 상태와 로그로 그려 Mock/Live 모두에서 동작한다.
 */
export function TaskGraphPanel() {
  const lastCommand = useAgentStore((s) => s.run?.command ?? null);
  const running = useAgentStore((s) => s.running);
  const tasks = useAgentStore((s) => s.tasks);
  const defs = useAgentStore((s) => s.defs);
  const logs = useAgentStore((s) => s.logs);

  const anyError = defs.some((d) => tasks[d.id]?.status === 'error');
  const rootStatus: TaskStatus = !lastCommand ? 'pending' : running ? 'running' : anyError ? 'error' : 'done';

  return (
    <section className="panel flex min-h-0 flex-col">
      <div className="panel-header">
        <h2 className="panel-title">
          <BranchIcon className="h-4 w-4 text-blue-300" />
          작업 트리 <span className="font-normal text-muted">(Task Graph)</span>
        </h2>
        <span className="text-[11px] text-muted">전체 보기 ›</span>
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto px-3 py-2">
        {!lastCommand ? (
          <p className="py-3 text-center text-[12px] text-slate-500">명령을 입력하면 작업 트리가 생성됩니다.</p>
        ) : (
          <>
            <div className="flex items-center justify-between gap-2 rounded-lg border border-accent/40 bg-accent/10 px-2.5 py-1.5">
              <span className="flex min-w-0 items-center gap-2 text-[12px] font-bold text-white">
                <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ backgroundColor: NODE_COLOR[rootStatus] }} />
                <span className="truncate">{lastCommand}</span>
              </span>
              <TaskStatusBadge status={rootStatus} />
            </div>

            <ul className="ml-3 border-l border-line-strong/70 pl-3 pt-1">
              {defs.map((meta) => {
                const role = meta.id;
                const task = tasks[role] ?? { status: 'pending' as const };
                const steps = task.status === 'running' ? logs.filter((l) => l.agent === role).slice(-2) : [];
                return (
                  <li key={role} className="relative py-1">
                    <span className="absolute -left-3 top-1/2 h-px w-3 bg-line-strong/70" />
                    <div className="flex items-center justify-between gap-2">
                      <span className="flex min-w-0 items-center gap-2 text-[12px] text-slate-200">
                        <span
                          className="flex h-4 w-4 shrink-0 items-center justify-center rounded-full text-[9px] font-bold text-white"
                          style={{ backgroundColor: NODE_COLOR[task.status] }}
                        >
                          {meta.shortName[0]}
                        </span>
                        <span className="truncate">
                          {meta.taskLabel} <span className="text-muted">({meta.shortName})</span>
                        </span>
                      </span>
                      <TaskStatusBadge status={task.status} />
                    </div>
                    {steps.length > 0 && (
                      <ul className="ml-2 mt-1 border-l border-line/80 pl-3">
                        {steps.map((s, i) => {
                          const last = i === steps.length - 1;
                          return (
                            <li key={s.id} className="relative flex items-center justify-between gap-2 py-0.5 text-[11px]">
                              <span className="absolute -left-3 top-1/2 h-px w-3 bg-line/80" />
                              <span className={`truncate ${last ? 'text-blue-200' : 'text-slate-400'}`}>{s.text}</span>
                              <TaskStatusBadge status={last ? 'running' : 'done'} />
                            </li>
                          );
                        })}
                      </ul>
                    )}
                  </li>
                );
              })}
            </ul>
          </>
        )}
      </div>
    </section>
  );
}
