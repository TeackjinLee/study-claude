'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import type { CommandChoice, CommandInfo } from '@/lib/ws';
import { useAgentStore } from '@/store/agentStore';
import { slashQuery } from '@/lib/slashQuery';

interface Props {
  /** 입력창의 현재 값. '/'로 시작할 때만 메뉴가 뜬다 */
  value: string;
  onPick: (completed: string) => void;
  /** 인자 선택지(모델 등)를 고르면 바로 보낸다 */
  onSubmit: (text: string) => void;
  /** 부모가 키 입력을 넘겨준다 (↑↓ 이동, Enter/Tab 선택, Esc 닫기). 처리했으면 true */
  registerKeyHandler: (handler: ((e: React.KeyboardEvent) => boolean) | null) => void;
}

/** 명령 입력창 위에 뜨는 슬래시 명령 자동완성 */
export function SlashCommandMenu({ value, onPick, onSubmit, registerKeyHandler }: Props) {
  const loadCommands = useAgentStore((s) => s.loadCommands);
  const cached = useAgentStore((s) => s.commands);
  const settings = useAgentStore((s) => s.settings);
  const [index, setIndex] = useState(0);
  const parsed = slashQuery(value);
  const query = parsed?.query ?? null;
  const scope = parsed?.scope ?? null;
  const arg = parsed?.arg;
  const prefix = scope === 'codex' ? '/codex ' : '';
  /** 인자 입력 중인 명령 (선택지가 있을 때만) */
  const argCommand = useMemo(
    () => (arg === undefined || !cached ? null : (cached.find((c) => c.name === query && (c.scope ?? null) === scope && c.choices?.length) ?? null)),
    [arg, cached, query, scope],
  );
  /** 인자 메뉴에서 "현재 값" 표시용 */
  const currentArg = useMemo(() => {
    if (!argCommand) return null;
    const key = argCommand.scope === 'codex' ? `codex:${argCommand.name}` : argCommand.name;
    const map: Record<string, string | undefined> = {
      model: settings?.model ?? 'default',
      'codex-model': settings?.codexModel ?? 'default',
      'codex:model': settings?.codexModel ?? 'default',
      effort: settings?.effort ?? 'off',
      'permission-mode': settings?.permissionMode,
    };
    return map[key] ?? null;
  }, [argCommand, settings]);
  const choiceItems = useMemo<CommandChoice[]>(() => {
    if (!argCommand || arg === undefined) return [];
    const q = arg.toLowerCase();
    const all = argCommand.choices ?? [];
    return [
      ...all.filter((c) => c.value.toLowerCase().startsWith(q) || c.label.toLowerCase().startsWith(q)),
      ...all.filter(
        (c) => !c.value.toLowerCase().startsWith(q) && !c.label.toLowerCase().startsWith(q) && (c.value.toLowerCase().includes(q) || c.label.toLowerCase().includes(q)),
      ),
    ];
  }, [argCommand, arg]);
  /** 고른 명령을 입력창 값으로. Codex 하위 명령은 `/codex /name ` 형태 */
  const complete = useCallback((c: CommandInfo) => `${scope === 'codex' ? '/codex ' : ''}/${c.name}${c.argumentHint ? ' ' : ''}`, [scope]);

  useEffect(() => {
    if (query !== null && !cached) void loadCommands();
  }, [query, cached, loadCommands]);

  const items = useMemo<CommandInfo[]>(() => {
    if (query === null || !cached || arg !== undefined) return [];
    const pool = cached.filter((c) => (c.scope ?? null) === scope);
    const list = pool.filter((c) => c.name.startsWith(query));
    // 앞글자 일치 우선, 그다음 포함
    const contains = query ? pool.filter((c) => !c.name.startsWith(query) && c.name.includes(query)) : [];
    return [...list, ...contains].slice(0, 12);
  }, [query, scope, cached, arg]);

  useEffect(() => {
    setIndex(0);
  }, [query, arg]);

  /** 인자 선택지를 고르면 명령을 바로 보낸다 */
  const submitChoice = useCallback((c: CommandChoice) => onSubmit(`${prefix}/${argCommand?.name ?? query} ${c.value}`), [onSubmit, prefix, argCommand, query]);

  useEffect(() => {
    const count = argCommand ? choiceItems.length : items.length;
    if (count === 0) {
      registerKeyHandler(null);
      return;
    }
    registerKeyHandler((e) => {
      if (e.key === 'ArrowDown') {
        setIndex((i) => (i + 1) % count);
        return true;
      }
      if (e.key === 'ArrowUp') {
        setIndex((i) => (i - 1 + count) % count);
        return true;
      }
      if (e.key === 'Tab' || (e.key === 'Enter' && !e.shiftKey)) {
        if (argCommand) {
          const c = choiceItems[index];
          if (!c) return false;
          // 값을 정확히 다 쳤으면 그대로 보내게 둔다
          if (e.key === 'Enter' && c.value === arg) return false;
          if (e.key === 'Tab') onPick(`${prefix}/${argCommand.name} ${c.value}`);
          else submitChoice(c);
          return true;
        }
        const c = items[index];
        if (!c) return false;
        // 이미 명령 이름을 다 친 상태에서 Enter면 완성 대신 그대로 보낸다
        if (e.key === 'Enter' && c.name === query) return false;
        onPick(complete(c));
        return true;
      }
      if (e.key === 'Escape') {
        onPick(value);
        return true;
      }
      return false;
    });
    return () => registerKeyHandler(null);
  }, [items, index, onPick, registerKeyHandler, value, query, complete, argCommand, choiceItems, arg, prefix, submitChoice]);

  if (query === null) return null;
  // 인자 입력 중인데 선택지가 없는 명령이면 메뉴를 안 띄운다
  if (arg !== undefined && !argCommand) return null;

  if (argCommand) {
    return (
      <div className="absolute bottom-full left-0 right-0 z-30 mb-1 max-h-64 overflow-y-auto rounded-xl border border-line-strong bg-[#0a1428]/97 p-1 shadow-[0_10px_30px_rgba(0,0,0,0.5)] backdrop-blur">
        <p className={`px-3 pb-1 pt-1.5 text-[10px] font-semibold ${scope === 'codex' ? 'text-[#10a37f]' : 'text-blue-300'}`}>
          {prefix}/{argCommand.name} — 고르면 바로 적용됩니다
        </p>
        {choiceItems.length === 0 && <p className="px-3 py-2 text-[12px] text-muted">일치하는 선택지가 없습니다. 그대로 보내면 입력한 값으로 설정합니다.</p>}
        {choiceItems.map((c, i) => (
          <button
            key={c.value}
            type="button"
            onMouseDown={(e) => e.preventDefault()}
            onClick={() => submitChoice(c)}
            onMouseEnter={() => setIndex(i)}
            className={`flex w-full items-start gap-3 rounded-lg px-3 py-1.5 text-left ${i === index ? 'bg-accent/20' : 'hover:bg-white/[0.04]'}`}
          >
            <span className="shrink-0 font-mono text-[12px] font-semibold text-blue-200">{c.value}</span>
            <span className="min-w-0 flex-1 truncate text-[12px] text-slate-300">
              {c.label}
              {c.description && <span className="text-muted"> · {c.description}</span>}
            </span>
            {c.value === currentArg && <span className="shrink-0 rounded bg-accent/25 px-1.5 text-[10px] text-blue-100">현재</span>}
          </button>
        ))}
        <p className="px-3 pt-1 text-[10px] text-muted">↑↓ 이동 · Enter 적용 · Tab 채우기 · Esc 닫기</p>
      </div>
    );
  }

  return (
    <div className="absolute bottom-full left-0 right-0 z-30 mb-1 max-h-64 overflow-y-auto rounded-xl border border-line-strong bg-[#0a1428]/97 p-1 shadow-[0_10px_30px_rgba(0,0,0,0.5)] backdrop-blur">
      {!cached && <p className="px-3 py-2 text-[12px] text-muted">명령 목록을 불러오는 중...</p>}
      {cached && items.length === 0 && scope === 'codex' && <p className="px-3 py-2 text-[12px] text-muted">일치하는 Codex 명령이 없습니다.</p>}
      {cached && items.length === 0 && scope !== 'codex' && (
        <p className="px-3 py-2 text-[12px] text-muted">
          일치하는 명령이 없습니다. 그대로 보내면 Claude Code에 <code className="font-mono">/{query}</code> 명령으로 전달됩니다.
        </p>
      )}
      {scope === 'codex' && items.length > 0 && <p className="px-3 pb-1 pt-1.5 text-[10px] font-semibold text-[#10a37f]">Codex 명령</p>}
      {items.map((c, i) => (
        <button
          key={c.name}
          type="button"
          onMouseDown={(e) => e.preventDefault()}
          onClick={() => onPick(complete(c))}
          onMouseEnter={() => setIndex(i)}
          className={`flex w-full items-start gap-3 rounded-lg px-3 py-1.5 text-left ${i === index ? 'bg-accent/20' : 'hover:bg-white/[0.04]'}`}
        >
          <span className="shrink-0 font-mono text-[12px] font-semibold text-blue-200">
            {scope === 'codex' && <span className="text-muted">/codex </span>}/{c.name} <span className="font-normal text-muted">{c.argumentHint}</span>
          </span>
          <span className="min-w-0 flex-1 truncate text-[12px] text-slate-300">{c.description}</span>
          {c.source === 'sdk' && <span className="shrink-0 rounded bg-white/10 px-1.5 text-[10px] text-slate-300">Claude Code</span>}
        </button>
      ))}
      <p className="px-3 pt-1 text-[10px] text-muted">↑↓ 이동 · Tab/Enter 선택 · Esc 닫기</p>
    </div>
  );
}
