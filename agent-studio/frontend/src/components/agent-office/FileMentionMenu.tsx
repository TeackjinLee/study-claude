'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { fetchFileSuggestions, type FileSuggestion } from '@/lib/fileSuggestions';
import { atQuery } from '@/lib/atQuery';
import { FileIcon, FolderIcon } from '@/components/ui/icons';

interface Props {
  value: string;
  /** 입력창의 커서 위치 */
  caret: number;
  /** 고른 경로로 바꾼 입력값과 그 뒤의 커서 위치 */
  onPick: (value: string, caret: number) => void;
  /** 부모가 키 입력을 넘겨준다 (↑↓ 이동, Enter/Tab 선택, Esc 닫기). 처리했으면 true */
  registerKeyHandler: (handler: ((e: React.KeyboardEvent) => boolean) | null) => void;
}

const DEBOUNCE_MS = 120;

/**
 * 입력창에서 @를 치면 뜨는 작업 폴더 파일 자동완성 (Claude Code의 @파일 참조).
 * 고르면 `@경로`가 들어가고, Claude Code가 그 파일 내용을 명령에 붙여 읽는다. 폴더를 고르면 그 안을 이어서 찾는다.
 */
export function FileMentionMenu({ value, caret, onPick, registerKeyHandler }: Props) {
  const at = useMemo(() => atQuery(value, caret), [value, caret]);
  const query = at?.query ?? null;
  const [items, setItems] = useState<FileSuggestion[] | null>(null);
  const [error, setError] = useState(false);
  const [index, setIndex] = useState(0);
  /** Esc로 닫은 @ 위치. 다른 @를 칠 때까지 다시 띄우지 않는다 */
  const [dismissed, setDismissed] = useState<number | null>(null);
  const cache = useRef(new Map<string, FileSuggestion[]>());
  const open = at !== null && dismissed !== at.start;

  useEffect(() => {
    if (query === null || !open) return;
    setIndex(0);
    const hit = cache.current.get(query);
    if (hit) {
      setItems(hit);
      return;
    }
    const ctrl = new AbortController();
    const t = setTimeout(() => {
      fetchFileSuggestions(query, ctrl.signal)
        .then((list) => {
          cache.current.set(query, list);
          setItems(list);
          setError(false);
        })
        .catch((err: unknown) => {
          if ((err as Error).name !== 'AbortError') setError(true);
        });
    }, DEBOUNCE_MS);
    return () => {
      clearTimeout(t);
      ctrl.abort();
    };
  }, [query, open]);

  // 다른 @를 치기 시작하면 닫았던 상태를 푼다. 메뉴를 새로 열 때는 목록 캐시도 비운다 (파일이 새로 생겼을 수 있다)
  useEffect(() => {
    if (at === null) {
      setDismissed(null);
      cache.current.clear();
    }
  }, [at]);

  const pick = (s: FileSuggestion) => {
    if (!at) return;
    // 파일 뒤에는 한 칸 띄우고, 폴더는 그 안을 이어서 찾게 붙여 둔다. 경로에 공백이 있으면 따옴표로 감싼다
    const path = /\s/.test(s.path) ? `"${s.path}"` : s.path;
    const inserted = `@${path}${s.dir ? '' : ' '}`;
    const next = value.slice(0, at.start) + inserted + value.slice(caret);
    onPick(next, at.start + inserted.length);
  };

  const list = open ? (items ?? []) : [];
  useEffect(() => {
    if (!open || list.length === 0) {
      registerKeyHandler(
        open
          ? (e) => {
              if (e.key !== 'Escape' || !at) return false;
              setDismissed(at.start);
              return true;
            }
          : null,
      );
      return;
    }
    registerKeyHandler((e) => {
      if (e.key === 'ArrowDown') {
        setIndex((i) => (i + 1) % list.length);
        return true;
      }
      if (e.key === 'ArrowUp') {
        setIndex((i) => (i - 1 + list.length) % list.length);
        return true;
      }
      if (e.key === 'Tab' || (e.key === 'Enter' && !e.shiftKey)) {
        const s = list[index];
        if (!s) return false;
        pick(s);
        return true;
      }
      if (e.key === 'Escape' && at) {
        setDismissed(at.start);
        return true;
      }
      return false;
    });
    return () => registerKeyHandler(null);
  });

  if (!open) return null;
  return (
    <div className="absolute bottom-full left-0 right-0 z-30 mb-1 max-h-64 overflow-y-auto rounded-xl border border-line-strong bg-[#0a1428]/97 p-1 shadow-[0_10px_30px_rgba(0,0,0,0.5)] backdrop-blur">
      <p className="px-3 pb-1 pt-1.5 text-[10px] font-semibold text-blue-300">@파일 참조 — 고른 파일의 내용을 Claude가 명령과 함께 읽습니다</p>
      {error && <p className="px-3 py-2 text-[12px] text-red-300">파일 목록을 불러오지 못했습니다.</p>}
      {!error && items === null && <p className="px-3 py-2 text-[12px] text-muted">파일 목록을 불러오는 중...</p>}
      {!error && items?.length === 0 && <p className="px-3 py-2 text-[12px] text-muted">일치하는 파일이 없습니다.</p>}
      {list.map((s, i) => {
        const cut = s.path.replace(/\/$/, '').lastIndexOf('/') + 1;
        const Icon = s.dir ? FolderIcon : FileIcon;
        return (
          <button
            key={s.path}
            type="button"
            onMouseDown={(e) => e.preventDefault()}
            onClick={() => pick(s)}
            onMouseEnter={() => setIndex(i)}
            className={`flex w-full items-center gap-2 rounded-lg px-3 py-1 text-left font-mono text-[12px] ${i === index ? 'bg-accent/20' : 'hover:bg-white/[0.04]'}`}
          >
            <Icon className={`h-3.5 w-3.5 shrink-0 ${s.dir ? 'text-amber-300' : 'text-slate-400'}`} />
            <span className="min-w-0 truncate">
              <span className="text-muted">{s.path.slice(0, cut)}</span>
              <span className="text-slate-100">{s.path.slice(cut)}</span>
            </span>
          </button>
        );
      })}
      <p className="px-3 pt-1 text-[10px] text-muted">↑↓ 이동 · Tab/Enter 선택 · Esc 닫기</p>
    </div>
  );
}
