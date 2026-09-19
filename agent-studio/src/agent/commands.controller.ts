import { Controller, Get, Query } from '@nestjs/common';
import { SlashCommandsService } from './slash-commands.service.js';
import { SettingsService } from './settings.service.js';
import { CostTrackerService } from './cost-tracker.service.js';
import { CodexAuthService } from '../auth/codex-auth.service.js';

/** 헤더 사용량 칩이 그리는 한도 창 하나 (utilization은 0~100) */
interface UsageWindow {
  label: string;
  utilization: number | null;
  resetsAt: string | null;
}

/**
 * 명령 입력창 자동완성용 + 헤더 표시용.
 *   GET /api/commands          슬래시 명령 목록 (서버 내장 + Claude Code 커스텀 명령/스킬)
 *   GET /api/settings          현재 실행 설정
 *   GET /api/usage?refresh=1   비용 누적(/cost) + Claude 구독 한도(/usage) + Codex 구독 한도. refresh=1이면 캐시를 건너뛴다
 */
@Controller('api')
export class CommandsController {
  constructor(
    private readonly slash: SlashCommandsService,
    private readonly settings: SettingsService,
    private readonly cost: CostTrackerService,
    private readonly codexAuth: CodexAuthService,
  ) {}

  @Get('usage')
  async usage(@Query('refresh') refresh?: string) {
    const st = this.cost.get();
    const last = st.runs[st.runs.length - 1];
    const cost = {
      last: last ? { at: last.at, command: last.command, ok: last.ok, costUsd: last.costUsd, turns: last.turns, durationMs: last.durationMs } : null,
      today: this.cost.today(),
      total: st.total,
      byModel: Object.entries(st.byModel)
        .map(([model, m]) => ({ model, ...m }))
        .sort((a, b) => b.costUsd - a.costUsd),
    };
    const force = refresh === '1';
    // Codex 한도는 로그인 안 돼 있으면 null. Claude 쪽과 병렬로 읽는다
    const codexPromise = this.codexAuth.rateLimits(force);
    // 구독 한도는 Claude Code 세션을 하나 여는 작업이라 실패해도 비용 쪽은 그대로 돌려준다
    try {
      const [u, codex] = await Promise.all([this.slash.planUsage(force), codexPromise]);
      const r = u.rate_limits_available ? u.rate_limits : null;
      const windows: UsageWindow[] = [];
      const push = (label: string, w?: { utilization: number | null; resets_at: string | null } | null) => {
        if (w) windows.push({ label, utilization: w.utilization, resetsAt: w.resets_at });
      };
      push('5시간 한도', r?.five_hour);
      push('주간 한도', r?.seven_day);
      push('주간 Opus', r?.seven_day_opus);
      push('주간 Sonnet', r?.seven_day_sonnet);
      for (const m of r?.model_scoped ?? []) push(m.display_name, m);
      const extra = r?.extra_usage?.is_enabled
        ? { used: r.extra_usage.used_credits ?? 0, limit: r.extra_usage.monthly_limit ?? null, currency: r.extra_usage.currency ?? '', utilization: r.extra_usage.utilization ?? null }
        : null;
      return { cost, plan: { available: !!r, subscription: u.subscription_type ?? null, windows, extra }, codex, fetchedAt: Date.now() };
    } catch (err) {
      return { cost, plan: null, planError: (err as Error).message, codex: await codexPromise, fetchedAt: Date.now() };
    }
  }

  @Get('commands')
  async commands() {
    return { commands: await this.slash.list(), models: await this.slash.models() };
  }

  @Get('settings')
  currentSettings() {
    return { settings: this.settings.get() };
  }
}
