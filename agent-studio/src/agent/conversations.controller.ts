import { Controller, Delete, Get, Param, Post } from '@nestjs/common';
import { ConversationStoreService } from './conversation-store.service.js';
import { AgentRunnerService } from './agent-runner.service.js';
import { SettingsService } from './settings.service.js';

/**
 * 지난 대화 (코드·채팅).
 *   GET    /api/conversations           지금 작업 폴더의 대화 목록 (최근 순)
 *   POST   /api/conversations/:id/open  그 대화를 이어가는 대화로 열기 (화면은 소켓으로 다시 그려진다)
 *   DELETE /api/conversations/:id       지우기
 */
@Controller('api/conversations')
export class ConversationsController {
  constructor(
    private readonly store: ConversationStoreService,
    private readonly runner: AgentRunnerService,
    private readonly settings: SettingsService,
  ) {}

  @Get()
  list() {
    const workspace = this.settings.workspaceDir;
    return { workspace, conversations: this.store.list(workspace), active: this.runner.activeConversations() };
  }

  @Post(':id/open')
  open(@Param('id') id: string) {
    return this.runner.openConversation(id);
  }

  @Delete(':id')
  remove(@Param('id') id: string) {
    return this.runner.deleteConversation(id);
  }
}
