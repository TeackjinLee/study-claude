import { Module } from '@nestjs/common';
import { AuthController } from './auth.controller.js';
import { ClaudeLoginService } from './claude-login.service.js';
import { CodexAuthController } from './codex-auth.controller.js';
import { CodexAuthService } from './codex-auth.service.js';

@Module({
  controllers: [AuthController, CodexAuthController],
  providers: [ClaudeLoginService, CodexAuthService],
  // AgentModule(Codex 협업 브리지)이 로그인 상태를 확인할 수 있게 내보낸다
  exports: [CodexAuthService],
})
export class AuthModule {}
