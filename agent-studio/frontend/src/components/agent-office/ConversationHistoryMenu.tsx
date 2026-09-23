'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { useAgentStore } from '@/store/agentStore';
import { conversationsApi, type ConversationMeta } from '@/lib/conversations';
import { ChatIcon, ClockIcon, CodeIcon, CoworkIcon, TrashIcon } from '@/components/ui/icons';

/** "3분 전", "어제 14:05" 같은 짧은 시각 */
function ago(at: number) {
  const diff = Date.now() - at;
  const min = Math.floor(diff / 60_000);
  if (min < 1) return '방금';
  if (min < 60) return `${min}분 전`;
  const hour = Math.floor(min / 60);
  if (hour < 24) return `${hour}시간 전`;
  const d = new Date(at);
  const hm = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
  if (hour < 48) return `어제 ${hm}`;
  return `${d.getMonth() + 1}/${d.getDate()} ${hm}`;
}

/**
 * 대화 화면 머리의 "지난 대화" 버튼과 목록.
 * 서버(data/conversations)에 저장된 코드·채팅·Cowork 대화를 최근 순으로 보여주고, 골라서 이어가거나(Cowork는 다시 열어 보기) 지운다.
 */
export function ConversationHistoryMenu() {
  const [open, setOpen] = useState(false);
  const [items, setItems] = useState<ConversationMeta[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const running = useAgentStore((s) => s.running);
  const version = useAgentStore((s) => s.conversationsVersion);
  const titles = useAgentStore((s) => s.conversationTitles);
  const box = useRef<HTMLDivElement | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      setItems((await conversationsApi.list()).conversations);
    } catch (err) {
      setError(err instanceof Error ? `목록을 불러오지 못했습니다: ${err.message}` : '목록을 불러오지 못했습니다.');
    }
  }, []);

  useEffect(() => {
    if (open) void load();
  }, [open, load, version]);

  // 바깥을 누르거나 Esc면 닫는다
  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (box.current && !box.current.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false);
    window.addEventListener('mousedown', onDown);
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('mousedown', onDown);
      window.removeEventListener('keydown', onKey);
    };
  }, [open]);

  const activeIds = new Set(Object.values(titles).map((t) => t?.id));

  const openOne = async (c: ConversationMeta) => {
    setBusy(c.id);
    setError(null);
    try {
      const res = await conversationsApi.open(c.id);
      if (res.ok) setOpen(false);
      else setError(res.error ?? '대화를 열지 못했습니다.');
    } catch (err) {
      setError(err instanceof Error ? err.message : '대화를 열지 못했습니다.');
    } finally {
      setBusy(null);
    }
  };

  const removeOne = async (c: ConversationMeta) => {
    if (!window.confirm(`"${c.title}" 대화를 지울까요? 지운 대화는 되살릴 수 없습니다.`)) return;
    setBusy(c.id);
    try {
      const res = await conversationsApi.remove(c.id);
      if (!res.ok) setError(res.error ?? '지우지 못했습니다.');
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : '지우지 못했습니다.');
    } finally {
      setBusy(null);
    }
  };

  return (
    <div ref={box} className="relative">
      <button
        type="button"
        onClick={() => setOpen(!open)}
        aria-expanded={open}
        className={`inline-flex items-center gap-1 rounded-md border px-2 py-0.5 text-[11px] font-semibold transition ${
          open ? 'border-accent/60 bg-accent/15 text-white' : 'border-line text-slate-300 hover:border-accent/60 hover:text-white'
        }`}
      >
        <ClockIcon className="h-3.5 w-3.5" />
        지난 대화
      </button>
      {open && (
        <div className="absolute right-0 top-full z-30 mt-1 flex max-h-[60vh] w-[min(380px,80vw)] flex-col overflow-hidden rounded-xl border border-line-strong bg-[#0a1428] shadow-[0_12px_32px_rgba(0,0,0,0.55)]">
          <p className="border-b border-line px-3 py-2 text-[11px] text-muted">지금 작업 폴더의 대화 · 누르면 이어서 대화합니다 (Cowork는 기록만 다시 엽니다)</p>
          {error && <p className="border-b border-red-500/30 bg-red-500/10 px-3 py-1.5 text-[12px] text-red-300">{error}</p>}
          <ul className="min-h-0 flex-1 overflow-y-auto py-1">
            {items === null && !error && <li className="px-3 py-3 text-[12px] text-slate-500">불러오는 중…</li>}
            {items?.length === 0 && <li className="px-3 py-3 text-[12px] text-slate-500">아직 저장된 대화가 없습니다.</li>}
            {items?.map((c) => {
              const active = activeIds.has(c.id);
              const Icon = c.mode === 'chat' ? ChatIcon : c.mode === 'cowork' ? CoworkIcon : CodeIcon;
              return (
                <li key={c.id} className={`group flex items-center gap-2 px-2 ${active ? 'bg-accent/10' : 'hover:bg-white/[0.04]'}`}>
                  <button
                    type="button"
                    disabled={running || busy !== null}
                    onClick={() => void openOne(c)}
                    title={running ? '실행이 끝난 뒤 열 수 있습니다' : c.title}
                    className="flex min-w-0 flex-1 items-center gap-2 py-1.5 text-left disabled:cursor-not-allowed"
                  >
                    <Icon className="h-3.5 w-3.5 shrink-0 text-slate-400" />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-[12px] font-semibold text-slate-100">{c.title}</span>
                      <span className="block text-[10px] text-muted">
                        {c.mode === 'cowork' && 'Cowork · '}
                        {ago(c.updatedAt)} · 명령 {c.runs}개 · ${c.costUsd.toFixed(4)}
                        {active && <span className="text-emerald-300"> · 이어가는 중</span>}
                      </span>
                    </span>
                  </button>
                  <button
                    type="button"
                    onClick={() => void removeOne(c)}
                    disabled={busy !== null}
                    aria-label={`${c.title} 지우기`}
                    title="지우기"
                    className="shrink-0 rounded p-1 text-slate-500 opacity-0 transition hover:bg-red-500/10 hover:text-red-300 focus:opacity-100 group-hover:opacity-100 disabled:opacity-30"
                  >
                    <TrashIcon className="h-3.5 w-3.5" />
                  </button>
                </li>
              );
            })}
          </ul>
        </div>
      )}
    </div>
  );
}
