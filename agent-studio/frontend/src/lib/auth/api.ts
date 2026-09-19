const BACKEND_URL = process.env.NEXT_PUBLIC_BACKEND_URL ?? 'http://localhost:3000';

/** claude: Claude 계정 토큰(setup-token) / codex: OpenAI Codex CLI 로그인 */
export type AuthProvider = 'claude' | 'codex';

/** Codex 로그인 방식: browser(기본, localhost 콜백) / device(URL + 일회용 코드) */
export type CodexLoginMethod = 'browser' | 'device';

export type LoginState = {
  status: 'idle' | 'running' | 'success' | 'error';
  method?: CodexLoginMethod;
  url?: string;
  /** Codex 기기 인증: 웹사이트에 입력할 일회용 코드 */
  code?: string;
  message?: string;
};

/**
 * 인증 방식. api_key면 대시보드에서 로그아웃할 수 없다 (.env의 키를 지워야 함).
 * available=false면 CLI 바이너리가 없어 로그인 자체가 불가능(Codex).
 */
export type AuthStatus = {
  hasAuth: boolean;
  method: 'api_key' | 'oauth' | 'chatgpt' | null;
  available?: boolean;
  message?: string;
  /** Codex: ~/.codex/config.toml 의 기본 모델 */
  defaultModel?: string;
};

async function call<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${BACKEND_URL}${path}`, {
    headers: init?.body ? { 'Content-Type': 'application/json' } : undefined,
    ...init,
  });
  return res.json() as Promise<T>;
}

function createAuthApi(base: string) {
  return {
    status: () => call<AuthStatus>(`${base}/status`),
    loginStart: (method?: CodexLoginMethod) =>
      call<LoginState>(`${base}/login/start`, { method: 'POST', body: method ? JSON.stringify({ method }) : undefined }),
    loginState: () => call<LoginState>(`${base}/login/state`),
    loginSubmitCode: (code: string) => call<LoginState>(`${base}/login/code`, { method: 'POST', body: JSON.stringify({ code }) }),
    loginCancel: () => call<LoginState>(`${base}/login/cancel`, { method: 'POST' }),
    logout: () => call<AuthStatus>(`${base}/logout`, { method: 'POST' }),
  };
}

export const authApi = createAuthApi('/api/auth');
export const codexAuthApi = createAuthApi('/api/auth/codex');
export const AUTH_API: Record<AuthProvider, ReturnType<typeof createAuthApi>> = { claude: authApi, codex: codexAuthApi };
