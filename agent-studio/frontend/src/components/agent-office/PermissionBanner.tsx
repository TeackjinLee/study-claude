'use client';

import { useAgentStore } from '@/store/agentStore';
import type { PermissionRequest } from '@/lib/ws';
import { ShieldIcon } from '@/components/ui/icons';
import { AgentAvatar } from './AgentAvatar';
import { BACKEND_URL } from '@/lib/backend';

/**
 * 에이전트가 도구 실행 승인을 기다릴 때 맵 위에 띄우는 승인 카드 (기존 대시보드의 "승인이 필요합니다").
 * 대화 화면에서는 대화 흐름 안에 같은 카드가 들어가므로 띄우지 않는다.
 */
export function PermissionBanner() {
  const permissions = useAgentStore((s) => s.permissions);
  const inConversation = useAgentStore((s) => s.centerView === 'conversation');
  if (permissions.length === 0 || inConversation) return null;

  return (
    <div
      className={`absolute inset-x-3 top-3 z-20 flex max-h-[calc(100%-1.5rem)] flex-col gap-2 overflow-y-auto md:left-auto md:right-3 ${permissions.some((p) => p.tool === 'ExitPlanMode' || p.image) ? 'md:w-[560px]' : 'md:w-[380px]'}`}
    >
      {permissions.map((p) => (
        <PermissionCard key={p.id} request={p} floating />
      ))}
    </div>
  );
}

/** 승인 카드. floating이면 맵 위에 뜨는 모양(그림자·반투명), 아니면 대화 흐름 안에 들어가는 카드 */
export function PermissionCard({ request: p, floating = false }: { request: PermissionRequest; floating?: boolean }) {
  const defsById = useAgentStore((s) => s.defsById);
  const reply = useAgentStore((s) => s.replyPermission);
  const meta = p.agent === 'system' ? null : (defsById[p.agent] ?? null);
  // "계획 먼저": Claude가 세운 계획을 넓게 보여주고 승인/거절만 고른다
  const plan = p.tool === 'ExitPlanMode';
  // 레퍼런스 확인: GPT로 만든 참고 이미지를 보고 이걸로 진행할지 다시 만들지 고른다
  const reference = p.tool === 'confirm_reference';
  const imageUrl = p.image ? `${BACKEND_URL}${p.image}` : null;
  return (
    <div
      role="alertdialog"
      aria-label="승인 요청"
      className={`rounded-xl border border-amber-400/50 p-3 ${floating ? 'bg-[#0a1428]/95 shadow-[0_10px_30px_rgba(0,0,0,0.5)] backdrop-blur' : 'bg-amber-400/[0.06]'}`}
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
            <pre
              className={`mt-1 overflow-auto rounded-md bg-black/40 px-2 py-1.5 text-slate-300 ${
                plan ? 'max-h-[45vh] whitespace-pre-wrap font-sans text-[12px] leading-relaxed' : reference ? 'whitespace-pre-wrap font-sans text-[12px] leading-relaxed' : 'max-h-20 font-mono text-[11px]'
              }`}
            >
              {p.detail}
            </pre>
          )}
          {imageUrl && (
            <a href={imageUrl} target="_blank" rel="noreferrer" title="원본 크기로 보기" className="mt-2 block overflow-hidden rounded-lg border border-line bg-black/40">
              {/* eslint-disable-next-line @next/next/no-img-element -- 백엔드가 주는 작업 폴더 이미지라 next/image 최적화 대상이 아니다 */}
              <img src={imageUrl} alt={p.title} className="max-h-[50vh] w-full object-contain" />
            </a>
          )}
        </div>
      </div>
      <div className="mt-2.5 flex flex-wrap justify-end gap-1.5">
        <button
          type="button"
          onClick={() => reply(p.id, false, false)}
          className="rounded-md border border-line px-3 py-1 text-[12px] font-semibold text-slate-300 hover:border-red-400/60 hover:text-red-300"
        >
          {plan ? '계획 거절' : reference ? '다시 생성' : '거부'}
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
        <button type="button" onClick={() => reply(p.id, true, false)} className="rounded-md bg-amber-400 px-3 py-1 text-[12px] font-bold text-[#0a1428] hover:bg-amber-300">
          {plan ? '계획대로 진행' : reference ? '이걸로 진행' : '허용'}
        </button>
      </div>
    </div>
  );
}
