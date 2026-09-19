'use client';

import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useAgentStore } from '@/store/agentStore';
import { ChevronDownIcon, FolderIcon } from '@/components/ui/icons';

/** 경로의 마지막 두 조각만 보여준다 (예: study/agent-studio → …/agent-studio/workspace) */
function shortPath(path: string) {
  const parts = path
    .replace(/[\\/]+$/, '')
    .split(/[\\/]/)
    .filter(Boolean);
  if (parts.length <= 2) return path;
  return `…/${parts.slice(-2).join('/')}`;
}

/**
 * 헤더의 작업 폴더 표시. 누르면 경로를 바로 고칠 수 있는 작은 편집창이 열리고,
 * 적용하면 /workspace 명령으로 서버에 보낸다 (명령창에 /workspace <경로> 를 직접 쳐도 같다).
 */
/**
 * placement: 팝업이 열리는 방향. 헤더에서는 아래(bottom), 명령 입력창 아래 컨트롤 바에서는 위(top)로 연다.
 * compact: 항상 표시(헤더는 md 이상에서만).
 */
export function WorkspaceChip({ placement = 'bottom', compact = false }: { placement?: 'top' | 'bottom'; compact?: boolean } = {}) {
  const workspaceDir = useAgentStore((s) => s.settings?.workspaceDir);
  const running = useAgentStore((s) => s.running);
  const sendCommand = useAgentStore((s) => s.sendCommand);

  const [open, setOpen] = useState(false);
  const [value, setValue] = useState('');
  const rootRef = useRef<HTMLDivElement>(null);
  const popRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  // top 배치는 스크롤 컨테이너(명령 입력창) 안이라 absolute가 잘린다 → body 포털 + fixed
  const [pos, setPos] = useState<{ left: number; bottom: number } | null>(null);

  useEffect(() => {
    if (!open) return;
    setValue(workspaceDir ?? '');
    if (placement === 'top') {
      const r = rootRef.current?.getBoundingClientRect();
      if (r) setPos({ left: Math.max(8, Math.min(r.left, window.innerWidth - 436)), bottom: window.innerHeight - r.top + 6 });
    }
    // 열리자마자 경로 전체가 선택돼 있어 바로 새 경로를 붙여넣을 수 있다
    requestAnimationFrame(() => {
      inputRef.current?.focus();
      inputRef.current?.select();
    });
    const onDown = (e: MouseEvent) => {
      const t = e.target as Node;
      if (!rootRef.current?.contains(t) && !popRef.current?.contains(t)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    document.addEventListener('mousedown', onDown);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('mousedown', onDown);
      document.removeEventListener('keydown', onKey);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- 열릴 때의 값으로만 초기화
  }, [open]);

  if (!workspaceDir) return null;

  const trimmed = value.trim();
  const changed = trimmed !== '' && trimmed !== workspaceDir;

  const apply = (path: string) => {
    sendCommand(`/workspace ${path}`);
    setOpen(false);
  };

  const popup = (
    <div
      role="dialog"
      aria-label="작업 폴더 변경"
      ref={popRef}
      style={placement === 'top' && pos ? { position: 'fixed', left: pos.left, bottom: pos.bottom } : undefined}
      className={`z-50 w-[420px] max-w-[calc(100vw-32px)] rounded-lg border border-line bg-[#0a1428] p-3 shadow-[0_10px_30px_rgba(0,0,0,0.5)] ${
        placement === 'top' ? '' : 'absolute right-0 top-[calc(100%+6px)]'
      }`}
    >
      <p className="text-[12px] font-semibold text-white">작업 폴더</p>
      <p className="mt-0.5 text-[11px] leading-snug text-muted">
        에이전트가 파일을 읽고 쓰는 폴더입니다. 절대 경로 또는 <code className="font-mono">~/</code>로 시작하는 경로를 넣으세요.
      </p>
      <form
        className="mt-2.5 flex gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          if (changed && !running) apply(trimmed);
        }}
      >
        <input
          ref={inputRef}
          value={value}
          onChange={(e) => setValue(e.target.value)}
          spellCheck={false}
          disabled={running}
          placeholder="~/projects/my-app"
          className="min-w-0 flex-1 rounded-md border border-line bg-panel px-2.5 py-1.5 font-mono text-[12px] text-white outline-none focus:border-accent disabled:opacity-50"
        />
        <button
          type="submit"
          disabled={!changed || running}
          className="shrink-0 rounded-md bg-accent px-3 py-1.5 text-[12px] font-bold text-white hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-40"
        >
          적용
        </button>
      </form>
      <div className="mt-2 flex items-center justify-between gap-2">
        <button
          type="button"
          onClick={() => apply('default')}
          disabled={running}
          className="text-[11px] text-muted underline-offset-2 hover:text-slate-200 hover:underline disabled:cursor-not-allowed disabled:opacity-40"
          title=".env의 WORKSPACE_DIR 값으로 되돌립니다"
        >
          기본값으로 되돌리기
        </button>
        {running && <span className="text-[11px] text-amber-300">작업 실행 중에는 바꿀 수 없습니다</span>}
      </div>
    </div>
  );

  return (
    <div ref={rootRef} className={`relative ${compact ? '' : 'hidden md:block'}`}>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-haspopup="dialog"
        aria-expanded={open}
        className={
          compact
            ? 'inline-flex max-w-[220px] items-center gap-1 rounded-md border border-transparent px-1.5 py-0.5 text-[11px] text-slate-300 hover:border-line hover:text-white'
            : 'inline-flex max-w-[260px] items-center gap-1.5 rounded-full border border-line bg-panel px-3 py-1 text-[12px] text-slate-300 hover:border-line-strong hover:text-white'
        }
        title={`작업 폴더: ${workspaceDir}\n클릭해서 바꾸기 (/workspace)`}
      >
        <FolderIcon className="h-3.5 w-3.5 shrink-0 text-muted" />
        <span className="truncate font-mono text-[11.5px]">{shortPath(workspaceDir)}</span>
        <ChevronDownIcon className={`h-3.5 w-3.5 shrink-0 text-muted transition-transform ${open ? 'rotate-180' : ''}`} />
      </button>

      {open && (placement === 'top' ? (pos ? createPortal(popup, document.body) : null) : popup)}
    </div>
  );
}
