'use client';

import { useEffect, useState, type FormEvent } from 'react';
import { apiFetch } from '@/lib/backend';
import { ClaudeMarkIcon, ShieldIcon } from '@/components/ui/icons';

/** 소켓·요청이 로그인 필요로 거절됐을 때 로그인 창을 다시 띄우는 이벤트 */
export const UNAUTHORIZED_EVENT = 'agent-studio:unauthorized';

type Gate = 'checking' | 'open' | 'login';

/**
 * 원격 접속(휴대폰 등) 로그인 관문.
 * 이 컴퓨터에서 열었거나 원격 접속이 꺼져 있으면 그대로 통과하고, 다른 기기면 서버 비밀번호(ACCESS_PASSWORD)로 로그인해야 화면을 연다.
 * 서버에 닿지 않으면(꺼져 있음) 막지 않고 화면을 연다 — 화면이 연결 끊김을 따로 보여준다.
 */
export function AccessGate({ children }: { children: React.ReactNode }) {
  const [gate, setGate] = useState<Gate>('checking');

  useEffect(() => {
    let cancelled = false;
    apiFetch('/api/access/status')
      .then((res) => (res.ok ? (res.json() as Promise<{ required: boolean; authed: boolean }>) : null))
      .then((s) => !cancelled && setGate(s && s.required && !s.authed ? 'login' : 'open'))
      .catch(() => !cancelled && setGate('open'));
    const onUnauthorized = () => setGate('login');
    window.addEventListener(UNAUTHORIZED_EVENT, onUnauthorized);
    return () => {
      cancelled = true;
      window.removeEventListener(UNAUTHORIZED_EVENT, onUnauthorized);
    };
  }, []);

  if (gate === 'open') return <>{children}</>;
  if (gate === 'checking') return <div className="h-dvh w-full bg-[#0b0f1e]" />;
  // 로그인에 성공하면 쿠키가 생기므로 화면을 처음부터 다시 연다 (소켓도 새 쿠키로 다시 붙는다)
  return <LoginScreen onDone={() => window.location.reload()} />;
}

function LoginScreen({ onDone }: { onDone: () => void }) {
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (!password || busy) return;
    setBusy(true);
    setError(null);
    try {
      const res = await apiFetch('/api/access/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ password }) });
      if (res.ok) {
        onDone();
        return;
      }
      const body = (await res.json().catch(() => null)) as { error?: string } | null;
      setError(body?.error ?? `로그인하지 못했습니다. (${res.status})`);
    } catch {
      setError('서버에 연결할 수 없습니다. 컴퓨터의 서버가 켜져 있고 같은 와이파이인지 확인하세요.');
    } finally {
      setBusy(false);
      setPassword('');
    }
  };

  return (
    <div className="flex min-h-dvh w-full items-center justify-center bg-[#0b0f1e] p-4">
      <form onSubmit={(e) => void submit(e)} className="w-full max-w-sm rounded-2xl border border-line-strong bg-[#0a1428] p-5 shadow-[0_20px_50px_rgba(0,0,0,0.5)]">
        <div className="mb-4 flex items-center gap-2">
          <ClaudeMarkIcon className="h-6 w-6 text-[#d97757]" />
          <p className="text-[15px] font-bold text-white">AI Agent Office</p>
        </div>
        <p className="mb-3 flex items-start gap-1.5 text-[12px] leading-relaxed text-slate-400">
          <ShieldIcon className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-300" />
          다른 기기에서 접속했습니다. 서버의 접속 비밀번호(ACCESS_PASSWORD)를 입력하세요. 로그인은 30일 동안 유지됩니다.
        </p>
        <input
          type="password"
          autoFocus
          autoComplete="current-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="접속 비밀번호"
          aria-label="접속 비밀번호"
          className="w-full rounded-lg border border-line bg-[#08101f] px-3 py-2.5 text-[15px] text-white outline-none focus:border-accent/70"
        />
        {error && <p className="mt-2 text-[12px] text-red-300">{error}</p>}
        <button
          type="submit"
          disabled={!password || busy}
          className="mt-3 w-full rounded-lg bg-accent px-3 py-2.5 text-[14px] font-bold text-white hover:bg-accent/85 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {busy ? '확인 중…' : '로그인'}
        </button>
      </form>
    </div>
  );
}
