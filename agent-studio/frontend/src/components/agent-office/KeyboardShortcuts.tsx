'use client';

import { useEffect, useState } from 'react';
import { useAgentStore } from '@/store/agentStore';
import { KeyboardIcon, XIcon } from '@/components/ui/icons';

/** 단축키 도움말을 여는 이벤트 (명령 입력의 "단축키" 버튼이 보낸다) */
export const OPEN_SHORTCUTS_EVENT = 'agent-studio:shortcuts';

const SHORTCUTS: { keys: string[]; text: string }[] = [
  { keys: ['Enter'], text: '보내기' },
  { keys: ['Shift', 'Enter'], text: '줄바꿈' },
  { keys: ['↑', '↓'], text: '이전에 보낸 명령 불러오기 (첫 줄·마지막 줄에서)' },
  { keys: ['/'], text: '명령 입력창으로 (입력창 밖에서) · 입력창 맨 앞에서는 슬래시 명령' },
  { keys: ['@'], text: '작업 폴더의 파일 참조' },
  { keys: ['Esc'], text: '실행 중지 (열린 메뉴가 있으면 메뉴 닫기)' },
  { keys: ['⌘/Ctrl', 'V'], text: '스크린샷 붙여넣어 첨부' },
  { keys: ['?'], text: '이 도움말 (입력창 밖에서)' },
];

/** 글을 입력하는 곳에 포커스가 있는지 (그때는 / ? 를 단축키로 쓰지 않는다) */
function isTyping(target: EventTarget | null) {
  const el = target as HTMLElement | null;
  if (!el) return false;
  return el.isContentEditable || el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT';
}

/**
 * 화면 전체 단축키: Esc 실행 중지, / 입력창으로, ? 도움말.
 * 메뉴(슬래시·@파일·지난 대화)가 먼저 처리한 키(preventDefault)는 건드리지 않는다.
 */
export function KeyboardShortcuts() {
  const [open, setOpen] = useState(false);
  const interrupt = useAgentStore((s) => s.interrupt);
  const stoppable = useAgentStore((s) => s.running || s.codexBusy);

  useEffect(() => {
    const onOpen = () => setOpen(true);
    window.addEventListener(OPEN_SHORTCUTS_EVENT, onOpen);
    return () => window.removeEventListener(OPEN_SHORTCUTS_EVENT, onOpen);
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.defaultPrevented || e.isComposing || e.metaKey || e.ctrlKey || e.altKey) return;
      if (e.key === 'Escape') {
        if (open) {
          setOpen(false);
          return;
        }
        // 다른 곳에 떠 있는 메뉴(지난 대화 등)가 있으면 그 메뉴만 닫히게 둔다
        if (stoppable && !document.querySelector('[aria-expanded="true"]')) {
          e.preventDefault();
          interrupt();
        }
        return;
      }
      if (isTyping(e.target)) return;
      if (e.key === '/') {
        e.preventDefault();
        window.dispatchEvent(new Event('agent-studio:focus-command'));
      } else if (e.key === '?') {
        e.preventDefault();
        setOpen((v) => !v);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, stoppable, interrupt]);

  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onMouseDown={() => setOpen(false)}>
      <div
        role="dialog"
        aria-label="단축키"
        onMouseDown={(e) => e.stopPropagation()}
        className="w-full max-w-md rounded-2xl border border-line-strong bg-[#0a1428] p-4 shadow-[0_20px_50px_rgba(0,0,0,0.6)]"
      >
        <div className="mb-3 flex items-center gap-2">
          <KeyboardIcon className="h-4 w-4 text-blue-300" />
          <p className="text-[14px] font-bold text-white">단축키</p>
          <button type="button" onClick={() => setOpen(false)} aria-label="닫기" className="ml-auto rounded-md p-1 text-slate-400 hover:bg-white/10 hover:text-white">
            <XIcon className="h-4 w-4" />
          </button>
        </div>
        <ul className="flex flex-col gap-1.5">
          {SHORTCUTS.map((s) => (
            <li key={s.text} className="flex items-center gap-3 text-[12px]">
              <span className="flex w-[104px] shrink-0 items-center gap-1">
                {s.keys.map((k) => (
                  <kbd key={k} className="rounded border border-line-strong bg-white/[0.06] px-1.5 py-0.5 font-mono text-[11px] text-slate-100">
                    {k}
                  </kbd>
                ))}
              </span>
              <span className="text-slate-300">{s.text}</span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
