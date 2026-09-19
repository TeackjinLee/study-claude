import { execFile, spawn, type ChildProcess } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { resolveCodexCommand } from './codex-cli.js';

export type CodexAuthMethod = 'api_key' | 'chatgpt' | null;

export interface CodexAuthStatus {
  hasAuth: boolean;
  method: CodexAuthMethod;
  /** codex 바이너리를 실행할 수 있는지. false면 npm install 이 필요하다 */
  available: boolean;
  message?: string;
  /** ~/.codex/config.toml 의 model (대시보드에서 따로 정하지 않았을 때 쓰는 모델). 없으면 CLI 기본값 */
  defaultModel?: string;
}

/**
 * browser: `codex login` — 브라우저에서 로그인하면 localhost:1455 콜백으로 CLI가 스스로 끝난다 (같은 컴퓨터에서 대시보드를 쓰므로 기본값).
 * device: `codex login --device-auth` — URL + 일회용 코드. 워크스페이스에서 기기 코드 로그인을 막아둔 경우 "잘못된 요청"이 뜰 수 있다.
 */
export type CodexLoginMethod = 'browser' | 'device';
export const CODEX_LOGIN_METHODS: readonly CodexLoginMethod[] = ['browser', 'device'];

/** Codex(ChatGPT) 구독 한도 창 하나. utilization은 0~100 */
export interface CodexRateWindow {
  label: string;
  utilization: number;
  resetsAt: string | null;
}

export interface CodexRateLimits {
  plan: string | null;
  windows: CodexRateWindow[];
  /** 남은 초기화 크레딧 수 (백엔드가 알려줄 때만) */
  resetCredits: number | null;
  /** 한도에 걸려 일반 사용이 막힌 상태 */
  blocked: boolean;
}

export interface CodexLoginState {
  status: 'idle' | 'running' | 'success' | 'error';
  method?: CodexLoginMethod;
  /** 브라우저에서 열 주소 (browser: OAuth 인가 URL / device: https://auth.openai.com/codex/device) */
  url?: string;
  /** device 방식에서 그 페이지에 입력할 일회용 코드 */
  code?: string;
  message?: string;
}

// eslint-disable-next-line no-control-regex
const ANSI_RE = /\x1b(?:[@-Z\\-_]|\[[0-9?;]*[a-zA-Z]|\][^\x07\x1b]*(?:\x07|\x1b\\))/g;
const URL_RE = /https:\/\/[^\s"'<>]+/g;
const DEVICE_URL_RE = /\/codex\/device/i;
const OAUTH_URL_RE = /\/oauth\/authorize/i;
// codex login --device-auth 가 출력하는 일회용 코드 (예: KOPA-A7NN9)
const CODE_RE = /\b[A-Z0-9]{4,6}-[A-Z0-9]{4,6}\b/;
const STATUS_CACHE_MS = 30_000;
const RATE_LIMIT_CACHE_MS = 60_000;
const RATE_LIMIT_TIMEOUT_MS = 15_000;

/** app-server의 RateLimitWindow → 화면용 (windowDurationMins로 5시간/주간을 구분) */
function toWindow(w: { usedPercent: number; resetsAt: number | null; windowDurationMins: number | null } | null | undefined): CodexRateWindow | null {
  if (!w) return null;
  const mins = w.windowDurationMins ?? 0;
  const label = mins === 300 ? '5시간 한도' : mins === 10080 ? '주간 한도' : mins >= 1440 ? `${Math.round(mins / 1440)}일 한도` : mins > 0 ? `${Math.round(mins / 60)}시간 한도` : '한도';
  return { label, utilization: w.usedPercent, resetsAt: w.resetsAt ? new Date(w.resetsAt * 1000).toISOString() : null };
}

const stripAnsi = (s: string) => s.replace(ANSI_RE, '');

/**
 * Codex CLI 로그인 상태 조회와 대시보드용 로그인/로그아웃.
 * 자격증명은 CLI가 ~/.codex/auth.json 에 직접 관리하므로 .env를 건드리지 않는다.
 * 로그인은 두 가지: `codex login`(브라우저 → localhost:1455 콜백) 또는 `codex login --device-auth`(URL + 코드). 둘 다 완료되면 CLI가 스스로 끝난다.
 */
@Injectable()
export class CodexAuthService implements OnModuleDestroy {
  private readonly logger = new Logger(CodexAuthService.name);
  private cache: { at: number; value: CodexAuthStatus } | null = null;
  private pendingStatus: Promise<CodexAuthStatus> | null = null;
  private child: ChildProcess | null = null;
  private buffer = '';
  private loginState: CodexLoginState = { status: 'idle' };
  private rateCache: { at: number; value: CodexRateLimits | null } | null = null;
  private pendingRate: Promise<CodexRateLimits | null> | null = null;

  /** 상태 확인은 프로세스를 하나 띄우므로 잠깐 캐시한다. 로그인/로그아웃 뒤엔 invalidate() */
  status(force = false): Promise<CodexAuthStatus> {
    if (process.env.CODEX_API_KEY) return this.withDefaultModel({ hasAuth: true, method: 'api_key', available: true });
    if (!force && this.cache && Date.now() - this.cache.at < STATUS_CACHE_MS) return Promise.resolve(this.cache.value);
    if (!this.pendingStatus) {
      this.pendingStatus = this.probe()
        .then((value) => this.withDefaultModel(value))
        .then((value) => {
        this.cache = { at: Date.now(), value };
        this.pendingStatus = null;
        return value;
      });
    }
    return this.pendingStatus;
  }

  invalidate() {
    this.cache = null;
    this.rateCache = null;
  }

  /**
   * ChatGPT 구독의 Codex 한도(5시간/주간). `codex app-server`를 잠깐 띄워 JSON-RPC `account/rateLimits/read`로 읽는다.
   * 로그인돼 있지 않거나(API 키 포함) 읽지 못하면 null. 헤더가 주기적으로 읽으므로 캐시한다.
   */
  rateLimits(force = false): Promise<CodexRateLimits | null> {
    if (!force && this.rateCache && Date.now() - this.rateCache.at < RATE_LIMIT_CACHE_MS) return Promise.resolve(this.rateCache.value);
    if (!this.pendingRate) {
      this.pendingRate = this.status(force)
        .then((s) => (s.hasAuth && s.method === 'chatgpt' ? this.readRateLimits() : null))
        .catch((err) => {
          this.logger.warn(`Codex 한도 조회 실패: ${(err as Error).message}`);
          return null;
        })
        .then((value) => {
          this.rateCache = { at: Date.now(), value };
          this.pendingRate = null;
          return value;
        });
    }
    return this.pendingRate;
  }

  getLoginState(): CodexLoginState {
    return { ...this.loginState };
  }

  startLogin(method: CodexLoginMethod = 'browser'): CodexLoginState {
    if (this.child) {
      if (this.loginState.method === method) return this.getLoginState();
      // 다른 방식으로 바꾸면 진행 중인 로그인은 버린다 (기존 코드는 무효가 된다)
      this.cancelLogin();
    }

    const { file, args } = resolveCodexCommand();
    this.buffer = '';
    this.loginState = { status: 'running', method };

    let child: ChildProcess;
    try {
      // browser 방식은 CLI가 기본 브라우저를 직접 열기도 한다. 대시보드에도 같은 URL을 띄워 두 번 열리는 것을 막기 위해 BROWSER를 비운다
      const env = method === 'browser' ? { ...process.env, BROWSER: 'true' } : process.env;
      const loginArgs = method === 'device' ? ['login', '--device-auth'] : ['login'];
      child = spawn(file, [...args, ...loginArgs], { env, stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (err) {
      this.loginState = { status: 'error', message: `codex CLI를 실행할 수 없습니다: ${(err as Error).message}` };
      return this.getLoginState();
    }
    this.child = child;

    const onData = (chunk: Buffer) => {
      this.buffer += chunk.toString('utf8');
      this.parseLoginOutput();
    };
    child.stdout?.on('data', onData);
    child.stderr?.on('data', onData);
    child.on('error', (err) => {
      if (this.child !== child) return;
      this.child = null;
      this.loginState = { status: 'error', method, message: `codex CLI를 실행할 수 없습니다: ${err.message}` };
    });
    child.on('exit', (code) => {
      // 취소했거나 다른 방식으로 새로 시작한 뒤 늦게 도착한 종료는 무시한다
      if (this.child !== child) return;
      this.child = null;
      if (this.loginState.status !== 'running') return;
      this.invalidate();
      if (code === 0) {
        // 코드 입력이 끝나면 CLI가 0으로 끝난다. 실제로 로그인됐는지 한 번 더 확인
        void this.status(true).then((s) => {
          this.loginState = s.hasAuth ? { status: 'success', method } : { status: 'error', method, message: '로그인이 확인되지 않았습니다. 다시 시도하세요.' };
          if (s.hasAuth) this.logger.log('Codex 로그인 완료');
        });
      } else {
        const tail = stripAnsi(this.buffer).trim().split('\n').slice(-3).join(' ');
        this.loginState = { status: 'error', method, message: `로그인이 완료되지 않고 종료됐습니다 (code ${code}). ${tail}`.trim() };
      }
    });

    return this.getLoginState();
  }

  cancelLogin(): CodexLoginState {
    this.child?.kill();
    this.child = null;
    this.loginState = { status: 'idle' };
    return this.getLoginState();
  }

  async logout(): Promise<void> {
    if (this.child) this.cancelLogin();
    const { file, args } = resolveCodexCommand();
    await new Promise<void>((resolve) => {
      execFile(file, [...args, 'logout'], { env: process.env, timeout: 10_000 }, (err, stdout, stderr) => {
        if (err) this.logger.warn(`codex logout 실패: ${stripAnsi(String(stderr || stdout || err.message)).trim()}`);
        else this.logger.log('Codex 로그아웃');
        resolve();
      });
    });
    this.invalidate();
  }

  onModuleDestroy() {
    this.child?.kill();
  }

  /** config.toml 최상위의 model 값을 붙인다 (섹션 아래 model은 무시) */
  private async withDefaultModel(s: CodexAuthStatus): Promise<CodexAuthStatus> {
    try {
      const toml = await readFile(join(process.env.CODEX_HOME ?? join(homedir(), '.codex'), 'config.toml'), 'utf8');
      const top = toml.split(/^\s*\[/m)[0];
      const m = /^\s*model\s*=\s*"([^"]+)"/m.exec(top);
      return m ? { ...s, defaultModel: m[1] } : s;
    } catch {
      return s;
    }
  }

  private readRateLimits(): Promise<CodexRateLimits | null> {
    const { file, args } = resolveCodexCommand();
    return new Promise((resolve, reject) => {
      const child = spawn(file, [...args, 'app-server'], { env: process.env, stdio: ['pipe', 'pipe', 'ignore'] });
      let buffer = '';
      let settled = false;
      const finish = (fn: () => void) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        child.kill();
        fn();
      };
      const timer = setTimeout(() => finish(() => reject(new Error('시간 초과'))), RATE_LIMIT_TIMEOUT_MS);
      child.on('error', (err) => finish(() => reject(err)));
      child.on('exit', () => finish(() => reject(new Error('app-server가 응답 없이 종료됐습니다'))));
      child.stdout?.on('data', (chunk: Buffer) => {
        buffer += chunk.toString('utf8');
        const lines = buffer.split('\n');
        buffer = lines.pop() ?? '';
        for (const line of lines) {
          let msg: { id?: number; result?: Record<string, unknown>; error?: { message?: string } };
          try {
            msg = JSON.parse(line);
          } catch {
            continue;
          }
          if (msg.id !== 2) continue;
          if (msg.error || !msg.result) {
            finish(() => reject(new Error(msg.error?.message ?? '알 수 없는 응답')));
            return;
          }
          const r = msg.result as {
            ordinaryUsageAllowed?: boolean | null;
            rateLimits?: {
              planType?: string | null;
              primary?: { usedPercent: number; resetsAt: number | null; windowDurationMins: number | null } | null;
              secondary?: { usedPercent: number; resetsAt: number | null; windowDurationMins: number | null } | null;
              rateLimitReachedType?: string | null;
            } | null;
            rateLimitResetCredits?: { availableCount: number } | null;
          };
          const rl = r.rateLimits;
          const windows = [toWindow(rl?.primary), toWindow(rl?.secondary)].filter((w): w is CodexRateWindow => w !== null);
          finish(() =>
            resolve({
              plan: rl?.planType ?? null,
              windows,
              resetCredits: r.rateLimitResetCredits?.availableCount ?? null,
              blocked: r.ordinaryUsageAllowed === false || !!rl?.rateLimitReachedType,
            }),
          );
          return;
        }
      });
      const send = (o: object) => child.stdin?.write(`${JSON.stringify(o)}\n`);
      send({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { clientInfo: { name: 'agent-studio', title: 'Agent Studio', version: '1.0.0' } } });
      send({ jsonrpc: '2.0', method: 'initialized' });
      send({ jsonrpc: '2.0', id: 2, method: 'account/rateLimits/read', params: { excludeResetCreditDetails: true } });
    });
  }

  private parseLoginOutput() {
    if (this.loginState.status !== 'running') return;
    const text = stripAnsi(this.buffer);
    const next = { ...this.loginState };
    if (!next.url) {
      const urls = text.match(URL_RE) ?? [];
      // 안내 문장 속 다른 링크가 섞여도 방식에 맞는 페이지를 우선 고른다
      const want = next.method === 'device' ? DEVICE_URL_RE : OAUTH_URL_RE;
      next.url = urls.find((u) => want.test(u)) ?? urls[0];
    }
    if (next.method === 'device' && !next.code) {
      const m = CODE_RE.exec(text);
      if (m) next.code = m[0];
    }
    this.loginState = next;
  }

  /** `codex login status`: 종료 코드 0이면 로그인됨. 출력 문구로 방식을 구분한다 */
  private probe(): Promise<CodexAuthStatus> {
    const { file, args } = resolveCodexCommand();
    return new Promise((resolve) => {
      execFile(file, [...args, 'login', 'status'], { env: process.env, timeout: 8_000 }, (err, stdout, stderr) => {
        const out = stripAnsi(`${stdout}\n${stderr}`).trim();
        if (err && (err as NodeJS.ErrnoException).code === 'ENOENT') {
          resolve({ hasAuth: false, method: null, available: false, message: 'codex CLI를 찾을 수 없습니다. npm install 을 다시 실행하세요.' });
          return;
        }
        if (err) {
          resolve({ hasAuth: false, method: null, available: true, message: out || undefined });
          return;
        }
        resolve({ hasAuth: true, method: /api key/i.test(out) ? 'api_key' : 'chatgpt', available: true });
      });
    });
  }
}
