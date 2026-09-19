import { existsSync, readdirSync, chmodSync } from 'node:fs';
import { join } from 'node:path';
import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import * as pty from 'node-pty';
import { resolveClaudeBinary } from './claude-cli.js';
import { persistOAuthToken, removeOAuthToken } from './env-file.js';

export type LoginStatus = 'idle' | 'running' | 'success' | 'error';

export interface LoginState {
  status: LoginStatus;
  /** 브라우저로 열어야 하는 로그인 URL (받으면 채워짐) */
  url?: string;
  message?: string;
}

// CSI(색상 등)와 OSC(하이퍼링크 등) 이스케이프 시퀀스를 걷어낸다
const ANSI_RE = /\x1b(?:[@-Z\\-_]|\[[0-9?;]*[a-zA-Z]|\][^\x07\x1b]*(?:\x07|\x1b\\))/g;
const URL_RE = /https:\/\/claude\.com\/cai\/oauth\/authorize\?[^\s\x00-\x20\x7f]+/;
// pty를 아주 넓게(cols: 300) 띄워서 토큰 줄이 줄바꿈되지 않게 한다. 공백을 허용하면
// 뒤따라오는 안내 문장("Store this token securely." 등)까지 같이 먹어버릴 수 있어 공백은 허용하지 않는다.
const TOKEN_RE = /sk-ant-oat01-[A-Za-z0-9_-]{20,160}/;

function stripAnsi(s: string): string {
  return s.replace(ANSI_RE, '');
}

/** node-pty가 배포하는 spawn-helper가 실행 권한 없이 풀린 경우를 대비한 방어적 보정 */
function ensurePtyHelperExecutable() {
  try {
    const dir = join(process.cwd(), 'node_modules/node-pty/prebuilds');
    for (const platform of readdirSync(dir)) {
      const helper = join(dir, platform, 'spawn-helper');
      if (existsSync(helper)) chmodSync(helper, 0o755);
    }
  } catch {
    // 무시: 없어도 되는 보정이다
  }
}

/**
 * 대시보드의 "Claude 로그인" 버튼이 쓰는 서비스.
 * 번들된 claude CLI의 `setup-token`을 pty로 띄워 로그인 URL을 뽑아 화면에 주고,
 * 완료되면 출력에서 1년짜리 OAuth 토큰을 읽어 .env와 현재 프로세스에 반영한다.
 */
@Injectable()
export class ClaudeLoginService implements OnModuleDestroy {
  private readonly logger = new Logger(ClaudeLoginService.name);
  private term: pty.IPty | null = null;
  private buffer = '';
  private state: LoginState = { status: 'idle' };

  getState(): LoginState {
    return { ...this.state };
  }

  start(): LoginState {
    if (this.term) return this.getState();

    ensurePtyHelperExecutable();
    this.buffer = '';
    this.state = { status: 'running' };

    const bin = resolveClaudeBinary();
    let term: pty.IPty;
    try {
      term = pty.spawn(bin, ['setup-token'], {
        name: 'xterm-256color',
        // 넉넉한 폭으로 띄워서 토큰이 줄바꿈으로 잘리지 않게 한다
        cols: 300,
        rows: 40,
        cwd: process.cwd(),
        env: process.env as Record<string, string>,
      });
    } catch (err) {
      this.state = {
        status: 'error',
        message: `claude CLI를 실행할 수 없습니다: ${err instanceof Error ? err.message : String(err)}`,
      };
      return this.getState();
    }

    this.term = term;
    term.onData((chunk) => {
      this.buffer += chunk;
      this.handleChunk();
    });
    term.onExit(({ exitCode }) => {
      this.term = null;
      if (this.state.status === 'running') {
        this.state = {
          status: 'error',
          message: `로그인이 완료되지 않고 종료됐습니다 (code ${exitCode}).`,
        };
      }
    });

    return this.getState();
  }

  /** 브라우저에 표시된 코드를 붙여넣기(엔터 포함)로 CLI에 전달한다 */
  submitCode(code: string): LoginState {
    const trimmed = code.trim();
    if (this.term && trimmed) this.term.write(`${trimmed}\r`);
    return this.getState();
  }

  cancel(): LoginState {
    this.term?.kill();
    this.term = null;
    this.state = { status: 'idle' };
    return this.getState();
  }

  /**
   * 로그아웃: 로그인으로 받은 OAuth 토큰을 현재 프로세스와 .env에서 지운다.
   * 이후 실행되는 에이전트는 process.env를 그대로 물려받으므로 재시작 없이 바로 인증 해제된다.
   * ANTHROPIC_API_KEY는 운영자가 직접 넣은 설정이라 여기서 건드리지 않는다.
   */
  async logout(): Promise<void> {
    if (this.term) this.cancel();
    delete process.env.CLAUDE_CODE_OAUTH_TOKEN;
    try {
      await removeOAuthToken();
      this.logger.log('로그아웃: .env에서 CLAUDE_CODE_OAUTH_TOKEN을 제거했습니다.');
    } catch (err) {
      this.logger.error(`.env 수정 실패 (이번 세션에서는 로그아웃 상태입니다): ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  onModuleDestroy() {
    this.term?.kill();
  }

  private handleChunk() {
    if (this.state.status !== 'running') return;

    if (!this.state.url) {
      const match = URL_RE.exec(this.buffer);
      if (match) this.state = { ...this.state, url: match[0] };
    }

    const tokenMatch = TOKEN_RE.exec(stripAnsi(this.buffer));
    if (tokenMatch) void this.finishWithToken(tokenMatch[0]);
  }

  private async finishWithToken(token: string) {
    this.state = { status: 'success' };
    process.env.CLAUDE_CODE_OAUTH_TOKEN = token;
    this.term?.kill();
    this.term = null;
    try {
      await persistOAuthToken(token);
      this.logger.log('로그인 완료: .env에 CLAUDE_CODE_OAUTH_TOKEN을 저장했습니다.');
    } catch (err) {
      this.logger.error(`.env 저장 실패 (이번 세션에서는 계속 쓸 수 있습니다): ${err instanceof Error ? err.message : String(err)}`);
    }
  }
}
