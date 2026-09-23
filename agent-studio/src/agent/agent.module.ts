import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { CodexBridgeService } from './codex-bridge.service.js';
import { AgentGateway } from './agent.gateway.js';
import { AgentRunnerService } from './agent-runner.service.js';
import { AgentRegistryService } from './agent-registry.service.js';
import { AgentsController } from './agents.controller.js';
import { UploadFilesController, UploadsController, WorkspaceFilesController } from './uploads.controller.js';
import { UploadCleanupService } from './upload-cleanup.service.js';
import { SettingsService } from './settings.service.js';
import { SlashCommandsService } from './slash-commands.service.js';
import { CommandsController } from './commands.controller.js';
import { CostTrackerService } from './cost-tracker.service.js';
import { GitService } from './git.service.js';
import { CheckpointService } from './checkpoint.service.js';
import { ConversationStoreService } from './conversation-store.service.js';
import { ConversationsController } from './conversations.controller.js';
import { GitController } from './git.controller.js';

import { FileSuggestionsController } from './file-suggestions.controller.js';
import { FileIndexService } from './file-index.service.js';
@Module({
  // AuthModule: Codex 협업 브리지가 Codex 로그인 상태를 확인한다
  imports: [AuthModule],
  controllers: [AgentsController, UploadsController, UploadFilesController, WorkspaceFilesController, CommandsController, GitController, ConversationsController, FileSuggestionsController],
  providers: [SettingsService, CostTrackerService, SlashCommandsService, AgentRegistryService, AgentRunnerService, AgentGateway, UploadCleanupService, CodexBridgeService, GitService, ConversationStoreService, CheckpointService, FileIndexService],
})
export class AgentModule {}
