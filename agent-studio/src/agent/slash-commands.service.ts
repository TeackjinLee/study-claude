import { homedir } from 'node:os';
import { mkdir, stat } from 'node:fs/promises';
import { isAbsolute, join, resolve } from 'node:path';
import { Injectable, Logger } from '@nestjs/common';
import {
  query,
  type ModelInfo,
  type Query,
  type SDKControlGetContextUsageResponse,
  type SDKControlGetUsageResponse,
  type SlashCommand,
} from '@anthropic-ai/claude-agent-sdk';
import { buildOrchestratorPrompt } from './agents.config.js';
import { config } from '../config.js';
import { AgentRegistryService } from './agent-registry.service.js';
import { EFFORT_LEVELS, PERMISSION_MODES, SettingsService, type EffortLevel, type RunSettings } from './settings.service.js';
import { CostTrackerService, type ModelTotals } from './cost-tracker.service.js';
import { CodexBridgeService } from './codex-bridge.service.js';
import { CodexAuthService } from '../auth/codex-auth.service.js';
import type { CodexMode, UiEventBody } from './ui-events.js';

/** 대시보드 자동완성에 내려주는 명령 정보 */
export interface CommandInfo {
  name: string;
  description: string;
  argumentHint: string;
  /** builtin: 서버가 직접 처리 / sdk: Claude Code(작업 폴더의 .claude/commands, 스킬 등)로 넘김 */
  source: 'builtin' | 'sdk';
}

/** 대시보드가 선택지 UI로 보여줄 항목. 고르면 `${command} ${value}`를 다시 보낸다 */
export interface CommandChoice {
  value: string;
  label: string;
  description?: string;
  current?: boolean;
}

export interface CommandChoices {
  /** 선택 후 다시 보낼 명령 (예: /model) */
  command: string;
  title: string;
  options: CommandChoice[];
}

export interface SlashResult {
  ok: boolean;
  /** 대시보드 로그에 보여줄 응답 */
  text: string;
  /** 인자 없이 불렀을 때 고를 수 있는 선택지 (대시보드가 목록 UI로 띄운다) */
  choices?: CommandChoices;
  /** 설정이 바뀌었으면 새 설정 */
  settings?: RunSettings;
  /** 화면 기록을 비우라는 신호 (/clear) */
  clear?: boolean;
}

export interface SlashContext {
  running: boolean;
  clearHistory: () => void;
  /** /codex 처럼 처리 중에 대시보드 이벤트를 흘려보내야 하는 명령용 */
  emit: (event: UiEventBody) => void;
}

const CODEX_MODES: CodexMode[] = ['discuss', 'review', 'implement', 'image'];

/**
 * Claude Code가 알려주는 명령 중 대화형 터미널에서만 의미 있는 것들(설정 화면, 사용량, 컴팩션 등).
 * 한 번 실행(-p) 방식인 여기서는 동작하지 않으므로 목록에서 뺀다.
 */
const INTERACTIVE_ONLY = new Set([
  'compact', 'autocompact', 'config', 'mcp', 'doctor', 'heapdump', 'context', 'fast', 'color', 'output-style', 'usage', 'usage-credits',
  'extra-usage', 'insights', 'recap', 'rename', 'reload-plugins', 'reload-skills', 'import', 'init', 'auto-mode-setup', 'team-onboarding',
  'design-consent', 'design-revoke', 'list-agents', 'workflow-launch-exec', 'run-skill-generator', 'update-config', 'fewer-permission-prompts',
  'skill-doctor', 'ultrareview', 'loop', 'schedule', 'batch', 'advisor', 'goal', 'run', 'workflow-authoring', 'design-sync', 'clear', 'help',
  'model', 'status', 'agents', 'permissions', 'effort', 'login', 'logout', 'exit', 'quit', 'resume', 'cost', 'memory', 'vim', 'terminal-setup',
  'bug', 'release-notes', 'privacy-settings', 'hooks', 'plugin', 'add-dir', 'ide', 'install-github-app', 'review', 'pr-comments',
]);

const USAGE_CACHE_MS = 60_000;

/** 모델 별칭 (Claude Code CLI가 받아들이는 이름) */
const MODEL_ALIASES = ['sonnet', 'opus', 'haiku', 'default'];

const BUILTIN: CommandInfo[] = [
  { name: 'help', description: '사용할 수 있는 명령 목록', argumentHint: '', source: 'builtin' },
  { name: 'model', description: '실행에 쓸 모델 보기/변경 (예: /model opus)', argumentHint: '[model]', source: 'builtin' },
  { name: 'codex', description: 'Codex 에이전트에게 직접 말하기 (예: /codex 이 설계 어때?, /codex review src/app.ts 봐줘)', argumentHint: '[discuss|review|implement|image] [@에이전트] [>저장경로] <메시지> | reset', source: 'builtin' },
  { name: 'codex-model', description: 'Codex 협업자가 쓸 모델 보기/변경 (예: /codex-model gpt-5-codex)', argumentHint: '[model|default]', source: 'builtin' },
  { name: 'workspace', description: '에이전트가 작업할 폴더 보기/변경 (예: /workspace ~/projects/my-app)', argumentHint: '[path|default]', source: 'builtin' },
  { name: 'effort', description: '추론 노력 수준 보기/변경', argumentHint: `[${EFFORT_LEVELS.join('|')}|off]`, source: 'builtin' },
  { name: 'permission-mode', description: '권한 모드 보기/변경 (acceptEdits: 파일 수정 자동 허용, default: 모두 확인)', argumentHint: '[acceptEdits|default]', source: 'builtin' },
  { name: 'budget', description: '명령당 비용 한도(USD) 보기/변경', argumentHint: '[usd]', source: 'builtin' },
  { name: 'turns', description: '명령당 최대 턴 수 보기/변경', argumentHint: '[n]', source: 'builtin' },
  { name: 'settings', description: '현재 실행 설정 전체 보기', argumentHint: '', source: 'builtin' },
  { name: 'reset-settings', description: '실행 설정을 .env 기본값으로 되돌리기', argumentHint: '', source: 'builtin' },
  { name: 'agents', description: '등록된 서브에이전트 목록', argumentHint: '', source: 'builtin' },
  { name: 'status', description: '서버 상태 (실행 중 여부, 작업 폴더, 설정)', argumentHint: '', source: 'builtin' },
  { name: 'usage', description: 'Claude 구독 사용량 (5시간/7일 한도 소진율)', argumentHint: '', source: 'builtin' },
  { name: 'cost', description: '실행 비용/토큰 (마지막 실행, 오늘, 전체 누적, 모델별)', argumentHint: '', source: 'builtin' },
  { name: 'context', description: '다음 실행이 시작할 때의 컨텍스트 창 사용량 (시스템 프롬프트/도구/메모리/에이전트)', argumentHint: '', source: 'builtin' },
  { name: 'clear', description: '로그와 결과 화면 비우기', argumentHint: '', source: 'builtin' },
];

/**
 * 명령 입력창의 슬래시 명령.
 * 서버가 아는 명령(/model, /effort ...)은 여기서 바로 처리하고, 모르는 /명령은 Claude Code에 그대로 넘겨
 * 작업 폴더의 커스텀 명령(.claude/commands/*.md)이나 스킬이 실행되게 한다.
 */
@Injectable()
export class SlashCommandsService {
  private readonly logger = new Logger(SlashCommandsService.name);
  private probe: Promise<{ models: ModelInfo[]; commands: SlashCommand[] }> | null = null;
  private usageCache: { at: number; value: SDKControlGetUsageResponse } | null = null;
  private pendingUsage: Promise<SDKControlGetUsageResponse> | null = null;

  constructor(
    private readonly settings: SettingsService,
    private readonly registry: AgentRegistryService,
    private readonly cost: CostTrackerService,
    private readonly codexBridge: CodexBridgeService,
    private readonly codexAuth: CodexAuthService,
  ) {}

  /** 슬래시로 시작하는 입력인지 */
  static isSlash(text: string) {
    return /^\/[a-zA-Z]/.test(text.trim());
  }

  /** 자동완성용 전체 명령 목록 (서버 내장 + Claude Code가 아는 것) */
  async list(): Promise<CommandInfo[]> {
    const sdk = await this.sdkInfo().catch(() => ({ models: [], commands: [] }));
    const builtinNames = new Set(BUILTIN.map((c) => c.name));
    const extra: CommandInfo[] = sdk.commands
      .filter((c) => !builtinNames.has(c.name) && !INTERACTIVE_ONLY.has(c.name) && !c.name.startsWith('__'))
      .map((c) => ({ name: c.name, description: c.description, argumentHint: c.argumentHint ?? '', source: 'sdk' as const }));
    return [...BUILTIN, ...extra];
  }

  async models(): Promise<ModelInfo[]> {
    return (await this.sdkInfo().catch(() => ({ models: [] as ModelInfo[] }))).models;
  }

  /**
   * 내장 명령이면 처리 결과를, 아니면 null(그대로 Claude Code에 전달)을 돌려준다.
   */
  async handle(input: string, ctx: SlashContext): Promise<SlashResult | null> {
    const text = input.trim();
    const m = /^\/([a-zA-Z][\w-]*)\s*([\s\S]*)$/.exec(text);
    if (!m) return null;
    const name = m[1].toLowerCase();
    const arg = m[2].trim();
    const s = this.settings.get();

    switch (name) {
      case 'help':
      case '?': {
        const list = await this.list();
        const lines = list.map((c) => `/${c.name}${c.argumentHint ? ` ${c.argumentHint}` : ''} — ${c.description}${c.source === 'sdk' ? ' (Claude Code)' : ''}`);
        return { ok: true, text: ['사용할 수 있는 명령:', ...lines, '', '그 밖의 /명령은 Claude Code에 그대로 전달됩니다.'].join('\n') };
      }

      case 'model': {
        if (!arg) {
          const models = await this.models();
          const rows = models.length
            ? models.map((mi) => `- ${mi.value}${mi.resolvedModel && mi.resolvedModel !== mi.value ? ` (${mi.resolvedModel})` : ''}: ${mi.displayName}${mi.description ? ` — ${mi.description}` : ''}`)
            : MODEL_ALIASES.map((a) => `- ${a}`);
          const options: CommandChoice[] = models.length
            ? models.map((mi) => ({
                value: mi.value,
                label: `${mi.displayName}${mi.resolvedModel && mi.resolvedModel !== mi.value ? ` (${mi.resolvedModel})` : ''}`,
                description: mi.description,
                current: (s.model ?? 'default') === mi.value,
              }))
            : MODEL_ALIASES.map((a) => ({ value: a, label: a, current: (s.model ?? 'default') === a }));
          if (!options.some((o) => o.value === 'default')) options.unshift({ value: 'default', label: '기본값 (Claude Code 설정)', current: !s.model });
          return {
            ok: true,
            text: [`현재 모델: ${s.model ?? '기본값 (Claude Code 설정)'}`, '', '사용 가능한 모델:', ...rows, '', '바꾸려면 /model <이름> (예: /model opus), 기본값으로 되돌리려면 /model default'].join('\n'),
            choices: { command: '/model', title: '모델 선택', options },
          };
        }
        if (arg === 'default' || arg === 'reset') {
          const next = await this.settings.update({ model: undefined });
          return { ok: true, text: '모델을 기본값으로 되돌렸습니다. 다음 명령부터 적용됩니다.', settings: next };
        }
        if (!/^[\w.:\[\]-]+$/.test(arg)) return { ok: false, text: `모델 이름 형식이 올바르지 않습니다: ${arg}` };
        // Claude Code가 아는 모델 목록이 있으면 오타를 걸러준다 (예: sonat → sonnet)
        const known = await this.models();
        if (known.length && !known.some((mi) => mi.value === arg || mi.resolvedModel === arg)) {
          const names = known.map((mi) => mi.value).join(', ');
          return { ok: false, text: `알 수 없는 모델입니다: ${arg}\n사용 가능: ${names}\n/model 만 입력하면 목록에서 고를 수 있습니다.` };
        }
        const next = await this.settings.update({ model: arg });
        return { ok: true, text: `모델을 ${arg}(으)로 바꿨습니다. 다음 명령부터 적용됩니다.`, settings: next };
      }

      case 'workspace':
      case 'cwd': {
        if (!arg) {
          return {
            ok: true,
            text: [
              `현재 작업 폴더: ${s.workspaceDir}`,
              '',
              '바꾸려면 /workspace <경로> (절대 경로 또는 ~/ 로 시작, 서버 실행 위치 기준 상대 경로도 가능)',
              '.env의 WORKSPACE_DIR 기본값으로 되돌리려면 /workspace default',
              '※ 에이전트는 이 폴더 안에서 파일을 읽고 쓰며, 첨부 파일도 이 폴더의 uploads/ 에 저장됩니다.',
            ].join('\n'),
          };
        }
        if (ctx.running) return { ok: false, text: '작업이 실행 중일 때는 작업 폴더를 바꿀 수 없습니다. 끝나거나 중지한 뒤 다시 시도하세요.' };

        const target = arg === 'default' || arg === 'reset' ? config.workspaceDir : expandPath(arg);
        try {
          const st = await stat(target);
          if (!st.isDirectory()) return { ok: false, text: `폴더가 아닙니다: ${target}` };
        } catch {
          return { ok: false, text: `폴더를 찾을 수 없습니다: ${target}\n먼저 폴더를 만든 뒤 다시 지정하세요.` };
        }
        // 첨부 저장/미리보기가 바로 되도록 uploads/ 를 준비해 둔다 (권한이 없으면 첨부 업로드 때 다시 시도된다)
        await mkdir(join(target, 'uploads'), { recursive: true }).catch(() => undefined);

        const next = await this.settings.update({ workspaceDir: target });
        this.logger.log(`작업 폴더 변경: ${next.workspaceDir}`);
        return {
          ok: true,
          text: `작업 폴더를 ${next.workspaceDir}(으)로 바꿨습니다. 다음 명령부터 이 폴더에서 실행됩니다.`,
          settings: next,
        };
      }

      case 'effort': {
        if (!arg) {
          const desc: Record<string, string> = { low: '빠르고 저렴', medium: '균형', high: '더 깊게 생각', xhigh: '매우 깊게', max: '최대' };
          return {
            ok: true,
            text: `현재 추론 노력: ${s.effort ?? '기본값'}\n바꾸려면 /effort <${EFFORT_LEVELS.join('|')}>, 끄려면 /effort off`,
            choices: {
              command: '/effort',
              title: '추론 노력 선택',
              options: [
                { value: 'off', label: '기본값', description: '모델 기본 설정', current: !s.effort },
                ...EFFORT_LEVELS.map((l) => ({ value: l, label: l, description: desc[l], current: s.effort === l })),
              ],
            },
          };
        }
        if (arg === 'off' || arg === 'default') {
          const next = await this.settings.update({ effort: undefined });
          return { ok: true, text: '추론 노력 설정을 기본값으로 되돌렸습니다.', settings: next };
        }
        if (!EFFORT_LEVELS.includes(arg as EffortLevel)) return { ok: false, text: `effort는 ${EFFORT_LEVELS.join(', ')} 중 하나여야 합니다.` };
        const next = await this.settings.update({ effort: arg as EffortLevel });
        return { ok: true, text: `추론 노력을 ${arg}(으)로 바꿨습니다. 다음 명령부터 적용됩니다.`, settings: next };
      }

      case 'permission-mode':
      case 'permissions':
      case 'permission': {
        if (!arg) {
          return {
            ok: true,
            text: `현재 권한 모드: ${s.permissionMode}\n- acceptEdits: 작업 폴더 안 파일 수정은 자동 허용, 명령 실행은 승인\n- default: 파일 수정과 명령 실행 모두 승인\n바꾸려면 /permission-mode <acceptEdits|default>`,
            choices: {
              command: '/permission-mode',
              title: '권한 모드 선택',
              options: [
                { value: 'acceptEdits', label: 'acceptEdits', description: '작업 폴더 안 파일 수정은 자동 허용, 명령 실행은 승인', current: s.permissionMode === 'acceptEdits' },
                { value: 'default', label: 'default', description: '파일 수정과 명령 실행 모두 승인', current: s.permissionMode === 'default' },
              ],
            },
          };
        }
        if (!PERMISSION_MODES.includes(arg as (typeof PERMISSION_MODES)[number])) return { ok: false, text: `권한 모드는 ${PERMISSION_MODES.join(', ')} 중 하나여야 합니다.` };
        const next = await this.settings.update({ permissionMode: arg as RunSettings['permissionMode'] });
        return { ok: true, text: `권한 모드를 ${arg}(으)로 바꿨습니다. 다음 명령부터 적용됩니다.`, settings: next };
      }

      case 'budget': {
        if (!arg) return { ok: true, text: `현재 명령당 비용 한도: $${s.maxBudgetUsd}\n바꾸려면 /budget <usd> (예: /budget 5)` };
        const n = Number(arg.replace(/^\$/, ''));
        if (!Number.isFinite(n) || n <= 0) return { ok: false, text: '비용 한도는 0보다 큰 숫자여야 합니다.' };
        const next = await this.settings.update({ maxBudgetUsd: n });
        return { ok: true, text: `명령당 비용 한도를 $${n}(으)로 바꿨습니다.`, settings: next };
      }

      case 'turns': {
        if (!arg) return { ok: true, text: `현재 최대 턴 수: ${s.maxTurns}\n바꾸려면 /turns <n>` };
        const n = Number.parseInt(arg, 10);
        if (!Number.isInteger(n) || n <= 0) return { ok: false, text: '턴 수는 1 이상의 정수여야 합니다.' };
        const next = await this.settings.update({ maxTurns: n });
        return { ok: true, text: `최대 턴 수를 ${n}(으)로 바꿨습니다.`, settings: next };
      }

      case 'settings':
        return { ok: true, text: this.describe(s) };

      case 'reset-settings': {
        const next = await this.settings.reset();
        return { ok: true, text: `실행 설정을 .env 기본값으로 되돌렸습니다.\n${this.describe(next)}`, settings: next };
      }

      case 'agents': {
        const rows = this.registry.list().map((a) => `- ${a.sdkName} (${a.name})${a.provider === 'codex' ? ' [Codex]' : ''}: ${a.sdkDescription}`);
        return { ok: true, text: ['등록된 에이전트:', ...rows, '', '추가/수정은 대시보드의 에이전트 관리에서 할 수 있습니다.'].join('\n') };
      }

      case 'codex': {
        const agents = this.registry.codexAgents();
        if (!arg) {
          const rows = agents.map((a) => `- @${a.sdkName} (${a.name})`);
          return {
            ok: true,
            text: [
              'Codex 에이전트에게 직접 메시지를 보냅니다. Claude를 거치지 않고 Codex 의견을 바로 들을 수 있습니다.',
              '',
              '/codex <메시지>                    — 첫 Codex 에이전트에게 토론(discuss) 모드로',
              '/codex review <메시지>             — 코드 리뷰 (읽기 전용). 파일 경로를 적어주세요',
              '/codex implement <메시지>          — 구현 요청 (작업 폴더 안 파일 수정 가능)',
              '/codex image [>경로] <프롬프트>     — 이미지 생성 (예: /codex image >assets/logo.png flat vector fox logo). 경로를 안 주면 generated/ 아래에 저장',
              '/codex @<에이전트> <메시지>          — 특정 Codex 에이전트에게',
              '/codex reset                       — 직접 대화 기억 초기화',
              '',
              agents.length ? `등록된 Codex 에이전트:\n${rows.join('\n')}` : '등록된 Codex 에이전트가 없습니다. 에이전트 추가에서 제공자를 Codex로 선택하세요.',
            ].join('\n'),
          };
        }
        if (arg === 'reset') {
          this.codexBridge.resetDirectThreads();
          return { ok: true, text: 'Codex 직접 대화 기억을 초기화했습니다. 다음 /codex 부터 새 대화로 시작합니다.' };
        }
        if (ctx.running) return { ok: false, text: '작업 실행 중에는 /codex 를 쓸 수 없습니다. 실행 중엔 Claude가 Codex와 대화합니다.' };
        if (agents.length === 0) return { ok: false, text: '등록된 Codex 에이전트가 없습니다. 에이전트 추가에서 제공자를 Codex로 선택하거나 "기본으로 되돌리기"를 하세요.' };

        // 앞 토큰: [mode] [@sdkName] [>저장경로] 순서 무관
        const tokens = arg.split(/\s+/);
        let mode: CodexMode = 'discuss';
        let agent = agents[0];
        let savePath: string | undefined;
        while (tokens.length > 1) {
          const t = tokens[0];
          if (CODEX_MODES.includes(t as CodexMode)) mode = t as CodexMode;
          else if (t.startsWith('>') && t.length > 1) savePath = t.slice(1);
          else if (t.startsWith('@')) {
            const found = agents.find((a) => a.sdkName === t.slice(1) || a.id === t.slice(1));
            if (!found) return { ok: false, text: `Codex 에이전트를 찾을 수 없습니다: ${t}\n사용 가능: ${agents.map((a) => `@${a.sdkName}`).join(', ')}` };
            agent = found;
          } else break;
          tokens.shift();
        }
        const message = tokens.join(' ').trim();
        if (!message) return { ok: false, text: 'Codex에게 보낼 메시지를 적어주세요.' };

        const auth = await this.codexAuth.status();
        if (!auth.available) return { ok: false, text: auth.message ?? 'Codex CLI를 찾을 수 없습니다.' };
        if (!auth.hasAuth) return { ok: false, text: 'Codex에 로그인되어 있지 않습니다. 헤더의 Codex 칩에서 로그인하세요.' };

        try {
          const reply = await this.codexBridge.askDirect(agent, message, mode, { emit: ctx.emit, workspaceDir: s.workspaceDir, model: s.codexModel }, savePath);
          return { ok: true, text: `${agent.shortName}:\n${reply}` };
        } catch (err) {
          return { ok: false, text: `Codex 응답 실패: ${(err as Error).message}` };
        }
      }

      case 'codex-model': {
        if (!arg) return { ok: true, text: `현재 Codex 모델: ${s.codexModel ?? '기본값 (~/.codex/config.toml)'}\n바꾸려면 /codex-model <이름>, 기본값으로 되돌리려면 /codex-model default` };
        if (arg === 'default' || arg === 'reset') {
          const next = await this.settings.update({ codexModel: undefined });
          return { ok: true, text: 'Codex 모델을 기본값으로 되돌렸습니다.', settings: next };
        }
        if (!/^[\w.:\[\]-]+$/.test(arg)) return { ok: false, text: `모델 이름 형식이 올바르지 않습니다: ${arg}` };
        const next = await this.settings.update({ codexModel: arg });
        return { ok: true, text: `Codex 모델을 ${arg}(으)로 바꿨습니다. 다음 Codex 호출부터 적용됩니다.`, settings: next };
      }

      case 'status':
        return {
          ok: true,
          text: [
            `상태: ${ctx.running ? '작업 실행 중' : '대기 중'}`,
            `인증: ${config.hasAuth() ? '설정됨' : '없음'}`,
            `Codex 인증: ${await this.codexAuth.status().then((a) => (!a.available ? 'CLI 없음' : a.hasAuth ? `설정됨 (${a.method})` : '없음'))}`,
            this.describe(s),
          ].join('\n'),
        };

      case 'usage': {
        try {
          return { ok: true, text: formatUsage(await this.planUsage(true)) };
        } catch (err) {
          return { ok: false, text: `사용량을 가져오지 못했습니다: ${(err as Error).message}` };
        }
      }

      case 'cost':
        return { ok: true, text: this.describeCost() };

      case 'context': {
        try {
          // 실제 실행과 같은 옵션(시스템 프롬프트, 에이전트, 모델)으로 세션을 열어 시작 시점의 컨텍스트를 잰다
          const u = await this.withSession((q) => q.getContextUsage({ detail: 'full' }), 40000, false, true);
          return { ok: true, text: formatContext(u) };
        } catch (err) {
          return { ok: false, text: `컨텍스트 사용량을 가져오지 못했습니다: ${(err as Error).message}` };
        }
      }

      case 'clear':
        if (ctx.running) return { ok: false, text: '작업이 실행 중일 때는 비울 수 없습니다. 끝나거나 중지한 뒤 다시 시도하세요.' };
        ctx.clearHistory();
        this.codexBridge.resetDirectThreads();
        return { ok: true, text: '로그와 결과를 비웠습니다.', clear: true };

      default:
        return null;
    }
  }

  /**
   * Claude 구독 사용량(5시간/7일 한도). 세션을 하나 열어야 해서 잠깐 캐시한다 (헤더 칩이 주기적으로 읽는다).
   * setup-token으로 만든 OAuth 토큰은 플랜 조회 권한이 없어 한도가 안 나오므로, 그럴 땐 이 컴퓨터의 Claude Code 로그인(claude login) 자격으로 다시 물어본다.
   */
  planUsage(force = false): Promise<SDKControlGetUsageResponse> {
    if (!force && this.usageCache && Date.now() - this.usageCache.at < USAGE_CACHE_MS) return Promise.resolve(this.usageCache.value);
    if (!this.pendingUsage) {
      const getUsage = (q: Query) => q.usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET({ skipBehaviors: true });
      this.pendingUsage = (async () => {
        let u = await this.withSession(getUsage);
        if (!u.rate_limits_available) u = await this.withSession(getUsage, 20000, true);
        return u;
      })()
        .then((value) => {
          this.usageCache = { at: Date.now(), value };
          return value;
        })
        .finally(() => {
          this.pendingUsage = null;
        });
    }
    return this.pendingUsage;
  }

  private describeCost(): string {
    const st = this.cost.get();
    const last = st.runs[st.runs.length - 1];
    const today = this.cost.today();
    const money = (n: number) => `$${n.toFixed(4)}`;
    const dur = (ms: number) => {
      const s = Math.round(ms / 1000);
      return s < 60 ? `${s}초` : `${Math.floor(s / 60)}분 ${s % 60}초`;
    };
    const tok = (n: number) => (n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(n));
    const lines: string[] = [];
    if (!last) return '아직 실행 기록이 없습니다.';
    lines.push(`마지막 실행: ${money(last.costUsd)} · ${last.turns}턴 · ${dur(last.durationMs)} (API ${dur(last.apiDurationMs)})${last.ok ? '' : ' · 실패'}`);
    lines.push(`  ${last.command.length > 60 ? `${last.command.slice(0, 60)}…` : last.command}`);
    for (const [model, m] of Object.entries(last.models)) lines.push(`  - ${model}: ${money(m.costUsd)} · 입력 ${tok(m.inputTokens)} / 출력 ${tok(m.outputTokens)} / 캐시 읽기 ${tok(m.cacheReadTokens)} / 캐시 쓰기 ${tok(m.cacheWriteTokens)}`);
    lines.push('');
    lines.push(`오늘: ${money(today.costUsd)} · ${today.runs}회 실행 · ${today.turns}턴 · ${dur(today.durationMs)}`);
    lines.push(`전체: ${money(st.total.costUsd)} · ${st.total.runs}회 실행 · ${st.total.turns}턴 · ${dur(st.total.durationMs)}`);
    const models = Object.entries(st.byModel) as [string, ModelTotals][];
    if (models.length) {
      lines.push('');
      lines.push('모델별 누적:');
      for (const [model, m] of models.sort((a, b) => b[1].costUsd - a[1].costUsd)) {
        lines.push(`  - ${model}: ${money(m.costUsd)} · 입력 ${tok(m.inputTokens)} / 출력 ${tok(m.outputTokens)} / 캐시 읽기 ${tok(m.cacheReadTokens)}`);
      }
    }
    lines.push('');
    lines.push('※ 구독(OAuth) 실행은 실제 청구가 아닌 API 환산 추정치입니다. 구독 한도는 /usage 로 확인하세요.');
    return lines.join('\n');
  }

  private describe(s: RunSettings) {
    return [
      `- 작업 폴더: ${s.workspaceDir}`,
      `- 모델: ${s.model ?? '기본값'}`,
      `- Codex 모델: ${s.codexModel ?? '기본값'}`,
      `- 추론 노력: ${s.effort ?? '기본값'}`,
      `- 권한 모드: ${s.permissionMode}`,
      `- 명령당 비용 한도: $${s.maxBudgetUsd}`,
      `- 최대 턴 수: ${s.maxTurns}`,
    ].join('\n');
  }

  /**
   * Claude Code에게 모델/명령 목록을 물어본다. 프롬프트를 보내지 않는 세션을 잠깐 열어 초기화 정보만 받고 닫으므로
   * API 호출(비용)은 없다. 결과는 캐시한다.
   */
  private sdkInfo() {
    if (!this.probe) {
      this.probe = this.runProbe().catch((err) => {
        this.probe = null;
        this.logger.warn(`Claude Code 명령/모델 목록을 가져오지 못했습니다: ${(err as Error).message}`);
        throw err;
      });
    }
    return this.probe;
  }

  private async runProbe() {
    return this.withSession(async (q) => {
      const [models, commands] = await Promise.all([q.supportedModels(), q.supportedCommands()]);
      this.logger.log(`Claude Code 정보: 모델 ${models.length}개, 명령 ${commands.length}개`);
      return { models, commands };
    });
  }

  /**
   * 프롬프트를 보내지 않는 Claude Code 세션을 잠깐 열어 제어 요청(모델 목록, 사용량 등)만 하고 닫는다.
   * 모델 호출이 없으므로 비용이 들지 않는다.
   */
  private async withSession<T>(fn: (q: Query) => Promise<T>, timeoutMs = 20000, useLocalLogin = false, likeRun = false): Promise<T> {
    const s = this.settings.get();
    let release: () => void = () => {};
    const hold = new Promise<void>((resolve) => {
      release = resolve;
    });
    const silent = async function* () {
      await hold;
    };
    const q = query({
      prompt: silent() as AsyncIterable<never>,
      options: {
        cwd: s.workspaceDir,
        settingSources: ['project'],
        agents: this.registry.sdkAgents(),
        // likeRun: 실제 실행(agent-runner)과 같은 시스템 프롬프트/모델을 붙여 /context 수치가 실제와 맞게
        ...(likeRun
          ? { model: s.model, effort: s.effort, systemPrompt: { type: 'preset' as const, preset: 'claude_code' as const, append: buildOrchestratorPrompt(this.registry.list()) } }
          : {}),
        env: useLocalLogin
          ? // 토큰/API 키 환경변수를 빼면 CLI가 로컬 로그인(키체인) 자격을 쓴다
            Object.fromEntries(Object.entries(process.env).filter(([k]) => k !== 'CLAUDE_CODE_OAUTH_TOKEN' && k !== 'ANTHROPIC_API_KEY'))
          : { ...process.env, CLAUDE_CODE_DISABLE_BACKGROUND_TASKS: '1' },
      },
    });
    try {
      const timeout = new Promise<never>((_, reject) => setTimeout(() => reject(new Error('시간 초과')), timeoutMs).unref());
      return await Promise.race([fn(q), timeout]);
    } finally {
      release();
      q.close();
    }
  }
}

/** 사용자가 적은 경로를 절대 경로로: 따옴표 제거, ~ 확장, 상대 경로는 서버 실행 위치 기준 */
function expandPath(input: string): string {
  let p = input.trim().replace(/^(['"])(.*)\1$/, '$2');
  if (p === '~') p = homedir();
  else if (p.startsWith('~/')) p = join(homedir(), p.slice(2));
  return isAbsolute(p) ? resolve(p) : resolve(process.cwd(), p);
}

// utilization은 0~100 퍼센트 값
const pct = (n: number | null | undefined) => (n === null || n === undefined ? '-' : `${Math.round(n)}%`);
const bar = (n: number | null | undefined) => {
  if (n === null || n === undefined) return '';
  const v = Math.max(0, Math.min(1, n / 100));
  const filled = Math.round(v * 20);
  return ` [${'█'.repeat(filled)}${'░'.repeat(20 - filled)}]`;
};
const resetIn = (iso: string | null | undefined) => {
  if (!iso) return '';
  const ms = new Date(iso).getTime() - Date.now();
  if (!Number.isFinite(ms) || ms <= 0) return '';
  const d = Math.floor(ms / 86400000);
  const h = Math.floor((ms % 86400000) / 3600000);
  const m = Math.floor((ms % 3600000) / 60000);
  return ` · ${d ? `${d}일 ` : ''}${h ? `${h}시간 ` : ''}${d ? '' : `${m}분 `}뒤 초기화`;
};

/** /usage 응답을 Claude Code 터미널의 /usage와 비슷한 텍스트로 */
function formatUsage(u: SDKControlGetUsageResponse): string {
  const lines: string[] = [];
  if (u.subscription_type) lines.push(`구독: ${u.subscription_type}`);
  if (u.session && u.session.total_cost_usd > 0) lines.push(`이 세션 비용: $${u.session.total_cost_usd.toFixed(4)}`);
  if (!u.rate_limits_available || !u.rate_limits) {
    lines.push('플랜 사용량 한도 정보가 없습니다 (API 키 방식이거나 구독 정보를 읽을 수 없음).');
  } else {
    const r = u.rate_limits;
    const row = (label: string, w?: { utilization: number | null; resets_at: string | null } | null) => {
      if (!w) return;
      lines.push(`${label.padEnd(14)} ${pct(w.utilization).padStart(4)}${bar(w.utilization)}${resetIn(w.resets_at)}`);
    };
    row('5시간 한도', r.five_hour);
    row('주간 한도(7일)', r.seven_day);
    row('주간 Opus', r.seven_day_opus);
    row('주간 Sonnet', r.seven_day_sonnet);
    for (const m of r.model_scoped ?? []) row(m.display_name, m);
    if (r.extra_usage?.is_enabled) {
      lines.push(`추가 사용량: ${r.extra_usage.used_credits ?? 0}/${r.extra_usage.monthly_limit ?? '-'} ${r.extra_usage.currency ?? ''} (${pct(r.extra_usage.utilization)})`);
    }
  }
  return lines.join('\n');
}

const fmtTok = (n: number) => (n >= 1000 ? `${(n / 1000).toFixed(n >= 10000 ? 0 : 1)}k` : String(n));

/** /context 응답을 Claude Code 터미널의 /context와 비슷한 표로 */
function formatContext(u: SDKControlGetContextUsageResponse): string {
  const lines: string[] = [];
  const max = u.maxTokens || u.rawMaxTokens || 1;
  lines.push(`모델: ${u.model}`);
  lines.push(`컨텍스트: ${fmtTok(u.totalTokens)} / ${fmtTok(u.rawMaxTokens || max)} 토큰 (${Math.round(u.percentage)}%)${bar(u.percentage)}`);
  lines.push('');
  lines.push('구성:');
  const rows = u.categories.filter((c) => c.tokens > 0 && c.kind !== 'deferred');
  const width = Math.max(...rows.map((c) => c.name.length), 8);
  for (const c of rows) {
    const p = (c.tokens / max) * 100;
    const tag = c.kind === 'free' ? ' (여유)' : c.kind === 'buffer' ? ' (압축 예비)' : '';
    lines.push(`  ${c.name.padEnd(width)}  ${fmtTok(c.tokens).padStart(6)}  ${p.toFixed(1).padStart(5)}%${tag}`);
  }
  const deferred = u.categories.filter((c) => c.kind === 'deferred' && c.tokens > 0);
  if (deferred.length) lines.push(`  (창 밖에 있다가 필요할 때만 로드되는 도구 스키마: ${fmtTok(deferred.reduce((a, c) => a + c.tokens, 0))} 토큰)`);
  if (u.memoryFiles.length) {
    lines.push('');
    lines.push('메모리 파일:');
    for (const f of u.memoryFiles) lines.push(`  - ${f.path} (${f.type}, ${fmtTok(f.tokens)})`);
  }
  if (u.mcpTools.length) {
    lines.push('');
    lines.push(`MCP 도구: ${u.mcpTools.length}개, ${fmtTok(u.mcpTools.reduce((a, t) => a + t.tokens, 0))} 토큰`);
  }
  lines.push('');
  lines.push('※ 명령을 보내기 전, 총괄 에이전트가 시작하는 시점의 컨텍스트입니다. 실행 중에는 대화/도구 결과가 여기에 더해집니다.');
  return lines.join('\n');
}
