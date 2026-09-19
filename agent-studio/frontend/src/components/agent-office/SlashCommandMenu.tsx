'use client';

import { useEffect, useMemo, useState } from 'react';
import type { CommandInfo } from '@/lib/ws';
import { useAgentStore } from '@/store/agentStore';

interface Props {
  /** 입력창의 현재 값. '/'로 시작할 때만 메뉴가 뜬다 */
  value: string;
  onPick: (completed: string) => void;
  /** 부모가 키 입력을 넘겨준다 (↑↓ 이동, Enter/Tab 선택, Esc 닫기). 처리했으면 true */
  registerKeyHandler: (handler: ((e: React.KeyboardEvent) => boolean) | null) => void;
}

/** 슬래시 명령을 고를 수 있는지 (첫 줄이 '/'로 시작하고 아직 인자를 입력하기 전) */
export function slashQuery(value: string): string | null {
  const m = /^\/([\w-]*)$/.exec(value);
  return m ? m[1].toLowerCase() : null;
}

/** 명령 입력창 위에 뜨는 슬래시 명령 자동완성 */
export function SlashCommandMenu({ value, onPick, registerKeyHandler }: Props) {
  const loadCommands = useAgentStore((s) => s.loadCommands);
  const cached = useAgentStore((s) => s.commands);
  const [index, setIndex] = useState(0);
  const query = slashQuery(value);

  useEffect(() => {
    if (query !== null && !cached) void loadCommands();
  }, [query, cached, loadCommands]);

  const items = useMemo<CommandInfo[]>(() => {
    if (query === null || !cached) return [];
    const list = cached.filter((c) => c.name.startsWith(query));
    // 앞글자 일치 우선, 그다음 포함
    const contains = query ? cached.filter((c) => !c.name.startsWith(query) && c.name.includes(query)) : [];
    return [...list, ...contains].slice(0, 12);
  }, [query, cached]);

  useEffect(() => {
    setIndex(0);
  }, [query]);

  useEffect(() => {
    if (items.length === 0) {
      registerKeyHandler(null);
      return;
    }
    registerKeyHandler((e) => {
      if (e.key === 'ArrowDown') {
        setIndex((i) => (i + 1) % items.length);
        return true;
      }
      if (e.key === 'ArrowUp') {
        setIndex((i) => (i - 1 + items.length) % items.length);
        return true;
      }
      if (e.key === 'Tab' || (e.key === 'Enter' && !e.shiftKey)) {
        const c = items[index];
        if (!c) return false;
        // 이미 명령 이름을 다 친 상태에서 Enter면 완성 대신 그대로 보낸다
        if (e.key === 'Enter' && c.name === query) return false;
        onPick(`/${c.name}${c.argumentHint ? ' ' : ''}`);
        return true;
      }
      if (e.key === 'Escape') {
        onPick(value);
        return true;
      }
      return false;
    });
    return () => registerKeyHandler(null);
  }, [items, index, onPick, registerKeyHandler, value, query]);

  if (query === null) return null;

  return (
    <div className="absolute bottom-full left-0 right-0 z-30 mb-1 max-h-64 overflow-y-auto rounded-xl border border-line-strong bg-[#0a1428]/97 p-1 shadow-[0_10px_30px_rgba(0,0,0,0.5)] backdrop-blur">
      {!cached && <p className="px-3 py-2 text-[12px] text-muted">명령 목록을 불러오는 중...</p>}
      {cached && items.length === 0 && (
        <p className="px-3 py-2 text-[12px] text-muted">
          일치하는 명령이 없습니다. 그대로 보내면 Claude Code에 <code className="font-mono">/{query}</code> 명령으로 전달됩니다.
        </p>
      )}
      {items.map((c, i) => (
        <button
          key={c.name}
          type="button"
          onMouseDown={(e) => e.preventDefault()}
          onClick={() => onPick(`/${c.name}${c.argumentHint ? ' ' : ''}`)}
          onMouseEnter={() => setIndex(i)}
          className={`flex w-full items-start gap-3 rounded-lg px-3 py-1.5 text-left ${i === index ? 'bg-accent/20' : 'hover:bg-white/[0.04]'}`}
        >
          <span className="shrink-0 font-mono text-[12px] font-semibold text-blue-200">
            /{c.name} <span className="font-normal text-muted">{c.argumentHint}</span>
          </span>
          <span className="min-w-0 flex-1 truncate text-[12px] text-slate-300">{c.description}</span>
          {c.source === 'sdk' && <span className="shrink-0 rounded bg-white/10 px-1.5 text-[10px] text-slate-300">Claude Code</span>}
        </button>
      ))}
      <p className="px-3 pt-1 text-[10px] text-muted">↑↓ 이동 · Tab/Enter 선택 · Esc 닫기</p>
    </div>
  );
}
