import { randomUUID } from 'node:crypto';
import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { query, type CanUseTool, type PermissionResult, type SDKUserMessage } from '@anthropic-ai/claude-agent-sdk';
import { config } from '../config.js';
import { AgentRegistryService } from './agent-registry.service.js';
import type { AgentConfig } from './agents.config.js';
import { clip, oneLine } from './artifact-utils.js';
import { buildPromptContent, validateAttachments, type Attachment } from './attachments.js';
import { SettingsService } from './settings.service.js';
import { SlashCommandsService } from './slash-commands.service.js';
import { CostTrackerService } from './cost-tracker.service.js';
import { CodexBridgeService, codexWrites, isCodexTool } from './codex-bridge.service.js';
import { codexMcpToolName } from './agents.config.js';
import { CodexAuthService } from '../auth/codex-auth.service.js';
import { MessageMapper } from './message-mapper.js';
import { RUN_MODES, type CodexMode, type RunMode, type UiEvent, type UiEventBody } from './ui-events.js';

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

/** 채팅 모드에서 빼는 도구: 파일 쓰기, 명령 실행, 서브에이전트, 할 일 목록. 읽기/검색/웹만 남긴다 */
const CHAT_DISALLOWED_TOOLS = [
  'Write', 'Edit', 'MultiEdit', 'NotebookEdit', 'Bash', 'BashOutput', 'KillShell',
  'Agent', 'Task', 'TodoWrite', 'TaskCreate', 'TaskUpdate', 'TaskList', 'TaskGet', 'TaskOutput', 'TaskStop',
  'Skill', 'EnterPlanMode', 'ExitPlanMode',
];

/** 직접 대화(/talk)에서 에이전트에게 주지 않는 도구. 서브에이전트 호출과 할 일 목록은 총괄 실행에서만 쓴다 */
const TALK_ALWAYS_DISALLOWED = ['Agent', 'Task', 'TodoWrite', 'TaskCreate', 'TaskUpdate', 'TaskList', 'TaskGet', 'TaskOutput', 'TaskStop', 'Skill', 'EnterPlanMode', 'ExitPlanMode'];
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
너는 AI Agent Studio 대시보드에서 사용자와 대화하는 상대다. 지금은 작업 모드(Cowork)가 아니라 채팅 모드다.
- 질문에 답하고, 코드를 설명하고, 방향을 상의한다. 작업 폴더의 파일은 읽기와 검색만 할 수 있다.
- 파일 수정, 명령 실행, 서브에이전트 호출, 할 일 목록 작성은 할 수 없고 하지 않는다. 사용자가 실제 작업(구현·수정·실행)을 원하면 "Cowork 모드로 바꿔서 요청해 주세요"라고 한 줄로 안내하고, 대신 방법이나 계획을 설명해 준다.
- 한국어로, 핵심부터 간결하게 답한다. 이전 대화를 기억하고 이어서 답한다.
- 답 맨 끝에 사용자가 다음에 물어보거나 시킬 만한 것 3개를 아래 형식으로 붙인다. 각 줄은 입력창에 그대로 넣을 수 있는 한국어 한 문장(40자 이내). 실제 작업이 필요한 항목이면 Cowork에서 할 명령으로 적어도 된다.
<next-steps>
- server.js의 에러 처리 방식을 설명해줘
- 비밀번호 길이 검증을 추가해줘
</next-steps>
`;

@Injectable()
export class AgentRunnerService implements OnModuleDestroy {
  private readonly logger = new Logger(AgentRunnerService.name);
  private readonly listeners = new Set<Listener>();
  private readonly pending = new Map<string, PendingPermission>();
  private readonly sessionAllowed = new Set<string>();
  /** "이번 실행 모두 허용"을 눌렀으면 남은 승인 요청을 전부 통과시킨다 (실행마다 초기화) */
  private allowAllThisRun = false;
  private history: UiEvent[] = [];
  private abort: AbortController | null = null;
  /** 채팅 모드는 이전 대화를 이어가기 위해 Claude Code 세션을 기억한다 (/clear 나 작업 폴더가 바뀌면 새로 시작) */
  private chat: { sessionId: string; workspaceDir: string } | null = null;
  /** 지금 실행 중인 명령이 쓰는 첨부 파일 (자동 정리에서 제외하려고 기억) */
  private currentAttachments: Attachment[] = [];
  /** /talk 직접 대화: 진행 중인 대화의 중단 컨트롤러와, 에이전트별로 이어갈 세션 */
  private talkAbort: AbortController | null = null;
  private talkAgent: string | null = null;
  private talks = new Map<string, { sessionId: string; workspaceDir: string }>();

  constructor(
    private readonly registry: AgentRegistryService,
    private readonly settings: SettingsService,
    private readonly slash: SlashCommandsService,
    private readonly cost: CostTrackerService,
    private readonly codexBridge: CodexBridgeService,
    private readonly codexAuth: CodexAuthService,
  ) {}

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
    };
  }

  subscribe(listener: Listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** attachments: /api/uploads가 돌려준 목록. 검증 후 실제로 존재하는 파일만 쓴다 */
  async start(prompt: unknown, attachments?: unknown, modeInput?: unknown): Promise<{ ok: true } | { ok: false; error: string }> {
    const text = typeof prompt === 'string' ? prompt.trim() : '';
    const mode: RunMode = RUN_MODES.find((m) => m === modeInput) ?? 'cowork';
    const files = await validateAttachments(this.settings.workspaceDir, attachments);
    if (!text && files.length === 0) return { ok: false, error: '명령을 입력하세요.' };

    // /model 같은 서버 내장 슬래시 명령은 실행 없이 바로 답한다. 모르는 /명령은 Claude Code로 넘어간다.
    if (SlashCommandsService.isSlash(text)) {
      const result = await this.slash.handle(text, {
        running: this.running,
        clearHistory: () => {
          this.history = [];
          this.chat = null;
          this.talks.clear();
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

    this.history = [];
    this.sessionAllowed.clear();
    this.allowAllThisRun = false;
    this.currentAttachments = files;
    const abort = new AbortController();
    this.abort = abort;
    void this.run(text || '첨부한 파일을 확인하고 적절히 처리해줘.', files, abort, mode);
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
    this.abort.abort();
    this.codexBridge.cancelDirect();
    this.denyAllPending();
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
    const prev = this.talks.get(agent.id);
    const resume = prev?.workspaceDir === workspaceDir ? prev.sessionId : undefined;
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
          this.talks.set(agent.id, { sessionId: e.sessionId, workspaceDir });
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
    for (const listener of this.listeners) listener(event);
  }

  private async run(prompt: string, attachments: Attachment[], abort: AbortController, mode: RunMode) {
    // 실행 도중 /workspace 로 바뀌어도 이번 실행은 시작 시점의 폴더를 끝까지 쓴다
    const workspaceDir = this.settings.workspaceDir;
    const settings = this.settings.get();
    const chat = mode === 'chat';
    // 채팅은 같은 작업 폴더에서의 이전 대화를 이어간다
    const resume = chat && this.chat?.workspaceDir === workspaceDir ? this.chat.sessionId : undefined;

    // Codex 협업자: 등록돼 있고 로그인돼 있을 때만 총괄에게 도구로 붙인다 (채팅 모드에서는 쓰지 않는다)
    const codexAgents = chat ? [] : this.registry.codexAgents();
    const codexAvailable = codexAgents.length > 0 && (await this.codexAuth.status()).hasAuth;
    const session = codexAvailable
      ? this.codexBridge.createSession({ emit: (e) => this.emit(e), workspaceDir, signal: abort.signal, agents: codexAgents, model: settings.codexModel })
      : null;

    const mapper = new MessageMapper(
      (e) => {
        if (chat && e.type === 'session') this.chat = { sessionId: e.sessionId, workspaceDir };
        // 결과가 나오면 스트림이 닫히기 전이라도 다음 명령을 받을 수 있게 먼저 "실행 중"을 푼다 (채팅에서 바로 이어 묻는 경우)
        if (e.type === 'run_done' && this.abort === abort) this.abort = null;
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
    this.emit({ type: 'run_start', command: prompt, workspace: workspaceDir, attachments, mode });
    this.logger.log(`${chat ? '채팅' : '작업'} 시작: ${prompt}${attachments.length ? ` (첨부 ${attachments.length}개)` : ''}${resume ? ' (이어서)' : ''}`);
    if (codexAgents.length > 0 && !codexAvailable) {
      this.emit({ type: 'main_note', text: '⚠ Codex 협업자가 로그인되지 않아 이번 실행에서는 제외됩니다. 헤더의 Codex 칩에서 로그인하세요.' });
    }

    try {
      // 첨부가 있으면 이미지 블록을 포함한 사용자 메시지 스트림으로, 없으면 문자열 그대로
      const content = await buildPromptContent(workspaceDir, prompt, attachments);
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
          maxTurns: settings.maxTurns,
          maxBudgetUsd: settings.maxBudgetUsd,
          permissionMode: settings.permissionMode,
          agents: chat ? undefined : this.registry.sdkAgents(),
          mcpServers: session ? { codex: session.mcpServer() } : undefined,
          disallowedTools: chat ? CHAT_DISALLOWED_TOOLS : undefined,
          resume,
          systemPrompt: { type: 'preset', preset: 'claude_code', append: chat ? CHAT_PROMPT : this.registry.orchestratorPrompt({ codexAvailable }) },
          // 사용자 전역 설정(~/.claude)의 훅이나 권한 규칙이 섞이지 않게, 작업 폴더의 설정만 읽는다.
          settingSources: ['project'],
          // 총괄 에이전트가 서브에이전트를 백그라운드로 띄우고 먼저 끝나버리면
          // 한 번 실행(one-shot)인 이 세션이 닫히면서 서브에이전트도 같이 죽는다. 항상 기다리게 한다.
          env: { ...process.env, CLAUDE_CODE_DISABLE_BACKGROUND_TASKS: '1' },
          canUseTool: this.makePermissionHandler(mapper),
          stderr: (data) => this.logger.debug(data.trim()),
        },
      });

      for await (const message of stream) {
        mapper.handle(message);
      }


      if (abort.signal.aborted) this.emit({ type: 'run_aborted' });
      else if (!mapper.hasResult) this.emit({ type: 'run_error', message: '에이전트가 결과 없이 종료되었습니다.' });
    } catch (err) {
      if (abort.signal.aborted) {
        this.emit({ type: 'run_aborted' });
      } else {
        const message = err instanceof Error ? err.message : String(err);
        this.logger.error(message, err instanceof Error ? err.stack : undefined);
        this.emit({ type: 'run_error', message });
      }
    } finally {
      // 이미 다음 실행이 시작됐으면(run_done 직후) 그쪽의 승인 대기는 건드리지 않는다
      if (this.abort === abort || this.abort === null) this.denyAllPending();
      if (this.abort === abort) this.abort = null;
      this.logger.log('작업 종료');
    }
  }

  private makePermissionHandler(mapper: MessageMapper): CanUseTool {
    return (toolName, input, options) => {
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

  private denyAllPending() {
    for (const entry of [...this.pending.values()]) entry.resolve(false);
  }
}
