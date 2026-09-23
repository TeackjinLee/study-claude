'use client';

import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useAgentStore } from '@/store/agentStore';
import { MASTER_ID } from '@/types/agent';
import { PencilIcon, XIcon } from '@/components/ui/icons';
import { AgentAvatar } from './AgentAvatar';
import { PokemonPicker } from './PokemonPicker';

const COLORS = ['#f8fafc', '#fbbf24', '#f472b6', '#60a5fa', '#34d399', '#f97316', '#a78bfa', '#ef4444'];

/**
 * 에이전트 목록 맨 위의 "나(Master)" 카드. 사무실에서 방향키/클릭으로 움직이는 사용자 캐릭터의 이름·모습·색을 바꾼다.
 * 에이전트가 아니라 브라우저에만 저장된다.
 */
export function MasterCard() {
  const master = useAgentStore((s) => s.master);
  const setMaster = useAgentStore((s) => s.setMaster);
  const nearby = useAgentStore((s) => (s.masterNearby ? s.defsById[s.masterNearby] : undefined));
  const talkTarget = useAgentStore((s) => (s.talkTarget ? s.defsById[s.talkTarget] : undefined));
  const [open, setOpen] = useState(false);
  const [name, setName] = useState(master.name);
  const dialogRef = useRef<HTMLDivElement>(null);

  useEffect(() => setName(master.name), [master.name]);
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [open]);

  const commitName = () => {
    const next = name.trim().slice(0, 16);
    if (next && next !== master.name) setMaster({ name: next });
    else setName(master.name);
  };

  const hint = talkTarget ? `${talkTarget.shortName}에게 말하는 중` : nearby ? `${nearby.shortName} 옆 · E 로 말 걸기` : '방향키/WASD 이동 · 바닥 클릭 · 에이전트 클릭';

  return (
    <>
      <div className="mx-2 mt-2 flex items-center gap-3 rounded-xl border px-2.5 py-2" style={{ borderColor: `${master.color}55`, background: `${master.color}0d` }}>
        <AgentAvatar role={MASTER_ID} size={46} />
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <span className="truncate text-[13px] font-bold text-white">{master.name}</span>
            <span className="rounded px-1 text-[10px] font-bold" style={{ backgroundColor: `${master.color}33`, color: master.color }}>
              나
            </span>
          </div>
          <p className="mt-0.5 truncate text-[11px] text-muted">{hint}</p>
        </div>
        <button
          type="button"
          onClick={() => setOpen(true)}
          aria-label="내 캐릭터 설정"
          title="내 캐릭터 설정"
          className="rounded-md p-1 text-muted hover:bg-white/10 hover:text-white"
        >
          <PencilIcon className="h-3.5 w-3.5" />
        </button>
      </div>

      {open &&
        createPortal(
          <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4" onMouseDown={(e) => e.target === e.currentTarget && setOpen(false)}>
            <div
              ref={dialogRef}
              role="dialog"
              aria-modal="true"
              aria-label="내 캐릭터 설정"
              className="flex max-h-[85vh] w-[520px] max-w-full flex-col gap-3 rounded-2xl border border-line-strong bg-[#0a1428] p-4 shadow-[0_20px_60px_rgba(0,0,0,0.6)]"
            >
              <div className="flex items-center justify-between">
                <h3 className="text-[14px] font-bold text-white">내 캐릭터 (Master)</h3>
                <button type="button" onClick={() => setOpen(false)} className="rounded-md p-1 text-muted hover:bg-white/10 hover:text-white" aria-label="닫기">
                  <XIcon className="h-4 w-4" />
                </button>
              </div>
              <p className="text-[12px] text-muted">
                사무실에서 직접 움직이는 사용자 캐릭터입니다. 에이전트 옆에 서서 E(또는 Enter)를 누르거나 에이전트를 클릭하면 그 에이전트에게 바로 말할 수 있습니다.
              </p>
              <div className="flex items-center gap-3">
                <AgentAvatar def={{ name, shortName: name, color: master.color, pokemonId: master.pokemonId }} size={56} />
                <label className="flex min-w-0 flex-1 flex-col gap-1 text-[11px] font-semibold text-slate-300">
                  이름
                  <input
                    value={name}
                    maxLength={16}
                    onChange={(e) => setName(e.target.value)}
                    onBlur={commitName}
                    onKeyDown={(e) => e.key === 'Enter' && commitName()}
                    className="rounded-md border border-line bg-panel-2 px-2 py-1 text-[13px] font-normal text-white outline-none focus:border-accent/60"
                  />
                </label>
                <div className="flex flex-col gap-1 text-[11px] font-semibold text-slate-300">
                  색
                  <div className="flex flex-wrap gap-1">
                    {COLORS.map((c) => (
                      <button
                        key={c}
                        type="button"
                        onClick={() => setMaster({ color: c })}
                        aria-label={c}
                        className={`h-5 w-5 rounded-full border-2 ${c === master.color ? 'border-white' : 'border-transparent'}`}
                        style={{ backgroundColor: c }}
                      />
                    ))}
                  </div>
                </div>
              </div>
              <div className="min-h-0 flex-1 overflow-hidden">
                <PokemonPicker value={master.pokemonId} color={master.color} onChange={(p) => setMaster({ pokemonId: p.id, pokemonName: p.name })} />
              </div>
            </div>
          </div>,
          document.body,
        )}
    </>
  );
}
