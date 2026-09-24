import { randomUUID } from 'node:crypto';
import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { query, type CanUseTool, type PermissionMode, type PermissionResult, type Query, type SDKUserMessage } from '@anthropic-ai/claude-agent-sdk';
import { config } from '../config.js';
import { AgentRegistryService } from './agent-registry.service.js';
import type { AgentConfig } from './agents.config.js';
import { clip, oneLine, workspaceFileUrl } from './artifact-utils.js';
import { buildPromptContent, validateAttachments, type Attachment } from './attachments.js';
import { SettingsService } from './settings.service.js';
import { SlashCommandsService } from './slash-commands.service.js';
import { CostTrackerService } from './cost-tracker.service.js';
import { CodexBridgeService, codexWrites, isCodexTool } from './codex-bridge.service.js';
import { codexMcpToolName } from './agents.config.js';
import { CodexAuthService } from '../auth/codex-auth.service.js';
import { MessageMapper } from './message-mapper.js';
import { REFERENCE_TOOL, resolveReferenceImage, studioMcpServer } from './reference-tool.js';
import { RUN_MODES, type CodexMode, type ContextInfo, type RunMode, type UiEvent, type UiEventBody } from './ui-events.js';
import { parseRunMode, runModeProfile } from './run-modes.js';
import { InputQueue, RunCompletion } from './input-queue.js';
import { ConversationStoreService, type ConversationMeta } from './conversation-store.service.js';
import { CheckpointService, type Snapshot } from './checkpoint.service.js';

const modeOf = (v: unknown): CodexMode => (v === 'review' || v === 'implement' || v === 'image' ? v : 'discuss');

type Listener = (event: UiEvent) => void;
type PendingPermission = { tool: string; resolve: (allowed: boolean) => void };

/** 묻지 않고 바로 허용하는 읽기 전용 도구와 조율용 도구 */
const AUTO_ALLOWED_TOOLS = new Set([
  'Read', 'Glob', 'Grep', 'WebSearch', 'WebFetch',
  'Agent', 'Task', 'TodoWrite', 'TaskCreate', 'TaskUpdate', 'TaskList', 'TaskGet',
]);

/** '이번 작업 동안 항상 허용'을 제공하지 않는 도구 (매번 확인) */
/** 허용 범위: true=이 도구를 이번 실행 동안, 'all'=모든 도구를 이번 실행 동안 */
type AlwaysScope = boolean | 'all';

const MAX_HISTORY = 3000;
/** 중지를 누른 뒤 부드럽게 멈추기(interrupt)를 기다리는 시간. 넘기면 프로세스를 끊는다 */
const STOP_GRACE_MS = 8000;

/** 실행 중인 명령: 추가 지시를 넣을 입력 큐, 종료 판정, SDK 세션, 중지 상태 */
interface LiveRun {
  input: InputQueue<SDKUserMessage>;
  completion: RunCompletion;
  query: Query | null;
  /** Codex 협업자 호출만 따로 끊는다 (부드럽게 멈추는 동안에도 Codex가 파일을 계속 고치지 않게) */
  codexAbort: AbortController;
  /** 사용자가 중지를 눌렀다 */
  stopping: boolean;
  /** 중지 뒤 멈춘 턴의 결과(비용 포함)를 받았다 */
  stopped: boolean;
}
/** 실행 끝에 컨텍스트 사용량을 기다리는 최대 시간 (늦으면 재지 않고 끝낸다) */
const CONTEXT_TIMEOUT_MS = 4000;

function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('시간 초과')), ms);
    p.then(
      (v) => (clearTimeout(t), resolve(v)),
      (e: unknown) => (clearTimeout(t), reject(e)),
    );
  });
}

/** 직접 대화(/talk)에서 에이전트에게 주지 않는 도구. 서브에이전트 호출과 할 일 목록은 총괄 실행에서만 쓴다 */
const TALK_ALWAYS_DISALLOWED = ['Agent', 'Task', 'TodoWrite', 'TaskCreate', 'TaskUpdate', 'TaskList', 'TaskGet', 'TaskOutput', 'TaskStop', 'Skill', 'EnterPlanMode', 'ExitPlanMode'];
/** 이 중 하나라도 있는 에이전트와 /talk 하면 실행 되돌리기용 스냅샷을 찍는다 */
const TALK_WRITE_TOOLS = new Set<string>(['Edit', 'Write', 'Bash']);
/** 에이전트 정의의 tools에 없으면 막는 도구 (편집기의 체크박스에 대응) */
const TALK_GATED_TOOLS: Record<string, string[]> = {
  Edit: ['Edit', 'MultiEdit', 'NotebookEdit'],
  Write: ['Write'],
  Bash: ['Bash', 'BashOutput', 'KillShell'],
  WebSearch: ['WebSearch'],
  WebFetch: ['WebFetch'],
};

/** /talk — 사용자가 사무실에서 에이전트에게 직접 말을 걸었을 때의 지시 */
const talkPrompt = (agent: AgentConfig) => `
# ${agent.name} — 사용자와 직접 대화
${agent.prompt}

## 지금 상황
지금은 총괄 에이전트가 시킨 작업이 아니라, 사용자(Master)가 사무실에서 너에게 직접 말을 건 것이다. 동료와 대화하듯 한국어로 핵심부터 간결하게 답한다.
- 질문이면 네 담당 분야의 관점에서 답하고, 작업을 부탁받았으면 네 도구 범위 안에서 요청받은 것만 한다. 담당이 아닌 일은 어느 에이전트에게 말하면 좋을지 알려준다.
- 사용자와의 이전 대화를 기억하고 이어서 답한다. 파일을 바꿨으면 경로를 말해준다.
- 할 일 목록이나 다른 에이전트 호출은 하지 않는다.
`;

const CHAT_PROMPT = `
# 채팅 모드
너는 AI Agent Studio 대시보드에서 사용자와 대화하는 상대다. 지금은 코드·Cowork 모드가 아니라 채팅 모드다.
- 질문에 답하고, 코드를 설명하고, 방향을 상의한다. 작업 폴더의 파일은 읽기와 검색만 할 수 있다.
- 파일 수정, 명령 실행, 서브에이전트 호출, 할 일 목록 작성은 할 수 없고 하지 않는다. 사용자가 실제 작업(구현·수정·실행)을 원하면 "코드 모드로 바꿔서 요청해 주세요"라고 한 줄로 안내하고, 대신 방법이나 계획을 설명해 준다.
- 한국어로, 핵심부터 간결하게 답한다. 이전 대화를 기억하고 이어서 답한다.
- 답 맨 끝에 사용자가 다음에 물어보거나 시킬 만한 것 3개를 아래 형식으로 붙인다. 각 줄은 입력창에 그대로 넣을 수 있는 한국어 한 문장(40자 이내). 실제 작업이 필요한 항목이면 코드 모드에서 할 명령으로 적어도 된다.
<next-steps>
- server.js의 에러 처리 방식을 설명해줘
- 비밀번호 길이 검증을 추가해줘
</next-steps>
`;

const CODE_PROMPT = `
# 코드 모드
너는 AI Agent Studio 대시보드에서 사용자의 요청을 받아 작업 폴더의 코드를 직접 다루는 Claude Code다. 지금은 코드 모드다.
- 서브에이전트나 다른 협업자에게 나누지 않고 네가 직접 코드를 읽고, 고치고, 명령(빌드·테스트·실행)을 돌린다.
- 먼저 관련 파일을 읽어 기존 구조와 스타일을 파악한 뒤, 요청받은 범위만 최소한으로 고친다. 고친 뒤에는 가능하면 빌드·테스트로 확인한다.
- 여러 단계 작업이면 할 일 목록(TodoWrite)으로 진행 상황을 보여준다.
- 이전 대화를 기억하고 이어서 작업한다.
- 끝나면 한국어로 무엇을 바꿨는지(파일 경로 포함), 어떻게 확인했는지, 남은 문제를 간결하게 요약한다.
- 요약 맨 끝에 사용자가 다음에 시킬 만한 것 3개를 아래 형식으로 붙인다. 각 줄은 입력창에 그대로 넣을 수 있는 한국어 한 문장(40자 이내).
<next-steps>
- 방금 만든 기능에 테스트를 추가해줘
- 에러 처리를 보강해줘
</next-steps>
`;

const PLAN_FIRST_PROMPT = `
## 계획 먼저
이번 요청은 "계획 먼저"로 왔다. 파일을 고치기 전에 관련 코드를 읽고, 바꿀 파일과 방법을 한국어 계획으로 정리해 ExitPlanMode로 사용자 승인을 받는다. 승인되면 그 계획대로 수정하고, 거절되면 수정하지 않는다.
`;

const MODE_LOG: Record<RunMode, string> = { code: '코드', chat: '채팅', cowork: '작업' };

@Injectable()
export class AgentRunnerService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(AgentRunnerService.name);
  private readonly listeners = new Set<Listener>();
  private readonly pending = new Map<string, PendingPermission>();
  private readonly sessionAllowed = new Set<string>();
  /** "이번 실행 모두 허용"을 눌렀으면 남은 승인 요청을 전부 통과시킨다 (실행마다 초기화) */
  private allowAllThisRun = false;
  private history: UiEvent[] = [];
  private abort: AbortController | null = null;
  /** 지금 실행의 이벤트를 기록하는 대화 (코드·채팅). 이어가는 세션 자체는 ConversationStore가 모드별로 기억한다 */
  private recording: string | null = null;
  /** 실행 중인 명령의 입력 큐와 종료 판정. 추가 지시(followUp)를 여기로 끼워 넣는다 */
  private live: LiveRun | null = null;
  /** 지금 실행 중인 명령이 쓰는 첨부 파일 (자동 정리에서 제외하려고 기억) */
  private currentAttachments: Attachment[] = [];
  /** /talk 직접 대화: 진행 중인 대화의 중단 컨트롤러 (에이전트별로 이어갈 세션은 ConversationStore가 저장한다) */
  private talkAbort: AbortController | null = null;
  private talkAgent: string | null = null;

  constructor(
    private readonly registry: AgentRegistryService,
    private readonly settings: SettingsService,
    private readonly slash: SlashCommandsService,
    private readonly cost: CostTrackerService,
    private readonly codexBridge: CodexBridgeService,
    private readonly codexAuth: CodexAuthService,
    private readonly store: ConversationStoreService,
    private readonly checkpoints: CheckpointService,
  ) {}

  /** 서버를 켜면 마지막으로 이어가던 대화를 화면 기록으로 되살린다 */
  async onModuleInit() {
    await this.store.ready;
    const latest = this.store.latestActive(this.settings.workspaceDir);
    if (latest) this.history = withTerminalEvent(await this.store.loadEvents(latest.id));
  }

  get running() {
    return this.abort !== null;
  }

  /** 실행 중인 명령의 첨부가 들어 있는 uploads/ 하위 폴더 이름들 */
  currentAttachmentFolders(): string[] {
    if (!this.running) return [];
    return [...new Set(this.currentAttachments.map((a) => a.path.split('/')[1]).filter(Boolean))];
  }

  /** 새로 접속한 화면이 현재 실행 상태를 복원할 수 있도록 지금까지의 이벤트를 준다 */
  snapshot() {
    return {
      running: this.running,
      events: this.history,
      workspace: this.settings.workspaceDir,
      permissionMode: this.settings.get().permissionMode,
      hasApiKey: config.hasAuth(),
      agents: this.registry.list(),
      settings: this.settings.get(),
      conversations: this.conversations(),
      activeConversations: this.activeConversations(),
    };
  }

  /** 모드별 이어가는 대화의 id·제목 (대화 화면 제목 표시용, 코드·채팅만) */
  activeConversations(): Partial<Record<RunMode, { id: string; title: string; context?: ContextInfo }>> {
    const dir = this.settings.workspaceDir;
    const out: Partial<Record<RunMode, { id: string; title: string; context?: ContextInfo }>> = {};
    for (const m of RUN_MODES) {
      const meta = this.store.activeFor(m, dir);
      if (meta && runModeProfile(m).resumable) out[m] = { id: meta.id, title: meta.title, context: meta.context };
    }
    return out;
  }

  /** 지난 대화를 다시 연다: 이 대화를 모드의 이어가는 대화로 정하고, 화면에 기록을 다시 그리게 한다 */
  async openConversation(idInput: unknown): Promise<{ ok: boolean; error?: string }> {
    if (this.running) return { ok: false, error: '실행 중에는 다른 대화를 열 수 없습니다. 끝나거나 중지한 뒤 다시 시도하세요.' };
    const meta = typeof idInput === 'string' ? this.store.get(idInput) : undefined;
    if (!meta) return { ok: false, error: '대화를 찾을 수 없습니다.' };
    if (meta.workspaceDir !== this.settings.workspaceDir) return { ok: false, error: `다른 작업 폴더(${meta.workspaceDir})의 대화입니다. /workspace 로 그 폴더로 바꾼 뒤 여세요.` };
    this.store.setActive(meta.mode, meta.id);
    const events = withTerminalEvent(await this.store.loadEvents(meta.id));
    this.history = events;
    // 기록 자체는 화면 기록(history)으로 이미 넣었으니 이 알림은 기록하지 않고 보낸다
    this.broadcast({ type: 'conversation_loaded', mode: meta.mode, conversationId: meta.id, title: meta.title, events, context: meta.context, at: Date.now() });
    this.logger.log(`대화 열기: ${meta.title} (${meta.mode})`);
    return { ok: true };
  }

  /** 지난 대화 지우기. 이어가던 대화였으면 그 모드는 새 대화가 된다 */
  async deleteConversation(idInput: unknown): Promise<{ ok: boolean; error?: string }> {
    const meta = typeof idInput === 'string' ? this.store.get(idInput) : undefined;
    if (!meta) return { ok: false, error: '대화를 찾을 수 없습니다.' };
    if (this.running && this.recording === meta.id) return { ok: false, error: '실행 중인 대화는 지울 수 없습니다.' };
    const wasActive = this.store.activeFor(meta.mode, meta.workspaceDir)?.id === meta.id;
    await this.store.remove(meta.id);
    if (wasActive) this.emit({ type: 'conversation', mode: meta.mode, active: false });
    return { ok: true };
  }

  /** 모드별로 지금 작업 폴더에서 이어갈 대화가 있는지 */
  conversations(): Record<RunMode, boolean> {
    const dir = this.settings.workspaceDir;
    // Cowork는 명령마다 새 대화라 "이어가는 대화"가 없다 (저장만 해서 지난 대화에서 다시 열어 본다)
    return Object.fromEntries(RUN_MODES.map((m) => [m, runModeProfile(m).resumable && !!this.store.activeFor(m, dir)])) as Record<RunMode, boolean>;
  }

  /** 새 대화: 이 모드(없으면 코드·채팅 모두)의 이어갈 세션을 잊는다 */
  newConversation(modeInput?: unknown): { ok: boolean; error?: string } {
    if (this.running) return { ok: false, error: '실행 중에는 새 대화를 시작할 수 없습니다. 끝나거나 중지한 뒤 다시 시도하세요.' };
    const modes = modeInput === undefined ? RUN_MODES : [parseRunMode(modeInput)];
    for (const m of modes) {
      // 대화 자체는 지난 대화 목록에 남는다
      this.store.setActive(m, undefined);
      this.emit({ type: 'conversation', mode: m, active: false });
    }
    this.logger.log(`새 대화: ${modes.join(', ')}`);
    return { ok: true };
  }

  /** 실행 도중 추가 지시. 다음 도구 호출 사이에 끼워 넣는다 (첨부 없이 글만) */
  followUp(prompt: unknown): { ok: boolean; error?: string } {
    const text = typeof prompt === 'string' ? prompt.trim() : '';
    if (!text) return { ok: false, error: '추가 지시를 입력하세요.' };
    const live = this.live;
    if (!this.running || !live || live.input.isClosed || live.completion.finished) return { ok: false, error: '실행 중인 작업이 없습니다. 새 명령으로 보내세요.' };
    live.completion.followUp();
    live.input.push({ type: 'user', message: { role: 'user', content: text }, parent_tool_use_id: null, priority: 'next' });
    this.emit({ type: 'follow_up', text: clip(text, 1200) });
    this.logger.log(`추가 지시: ${oneLine(text, 80)}`);
    return { ok: true };
  }

  subscribe(listener: Listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** attachments: /api/uploads가 돌려준 목록. 검증 후 실제로 존재하는 파일만 쓴다 */
  async start(prompt: unknown, attachments?: unknown, modeInput?: unknown, planFirstInput?: unknown): Promise<{ ok: true } | { ok: false; error: string }> {
    const text = typeof prompt === 'string' ? prompt.trim() : '';
    const mode = parseRunMode(modeInput);
    const files = await validateAttachments(this.settings.workspaceDir, attachments);
    if (!text && files.length === 0) return { ok: false, error: '명령을 입력하세요.' };

    // /model 같은 서버 내장 슬래시 명령은 실행 없이 바로 답한다. 모르는 /명령은 Claude Code로 넘어간다.
    if (SlashCommandsService.isSlash(text)) {
      const result = await this.slash.handle(text, {
        running: this.running,
        clearHistory: () => {
          this.history = [];
          for (const m of RUN_MODES) this.store.setActive(m, undefined);
          this.store.clearTalkSessions();
        },
        emit: (e) => this.emit(e),
        talk: (agent, message, attachments) => this.talk(agent, message, attachments),
        attachments: files,
      });
      if (result) {
        if (result.clear) this.emit({ type: 'cleared' });
        this.emit({ type: 'command_result', command: text, ok: result.ok, text: result.text, choices: result.choices });
        if (result.settings) this.emit({ type: 'settings', settings: result.settings });
        return result.ok ? { ok: true } : { ok: false, error: result.text };
      }
    }
    if (this.running) return { ok: false, error: '이미 실행 중인 작업이 있습니다. 끝나거나 중지한 뒤 다시 실행하세요.' };
    if (this.codexBridge.busy) return { ok: false, error: 'Codex가 /codex 메시지에 답하는 중입니다. 끝난 뒤 다시 실행하세요.' };
    if (this.talkAbort) return { ok: false, error: '에이전트가 /talk 메시지에 답하는 중입니다. 끝난 뒤 다시 실행하세요.' };
    if (!config.hasAuth()) return { ok: false, error: '아직 인증되지 않았습니다. 대시보드 상단의 "로그인 필요" 버튼을 눌러 로그인하거나 .env에 ANTHROPIC_API_KEY를 넣으세요.' };

    const profile = runModeProfile(mode);
    // /compact: 이어가는 대화를 요약해 컨텍스트를 비운다 (Claude Code가 처리한다)
    const compact = /^\/compact(\s|$)/i.test(text);
    if (compact) {
      if (!profile.resumable) return { ok: false, error: '대화 압축은 코드·채팅 모드에서만 쓸 수 있습니다.' };
      if (!this.store.activeFor(mode, this.settings.workspaceDir)?.sessionId) return { ok: false, error: '압축할 대화가 없습니다. 먼저 명령을 실행해 대화를 시작하세요.' };
      if (files.length > 0) return { ok: false, error: '대화 압축에는 파일을 첨부할 수 없습니다.' };
    }
    // 기다리는(await) 동안 다른 명령이 끼어들지 않게 먼저 "실행 중"으로 표시한다
    const abort = new AbortController();
    this.abort = abort;
    const conversation = profile.resumable ? this.store.activeFor(mode, this.settings.workspaceDir) : undefined;
    const resume = conversation?.sessionId;
    // 이어 쓰기 전에 기존 기록을 불러 둔다 (안 그러면 새 기록만 남아 앞의 대화가 지워진다)
    const saved = conversation ? await this.store.loadEvents(conversation.id) : [];
    // 이어가는 대화면 화면 기록도 이어 붙인다. 다른 대화를 보고 있었으면 이 대화의 기록으로 바꾼다
    if (!resume) this.history = [];
    else if (!this.history.some((e) => e.type === 'run_start' && e.mode === mode)) this.history = withTerminalEvent(saved);
    this.sessionAllowed.clear();
    this.allowAllThisRun = false;
    this.currentAttachments = files;
    const planFirst = planFirstInput === true && profile.canPlan && !compact;
    void this.run(text || '첨부한 파일을 확인하고 적절히 처리해줘.', files, abort, mode, { resume, planFirst, conversation, compact });
    return { ok: true };
  }

  interrupt() {
    // 실행 중인 작업이 없어도 /codex, /talk 직접 대화는 중지할 수 있다
    if (!this.abort) {
      if (this.talkAbort) {
        this.logger.log('사용자가 /talk 대화를 중지했습니다.');
        this.talkAbort.abort();
        this.denyAllPending();
        return true;
      }
      if (!this.codexBridge.busy) return false;
      this.logger.log('사용자가 /codex 대화를 중지했습니다.');
      this.codexBridge.cancelDirect();
      return true;
    }
    this.logger.log('사용자가 작업을 중지했습니다.');
    const abort = this.abort;
    const live = this.live;
    this.codexBridge.cancelDirect();
    this.denyAllPending();
    const hardStop = () => {
      live?.input.close();
      abort.abort();
    };
    if (!live?.query || live.stopping) {
      hardStop();
      return true;
    }
    // 부드럽게 멈춘다: 지금 턴을 끝내게 하면 결과 메시지(비용 포함)가 와서 비용 기록이 남는다.
    // Codex 호출은 바로 끊고, 제때 멈추지 않으면 프로세스를 끊는다 (그때는 비용이 기록되지 않는다)
    live.stopping = true;
    live.codexAbort.abort();
    const timer = setTimeout(() => {
      if (!live.stopped && this.abort === abort) hardStop();
    }, STOP_GRACE_MS);
    live.query.interrupt().catch(() => {
      clearTimeout(timer);
      if (!live.stopped) hardStop();
    });
    return true;
  }

  replyPermission(id: unknown, allowed: unknown, always: unknown) {
    const entry = typeof id === 'string' ? this.pending.get(id) : undefined;
    if (!entry) return false;
    const scope: AlwaysScope = always === 'all' ? 'all' : always === true;
    if (allowed === true && scope === 'all') this.allowAllThisRun = true;
    else if (allowed === true && scope === true) this.sessionAllowed.add(entry.tool);
    entry.resolve(allowed === true);
    // 같은 범위에 들어가는 다른 대기 요청도 함께 허용해 배너가 연달아 뜨지 않게 한다
    if (allowed === true && scope) {
      for (const [otherId, other] of [...this.pending.entries()]) {
        if (otherId !== id && (scope === 'all' || other.tool === entry.tool)) other.resolve(true);
      }
    }
    return true;
  }

  onModuleDestroy() {
    this.abort?.abort();
    this.talkAbort?.abort();
  }

  /**
   * /talk — 사용자(Master)가 사무실에서 Claude 서브에이전트에게 직접 말을 건다.
   * 그 에이전트의 프롬프트·도구로 한 번 실행(query)하고, 대시보드에는 그 에이전트가 말하고 일하는 것으로 보인다.
   * 에이전트별로 세션을 이어가서(resume) 이전 대화를 기억한다. 총괄 실행과 동시에는 못 한다.
   */
  async talk(agent: AgentConfig, message: string, attachments: Attachment[] = []): Promise<{ ok: boolean; text: string }> {
    if (this.running) return { ok: false, text: '작업 실행 중에는 에이전트에게 직접 말할 수 없습니다. 끝나거나 중지한 뒤 다시 시도하세요.' };
    if (this.talkAbort) return { ok: false, text: `${this.talkAgent ?? '다른 에이전트'}가 답하는 중입니다. 끝난 뒤 다시 말하세요.` };
    if (!config.hasAuth()) return { ok: false, text: '아직 인증되지 않았습니다. 헤더에서 로그인하세요.' };

    const workspaceDir = this.settings.workspaceDir;
    const settings = this.settings.get();
    const resume = this.store.talkSession(agent.id, workspaceDir);
    const abort = new AbortController();
    this.talkAbort = abort;
    this.talkAgent = agent.shortName;
    this.sessionAllowed.clear();
    this.allowAllThisRun = false;
    const callId = `talk-${randomUUID()}`;
    let result: { ok: boolean; text: string } | null = null;

    const disallowed = [...TALK_ALWAYS_DISALLOWED, ...Object.entries(TALK_GATED_TOOLS).flatMap(([tool, names]) => (agent.tools.includes(tool as AgentConfig['tools'][number]) ? [] : names))];
    const mapper = new MessageMapper(
      (e) => {
        if (e.type === 'session') {
          this.store.setTalkSession(agent.id, { sessionId: e.sessionId, workspaceDir });
          return;
        }
        if (e.type === 'run_done') {
          result = { ok: e.ok, text: e.result };
          this.emit({ type: 'agent_done', agent: agent.id, callId, ok: e.ok, summary: clip(e.result, 1200) });
          return;
        }
        if (e.type === 'plan' || e.type === 'main_note') return;
        this.emit(e);
      },
      workspaceDir,
      (name) => this.registry.toUiAgentId(name),
      (r) => void this.cost.record({ at: Date.now(), command: `/talk @${agent.sdkName} ${message}`, ...r }),
      undefined,
      agent.id,
    );

    const shown = attachments.length ? `${message} (첨부 ${attachments.map((a) => a.name).join(', ')})` : message;
    this.emit({ type: 'direct_talk', active: true, agent: agent.id });
    this.emit({ type: 'agent_message', from: 'user', to: agent.id, mode: 'discuss', text: clip(shown, 1200) });
    this.emit({ type: 'agent_start', agent: agent.id, callId, task: oneLine(shown) });
    this.logger.log(`/talk @${agent.sdkName}: ${oneLine(message, 80)}${resume ? ' (이어서)' : ''}`);
    // 실행 되돌리기: 파일을 고칠 수 있는 에이전트면 말하기 전 작업 폴더를 찍어 둔다
    const before = agent.tools.some((t) => TALK_WRITE_TOOLS.has(t)) ? await this.checkpoints.capture() : null;

    try {
      const content = await buildPromptContent(workspaceDir, message, attachments);
      const userMessage = async function* (): AsyncIterable<SDKUserMessage> {
        yield { type: 'user', message: { role: 'user', content }, parent_tool_use_id: null };
      };
      const stream = query({
        prompt: typeof content === 'string' ? content : userMessage(),
        options: {
          abortController: abort,
          cwd: workspaceDir,
          model: settings.model,
          effort: settings.effort,
          maxTurns: Math.min(settings.maxTurns, 25),
          maxBudgetUsd: settings.maxBudgetUsd,
          permissionMode: settings.permissionMode,
          disallowedTools: disallowed,
          resume,
          systemPrompt: { type: 'preset', preset: 'claude_code', append: talkPrompt(agent) },
          settingSources: ['project'],
          env: { ...process.env, CLAUDE_CODE_DISABLE_BACKGROUND_TASKS: '1' },
          canUseTool: this.makePermissionHandler(mapper),
          stderr: (data) => this.logger.debug(data.trim()),
        },
      });
      for await (const msg of stream) mapper.handle(msg);
      if (abort.signal.aborted) {
        this.emit({ type: 'agent_done', agent: agent.id, callId, ok: false, summary: '중단됨' });
        return { ok: false, text: '대화를 중단했습니다.' };
      }
      return result ?? { ok: false, text: '에이전트가 답 없이 끝났습니다.' };
    } catch (err) {
      if (abort.signal.aborted) {
        this.emit({ type: 'agent_done', agent: agent.id, callId, ok: false, summary: '중단됨' });
        return { ok: false, text: '대화를 중단했습니다.' };
      }
      const text = err instanceof Error ? err.message : String(err);
      this.logger.error(text, err instanceof Error ? err.stack : undefined);
      this.emit({ type: 'agent_done', agent: agent.id, callId, ok: false, summary: clip(text, 400) });
      return { ok: false, text };
    } finally {
      this.denyAllPending();
      // 바뀐 파일이 있으면 "되돌리기"를 남긴다. 다음 명령이 끼어들기 전에(talkAbort를 풀기 전에) 찍는다
      const checkpoint = before ? await this.recordCheckpoint(before, `/talk @${agent.sdkName} ${message}`) : null;
      if (checkpoint) this.emit({ type: 'checkpoint', ...checkpoint });
      if (this.talkAbort === abort) {
        this.talkAbort = null;
        this.talkAgent = null;
      }
      this.emit({ type: 'direct_talk', active: false, agent: agent.id });
    }
  }

  private emit(body: UiEventBody) {
    const event = { ...body, at: Date.now() } as UiEvent;
    this.history.push(event);
    if (this.history.length > MAX_HISTORY) this.history.splice(0, this.history.length - MAX_HISTORY);
    if (this.recording) this.store.append(this.recording, event);
    this.broadcast(event);
  }

  /** 화면 기록·대화 저장 없이 화면에만 보낸다 */
  private broadcast(event: UiEvent) {
    for (const listener of this.listeners) listener(event);
  }

  private async run(prompt: string, attachments: Attachment[], abort: AbortController, mode: RunMode, opts: { resume?: string; planFirst: boolean; conversation?: ConversationMeta; compact?: boolean }) {
    // 실행 도중 /workspace 로 바뀌어도 이번 실행은 시작 시점의 폴더를 끝까지 쓴다
    const workspaceDir = this.settings.workspaceDir;
    const settings = this.settings.get();
    const profile = runModeProfile(mode);
    const { resume, planFirst } = opts;
    // 대화로 저장한다. 코드·채팅은 이어가는 대화에 붙이고(없으면 새로), Cowork는 명령마다 새 대화 (지난 대화에서 다시 열어 볼 수 있게)
    const conversation = opts.conversation ?? this.store.create(mode, workspaceDir, prompt);
    this.recording = conversation?.id ?? null;

    // Codex 협업자: 등록돼 있고 로그인돼 있을 때만 총괄에게 도구로 붙인다 (Cowork 모드에서만 쓴다)
    const codexAgents = profile.codex ? this.registry.codexAgents() : [];
    const codexAvailable = codexAgents.length > 0 && (await this.codexAuth.status()).hasAuth;
    const codexAbort = new AbortController();
    abort.signal.addEventListener('abort', () => codexAbort.abort(), { once: true });
    const session = codexAvailable
      ? this.codexBridge.createSession({ emit: (e) => this.emit(e), workspaceDir, signal: codexAbort.signal, agents: codexAgents, model: settings.codexModel })
      : null;

    // 스트리밍 입력: 첫 명령을 넣고 시작한 뒤, 실행 도중의 추가 지시를 끼워 넣는다. 끝나면 입력을 닫아 세션을 닫는다
    const input = new InputQueue<SDKUserMessage>();
    let heldDone: Extract<UiEventBody, { type: 'run_done' }> | null = null;
    /** 실행 전 작업 폴더 (실행 되돌리기용). run_start를 보낸 뒤 찍는다 */
    let before: Snapshot | null = null;
    let finishing: Promise<void> | null = null;
    const completion = new RunCompletion(() => {
      finishing = (async () => {
        // 세션이 닫히기 전에 컨텍스트 사용량을 잰다 (긴 대화 관리: 화면의 게이지와 압축 권유)
        if (profile.resumable && heldDone && !abort.signal.aborted) await this.measureContext(live.query, mode, conversation.id);
        input.close();
        // 실행 후 스냅샷을 찍은 뒤에 "실행 중"을 푼다 (다음 실행이 먼저 시작되면 그 변경까지 섞인다)
        const checkpoint = before ? await this.recordCheckpoint(before, prompt, conversation?.id) : null;
        // 결과가 나오면 스트림이 닫히기 전이라도 다음 명령을 받을 수 있게 먼저 "실행 중"을 푼다 (채팅·코드에서 바로 이어 묻는 경우)
        if (this.abort === abort) this.abort = null;
        if (heldDone) this.emit(heldDone);
        // 중지로 멈춘 턴: 비용은 기록했고, 화면에는 실패가 아니라 "중단"으로 끝낸다
        else if (live.stopped) this.emit({ type: 'run_aborted' });
        if (checkpoint) this.emit({ type: 'checkpoint', ...checkpoint });
        // 결과까지 기록했으면 이 실행의 대화 기록은 끝. 바로 파일에 쓴다
        if (conversation && this.recording === conversation.id) this.recording = null;
        void this.store.flush();
      })();
    });
    const live: LiveRun = { input, completion, query: null, codexAbort, stopping: false, stopped: false };
    this.live = live;

    const mapper = new MessageMapper(
      (e) => {
        if (e.type === 'session') {
          const fresh = !conversation.sessionId;
          this.store.setSession(conversation.id, e.sessionId);
          // 이어가는 대화가 생겼다고 알린다 (Cowork는 이어가지 않으므로 알리지 않는다)
          if (fresh && profile.resumable) this.emit({ type: 'conversation', mode, active: true, id: conversation.id, title: conversation.title });
        }
        // 결과는 추가 지시까지 다 끝났을 때 한 번만 내보낸다 (RunCompletion이 판단)
        // 쓰는 중인 글 조각은 화면에만 보낸다 (블록이 끝나면 전체 글이 따로 기록된다)
        if (e.type === 'assistant_delta') {
          this.broadcast({ ...e, at: Date.now() });
          return;
        }
        // 중지 뒤에 온 결과: 비용은 onResult에서 이미 기록했다. 추가 지시를 기다리지 않고 바로 끝낸다
        if (e.type === 'run_done' && live.stopping) {
          live.stopped = true;
          completion.finish();
          return;
        }
        if (e.type === 'run_done') {
          heldDone = e;
          completion.result();
          return;
        }
        this.emit(e);
      },
      workspaceDir,
      (name) => this.registry.toUiAgentId(name),
      // 메모리 집계는 바로 반영되고 파일 저장만 뒤에서 이어진다
      (result) => void this.cost.record({ at: Date.now(), command: prompt, ...result }),
      session
        ? {
            agentFor: (toolName) => session.toolAgentMap.get(toolName) ?? null,
            onCall: (toolName, input, callId) => session.expectCall(toolName, input, callId),
            labelFor: (agentId) => codexAgents.find((a) => a.id === agentId)?.shortName ?? agentId,
          }
        : undefined,
    );
    this.emit({ type: 'run_start', command: prompt, workspace: workspaceDir, attachments, mode, continued: Boolean(resume), planFirst });
    this.logger.log(`${MODE_LOG[mode]} 시작: ${prompt}${attachments.length ? ` (첨부 ${attachments.length}개)` : ''}${resume ? ' (이어서)' : ''}${planFirst ? ' (계획 먼저)' : ''}`);
    // 실행 되돌리기: 파일을 고칠 수 있는 모드면 실행 전 작업 폴더를 찍어 둔다 (git 저장소일 때만)
    if (mode !== 'chat' && !opts.compact) before = await this.checkpoints.capture();
    if (codexAgents.length > 0 && !codexAvailable) {
      this.emit({ type: 'main_note', text: '⚠ Codex 협업자가 로그인되지 않아 이번 실행에서는 제외됩니다. 헤더의 Codex 칩에서 로그인하세요.' });
    }

    try {
      // 첨부가 있으면 이미지 블록을 포함한 사용자 메시지로
      const content = await buildPromptContent(workspaceDir, prompt, attachments);
      input.push({ type: 'user', message: { role: 'user', content }, parent_tool_use_id: null });

      const append = mode === 'chat' ? CHAT_PROMPT : mode === 'cowork' ? this.registry.orchestratorPrompt({ codexAvailable }) : CODE_PROMPT;
      const stream = query({
        prompt: input,
        options: {
          abortController: abort,
          cwd: workspaceDir,
          model: settings.model,
          effort: settings.effort,
          maxTurns: settings.maxTurns,
          maxBudgetUsd: settings.maxBudgetUsd,
          permissionMode: planFirst ? 'plan' : settings.permissionMode,
          // 글을 토큰 단위로 받아 대화 화면에 실시간으로 보여준다
          includePartialMessages: true,
          agents: profile.subagents ? this.registry.sdkAgents() : undefined,
          // Codex(이미지 생성)가 있을 때만 레퍼런스 확인 도구도 붙인다
          mcpServers: session ? { codex: session.mcpServer(), studio: studioMcpServer() } : undefined,
          disallowedTools: profile.disallowedTools,
          resume,
          systemPrompt: { type: 'preset', preset: 'claude_code', append: planFirst ? `${append}\n${PLAN_FIRST_PROMPT}` : append },
          // 사용자 전역 설정(~/.claude)의 훅이나 권한 규칙이 섞이지 않게, 작업 폴더의 설정만 읽는다.
          settingSources: ['project'],
          // 총괄 에이전트가 서브에이전트를 백그라운드로 띄우고 먼저 끝나버리면
          // 한 번 실행(one-shot)인 이 세션이 닫히면서 서브에이전트도 같이 죽는다. 항상 기다리게 한다.
          env: { ...process.env, CLAUDE_CODE_DISABLE_BACKGROUND_TASKS: '1' },
          // 계획을 승인하면 plan 모드를 풀고 설정의 권한 모드로 실제 수정을 시작한다
          canUseTool: this.makePermissionHandler(mapper, () => live.query?.setPermissionMode(settings.permissionMode as PermissionMode)),
          stderr: (data) => this.logger.debug(data.trim()),
        },
      });
      live.query = stream;

      for await (const message of stream) {
        if (message.type === 'assistant' && !message.parent_tool_use_id) completion.activity();
        else if (message.type === 'system' && message.subtype === 'session_state_changed' && message.state === 'idle') completion.idle();
        mapper.handle(message);
      }
      // 스트림이 먼저 끝났으면(오류, 중단) 끝맺음을 기록한 뒤 마무리한다
      if (abort.signal.aborted) this.emit({ type: 'run_aborted' });
      else if (!mapper.hasResult) this.emit({ type: 'run_error', message: '에이전트가 결과 없이 종료되었습니다.' });
      completion.finish();
    } catch (err) {
      input.close();
      if (live.stopped) {
        // 부드럽게 멈춘 뒤 스트림이 "오류 결과"로 끝나는 건 정상이다 (중단은 이미 알렸다)
        this.logger.debug(`중지 후 스트림 종료: ${err instanceof Error ? err.message : String(err)}`);
      } else if (abort.signal.aborted || live.stopping) {
        this.emit({ type: 'run_aborted' });
      } else {
        const message = err instanceof Error ? err.message : String(err);
        this.logger.error(message, err instanceof Error ? err.stack : undefined);
        this.emit({ type: 'run_error', message });
      }
    } finally {
      // 오류로 끝났어도 그때까지 바뀐 파일은 되돌릴 수 있게 체크포인트를 남긴다
      completion.finish();
      await finishing;
      if (this.live === live) this.live = null;
      if (conversation && this.recording === conversation.id) this.recording = null;
      void this.store.flush();
      // 이미 다음 실행이 시작됐으면(run_done 직후) 그쪽의 승인 대기는 건드리지 않는다
      if (this.abort === abort || this.abort === null) this.denyAllPending();
      if (this.abort === abort) this.abort = null;
      this.logger.log('작업 종료');
    }
  }

  /** 실행 중인 세션의 컨텍스트 사용량을 재서 대화에 저장하고 화면에 알린다. 실패하면 그냥 넘어간다 */
  private async measureContext(q: Query | null, mode: RunMode, conversationId: string) {
    if (!q) return;
    try {
      const u = await withTimeout(q.getContextUsage({ detail: 'summary' }), CONTEXT_TIMEOUT_MS);
      if (!u.maxTokens) return;
      const context: ContextInfo = { tokens: u.totalTokens, max: u.maxTokens, pct: Math.min(100, Math.round(u.percentage)), at: Date.now() };
      this.store.setContext(conversationId, context);
      this.broadcast({ type: 'context_usage', mode, conversationId, context, at: Date.now() });
    } catch (err) {
      this.logger.debug(`컨텍스트 사용량을 재지 못했습니다: ${(err as Error).message}`);
    }
  }

  private async recordCheckpoint(before: Snapshot, command: string, conversationId?: string) {
    const after = await this.checkpoints.capture();
    if (!after) return null;
    try {
      return await this.checkpoints.record(before, after, { command, conversationId });
    } catch (err) {
      this.logger.warn(`체크포인트 기록 실패: ${(err as Error).message}`);
      return null;
    }
  }

  /** 실행 되돌리기. force면 실행 뒤에 다시 바뀐 파일도 실행 전 내용으로 덮어쓴다 */
  async undoCheckpoint(idInput: unknown, forceInput?: unknown) {
    if (this.running || this.talkAbort) return { ok: false, error: '실행 중에는 되돌릴 수 없습니다. 끝나거나 중지한 뒤 다시 시도하세요.' };
    const id = typeof idInput === 'string' ? idInput : '';
    const res = await this.checkpoints.undo(id, forceInput === true);
    if (!res.ok) return res;
    const event: UiEventBody = { type: 'checkpoint_undone', id, restored: res.restored, skipped: res.skipped, complete: res.complete };
    this.emit(event);
    // 대화를 다시 열어도 되돌린 상태가 보이게 그 대화 기록에도 남긴다
    const conversationId = this.checkpoints.get(id)?.conversationId;
    if (conversationId && this.store.get(conversationId)) {
      await this.store.loadEvents(conversationId);
      this.store.append(conversationId, { ...event, at: Date.now() } as UiEvent);
      void this.store.flush();
    }
    return res;
  }

  /** onPlanApproved: "계획 먼저" 실행에서 사용자가 계획(ExitPlanMode)을 승인했을 때 */
  private makePermissionHandler(mapper: MessageMapper, onPlanApproved?: () => Promise<void> | undefined): CanUseTool {
    return (toolName, input, options) => {
      // 계획 승인은 "모두 허용" 중이어도 사용자가 계획을 직접 보고 고른다
      if (toolName === 'ExitPlanMode') return this.askPlanApproval(mapper, input, options, onPlanApproved);
      // 레퍼런스 이미지 확인도 마찬가지로 늘 사용자가 이미지를 보고 고른다
      if (toolName === REFERENCE_TOOL) return this.askReferenceApproval(mapper, input, options);
      if (this.allowAllThisRun || AUTO_ALLOWED_TOOLS.has(toolName) || this.sessionAllowed.has(toolName)) {
        return Promise.resolve<PermissionResult>({ behavior: 'allow', updatedInput: input });
      }
      // Codex: 에이전트 설정의 권한(Edit/Write/Bash)이 없거나 review면 읽기 전용 샌드박스라 바로 허용. 쓰기면 acceptEdits일 때만 자동, default면 묻는다.
      // 주의: Codex의 workspace-write 샌드박스는 파일 수정뿐 아니라 샌드박스 안 명령 실행도 허용한다.
      if (isCodexTool(toolName)) {
        const codexAgent = this.registry.codexAgents().find((a) => codexMcpToolName(a) === toolName);
        // 읽기 전용(권한 없음/리뷰)이면 바로 허용, 쓰기면 acceptEdits일 때만 자동 허용
        if (!codexAgent || !codexWrites(codexAgent, modeOf(input.mode)) || this.settings.get().permissionMode === 'acceptEdits') {
          return Promise.resolve<PermissionResult>({ behavior: 'allow', updatedInput: input });
        }
      }

      const id = randomUUID();
      const agent = mapper.ownerOf(options.toolUseID);

      return new Promise<PermissionResult>((resolve) => {
        const finish = (allowed: boolean) => {
          if (!this.pending.delete(id)) return;
          options.signal.removeEventListener('abort', onAbort);
          this.emit({ type: 'permission_resolved', id, allowed });
          resolve(
            allowed
              ? { behavior: 'allow', updatedInput: input }
              : { behavior: 'deny', message: '사용자가 대시보드에서 이 작업을 거부했습니다. 다른 방법을 찾거나 필요한 이유를 설명하세요.' },
          );
        };
        const onAbort = () => finish(false);

        this.pending.set(id, { tool: toolName, resolve: finish });
        options.signal.addEventListener('abort', onAbort, { once: true });

        this.emit({
          type: 'permission_request',
          id,
          agent,
          tool: toolName,
          title: options.title ?? mapper.label(toolName, input),
          detail: mapper.describeForPermission(toolName, input),
          canAlwaysAllow: true,
        });
      });
    };
  }

  private askPlanApproval(
    mapper: MessageMapper,
    input: Record<string, unknown>,
    options: Parameters<CanUseTool>[2],
    onApproved?: () => Promise<void> | undefined,
  ): Promise<PermissionResult> {
    const id = randomUUID();
    const plan = typeof input.plan === 'string' && input.plan.trim() ? input.plan : '(계획 본문 없음)';
    return new Promise<PermissionResult>((resolve) => {
      const finish = (allowed: boolean) => {
        if (!this.pending.delete(id)) return;
        options.signal.removeEventListener('abort', onAbort);
        this.emit({ type: 'permission_resolved', id, allowed });
        if (!allowed) {
          resolve({ behavior: 'deny', message: '사용자가 계획을 승인하지 않았습니다. 수정하지 말고, 무엇을 바꾸면 좋을지 묻거나 계획을 고쳐 다시 제시하세요.' });
          return;
        }
        void Promise.resolve(onApproved?.())
          .catch((err: unknown) => this.logger.warn(`권한 모드 전환 실패: ${err instanceof Error ? err.message : String(err)}`))
          .finally(() => resolve({ behavior: 'allow', updatedInput: input }));
      };
      const onAbort = () => finish(false);
      this.pending.set(id, { tool: 'ExitPlanMode', resolve: finish });
      options.signal.addEventListener('abort', onAbort, { once: true });
      this.emit({
        type: 'permission_request',
        id,
        agent: mapper.ownerOf(options.toolUseID),
        tool: 'ExitPlanMode',
        title: '계획 승인 — 승인하면 이 계획대로 수정을 시작합니다',
        detail: clip(plan, 6000),
        canAlwaysAllow: false,
      });
    });
  }

  /** 레퍼런스 이미지 확인 카드. 승인하면 도구가 실행되고(= 진행), 거절하면 총괄이 다시 생성한다 */
  private async askReferenceApproval(mapper: MessageMapper, input: Record<string, unknown>, options: Parameters<CanUseTool>[2]): Promise<PermissionResult> {
    const image = await resolveReferenceImage(this.settings.workspaceDir, input.image_path);
    if (!image.ok) return { behavior: 'deny', message: `${image.error} 레퍼런스 이미지를 먼저 만든 뒤 다시 확인을 요청하세요.` };
    const target = typeof input.target === 'string' ? input.target : '레퍼런스';
    const summary = typeof input.summary === 'string' ? input.summary.trim() : '';
    const id = randomUUID();
    return new Promise<PermissionResult>((resolve) => {
      const finish = (allowed: boolean) => {
        if (!this.pending.delete(id)) return;
        options.signal.removeEventListener('abort', onAbort);
        this.emit({ type: 'permission_resolved', id, allowed });
        resolve(
          allowed
            ? { behavior: 'allow', updatedInput: input }
            : {
                behavior: 'deny',
                message:
                  '사용자가 이 레퍼런스를 거절했다. 구현을 시작하지 마라. 사용자가 추가 지시로 원하는 방향을 적었으면 반영해 이미지 프롬프트를 고치고, ' +
                  '다른 파일 이름으로 다시 생성한 뒤 confirm_reference로 다시 확인받아라. 방향을 모르겠으면 무엇을 바꿀지 사용자에게 물어라.',
              },
        );
      };
      const onAbort = () => finish(false);
      this.pending.set(id, { tool: REFERENCE_TOOL, resolve: finish });
      options.signal.addEventListener('abort', onAbort, { once: true });
      this.emit({
        type: 'permission_request',
        id,
        agent: mapper.ownerOf(options.toolUseID),
        tool: 'confirm_reference',
        title: `레퍼런스 확인 — ${clip(target, 80)}`,
        detail: [summary, `${image.rel}`, '이 이미지를 기준으로 구현할까요? 다시 생성하려면 원하는 방향을 추가 지시로 적은 뒤 "다시 생성"을 누르세요.'].filter(Boolean).join('\n'),
        image: `${workspaceFileUrl(image.rel)}?v=${Date.now()}`,
        canAlwaysAllow: false,
      });
    });
  }

  private denyAllPending() {
    for (const entry of [...this.pending.values()]) entry.resolve(false);
  }
}

/**
 * 저장된 기록을 화면 기록(history)으로 쓸 복사본. 저장소의 배열을 그대로 쓰면 이후 이벤트가 두 번 저장된다.
 * 서버가 실행 도중 꺼졌으면 기록이 run_start로 끝나므로, "실행 중"에 멈추지 않게 끝맺음을 붙인다.
 */
function withTerminalEvent(saved: UiEvent[]): UiEvent[] {
  const events = [...saved];
  const lastStart = events.map((e) => e.type).lastIndexOf('run_start');
  if (lastStart < 0) return events;
  const ended = events.slice(lastStart).some((e) => e.type === 'run_done' || e.type === 'run_error' || e.type === 'run_aborted');
  if (ended) return events;
  const at = events[events.length - 1].at;
  return [...events, { type: 'run_error', message: '서버가 다시 시작되어 이 실행은 중간에 끊겼습니다.', at }];
}
