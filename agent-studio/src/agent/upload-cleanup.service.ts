import { readdir, rm, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { config } from '../config.js';
import { AgentRunnerService } from './agent-runner.service.js';
import { SettingsService } from './settings.service.js';
import { UPLOAD_DIR } from './attachments.js';

/**
 * 오래된 업로드 폴더(workspace/uploads/<시각-난수>/)를 주기적으로 지운다.
 * 보관 기간은 UPLOAD_RETENTION_DAYS(기본 7일), 검사 주기는 1시간. 서버 시작 직후에도 한 번 돈다.
 * 지금 실행 중인 명령이 쓰는 첨부 폴더는 기간이 지났어도 건드리지 않는다.
 */
@Injectable()
export class UploadCleanupService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(UploadCleanupService.name);
  private timer: ReturnType<typeof setInterval> | null = null;
  private busy = false;

  constructor(
    private readonly runner: AgentRunnerService,
    private readonly settings: SettingsService,
  ) {}

  onModuleInit() {
    if (config.uploadRetentionDays <= 0) {
      this.logger.log('업로드 자동 정리 꺼짐 (UPLOAD_RETENTION_DAYS=0)');
      return;
    }
    this.logger.log(`업로드 자동 정리: ${config.uploadRetentionDays}일 지난 파일을 1시간마다 확인`);
    void this.cleanup();
    this.timer = setInterval(() => void this.cleanup(), config.uploadCleanupIntervalMs);
    this.timer.unref();
  }

  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }

  /** 기간이 지난 폴더를 지우고 지운 개수를 돌려준다 (API에서도 부를 수 있게 공개) */
  async cleanup(maxAgeMs = config.uploadRetentionDays * 24 * 60 * 60 * 1000): Promise<{ removed: number; freedBytes: number }> {
    if (this.busy) return { removed: 0, freedBytes: 0 };
    this.busy = true;
    const root = join(this.settings.workspaceDir, UPLOAD_DIR);
    const cutoff = Date.now() - maxAgeMs;
    const inUse = new Set(this.runner.currentAttachmentFolders());
    let removed = 0;
    let freedBytes = 0;

    try {
      const entries = await readdir(root, { withFileTypes: true }).catch(() => []);
      for (const entry of entries) {
        if (!entry.isDirectory()) continue;
        if (inUse.has(entry.name)) continue;
        const dir = join(root, entry.name);
        try {
          const newest = await this.newestMtime(dir);
          if (newest > cutoff) continue;
          freedBytes += await this.dirSize(dir);
          await rm(dir, { recursive: true, force: true });
          removed += 1;
        } catch (err) {
          this.logger.warn(`업로드 폴더를 지우지 못했습니다: ${entry.name} (${(err as Error).message})`);
        }
      }
      if (removed > 0) this.logger.log(`오래된 업로드 ${removed}개 폴더 정리 (${(freedBytes / 1024 / 1024).toFixed(1)}MB)`);
    } finally {
      this.busy = false;
    }
    return { removed, freedBytes };
  }

  /** 폴더와 그 안 파일 중 가장 최근 수정 시각. 폴더 이름(시각)보다 실제 파일 시각을 믿는다 */
  private async newestMtime(dir: string): Promise<number> {
    const st = await stat(dir);
    let newest = st.mtimeMs;
    for (const name of await readdir(dir)) {
      const s = await stat(join(dir, name)).catch(() => null);
      if (s && s.mtimeMs > newest) newest = s.mtimeMs;
    }
    return newest;
  }

  private async dirSize(dir: string): Promise<number> {
    let total = 0;
    for (const name of await readdir(dir)) {
      const s = await stat(join(dir, name)).catch(() => null);
      if (s?.isFile()) total += s.size;
    }
    return total;
  }
}
