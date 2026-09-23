import { randomUUID } from 'node:crypto';
import { readFile, stat } from 'node:fs/promises';
import { isAbsolute, join, relative } from 'node:path';
import { Injectable, Logger } from '@nestjs/common';
import { createSdkMcpServer, tool, type McpSdkServerConfigWithInstance } from '@anthropic-ai/claude-agent-sdk';
import { Codex, type Input, type ThreadEvent, type ThreadItem, type ThreadOptions, type UserInput } from '@openai/codex-sdk';
import { z } from 'zod';
import { CodexAuthService } from '../auth/codex-auth.service.js';
import { resolveCodexBinary } from '../auth/codex-cli.js';
import { CODEX_MCP_SERVER, codexAccessNote, codexCanWrite, codexMcpToolName, codexToolName, type AgentConfig } from './agents.config.js';
import { type Attachment } from './attachments.js';
import { ARTIFACT_MAX_CHARS, TEST_COMMAND, artifactKindOf, clip, isImagePath, langOf, oneLine, workspaceFileUrl } from './artifact-utils.js';
import type { CodexMode, UiAgentId, UiEventBody } from './ui-events.js';

export const isCodexTool = (name: string) => name.startsWith(`mcp__${CODEX_MCP_SERVER}__ask_`);
/** 에이전트 설정에서 권한(Edit/Write/Bash)을 하나라도 켰고 review가 아니면 workspace-write, 아니면 read-only */
export const codexWrites = (agent: Pick<AgentConfig, 'tools'>, mode: CodexMode) => mode !== 'review' && codexCanWrite(agent);
export const sandboxFor = (agent: Pick<AgentConfig, 'tools'>, mode: CodexMode): ThreadOptions['sandboxMode'] => (codexWrites(agent, mode) ? 'workspace-write' : 'read-only');

/** 총괄 도구가 돌려받는 Codex 답변 최대 길이 (총괄의 컨텍스트 보호) */
const REPLY_MAX_CHARS = 12000;

export interface CodexSessionCtx {
  emit: (event: UiEventBody) => void;
  workspaceDir: string;
  signal: AbortSignal;
  /** provider === 'codex' 인 에이전트만 */
  agents: AgentConfig[];
  model?: string;
}

type AgentThread = { threadId: string | null; introduced: boolean; queue: Promise<unknown> };

const MODE_NOTE: Record<CodexMode, string> = {
  discuss: '대화/작업 요청이다. 질문이면 답하고, 파일 수정을 요청받았으면 작업 폴더 안에서 필요한 최소 범위로 고친 뒤 바꾼 파일 경로를 보고해라. 요청받지 않은 파일은 건드리지 마라.',
  review: '코드 리뷰 요청이다. 파일은 읽기만 하고 수정하지 마라. 문제를 심각도 순으로 정리해라.',
  implement: '구현 요청이다. 필요한 최소 범위로 파일을 수정하고, 바꾼 파일 경로와 내용을 보고해라.',
  image:
    '이미지 생성 요청이다. 아래 프롬프트로 내장 이미지 생성 도구(imagegen)를 써서 그림을 만들어라. SVG/PIL/캔버스 등 코드로 그리지 마라. ' +
    '지정된 경로에 저장하고(필요한 폴더는 만들어라), 마지막 줄에 `saved: <작업 폴더 기준 경로>` 형식으로 저장 경로를 적어라.',
};

/** 이미지 생성 결과의 기본 저장 위치 (총괄/사용자가 경로를 안 줬을 때) */
const defaultImagePath = () => `generated/codex-${new Date().toISOString().slice(0, 19).replace(/[-:T]/g, '')}.png`;
/** Codex 답변에서 작업 폴더 기준 이미지 경로를 찾는다 (saved: 줄, 마크다운 링크, 그냥 경로) */
const IMAGE_PATH_RE = /[\w./~-]+\.(?:png|jpe?g|webp|gif|svg)\b/gi;

/**
 * Claude 총괄 ↔ OpenAI Codex 대화 다리.
 * Codex 에이전트 하나가 MCP 도구 하나(ask_<sdkName>)가 되고, 실행(run) 동안 에이전트별 Codex 스레드를 유지해
 * 총괄이 여러 번 주고받아도 Codex가 앞 대화를 기억한다. Codex의 활동(명령 실행, 파일 변경, 말)은 대시보드 이벤트로 흘려보낸다.
 */
@Injectable()
export class CodexBridgeService {
  private readonly logger = new Logger(CodexBridgeService.name);
  private codexClient: Codex | null = null;
  /** /codex 직접 대화용 스레드 (에이전트별). 실행 스레드와는 별개 */
  private readonly directThreads = new Map<UiAgentId, AgentThread>();
  private directAbort: AbortController | null = null;

  constructor(private readonly codexAuth: CodexAuthService) {}

  /** /codex 응답 중인지 (이때는 새 실행을 시작하지 않는다) */
  get busy() {
    return this.directAbort !== null;
  }

  /** 실행 1회에 해당하는 세션. 총괄의 query()에 mcpServers로 붙인다 */
  createSession(ctx: CodexSessionCtx): CodexSession {
    return new CodexSession(this, ctx);
  }

  /**
   * /codex: 사용자가 Codex에게 직접 말한다. 총괄 실행과 같은 이벤트를 내보내고 답 전문을 돌려준다.
   * 스레드는 다음 /codex reset 이나 /clear 까지 유지된다.
   */
  async askDirect(
    agent: AgentConfig,
    message: string,
    mode: CodexMode,
    ctx: Omit<CodexSessionCtx, 'signal' | 'agents'>,
    savePath?: string,
    timeoutMs = 180_000,
    attachments: Attachment[] = [],
  ): Promise<string> {
    if (this.directAbort) throw new Error('Codex가 아직 이전 /codex 메시지에 답하는 중입니다.');
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), timeoutMs);
    timer.unref();
    this.directAbort = abort;

    const callId = `codex-${randomUUID()}`;
    const state = this.directThreads.get(agent.id) ?? { threadId: null, introduced: false, queue: Promise.resolve() };
    this.directThreads.set(agent.id, state);
    ctx.emit({ type: 'codex_direct', active: true });
    const shown = attachments.length ? `${message} (첨부 ${attachments.map((a) => a.name).join(', ')})` : message;
    ctx.emit({ type: 'agent_message', from: 'user', to: agent.id, mode, text: clip(shown, 1200) });
    ctx.emit({ type: 'agent_start', agent: agent.id, callId, task: `[${mode}] ${oneLine(shown)}` });
    try {
      const result = await this.ask(agent, state, message, mode, callId, { ...ctx, signal: abort.signal, agents: [agent] }, savePath, attachments);
      ctx.emit({ type: 'agent_done', agent: agent.id, callId, ok: result.ok, summary: clip(result.text, 1200) });
      if (!result.ok) throw new Error(result.text);
      return result.text;
    } finally {
      clearTimeout(timer);
      this.directAbort = null;
      ctx.emit({ type: 'codex_direct', active: false });
    }
  }

  cancelDirect() {
    this.directAbort?.abort();
  }

  resetDirectThreads() {
    this.directThreads.clear();
  }

  /**
   * Codex에게 한 턴 보내고 답을 받는다. 같은 에이전트에 대한 호출은 직렬로 처리한다(같은 스레드를 동시에 resume하면 깨진다).
   * 이벤트 매핑: 명령 실행 → action_start/done, 파일 변경 → artifact, 생각 → agent_progress, 말 → agent_note.
   */
  async ask(
    agent: AgentConfig,
    state: AgentThread,
    message: string,
    mode: CodexMode,
    callId: string,
    ctx: CodexSessionCtx,
    savePath?: string,
    attachments: Attachment[] = [],
  ): Promise<{ ok: boolean; text: string }> {
    const run = async () => {
      const auth = await this.codexAuth.status();
      if (!auth.hasAuth) {
        ctx.emit({ type: 'agent_note', agent: agent.id, text: 'Codex에 로그인되어 있지 않아 답할 수 없습니다.' });
        return { ok: false, text: 'Codex is not logged in. Tell the user to log in from the dashboard header (Codex chip) and continue without Codex.' };
      }
      let codex: Codex;
      try {
        codex = this.client();
      } catch (err) {
        return { ok: false, text: (err as Error).message };
      }

      const opts: ThreadOptions = {
        workingDirectory: ctx.workspaceDir,
        skipGitRepoCheck: true,
        sandboxMode: sandboxFor(agent, mode),
        approvalPolicy: 'never',
        model: ctx.model,
      };
      // 매 턴 새 codex 프로세스가 뜨므로 샌드박스 모드는 턴마다 바꿀 수 있고, 대화는 thread id로 이어진다
      const thread = state.threadId ? codex.resumeThread(state.threadId, opts) : codex.startThread(opts);
      // 이미지 생성이면 저장 경로를 정해 메시지에 붙인다 (작업 폴더 밖 경로는 기본 위치로 대체)
      const imagePath = mode === 'image' ? (savePath && this.rel(ctx.workspaceDir, savePath)) || defaultImagePath() : null;
      const body = imagePath ? `[저장 경로] ${imagePath}\n\n[이미지 프롬프트]\n${message}` : message;
      // 권한이 없는 에이전트는 어떤 모드든 읽기 전용이라고 알려준다 (샌드박스도 read-only)
      const note = codexWrites(agent, mode) ? `${MODE_NOTE[mode]} ${codexAccessNote(agent)}` : mode === 'review' ? MODE_NOTE.review : `${MODE_NOTE[mode]} 단, 이 에이전트는 ${codexAccessNote(agent)}`;
      const input = state.introduced
        ? `[mode=${mode}] ${note}\n\n${body}`
        : [`[역할]`, agent.prompt, '', '[협업 규칙]', '상대는 Claude 총괄 에이전트(또는 사용자)다. 한국어로 핵심부터 간결하게 답한다.', note, '', '[메시지]', body].join('\n');

      // 첨부: 이미지는 Codex가 직접 보게 local_image로, 나머지는 경로를 알려줘 읽게 한다
      let turnInput: Input = input;
      if (attachments.length > 0) {
        const lines = attachments.map((a) => `- ${a.path} (${a.kind === 'image' ? '이미지' : a.mime}, ${Math.round(a.size / 1024)}KB)`);
        const parts: UserInput[] = [
          { type: 'text', text: `${input}\n\n[첨부 파일]\n사용자가 함께 첨부한 파일이다. 작업 폴더 기준 경로이며 필요하면 읽어라.\n${lines.join('\n')}` },
          ...attachments.filter((a) => a.kind === 'image').map((a): UserInput => ({ type: 'local_image', path: join(ctx.workspaceDir, a.path) })),
        ];
        turnInput = parts;
      }

      let lastText = '';
      let failure: string | null = null;
      try {
        const { events } = await thread.runStreamed(turnInput, { signal: ctx.signal });
        for await (const event of events) {
          const stop = await this.handleEvent(event, agent.id, callId, ctx, state, (t) => (lastText = t));
          if (stop) {
            failure = stop;
            break;
          }
        }
      } catch (err) {
        if (ctx.signal.aborted) return { ok: false, text: '중단됨' };
        failure = (err as Error).message;
      }
      state.introduced = true;
      if (!state.threadId && thread.id) state.threadId = thread.id;

      if (failure) {
        this.logger.warn(`Codex(${agent.id}) 턴 실패: ${failure}`);
        ctx.emit({ type: 'agent_note', agent: agent.id, text: oneLine(`오류: ${failure}`, 200) });
        return { ok: false, text: `Codex 오류: ${failure}` };
      }
      // Codex는 이미지를 셸 명령(cp)으로 옮기는 경우가 많아 file_change 이벤트가 없다. 답변에 적힌 경로를 확인해 결과 미리보기에 올린다
      const images = await this.findImages(ctx.workspaceDir, lastText, imagePath);
      for (const rel of images) {
        ctx.emit({ type: 'artifact', kind: 'image', key: rel, title: rel, lang: langOf(rel), text: rel, url: workspaceFileUrl(rel) });
      }
      if (imagePath && images.length === 0) ctx.emit({ type: 'agent_note', agent: agent.id, text: `이미지 파일을 찾지 못했습니다: ${imagePath}` });
      return { ok: true, text: clip(lastText || '(응답 없음)', REPLY_MAX_CHARS) };
    };

    const next = state.queue.then(run, run);
    state.queue = next.catch(() => undefined);
    return next;
  }

  /** 스트림 이벤트 하나를 대시보드 이벤트로. 치명적 오류면 메시지를 돌려 루프를 끊는다 */
  private async handleEvent(
    event: ThreadEvent,
    agent: UiAgentId,
    callId: string,
    ctx: CodexSessionCtx,
    state: AgentThread,
    setText: (t: string) => void,
  ): Promise<string | null> {
    switch (event.type) {
      case 'thread.started':
        state.threadId = event.thread_id;
        return null;
      case 'turn.failed':
        return event.error.message || '알 수 없는 오류';
      case 'error':
        return event.message || '알 수 없는 오류';
      case 'item.started':
        if (event.item.type === 'command_execution') {
          ctx.emit({ type: 'action_start', agent, actionId: event.item.id, tool: 'Bash', label: `명령 실행: ${oneLine(event.item.command, 80)}` });
        }
        return null;
      case 'item.completed':
        await this.handleItem(event.item, agent, callId, ctx, setText);
        return null;
      default:
        return null;
    }
  }

  private async handleItem(item: ThreadItem, agent: UiAgentId, callId: string, ctx: CodexSessionCtx, setText: (t: string) => void) {
    switch (item.type) {
      case 'agent_message':
        setText(item.text);
        ctx.emit({ type: 'agent_note', agent, text: oneLine(item.text, 200) });
        return;
      case 'reasoning':
        if (item.text.trim()) ctx.emit({ type: 'agent_progress', agent, callId, text: oneLine(item.text) });
        return;
      case 'command_execution': {
        const ok = item.status === 'completed' && (item.exit_code ?? 0) === 0;
        ctx.emit({ type: 'action_done', agent, actionId: item.id, ok });
        if (TEST_COMMAND.test(item.command)) {
          ctx.emit({
            type: 'artifact', kind: 'test', key: `bash:${item.command}`, title: oneLine(item.command, 60),
            lang: 'Shell', text: clip(`$ ${item.command}\n\n${item.aggregated_output}`, ARTIFACT_MAX_CHARS),
          });
        }
        return;
      }
      case 'file_change': {
        const actionId = item.id;
        ctx.emit({ type: 'action_start', agent, actionId, tool: 'Edit', label: `파일 변경: ${item.changes.length}개` });
        for (const change of item.changes) {
          const rel = this.rel(ctx.workspaceDir, change.path);
          if (!rel) {
            ctx.emit({ type: 'agent_note', agent, text: `작업 폴더 밖 파일은 표시하지 않습니다: ${oneLine(change.path, 80)}` });
            continue;
          }
          if (change.kind === 'delete') {
            ctx.emit({ type: 'agent_note', agent, text: `파일 삭제: ${rel}` });
            continue;
          }
          if (isImagePath(rel)) {
            ctx.emit({ type: 'artifact', kind: 'image', key: rel, title: rel, lang: langOf(rel), text: rel, url: workspaceFileUrl(rel) });
            continue;
          }
          try {
            const text = await readFile(join(ctx.workspaceDir, rel), 'utf8');
            ctx.emit({ type: 'artifact', kind: artifactKindOf(rel), key: rel, title: rel, lang: langOf(rel), text: clip(text, ARTIFACT_MAX_CHARS) });
          } catch {
            ctx.emit({ type: 'agent_note', agent, text: `변경된 파일을 읽지 못했습니다: ${rel}` });
          }
        }
        ctx.emit({ type: 'action_done', agent, actionId, ok: item.status === 'completed' });
        return;
      }
      case 'error':
        ctx.emit({ type: 'agent_note', agent, text: oneLine(`오류: ${item.message}`, 200) });
        return;
      default:
        return;
    }
  }

  /** 작업 폴더 기준 상대 경로. 폴더 밖이면 null */
  /** 답변 텍스트와 지정 경로 중 실제로 작업 폴더에 존재하는 이미지 파일 (중복 제거) */
  private async findImages(workspaceDir: string, text: string, savePath: string | null): Promise<string[]> {
    const candidates = new Set<string>();
    if (savePath) candidates.add(savePath);
    for (const m of text.match(IMAGE_PATH_RE) ?? []) candidates.add(m.replace(/^~\//, ''));
    const found: string[] = [];
    for (const c of candidates) {
      const rel = this.rel(workspaceDir, c);
      if (!rel || found.includes(rel)) continue;
      try {
        if ((await stat(join(workspaceDir, rel))).isFile()) found.push(rel);
      } catch {
        // 없는 파일은 건너뛴다
      }
    }
    return found;
  }

  private rel(workspaceDir: string, path: string): string | null {
    const abs = isAbsolute(path) ? path : join(workspaceDir, path);
    const r = relative(workspaceDir, abs);
    return r && !r.startsWith('..') && !isAbsolute(r) ? r : null;
  }

  private client(): Codex {
    if (!this.codexClient) {
      const bin = resolveCodexBinary();
      try {
        this.codexClient = new Codex(bin ? { codexPathOverride: bin } : {});
      } catch (err) {
        throw new Error(`Codex CLI를 실행할 수 없습니다 (npm install 을 다시 실행하세요): ${(err as Error).message}`);
      }
    }
    return this.codexClient;
  }
}

/**
 * 실행 1회 동안의 Codex 상태: 에이전트별 스레드, MCP 서버, tool_use id 전달.
 * MCP 도구 핸들러는 Claude의 tool_use id를 받지 못하므로 MessageMapper가 tool_use를 볼 때 expectCall()로 넘겨주고,
 * 핸들러가 takeCallId()로 꺼내 같은 callId로 이벤트를 묶는다.
 */
export class CodexSession {
  /** MCP 도구 풀네임(mcp__codex__ask_x) → 대시보드 에이전트 id */
  readonly toolAgentMap = new Map<string, UiAgentId>();
  private readonly threads = new Map<UiAgentId, AgentThread>();
  private readonly pendingCalls = new Map<string, string[]>();

  constructor(
    private readonly bridge: CodexBridgeService,
    private readonly ctx: CodexSessionCtx,
  ) {
    for (const a of ctx.agents) this.toolAgentMap.set(codexMcpToolName(a), a.id);
  }

  mcpServer(): McpSdkServerConfigWithInstance {
    const tools = this.ctx.agents.map((agent) =>
      tool(
        codexToolName(agent),
        `${agent.name} (OpenAI Codex)에게 메시지를 보내고 답을 받는다. ${agent.sdkDescription} ` +
          `[권한: ${codexCanWrite(agent) ? agent.tools.join(', ') : '읽기 전용'}] ` +
          'mode: discuss=설계/의견 토론·작업 부탁, review=코드 리뷰(항상 읽기 전용, 파일 경로를 적을 것), implement=구현 위임(권한이 있을 때만 파일 수정/생성), ' +
          'image=이미지 생성(message에 상세한 영어 이미지 프롬프트, savePath에 저장 경로). 같은 실행 안에서는 이전 대화를 기억한다.',
        {
          message: z.string().min(1).describe('Codex에게 보낼 메시지. image 모드면 이미지 프롬프트(주제·스타일·구도·색·배경·용도).'),
          mode: z.enum(['discuss', 'review', 'implement', 'image']).default('discuss').describe('요청 종류'),
          savePath: z.string().optional().describe('image 모드에서 그림을 저장할 작업 폴더 기준 경로 (예: assets/logo.png)'),
        },
        async ({ message, mode, savePath }) => {
          const callId = this.takeCallId(codexMcpToolName(agent)) ?? `codex-${randomUUID()}`;
          const result = await this.bridge.ask(agent, this.thread(agent.id), message, mode, callId, this.ctx, savePath);
          return { content: [{ type: 'text' as const, text: result.text }], isError: !result.ok };
        },
        { alwaysLoad: true },
      ),
    );
    return createSdkMcpServer({ name: CODEX_MCP_SERVER, version: '1.0.0', tools });
  }

  /** MessageMapper: 총괄이 이 도구를 호출하는 tool_use 블록을 봤다 */
  expectCall(toolName: string, _input: Record<string, unknown>, callId: string) {
    const list = this.pendingCalls.get(toolName) ?? [];
    list.push(callId);
    this.pendingCalls.set(toolName, list);
  }

  private takeCallId(toolName: string): string | undefined {
    return this.pendingCalls.get(toolName)?.shift();
  }

  private thread(agentId: UiAgentId): AgentThread {
    let t = this.threads.get(agentId);
    if (!t) {
      t = { threadId: null, introduced: false, queue: Promise.resolve() };
      this.threads.set(agentId, t);
    }
    return t;
  }
}
