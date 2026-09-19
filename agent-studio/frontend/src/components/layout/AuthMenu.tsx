'use client';

import { useEffect, useRef, useState } from 'react';
import { AUTH_API, type AuthProvider, type AuthStatus } from '@/lib/auth/api';
import { ChevronDownIcon } from '@/components/ui/icons';

const METHOD_LABEL = { api_key: 'API 키', oauth: 'Claude 계정', chatgpt: 'ChatGPT 계정' } as const;

/** 제공자별 문구 */
const COPY: Record<AuthProvider, { name: string; needLogin: string; authed: string; envKey: string; loginTitle: string; relogin: string }> = {
  claude: { name: 'Claude', needLogin: '로그인 필요', authed: '인증됨', envKey: 'ANTHROPIC_API_KEY', loginTitle: 'Claude 계정으로 로그인해서 인증 토큰을 받습니다', relogin: '다시 로그인' },
  codex: {
    name: 'Codex',
    needLogin: 'Codex 로그인',
    authed: 'Codex 인증됨',
    envKey: 'CODEX_API_KEY',
    loginTitle: 'OpenAI Codex CLI에 ChatGPT 계정으로 로그인합니다 (Codex 협업 에이전트에 필요)',
    relogin: '다시 로그인 (기존 로그인은 해제됨)',
  },
};

/**
 * 헤더의 인증 상태 버튼. 로그인 전엔 "로그인 필요"만 보이고,
 * 로그인 후엔 눌러서 다시 로그인 / 로그아웃을 고를 수 있는 메뉴가 열린다. provider로 Claude/Codex 문구를 고른다.
 */
export function AuthMenu({
  provider = 'claude',
  auth,
  running,
  onLogin,
  onChanged,
}: {
  provider?: AuthProvider;
  auth: AuthStatus | null;
  /** 작업 실행 중이면 로그아웃을 막는다 (실행 중 인증이 사라지면 중간에 깨질 수 있음) */
  running: boolean;
  onLogin: () => void;
  onChanged: (next: AuthStatus) => void;
}) {
  const [open, setOpen] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const rootRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (!rootRef.current?.contains(e.target as Node)) close();
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') close();
    };
    document.addEventListener('mousedown', onDown);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('mousedown', onDown);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  const close = () => {
    setOpen(false);
    setConfirming(false);
    setError(null);
  };

  if (!auth) return null;
  const copy = COPY[provider];

  if (auth.available === false) {
    return (
      <span
        className="inline-flex items-center gap-1.5 rounded-full border border-line bg-panel px-3 py-1 text-[12px] font-semibold text-muted"
        title={auth.message ?? `${copy.name} CLI를 찾을 수 없습니다`}
      >
        {copy.name} 없음
      </span>
    );
  }

  if (!auth.hasAuth) {
    return (
      <button
        type="button"
        onClick={onLogin}
        className="inline-flex items-center gap-1.5 rounded-full border border-red-400/40 bg-red-400/10 px-3 py-1 text-[12px] font-semibold text-red-300 hover:bg-red-400/20"
        title={copy.loginTitle}
      >
        {copy.needLogin}
      </button>
    );
  }

  const canLogout = auth.method !== 'api_key';

  const handleLogout = async () => {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      const next = await AUTH_API[provider].logout();
      onChanged(next);
      close();
    } catch {
      setError('로그아웃에 실패했습니다. 서버 로그를 확인하세요.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div ref={rootRef} className="relative">
      <button
        type="button"
        onClick={() => (open ? close() : setOpen(true))}
        aria-haspopup="menu"
        aria-expanded={open}
        className="inline-flex items-center gap-1.5 rounded-full border border-emerald-400/40 bg-emerald-400/10 px-3 py-1 text-[12px] font-semibold text-emerald-300 hover:bg-emerald-400/20"
        title={`${METHOD_LABEL[auth.method ?? 'oauth']}로 인증됨`}
      >
        {copy.authed}
        <ChevronDownIcon className={`h-3.5 w-3.5 transition-transform ${open ? 'rotate-180' : ''}`} />
      </button>

      {open && (
        <div
          role="menu"
          className="absolute right-0 top-[calc(100%+6px)] z-40 w-[240px] rounded-lg border border-line bg-[#0a1428] p-1.5 shadow-[0_10px_30px_rgba(0,0,0,0.5)]"
        >
          <p className="px-2.5 pb-1.5 pt-1 text-[11px] text-muted">
            인증 방식 · <span className="font-semibold text-slate-200">{METHOD_LABEL[auth.method ?? 'oauth']}</span>
          </p>

          {!confirming ? (
            <>
              <button
                type="button"
                role="menuitem"
                onClick={() => {
                  close();
                  onLogin();
                }}
                className="block w-full rounded-md px-2.5 py-1.5 text-left text-[12px] font-medium text-slate-200 hover:bg-white/5 hover:text-white"
              >
                {copy.relogin}
              </button>
              <button
                type="button"
                role="menuitem"
                disabled={!canLogout || running}
                onClick={() => setConfirming(true)}
                className="block w-full rounded-md px-2.5 py-1.5 text-left text-[12px] font-medium text-red-300 hover:bg-red-400/10 disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:bg-transparent"
                title={
                  !canLogout
                    ? `.env의 ${copy.envKey}로 인증돼 있어 여기서는 로그아웃할 수 없습니다`
                    : running
                      ? '작업이 끝난 뒤 로그아웃할 수 있습니다'
                      : undefined
                }
              >
                로그아웃
              </button>
              {!canLogout && (
                <p className="px-2.5 pb-1 pt-1.5 text-[11px] leading-snug text-muted">
                  API 키 인증은 .env에서 {copy.envKey}를 지워야 해제됩니다.
                </p>
              )}
              {canLogout && running && (
                <p className="px-2.5 pb-1 pt-1.5 text-[11px] leading-snug text-muted">작업 실행 중에는 로그아웃할 수 없습니다.</p>
              )}
            </>
          ) : (
            <div className="px-2.5 pb-1.5 pt-1">
              <p className="text-[12px] leading-snug text-slate-200">
                {provider === 'codex'
                  ? 'Codex CLI에서 로그아웃합니다(~/.codex/auth.json 삭제). 실행 중 Codex 협업자는 제외됩니다.'
                  : '저장된 인증 토큰을 서버와 .env에서 지웁니다. 다시 쓰려면 새로 로그인해야 합니다.'}
              </p>
              {error && <p className="mt-1.5 text-[11px] text-red-400">{error}</p>}
              <div className="mt-2.5 flex justify-end gap-1.5">
                <button
                  type="button"
                  onClick={() => setConfirming(false)}
                  disabled={busy}
                  className="rounded-md border border-line px-2.5 py-1 text-[12px] font-semibold text-slate-300 hover:text-white disabled:opacity-50"
                >
                  취소
                </button>
                <button
                  type="button"
                  onClick={handleLogout}
                  disabled={busy}
                  className="rounded-md bg-red-500/80 px-2.5 py-1 text-[12px] font-bold text-white hover:bg-red-500 disabled:opacity-50"
                >
                  {busy ? '로그아웃 중…' : '로그아웃'}
                </button>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
