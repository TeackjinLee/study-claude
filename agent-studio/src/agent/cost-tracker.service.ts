import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { config } from '../config.js';

export interface ModelTotals {
  costUsd: number;
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
}

export interface RunCost {
  at: number;
  command: string;
  ok: boolean;
  costUsd: number;
  turns: number;
  durationMs: number;
  apiDurationMs: number;
  models: Record<string, ModelTotals>;
}

interface CostStats {
  /** 최근 실행 기록 (최신이 뒤) */
  runs: RunCost[];
  /** 전체 누적 */
  total: { runs: number; costUsd: number; turns: number; durationMs: number };
  /** 모델별 누적 */
  byModel: Record<string, ModelTotals>;
}

const MAX_RUNS = 200;

const emptyTotals = (): ModelTotals => ({ costUsd: 0, inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 });

/**
 * 실행마다 든 비용/토큰을 data/cost.json에 쌓는다 (/cost 명령용).
 * Claude Code의 /cost가 "이 세션" 비용을 보여주듯, 여기서는 마지막 실행 + 오늘 + 전체 누적을 보여준다.
 */
@Injectable()
export class CostTrackerService implements OnModuleInit {
  private readonly logger = new Logger(CostTrackerService.name);
  private stats: CostStats = { runs: [], total: { runs: 0, costUsd: 0, turns: 0, durationMs: 0 }, byModel: {} };

  async onModuleInit() {
    try {
      const raw = JSON.parse(await readFile(config.costFile, 'utf8')) as CostStats;
      if (raw && Array.isArray(raw.runs) && raw.total) this.stats = raw;
    } catch {
      // 파일이 없으면 빈 통계로 시작
    }
  }

  async record(run: RunCost) {
    const s = this.stats;
    s.runs = [...s.runs, run].slice(-MAX_RUNS);
    s.total = {
      runs: s.total.runs + 1,
      costUsd: s.total.costUsd + run.costUsd,
      turns: s.total.turns + run.turns,
      durationMs: s.total.durationMs + run.durationMs,
    };
    for (const [model, m] of Object.entries(run.models)) {
      const acc = s.byModel[model] ?? emptyTotals();
      s.byModel[model] = {
        costUsd: acc.costUsd + m.costUsd,
        inputTokens: acc.inputTokens + m.inputTokens,
        outputTokens: acc.outputTokens + m.outputTokens,
        cacheReadTokens: acc.cacheReadTokens + m.cacheReadTokens,
        cacheWriteTokens: acc.cacheWriteTokens + m.cacheWriteTokens,
      };
    }
    try {
      await mkdir(dirname(config.costFile), { recursive: true });
      await writeFile(config.costFile, `${JSON.stringify(s, null, 2)}\n`, 'utf8');
    } catch (err) {
      this.logger.warn(`비용 기록을 저장하지 못했습니다: ${(err as Error).message}`);
    }
  }

  get(): CostStats {
    return this.stats;
  }

  /** 오늘(로컬 날짜) 실행들의 합 */
  today(): { runs: number; costUsd: number; turns: number; durationMs: number } {
    const start = new Date();
    start.setHours(0, 0, 0, 0);
    const runs = this.stats.runs.filter((r) => r.at >= start.getTime());
    return {
      runs: runs.length,
      costUsd: runs.reduce((a, r) => a + r.costUsd, 0),
      turns: runs.reduce((a, r) => a + r.turns, 0),
      durationMs: runs.reduce((a, r) => a + r.durationMs, 0),
    };
  }
}
