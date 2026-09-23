import { Body, Controller, Get, Post } from '@nestjs/common';
import { GitService } from './git.service.js';
import { AgentRunnerService } from './agent-runner.service.js';

/**
 * 결과 미리보기의 "변경사항" 탭.
 *   GET  /api/git/changes          작업 폴더의 변경 파일 + diff
 *   POST /api/git/revert           { path }                  파일 하나 되돌리기
 *   POST /api/git/commit           { message, branch?, paths? }  커밋 (branch를 주면 새 브랜치에)
 *   POST /api/git/commit-message                             Claude가 커밋 메시지 제안
 * 에이전트가 파일을 고치는 중에는 되돌리기/커밋을 막는다.
 */
@Controller('api/git')
export class GitController {
  constructor(
    private readonly git: GitService,
    private readonly runner: AgentRunnerService,
  ) {}

  private busy() {
    return this.runner.running ? { ok: false, error: '에이전트가 작업 중입니다. 끝난 뒤 다시 시도하세요.' } : null;
  }

  @Get('changes')
  changes() {
    return this.git.changes();
  }

  @Post('revert')
  revert(@Body() body: { path?: unknown } | undefined) {
    return this.busy() ?? this.git.revert(body?.path);
  }

  @Post('commit')
  commit(@Body() body: { message?: unknown; branch?: unknown; paths?: unknown } | undefined) {
    return this.busy() ?? this.git.commit(body ?? {});
  }

  @Post('commit-message')
  commitMessage() {
    return this.git.suggestCommitMessage();
  }
}
