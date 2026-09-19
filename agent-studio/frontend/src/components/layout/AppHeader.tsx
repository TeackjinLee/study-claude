'use client';

import { useCallback, useEffect, useState } from 'react';
import { useAgentStore } from '@/store/agentStore';
import { BellIcon, ClockIcon, LogoMark, UserIcon } from '@/components/ui/icons';
import { authApi, codexAuthApi, type AuthStatus } from '@/lib/auth/api';
import { ClaudeLoginDialog } from './ClaudeLoginDialog';
import { AuthMenu } from './AuthMenu';
import { WorkspaceChip } from './WorkspaceChip';
import { UsageChip } from './UsageChip';

function pad(n: number) {
  return String(n).padStart(2, '0');
}

/** 하이드레이션 불일치를 피하려고 마운트 후에만 시각을 채운다. */
function useClock() {
  const [now, setNow] = useState<string | null>(null);
  useEffect(() => {
    const tick = () => {
      const d = new Date();
      setNow(`${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`);
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, []);
  return now;
}

const SYSTEM_LABEL = {
  connected: { text: '시스템 정상', color: '#4ade80' },
  connecting: { text: '연결 중', color: '#fbbf24' },
  disconnected: { text: '연결 끊김', color: '#f87171' },
} as const;

export function AppHeader() {
  const connection = useAgentStore((s) => s.connection);
  const running = useAgentStore((s) => s.running);
  const model = useAgentStore((s) => s.settings?.model);
  const effort = useAgentStore((s) => s.settings?.effort);
  const codexModel = useAgentStore((s) => s.settings?.codexModel);
  const clock = useClock();
  const sys = SYSTEM_LABEL[connection];

  const [auth, setAuth] = useState<AuthStatus | null>(null);
  const [loginOpen, setLoginOpen] = useState(false);
  const refreshAuth = useCallback(() => {
    authApi
      .status()
      .then(setAuth)
      .catch(() => setAuth(null));
  }, []);
  // Codex 협업 에이전트용 로그인 (별도 CLI라 상태도 따로 본다)
  const [codexAuth, setCodexAuth] = useState<AuthStatus | null>(null);
  const [codexLoginOpen, setCodexLoginOpen] = useState(false);
  const refreshCodexAuth = useCallback(() => {
    codexAuthApi
      .status()
      .then(setCodexAuth)
      .catch(() => setCodexAuth(null));
  }, []);
  useEffect(() => {
    refreshAuth();
    refreshCodexAuth();
  }, [refreshAuth, refreshCodexAuth]);

  return (
    <header className="relative z-30 flex h-[60px] shrink-0 items-center gap-4 border-b border-line bg-[#0a1428]/90 px-4 backdrop-blur md:px-5">
      <div className="flex items-center gap-3">
        <LogoMark className="h-9 w-9 drop-shadow-[0_0_10px_rgba(255,107,107,0.35)]" />
        <div className="leading-tight">
          <h1 className="text-[18px] font-extrabold tracking-tight text-white md:text-[20px]">AI Agent Office Simulator</h1>
        </div>
        <p className="hidden text-[13px] text-muted lg:block">AI 에이전트들이 함께 만드는 더 나은 코드 세상</p>
      </div>

      <div className="ml-auto flex items-center gap-2 md:gap-3">
        <WorkspaceChip />
        <span
          className="hidden items-center gap-1.5 rounded-full border border-line bg-panel px-3 py-1 text-[12px] text-slate-300 md:inline-flex"
          title={`Claude 모델: ${model ?? '기본'}${effort ? ` (${effort})` : ''} — /model 로 변경\nCodex 모델: ${codexModel ?? codexAuth?.defaultModel ?? '기본'} — /codex-model 로 변경`}
        >
          <span className="text-muted">Claude</span>
          <span className="font-semibold text-white">{model ?? '기본'}</span>
          {effort && <span className="text-muted">· {effort}</span>}
          {codexAuth?.available !== false && (
            <>
              <span className="text-muted">·</span>
              <span className="text-muted">Codex</span>
              <span className="max-w-[140px] truncate font-semibold text-white">{codexModel ?? codexAuth?.defaultModel ?? '기본'}</span>
            </>
          )}
        </span>
        <UsageChip />
        <span
          className="inline-flex items-center gap-2 rounded-full border px-3 py-1 text-[12px] font-semibold"
          style={{ color: sys.color, borderColor: `${sys.color}55`, backgroundColor: `${sys.color}14` }}
        >
          <span className={`h-2 w-2 rounded-full ${connection === 'connected' ? 'pulse-dot' : ''}`} style={{ backgroundColor: sys.color }} />
          {running ? '작업 실행 중' : sys.text}
        </span>

        <AuthMenu auth={auth} running={running} onLogin={() => setLoginOpen(true)} onChanged={setAuth} />
        <AuthMenu provider="codex" auth={codexAuth} running={running} onLogin={() => setCodexLoginOpen(true)} onChanged={setCodexAuth} />

        <span className="hidden items-center gap-1.5 text-[13px] font-medium tabular-nums text-slate-200 sm:inline-flex">
          <ClockIcon className="h-4 w-4 text-muted" />
          {clock ?? '--:--:--'}
        </span>

        <button
          type="button"
          className="relative rounded-full border border-line bg-panel p-2 text-slate-300 hover:border-line-strong hover:text-white"
          aria-label="알림"
        >
          <BellIcon className="h-4 w-4" />
          {running && <span className="absolute right-1.5 top-1.5 h-1.5 w-1.5 rounded-full bg-red-400" />}
        </button>

        <div className="hidden items-center gap-2 sm:flex">
          <div className="text-right leading-tight">
            <p className="text-[13px] font-semibold text-white">관리자</p>
            <p className="text-[11px] text-muted">개발자</p>
          </div>
          <div className="flex h-9 w-9 items-center justify-center rounded-full border border-line-strong bg-panel-2 text-slate-300">
            <UserIcon className="h-5 w-5" />
          </div>
        </div>
      </div>

      <ClaudeLoginDialog
        open={loginOpen}
        onClose={() => setLoginOpen(false)}
        onSuccess={() => {
          refreshAuth();
        }}
      />
      <ClaudeLoginDialog
        provider="codex"
        open={codexLoginOpen}
        onClose={() => {
          setCodexLoginOpen(false);
          refreshCodexAuth();
        }}
        onSuccess={refreshCodexAuth}
      />
    </header>
  );
}
