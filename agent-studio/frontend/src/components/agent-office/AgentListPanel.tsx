'use client';

import { useAgentStore } from '@/store/agentStore';
import { providerOf } from '@/types/agent';
import { PencilIcon, PlusIcon, UsersIcon } from '@/components/ui/icons';
import { AgentAvatar } from './AgentAvatar';
import { StatusBadge } from './StatusBadge';

export function AgentListPanel() {
  const defs = useAgentStore((s) => s.defs);
  const agents = useAgentStore((s) => s.agents);
  const selected = useAgentStore((s) => s.selectedAgent);
  const selectAgent = useAgentStore((s) => s.selectAgent);
  const openEditor = useAgentStore((s) => s.openEditor);

  return (
    <section className="panel flex min-h-0 flex-1 flex-col overflow-hidden">
      <div className="panel-header">
        <h2 className="panel-title">
          <span className="flex h-7 w-7 items-center justify-center rounded-lg bg-accent/15 text-blue-300">
            <UsersIcon className="h-4 w-4" />
          </span>
          에이전트 관리
          <span className="rounded-full bg-accent/20 px-2 py-0.5 text-[11px] font-bold text-blue-200">{defs.length}</span>
        </h2>
        <button
          type="button"
          onClick={() => openEditor('new')}
          className="inline-flex items-center gap-1 rounded-lg border border-accent/50 bg-accent/15 px-2 py-1 text-[11px] font-semibold text-blue-200 hover:bg-accent/25 hover:text-white"
        >
          <PlusIcon className="h-3.5 w-3.5" />
          추가
        </button>
      </div>

      <ul className="min-h-0 flex-1 overflow-y-auto p-2">
        {defs.map((def) => {
          const state = agents[def.id];
          if (!state) return null;
          const isSelected = selected === def.id;
          return (
            <li key={def.id} className="group relative">
              <button
                type="button"
                onClick={() => selectAgent(def.id)}
                className={`flex w-full items-center gap-3 rounded-xl border px-2.5 py-2 text-left transition ${
                  isSelected
                    ? 'border-accent/60 bg-accent/10 shadow-[inset_0_0_0_1px_rgba(59,130,246,0.25)]'
                    : 'border-transparent hover:border-line hover:bg-white/[0.03]'
                }`}
              >
                <AgentAvatar role={def.id} size={46} />
                <div className="min-w-0 flex-1">
                  <div className="flex items-center justify-between gap-2">
                    <span className="truncate text-[13px] font-bold text-white">{def.name}</span>
                    <StatusBadge status={state.status} />
                  </div>
                  <p className="mt-0.5 flex items-center gap-1.5 text-[11px] text-muted">
                    {providerOf(def) === 'codex' && (
                      <span className="rounded bg-[#10a37f]/20 px-1 text-[10px] font-bold text-[#34d399]" title="OpenAI Codex 협업자">
                        Codex
                      </span>
                    )}
                    <span className="truncate">{def.roleLabel}</span>
                  </p>
                  <p className="truncate text-[11px] text-slate-400">{state.status === 'idle' ? def.description : state.message}</p>
                </div>
              </button>
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation();
                  openEditor(def.id);
                }}
                aria-label={`${def.name} 설정`}
                title="에이전트 설정"
                className="absolute bottom-3 right-3 rounded-md p-1 text-muted opacity-0 transition hover:bg-white/10 hover:text-white group-hover:opacity-100 focus:opacity-100"
              >
                <PencilIcon className="h-3.5 w-3.5" />
              </button>
              <div className="mx-3 border-b border-line/70 last:hidden" />
            </li>
          );
        })}
      </ul>
    </section>
  );
}
