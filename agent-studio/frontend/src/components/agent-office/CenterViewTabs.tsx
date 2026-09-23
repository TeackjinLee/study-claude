'use client';

import { useAgentStore, type CenterView } from '@/store/agentStore';
import { ChatIcon, FileIcon, MapIcon } from '@/components/ui/icons';

/** 가운데 영역을 "대화" / "사무실 맵" / "결과 미리보기" 사이에서 전환하는 탭 */
export function CenterViewTabs() {
  const view = useAgentStore((s) => s.centerView);
  const setView = useAgentStore((s) => s.setCenterView);
  const fresh = useAgentStore((s) => s.freshResults);
  const artifacts = useAgentStore((s) => s.artifacts);
  const run = useAgentStore((s) => s.run);
  const running = useAgentStore((s) => s.running);

  const resultCount =
    Object.keys(artifacts.code).length + Object.keys(artifacts.test).length + Object.keys(artifacts.doc).length + (run?.result ? 1 : 0);
  const hasFresh = Object.values(fresh).some(Boolean);

  const tabs: { id: CenterView; label: string; icon: React.ReactNode; badge?: React.ReactNode }[] = [
    {
      id: 'conversation',
      label: '대화',
      icon: <ChatIcon className="h-4 w-4" />,
      badge: running && view !== 'conversation' ? <span className="pulse-dot h-1.5 w-1.5 rounded-full bg-blue-400" /> : undefined,
    },
    { id: 'office', label: '사무실 맵', icon: <MapIcon className="h-4 w-4" /> },
    {
      id: 'results',
      label: '결과 미리보기',
      icon: <FileIcon className="h-4 w-4" />,
      badge:
        resultCount > 0 ? (
          <span className="relative rounded-full bg-white/10 px-1.5 text-[10px] text-slate-200">
            {resultCount}
            {hasFresh && view !== 'results' && (
              <span className="absolute -right-1 -top-1 h-2 w-2 rounded-full bg-emerald-400 ring-2 ring-[#0d192f]" />
            )}
          </span>
        ) : undefined,
    },
  ];

  return (
    <div className="flex shrink-0 items-center gap-1 rounded-xl border border-line bg-panel p-1" role="tablist" aria-label="가운데 화면">
      {tabs.map((t) => {
        const active = view === t.id;
        return (
          <button
            key={t.id}
            role="tab"
            type="button"
            aria-selected={active}
            onClick={() => setView(t.id)}
            className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-[12px] font-semibold transition ${
              active ? 'bg-accent/20 text-white shadow-[inset_0_0_0_1px_rgba(59,130,246,0.4)]' : 'text-muted hover:text-slate-200'
            }`}
          >
            {t.icon}
            {t.label}
            {t.badge}
          </button>
        );
      })}
    </div>
  );
}
