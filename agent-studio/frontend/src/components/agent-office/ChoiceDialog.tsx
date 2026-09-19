'use client';

import { useEffect, useState } from 'react';
import { useAgentStore } from '@/store/agentStore';
import { CheckIcon } from './StatusBadge';

/**
 * /model, /effort 처럼 인자 없이 부른 명령의 선택 창 (Claude Code 터미널의 모델 선택과 같은 흐름).
 * ↑↓로 고르고 Enter로 확정, Esc로 취소. 고르면 `${command} ${value}`를 서버로 보낸다.
 */
export function ChoiceDialog() {
  const choice = useAgentStore((s) => s.pendingChoice);
  const resolve = useAgentStore((s) => s.resolveChoice);
  const [index, setIndex] = useState(0);

  useEffect(() => {
    if (!choice) return;
    const cur = choice.options.findIndex((o) => o.current);
    setIndex(cur >= 0 ? cur : 0);
  }, [choice]);

  useEffect(() => {
    if (!choice) return;
    const onKey = (e: KeyboardEvent) => {
      const n = choice.options.length;
      if (e.key === 'ArrowDown' || (e.key === 'j' && !e.metaKey && !e.ctrlKey)) {
        e.preventDefault();
        setIndex((i) => (i + 1) % n);
      } else if (e.key === 'ArrowUp' || (e.key === 'k' && !e.metaKey && !e.ctrlKey)) {
        e.preventDefault();
        setIndex((i) => (i - 1 + n) % n);
      } else if (e.key === 'Enter') {
        e.preventDefault();
        resolve(choice.options[index]?.value ?? null);
      } else if (e.key === 'Escape') {
        e.preventDefault();
        resolve(null);
      } else if (/^[1-9]$/.test(e.key) && Number(e.key) <= n) {
        e.preventDefault();
        resolve(choice.options[Number(e.key) - 1].value);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [choice, index, resolve]);

  if (!choice) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/55 p-4 backdrop-blur-sm" onMouseDown={(e) => e.target === e.currentTarget && resolve(null)}>
      <div role="dialog" aria-modal="true" aria-labelledby="choice-title" className="panel w-full max-w-lg overflow-hidden">
        <div className="panel-header">
          <h2 id="choice-title" className="panel-title">
            <code className="rounded bg-accent/15 px-1.5 py-0.5 font-mono text-[12px] text-blue-200">{choice.command}</code>
            {choice.title}
          </h2>
          <span className="text-[11px] text-muted">↑↓ 이동 · Enter 선택 · Esc 취소</span>
        </div>
        <ul className="max-h-[60vh] overflow-y-auto p-2">
          {choice.options.map((o, i) => {
            const active = i === index;
            return (
              <li key={o.value}>
                <button
                  type="button"
                  onMouseEnter={() => setIndex(i)}
                  onClick={() => resolve(o.value)}
                  className={`flex w-full items-start gap-3 rounded-lg px-3 py-2 text-left transition ${active ? 'bg-accent/20' : 'hover:bg-white/[0.04]'}`}
                >
                  <span className={`mt-0.5 w-4 shrink-0 text-center font-mono text-[12px] ${active ? 'text-blue-200' : 'text-muted'}`}>{i < 9 ? i + 1 : ''}</span>
                  <span className="min-w-0 flex-1">
                    <span className="flex items-center gap-2 text-[13px] font-semibold text-white">
                      {o.label}
                      {o.current && (
                        <span className="inline-flex items-center gap-1 rounded-full bg-emerald-500/15 px-1.5 text-[10px] font-semibold text-emerald-300">
                          <CheckIcon className="h-3 w-3" />
                          현재
                        </span>
                      )}
                    </span>
                    {o.description && <span className="block text-[11.5px] text-muted">{o.description}</span>}
                  </span>
                  <span className={`shrink-0 self-center text-[12px] ${active ? 'text-blue-200' : 'text-transparent'}`}>›</span>
                </button>
              </li>
            );
          })}
        </ul>
      </div>
    </div>
  );
}
