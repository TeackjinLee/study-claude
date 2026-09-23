'use client';

import dynamic from 'next/dynamic';
import { useAgentStore } from '@/store/agentStore';
import { PinIcon, UserIcon } from '@/components/ui/icons';
import { AttachmentChips } from './AttachmentChips';

const OfficeCanvas = dynamic(() => import('./OfficeCanvas').then((m) => m.OfficeCanvas), {
  ssr: false,
  loading: () => <div className="flex h-full w-full items-center justify-center text-sm text-muted">사무실을 불러오는 중...</div>,
});

/** Phaser 캔버스 위에 시안의 제목 칩과 사용자 명령 말풍선을 겹쳐 놓는 무대 */
export function OfficeStage() {
  const lastCommand = useAgentStore((s) => s.run?.command ?? null);
  // 선택자에서 새 배열을 만들면(?? []) 렌더마다 참조가 바뀌어 무한 렌더가 나므로 밖에서 기본값을 준다
  const runAttachments = useAgentStore((s) => s.run?.attachments);
  const attachments = runAttachments ?? [];
  const finished = useAgentStore((s) => s.run?.status === 'done' || s.run?.status === 'error');
  const setCenterView = useAgentStore((s) => s.setCenterView);
  const running = useAgentStore((s) => s.running);
  const agents = useAgentStore((s) => s.agents);
  const total = Object.keys(agents).length;
  const active = Object.values(agents).filter((a) => a.status !== 'idle').length;

  return (
    <div className="relative h-full w-full overflow-hidden rounded-2xl border border-line bg-[#08101f] shadow-[0_10px_40px_rgba(0,0,0,0.4)]">
      <OfficeCanvas />

      <div className="pointer-events-none absolute left-3 top-3 flex items-start gap-2.5 rounded-xl border border-line-strong/70 bg-[#0a1428]/85 px-3.5 py-2.5 backdrop-blur">
        <span className="mt-0.5 flex h-6 w-6 items-center justify-center rounded-md bg-accent/20 text-blue-300">
          <PinIcon className="h-3.5 w-3.5" />
        </span>
        <div className="leading-tight">
          <p className="text-[14px] font-bold text-white">AI Agent Office</p>
          <p className="text-[11px] text-slate-300">
            {running
              ? `${active}명의 에이전트가 열심히 일하고 있습니다.`
              : `오늘도 ${total}명의 에이전트가 대기 중입니다.`}
          </p>
        </div>
      </div>

      {lastCommand && (
        <div className="pointer-events-none absolute bottom-3 left-1/2 flex -translate-x-1/2 items-center gap-3 rounded-xl border border-line-strong/70 bg-[#0a1428]/90 px-3.5 py-2 backdrop-blur">
          <span className="flex h-8 w-8 items-center justify-center rounded-full border border-line-strong bg-panel-2 text-slate-300">
            <UserIcon className="h-4 w-4" />
          </span>
          <div className="leading-tight">
            <p className="text-[10px] text-muted">사용자</p>
            <p className="max-w-[360px] truncate text-[13px] font-semibold text-white">{lastCommand}</p>
            {attachments.length > 0 && (
              <div className="mt-1">
                <AttachmentChips items={attachments} size="sm" />
              </div>
            )}
          </div>
          {finished && !running && (
            <button
              type="button"
              onClick={() => setCenterView('results')}
              className="pointer-events-auto ml-1 shrink-0 rounded-lg bg-emerald-500/20 px-2.5 py-1 text-[12px] font-semibold text-emerald-300 hover:bg-emerald-500/30"
            >
              결과 보기 →
            </button>
          )}
        </div>
      )}
    </div>
  );
}
