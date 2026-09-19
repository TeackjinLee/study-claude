import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, isAbsolute, resolve } from 'node:path';
import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import type { PermissionMode } from '@anthropic-ai/claude-agent-sdk';
import { config } from '../config.js';

export const EFFORT_LEVELS = ['low', 'medium', 'high', 'xhigh', 'max'] as const;
export type EffortLevel = (typeof EFFORT_LEVELS)[number];
export const PERMISSION_MODES = ['acceptEdits', 'default'] as const;

/** 대시보드의 /model 같은 명령으로 바꾸는 실행 설정. 서버를 재시작해도 유지되도록 data/settings.json에 저장 */
export interface RunSettings {
  /** undefined면 Claude Code 기본 모델 */
  model?: string;
  /** Codex 협업자가 쓸 모델. undefined면 Codex CLI 기본값(~/.codex/config.toml) */
  codexModel?: string;
  /** 에이전트가 파일을 읽고 쓰는 작업 폴더 (절대 경로). 기본값은 .env의 WORKSPACE_DIR */
  workspaceDir: string;
  permissionMode: PermissionMode;
  effort?: EffortLevel;
  maxTurns: number;
  maxBudgetUsd: number;
}

type Listener = (settings: RunSettings) => void;

@Injectable()
export class SettingsService implements OnModuleInit {
  private readonly logger = new Logger(SettingsService.name);
  private readonly listeners = new Set<Listener>();
  private settings: RunSettings = this.defaults();

  /** .env(config)에서 오는 기본값 */
  private defaults(): RunSettings {
    return {
      model: config.model,
      codexModel: undefined,
      workspaceDir: config.workspaceDir,
      permissionMode: config.permissionMode,
      effort: undefined,
      maxTurns: config.maxTurns,
      maxBudgetUsd: config.maxBudgetUsd,
    };
  }

  async onModuleInit() {
    try {
      const raw = JSON.parse(await readFile(config.settingsFile, 'utf8')) as Partial<RunSettings>;
      this.settings = this.sanitize({ ...this.defaults(), ...raw });
      this.logger.log(`실행 설정 로드: 모델=${this.settings.model ?? '기본'}, 권한=${this.settings.permissionMode}, 작업 폴더=${this.settings.workspaceDir}`);
    } catch {
      this.settings = this.defaults();
    }
  }

  get(): RunSettings {
    return { ...this.settings };
  }

  /** 현재 작업 폴더 (절대 경로). 여러 곳에서 자주 쓰여서 따로 뺐다 */
  get workspaceDir(): string {
    return this.settings.workspaceDir;
  }

  subscribe(listener: Listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  async update(patch: Partial<RunSettings>): Promise<RunSettings> {
    this.settings = this.sanitize({ ...this.settings, ...patch });
    await this.persist();
    return this.get();
  }

  async reset(): Promise<RunSettings> {
    this.settings = this.defaults();
    await this.persist();
    return this.get();
  }

  private sanitize(s: RunSettings): RunSettings {
    const model = typeof s.model === 'string' && s.model.trim() ? s.model.trim() : undefined;
    const codexModel = typeof s.codexModel === 'string' && s.codexModel.trim() ? s.codexModel.trim() : undefined;
    // 상대 경로가 저장돼 있어도 서버 실행 위치 기준으로 절대 경로로 맞춘다
    const workspaceDir =
      typeof s.workspaceDir === 'string' && s.workspaceDir.trim()
        ? isAbsolute(s.workspaceDir.trim())
          ? s.workspaceDir.trim()
          : resolve(s.workspaceDir.trim())
        : config.workspaceDir;
    const permissionMode = PERMISSION_MODES.includes(s.permissionMode as (typeof PERMISSION_MODES)[number]) ? s.permissionMode : 'acceptEdits';
    const effort = EFFORT_LEVELS.includes(s.effort as EffortLevel) ? s.effort : undefined;
    const maxTurns = Number.isInteger(s.maxTurns) && s.maxTurns > 0 ? s.maxTurns : config.maxTurns;
    const maxBudgetUsd = Number.isFinite(s.maxBudgetUsd) && s.maxBudgetUsd > 0 ? s.maxBudgetUsd : config.maxBudgetUsd;
    return { model, codexModel, workspaceDir, permissionMode, effort, maxTurns, maxBudgetUsd };
  }

  private async persist() {
    await mkdir(dirname(config.settingsFile), { recursive: true });
    await writeFile(config.settingsFile, `${JSON.stringify(this.settings, null, 2)}\n`, 'utf8');
    for (const listener of this.listeners) listener(this.get());
  }
}
