'use client';

import { useAgentStore } from '@/store/agentStore';
import { STATUS_COLOR } from '@/types/agent';
import { BotIcon } from '@/components/ui/icons';
import { AgentAvatar } from './AgentAvatar';
import { CheckIcon, StatusBadge } from './StatusBadge';
import { formatTime } from '@/lib/format';

const ACTIVE = new Set(['thinking', 'working', 'testing', 'deploying']);

/** 시안의 "선택된 에이전트" 카드: 프로필 + 진행률 + 현재 작업 체크리스트 + 최근 활동 */
export function SelectedAgentPanel() {
  const role = useAgentStore((s) => s.selectedAgent);
  const meta = useAgentStore((s) => (s.selectedAgent ? s.defsById[s.selectedAgent] : undefined));
  const stateFromStore = useAgentStore((s) => (s.selectedAgent ? s.agents[s.selectedAgent] : undefined));
  const taskFromStore = useAgentStore((s) => (s.selectedAgent ? s.tasks[s.selectedAgent] : undefined));
  const logs = useAgentStore((s) => s.logs);
  const openEditor = useAgentStore((s) => s.openEditor);

  if (!role || !meta) {
    return (
      <section className="panel flex min-h-0 flex-col">
        <div className="panel-header">
          <h2 className="panel-title">
            <BotIcon className="h-4 w-4 text-blue-300" />
            선택된 에이전트
          </h2>
        </div>
        <p className="flex flex-1 items-center justify-center text-[12px] text-slate-500">에이전트가 없습니다. 왼쪽에서 추가해보세요.</p>
      </section>
    );
  }
  const state = stateFromStore ?? { id: role, status: 'idle' as const, room: 'lounge' as const, message: '대기중' };
  const task = taskFromStore ?? { status: 'pending' as const };

  const mine = logs.filter((l) => l.agent === role);
  const recent = mine.slice(-6).reverse();
  const checklist = mine.slice(-3);
  const isActive = ACTIVE.has(state.status);
  const percent = task.progress ?? (task.status === 'done' ? 100 : 0);
  const color = STATUS_COLOR[state.status];

  return (
    <section className="panel flex min-h-0 flex-col">
      <div className="panel-header">
        <h2 className="panel-title">
          <BotIcon className="h-4 w-4 text-blue-300" />
          선택된 에이전트
        </h2>
        <button type="button" onClick={() => openEditor(role)} className="text-[11px] font-semibold text-muted hover:text-white">
          설정 ›
        </button>
      </div>

      <div className="grid min-h-0 flex-1 grid-cols-1 gap-3 p-3 md:grid-cols-[1.15fr_1fr]">
        <div className="flex min-h-0 flex-col gap-2 overflow-hidden">
          <div className="flex items-center gap-3">
            <AgentAvatar role={role} size={56} />
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <span className="truncate text-[14px] font-bold text-white">{meta.name}</span>
                <StatusBadge status={state.status} />
              </div>
              <p className="mt-0.5 truncate text-[11px] text-muted">
                {meta.roleLabel} <span className="mx-1 text-line-strong">|</span> {meta.description}
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <div className="h-2 flex-1 overflow-hidden rounded-full bg-[#1a2a4a]">
              <div
                className="h-full rounded-full transition-[width] duration-500"
                style={{ width: `${percent}%`, background: `linear-gradient(90deg, ${color}, #60a5fa)` }}
              />
            </div>
            <span className="w-9 text-right text-[12px] font-bold tabular-nums text-slate-200">{Math.round(percent)}%</span>
          </div>

          <div className="flex items-center gap-2 rounded-lg border border-line bg-[#08101f]/60 px-2.5 py-1.5">
            <span className="shrink-0 text-[11px] text-muted">현재 작업</span>
            <span className="truncate text-[12px] font-semibold text-slate-100">{state.status === 'idle' ? '대기 중' : state.message}</span>
          </div>

          <ul className="flex min-h-0 flex-col gap-1 overflow-hidden">
            {checklist.length === 0 && <li className="text-[12px] text-slate-500">아직 진행한 작업이 없습니다.</li>}
            {checklist.map((log, i) => {
              const isLast = i === checklist.length - 1;
              const running = isLast && isActive;
              return (
                <li key={log.id} className="flex items-center gap-2 text-[12px] text-slate-200">
                  {running ? (
                    <span className="flex h-4 w-4 items-center justify-center rounded-full border-2 border-blue-400/40 border-t-blue-400 animate-spin" />
                  ) : (
                    <span className="flex h-4 w-4 items-center justify-center rounded-full bg-emerald-500/20 text-emerald-400">
                      <CheckIcon className="h-3 w-3" />
                    </span>
                  )}
                  <span className="truncate">{log.text}</span>
                </li>
              );
            })}
          </ul>
        </div>

        <div className="flex min-h-0 flex-col rounded-xl border border-line bg-[#08101f]/60">
          <p className="border-b border-line px-3 py-1.5 text-[12px] font-semibold text-slate-200">최근 활동</p>
          <ul className="min-h-0 flex-1 overflow-y-auto px-3 py-1.5">
            {recent.length === 0 && <li className="py-1 text-[12px] text-slate-500">활동 기록이 없습니다.</li>}
            {recent.map((log) => (
              <li key={log.id} className="flex gap-2.5 py-1 text-[12px]">
                <span className="shrink-0 tabular-nums text-muted">{formatTime(log.at)}</span>
                <span className="truncate text-slate-300">{log.text}</span>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </section>
  );
}
