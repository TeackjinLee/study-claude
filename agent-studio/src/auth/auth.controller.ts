import { Body, Controller, Get, Post } from '@nestjs/common';
import { config } from '../config.js';
import { ClaudeLoginService } from './claude-login.service.js';

/**
 * .env를 직접 편집하지 않고 브라우저 로그인으로 CLAUDE_CODE_OAUTH_TOKEN을 받는 API.
 *   GET  /api/auth/status       인증(ANTHROPIC_API_KEY 또는 토큰) 여부
 *   POST /api/auth/login/start  로그인 절차 시작 (URL이 나올 때까지 상태를 폴링해서 받는다)
 *   GET  /api/auth/login/state  현재 진행 상태
 *   POST /api/auth/login/code   브라우저에 표시된 코드 제출
 *   POST /api/auth/login/cancel 진행 중인 로그인 취소
 *   POST /api/auth/logout       로그인으로 받은 토큰을 프로세스와 .env에서 제거
 */
@Controller('api/auth')
export class AuthController {
  constructor(private readonly login: ClaudeLoginService) {}

  @Get('status')
  status() {
    return { hasAuth: config.hasAuth(), method: config.authMethod() };
  }

  @Post('login/start')
  start() {
    return this.login.start();
  }

  @Get('login/state')
  state() {
    return this.login.getState();
  }

  @Post('login/code')
  submitCode(@Body() body: { code?: unknown }) {
    return this.login.submitCode(typeof body?.code === 'string' ? body.code : '');
  }

  @Post('login/cancel')
  cancel() {
    return this.login.cancel();
  }

  @Post('logout')
  async logout() {
    await this.login.logout();
    return this.status();
  }
}
