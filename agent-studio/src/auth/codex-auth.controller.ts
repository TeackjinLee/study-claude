import { Body, Controller, Get, Post } from '@nestjs/common';
import { CODEX_LOGIN_METHODS, CodexAuthService, type CodexLoginMethod } from './codex-auth.service.js';

/**
 * OpenAI Codex CLI 로그인 (자격증명은 ~/.codex/auth.json 에 CLI가 관리).
 *   GET  /api/auth/codex/status       로그인 여부/방식
 *   POST /api/auth/codex/login/start  { method?: 'browser' | 'device' } — `codex login` 또는 `codex login --device-auth` 시작 (URL/코드는 state로 받는다)
 *   GET  /api/auth/codex/login/state  진행 상태
 *   POST /api/auth/codex/login/cancel 취소
 *   POST /api/auth/codex/logout       `codex logout`
 */
@Controller('api/auth/codex')
export class CodexAuthController {
  constructor(private readonly codex: CodexAuthService) {}

  @Get('status')
  status() {
    return this.codex.status();
  }

  @Post('login/start')
  start(@Body() body?: { method?: string }) {
    const method = CODEX_LOGIN_METHODS.find((m) => m === body?.method) ?? 'browser';
    return this.codex.startLogin(method as CodexLoginMethod);
  }

  @Get('login/state')
  state() {
    return this.codex.getLoginState();
  }

  @Post('login/cancel')
  cancel() {
    return this.codex.cancelLogin();
  }

  @Post('logout')
  async logout() {
    await this.codex.logout();
    return this.codex.status(true);
  }
}
