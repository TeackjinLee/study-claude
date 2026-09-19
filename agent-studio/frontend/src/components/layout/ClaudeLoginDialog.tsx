'use client';

import { useEffect, useRef, useState } from 'react';
import { AUTH_API, type AuthProvider, type CodexLoginMethod, type LoginState } from '@/lib/auth/api';

const COPY: Record<AuthProvider, { title: string; intro: string; openLink: string; hint: string; done: string }> = {
  claude: {
    title: 'Claude 계정으로 로그인',
    intro: '구독 계정으로 1년짜리 인증 토큰을 발급받아 이 서버에 등록합니다. .env를 직접 수정할 필요가 없습니다.',
    openLink: '브라우저에서 Claude 로그인 열기',
    hint: '로그인 후 화면에 코드가 표시되면 복사해서 아래에 붙여넣고 확인을 누르세요. 자동으로 완료되면 붙여넣지 않아도 됩니다.',
    done: '로그인 완료! 토큰이 저장됐습니다.',
  },
  codex: {
    title: 'Codex (ChatGPT 계정)으로 로그인',
    intro: 'OpenAI Codex CLI에 로그인합니다. 브라우저에서 ChatGPT 계정으로 로그인하면 자동으로 완료됩니다. 자격증명은 ~/.codex 에 저장됩니다.',
    openLink: '브라우저에서 ChatGPT 로그인 열기',
    hint: '로그인이 끝나면 이 창이 자동으로 완료 상태가 됩니다. 페이지가 열리지 않으면 링크를 다시 누르세요.',
    done: 'Codex 로그인 완료!',
  },
};

/** Codex 기기 코드 방식일 때 바뀌는 문구 */
const CODEX_DEVICE_COPY = {
  openLink: '브라우저에서 Codex 기기 인증 열기',
  hint: '열린 페이지에 아래 일회용 코드를 입력하세요. 코드는 15분 동안 유효합니다. "잘못된 요청"이 뜨면 워크스페이스에서 기기 코드 로그인이 꺼진 것이니 브라우저 로그인을 쓰세요.',
};

const CODEX_METHOD_LABEL: Record<CodexLoginMethod, string> = { browser: '브라우저 로그인 (권장)', device: '기기 코드' };

/**
 * 대시보드에서 하는 CLI 로그인 모달.
 * claude: setup-token 흐름 (URL 열기 → 코드 붙여넣기)
 * codex: 브라우저 로그인 (URL 열기 → localhost 콜백으로 자동 완료) 또는 기기 인증 (URL 열기 → 화면의 코드를 웹사이트에 입력)
 */
export function ClaudeLoginDialog({
  provider = 'claude',
  open,
  onClose,
  onSuccess,
}: {
  provider?: AuthProvider;
  open: boolean;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const api = AUTH_API[provider];
  const [method, setMethod] = useState<CodexLoginMethod>('browser');
  const isDevice = provider === 'codex' && method === 'device';
  const copy = isDevice ? { ...COPY.codex, ...CODEX_DEVICE_COPY } : COPY[provider];
  const [state, setState] = useState<LoginState>({ status: 'idle' });
  const [code, setCode] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [copied, setCopied] = useState(false);
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    if (!open) return;
    let cancelled = false;

    setCopied(false);
    void api.loginStart(provider === 'codex' ? method : undefined).then((s) => {
      if (!cancelled) setState(s);
    });

    pollRef.current = setInterval(async () => {
      const s = await api.loginState();
      if (cancelled) return;
      setState(s);
      if (s.status === 'success') {
        if (pollRef.current) clearInterval(pollRef.current);
        onSuccess();
      }
    }, 800);

    return () => {
      cancelled = true;
      if (pollRef.current) clearInterval(pollRef.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, method]);

  if (!open) return null;

  const handleClose = async () => {
    if (state.status === 'running') await api.loginCancel();
    setCode('');
    onClose();
  };

  const handleSubmitCode = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!code.trim() || submitting) return;
    setSubmitting(true);
    try {
      await api.loginSubmitCode(code);
      setCode('');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
      <div className="w-[440px] max-w-[calc(100vw-24px)] rounded-xl border border-line bg-[#0a1428] p-5 shadow-[0_10px_40px_rgba(0,0,0,0.6)]">
        <h2 className="text-[15px] font-bold text-white">{copy.title}</h2>
        <p className="mt-1 text-[12px] text-muted">{copy.intro}</p>

        {provider === 'codex' && state.status !== 'success' && (
          <div className="mt-3 flex gap-1 rounded-md border border-line bg-panel p-0.5" role="radiogroup" aria-label="로그인 방식">
            {(Object.keys(CODEX_METHOD_LABEL) as CodexLoginMethod[]).map((m) => (
              <button
                key={m}
                type="button"
                role="radio"
                aria-checked={method === m}
                onClick={() => setMethod(m)}
                className={`flex-1 rounded px-2 py-1 text-[12px] font-semibold transition ${
                  method === m ? 'bg-accent/25 text-white' : 'text-muted hover:text-slate-200'
                }`}
              >
                {CODEX_METHOD_LABEL[m]}
              </button>
            ))}
          </div>
        )}

        {state.status === 'running' && !state.url && (
          <p className="mt-4 text-[13px] text-slate-300">로그인 절차를 준비하는 중…</p>
        )}

        {state.url && state.status === 'running' && (
          <div className="mt-4 space-y-3">
            <a
              href={state.url}
              target="_blank"
              rel="noreferrer"
              className="block rounded-md bg-amber-400 px-3 py-2 text-center text-[13px] font-bold text-[#0a1428] hover:bg-amber-300"
            >
              {copy.openLink}
            </a>
            <p className="text-[11px] text-muted">{copy.hint}</p>
            {isDevice && (
              <div className="flex items-center justify-between gap-3 rounded-lg border border-line bg-panel px-3 py-2.5">
                <span className="font-mono text-[22px] font-bold tracking-[0.15em] text-white">{state.code ?? '········'}</span>
                <button
                  type="button"
                  disabled={!state.code}
                  onClick={() => {
                    if (!state.code) return;
                    void navigator.clipboard?.writeText(state.code).then(() => setCopied(true));
                  }}
                  className="shrink-0 rounded-md border border-line px-2.5 py-1 text-[12px] font-semibold text-slate-200 hover:border-accent/60 hover:text-white disabled:opacity-50"
                >
                  {copied ? '복사됨' : '복사'}
                </button>
              </div>
            )}
            {provider === 'claude' && (
              <form onSubmit={handleSubmitCode} className="flex gap-2">
                <input
                  value={code}
                  onChange={(e) => setCode(e.target.value)}
                  placeholder="코드 붙여넣기"
                  className="min-w-0 flex-1 rounded-md border border-line bg-panel px-2.5 py-1.5 text-[13px] text-white outline-none focus:border-accent"
                />
                <button
                  type="submit"
                  disabled={submitting}
                  className="shrink-0 rounded-md border border-line px-3 py-1.5 text-[12px] font-semibold text-slate-200 hover:border-accent/60 hover:text-white disabled:opacity-50"
                >
                  확인
                </button>
              </form>
            )}
          </div>
        )}

        {state.status === 'success' && <p className="mt-4 text-[13px] font-semibold text-emerald-400">{copy.done}</p>}

        {state.status === 'error' && (
          <p className="mt-4 text-[13px] font-semibold text-red-400">{state.message ?? '로그인에 실패했습니다.'}</p>
        )}

        <div className="mt-5 flex justify-end gap-2">
          <button
            type="button"
            onClick={handleClose}
            className="rounded-md border border-line px-3 py-1.5 text-[12px] font-semibold text-slate-300 hover:border-red-400/60 hover:text-red-300"
          >
            {state.status === 'success' ? '닫기' : '취소'}
          </button>
        </div>
      </div>
    </div>
  );
}
