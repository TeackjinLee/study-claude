'use client';

import { useAgentStore } from '@/store/agentStore';
import { ShieldIcon } from '@/components/ui/icons';
import { AgentAvatar } from './AgentAvatar';

/** 에이전트가 도구 실행 승인을 기다릴 때 맵 위에 띄우는 승인 카드 (기존 대시보드의 "승인이 필요합니다") */
export function PermissionBanner() {
  const permissions = useAgentStore((s) => s.permissions);
  const defsById = useAgentStore((s) => s.defsById);
  const reply = useAgentStore((s) => s.replyPermission);
  if (permissions.length === 0) return null;

  return (
    <div className="absolute inset-x-3 top-3 z-20 flex flex-col gap-2 md:left-auto md:right-3 md:w-[380px]">
      {permissions.map((p) => {
        const meta = p.agent === 'system' ? null : (defsById[p.agent] ?? null);
        return (
          <div
            key={p.id}
            role="alertdialog"
            aria-label="승인 요청"
            className="rounded-xl border border-amber-400/50 bg-[#0a1428]/95 p-3 shadow-[0_10px_30px_rgba(0,0,0,0.5)] backdrop-blur"
          >
            <div className="flex items-start gap-2.5">
              {p.agent === 'system' || !meta ? (
                <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-amber-400/15 text-amber-300">
                  <ShieldIcon className="h-5 w-5" />
                </span>
              ) : (
                <AgentAvatar role={p.agent} size={36} />
              )}
              <div className="min-w-0 flex-1">
                <p className="flex items-center gap-1.5 text-[11px] font-semibold text-amber-300">
                  <ShieldIcon className="h-3.5 w-3.5" />
                  승인이 필요합니다 <span className="text-muted">· {meta?.shortName ?? 'System'}</span>
                </p>
                <p className="mt-0.5 text-[13px] font-bold text-white">{p.title}</p>
                {p.detail && (
                  <pre className="mt-1 max-h-20 overflow-auto rounded-md bg-black/40 px-2 py-1.5 font-mono text-[11px] text-slate-300">
                    {p.detail}
                  </pre>
                )}
              </div>
            </div>
            <div className="mt-2.5 flex justify-end gap-1.5">
              <button
                type="button"
                onClick={() => reply(p.id, false, false)}
                className="rounded-md border border-line px-3 py-1 text-[12px] font-semibold text-slate-300 hover:border-red-400/60 hover:text-red-300"
              >
                거부
              </button>
              {p.canAlwaysAllow && (
                <>
                  <button
                    type="button"
                    onClick={() => reply(p.id, true, 'all')}
                    title="이번 명령이 끝날 때까지 어떤 도구든 다시 묻지 않습니다"
                    className="rounded-md border border-line px-3 py-1 text-[12px] font-semibold text-slate-200 hover:border-accent/60 hover:text-white"
                  >
                    이번 실행 모두 허용
                  </button>
                  <button
                    type="button"
                    onClick={() => reply(p.id, true, true)}
                    title={`이번 명령이 끝날 때까지 ${p.tool} 은(는) 다시 묻지 않습니다`}
                    className="rounded-md border border-line px-3 py-1 text-[12px] font-semibold text-slate-200 hover:border-accent/60 hover:text-white"
                  >
                    {p.tool} 계속 허용
                  </button>
                </>
              )}
              <button
                type="button"
                onClick={() => reply(p.id, true, false)}
                className="rounded-md bg-amber-400 px-3 py-1 text-[12px] font-bold text-[#0a1428] hover:bg-amber-300"
              >
                허용
              </button>
            </div>
          </div>
        );
      })}
    </div>
  );
}
