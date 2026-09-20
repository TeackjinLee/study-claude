import { isAbsolute, relative } from 'node:path';
import type { SDKMessage } from '@anthropic-ai/claude-agent-sdk';
import type { AgentRef, ArtifactKind, CodexMode, PlanItem, UiAgentId, UiEventBody } from './ui-events.js';
import { TEST_COMMAND, artifactKindOf, clip, langOf, oneLine, splitNextSteps, str } from './artifact-utils.js';

type Emit = (event: UiEventBody) => void;

type ToolCall = { name: string; input: Record<string, unknown>; owner: AgentRef };

/**
 * 총괄이 MCP 도구로 부르는 외부 협업자(Codex). 도구 이름으로 어느 대시보드 에이전트인지 찾고,
 * tool_use id를 브리지에 알려서 브리지가 내보내는 이벤트가 같은 호출(callId)로 묶이게 한다.
 */
export interface ExternalAgentHooks {
  agentFor: (toolName: string) => UiAgentId | null;
  onCall: (toolName: string, input: Record<string, unknown>, callId: string) => void;
  labelFor: (agentId: UiAgentId) => string;
}

export const CODEX_MODE_LABEL: Record<CodexMode, string> = { discuss: '토론', review: '리뷰', implement: '구현 요청', image: '이미지 생성' };
const modeOf = (v: unknown): CodexMode => (v === 'review' || v === 'implement' || v === 'image' ? v : 'discuss');

/** 서브에이전트를 호출하는 도구 이름 (최신 버전은 Agent, 이전 버전은 Task) */
const SUBAGENT_TOOLS = new Set(['Agent', 'Task']);

const RESULT_ERROR_TEXT: Record<string, string> = {
  error_max_budget_usd: '설정한 비용 한도(MAX_BUDGET_USD)에 도달해 작업을 멈췄습니다.',
  error_max_turns: '설정한 최대 턴 수(MAX_TURNS)에 도달해 작업을 멈췄습니다.',
};

const API_ERROR_TEXT: Record<string, string> = {
  authentication_failed: 'API 키 인증에 실패했습니다. .env의 ANTHROPIC_API_KEY를 확인하세요.',
  billing_error: 'API 결제 정보에 문제가 있습니다. Claude Console에서 크레딧을 확인하세요.',
  rate_limit: '요청 한도에 걸렸습니다. 잠시 후 다시 시도합니다.',
  overloaded: 'API 서버가 혼잡합니다. 잠시 후 다시 시도합니다.',
  server_error: 'API 서버 오류가 발생했습니다.',
  model_not_found: '설정한 모델을 찾을 수 없습니다. .env의 MODEL 값을 확인하세요.',
  invalid_request: 'API 요청 형식이 잘못되었습니다.',
};

function toolResultText(content: unknown): string {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content
      .map((part) => (part && typeof part === 'object' && 'text' in part ? str((part as { text: unknown }).text) : ''))
      .filter(Boolean)
      .join('\n');
  }
  return '';
}

export class MessageMapper {
  /** 모든 tool_use id → 호출 정보 */
  private readonly calls = new Map<string, ToolCall>();
  /** 서브에이전트 호출(tool_use id) → 어느 카드인지 */
  private readonly subagentCalls = new Map<string, UiAgentId>();
  /** TaskCreate/TaskUpdate 방식의 할 일 목록 */
  private readonly tasks = new Map<string, PlanItem>();
  private finished = false;
  /** result 메시지의 비용/토큰 요약 (/cost 기록용) */
  lastResult: {
    ok: boolean;
    costUsd: number;
    turns: number;
    durationMs: number;
    apiDurationMs: number;
    models: Record<string, { costUsd: number; inputTokens: number; outputTokens: number; cacheReadTokens: number; cacheWriteTokens: number }>;
  } | null = null;

  constructor(
    private readonly emit: Emit,
    private readonly workspace: string,
    /** subagent_type(SDK 이름) → 대시보드 에이전트 id. 등록되지 않은 이름이면 null */
    private readonly toUiAgentId: (sdkName: unknown) => UiAgentId | null,
    /** result 메시지를 받으면 run_done을 내보내기 전에 호출 (비용 기록용) */
    private readonly onResult?: (result: NonNullable<MessageMapper['lastResult']>) => void,
    /** Codex 같은 외부 협업자 도구 (없으면 MCP 도구는 일반 동작으로 보인다) */
    private readonly external?: ExternalAgentHooks,
    /** 최상위 메시지의 주인. 총괄 실행은 'main', /talk 직접 대화는 그 에이전트 id (텍스트가 agent_note로, 도구가 그 에이전트의 action으로 보인다) */
    private readonly defaultOwner: AgentRef = 'main',
  ) {}

  get hasResult() {
    return this.finished;
  }

  /** 권한 요청이 어느 에이전트에게서 왔는지 찾는다 */
  ownerOf(toolUseId: string | undefined): AgentRef {
    return (toolUseId && this.calls.get(toolUseId)?.owner) || this.defaultOwner;
  }

  handle(msg: SDKMessage) {
    switch (msg.type) {
      case 'system':
        if (msg.subtype === 'init') {
          this.emit({ type: 'session', sessionId: msg.session_id, model: msg.model });
        } else if (msg.subtype === 'api_retry') {
          this.emit({
            type: 'api_retry',
            attempt: msg.attempt,
            maxRetries: msg.max_retries,
            delayMs: msg.retry_delay_ms,
            reason: API_ERROR_TEXT[msg.error] ?? `${msg.error}${msg.error_status ? ` (${msg.error_status})` : ''}`,
          });
        } else if (msg.subtype === 'task_progress' && msg.tool_use_id) {
          const agent = this.subagentCalls.get(msg.tool_use_id);
          const text = msg.summary || msg.description;
          if (agent && text) {
            this.emit({ type: 'agent_progress', agent, callId: msg.tool_use_id, text: oneLine(text) });
          }
        }
        break;
      case 'assistant':
        if (msg.error && !msg.parent_tool_use_id) {
          this.emit({ type: 'api_error', reason: API_ERROR_TEXT[msg.error] ?? msg.error });
        }
        this.onAssistant(msg.message.content as unknown[], msg.parent_tool_use_id);
        break;
      case 'user':
        this.onUser(msg.message.content, msg.tool_use_result);
        break;
      case 'result':
        this.finished = true;
        this.lastResult = {
          ok: msg.subtype === 'success' && !msg.is_error,
          costUsd: msg.total_cost_usd,
          turns: msg.num_turns,
          durationMs: msg.duration_ms,
          apiDurationMs: msg.duration_api_ms,
          models: Object.fromEntries(
            Object.entries(msg.modelUsage ?? {}).map(([model, u]) => [
              model,
              {
                costUsd: u.costUSD,
                inputTokens: u.inputTokens,
                outputTokens: u.outputTokens,
                cacheReadTokens: u.cacheReadInputTokens,
                cacheWriteTokens: u.cacheCreationInputTokens,
              },
            ]),
          ),
        };
        this.onResult?.(this.lastResult);
        // 요약 끝의 <next-steps>는 화면 버튼으로 쓰고 본문에서는 뗀다
        const parsed = splitNextSteps(msg.subtype === 'success' ? msg.result : RESULT_ERROR_TEXT[msg.subtype] ?? (msg.errors.join('\n') || msg.subtype));
        this.emit({
          type: 'run_done',
          ok: msg.subtype === 'success' && !msg.is_error,
          result: parsed.body,
          costUsd: msg.total_cost_usd,
          turns: msg.num_turns,
          durationMs: msg.duration_ms,
          suggestions: parsed.suggestions.length ? parsed.suggestions : undefined,
        });
        break;
      default:
        break;
    }
  }

  private ownerFromParent(parentToolUseId: string | null): AgentRef {
    return (parentToolUseId && this.subagentCalls.get(parentToolUseId)) || this.defaultOwner;
  }

  private onAssistant(blocks: unknown[], parentToolUseId: string | null) {
    const owner = this.ownerFromParent(parentToolUseId);

    for (const raw of blocks) {
      const block = raw as { type: string; text?: string; id?: string; name?: string; input?: unknown };

      if (block.type === 'text' && block.text?.trim()) {
        if (owner === 'main') {
          const text = splitNextSteps(block.text).body;
          if (text) this.emit({ type: 'main_note', text: oneLine(text, 200) });
        }
        else this.emit({ type: 'agent_note', agent: owner, text: oneLine(block.text, 200) });
        continue;
      }

      if (block.type !== 'tool_use' || !block.id || !block.name) continue;
      const input = (block.input ?? {}) as Record<string, unknown>;
      this.calls.set(block.id, { name: block.name, input, owner });

      // 총괄 → Codex 메시지. 서브에이전트 호출과 같은 카드(agent_start/agent_done)로 보이게 한다
      const external = this.external?.agentFor(block.name);
      if (external) {
        const mode = modeOf(input.mode);
        const message = str(input.message);
        this.subagentCalls.set(block.id, external);
        this.external?.onCall(block.name, input, block.id);
        this.emit({ type: 'agent_message', from: owner, to: external, mode, text: clip(message, 1200) });
        this.emit({ type: 'agent_start', agent: external, callId: block.id, task: `[${CODEX_MODE_LABEL[mode]}] ${oneLine(message || '메시지')}` });
        continue;
      }

      if (SUBAGENT_TOOLS.has(block.name)) {
        const agent = this.toUiAgentId(input.subagent_type);
        if (agent) {
          this.subagentCalls.set(block.id, agent);
          this.emit({ type: 'agent_start', agent, callId: block.id, task: oneLine(str(input.description) || '작업') });
          continue;
        }
      }

      if (block.name === 'TodoWrite' && Array.isArray(input.todos)) {
        const items = (input.todos as Array<Record<string, unknown>>).map((t) => ({
          text: str(t.content),
          status: (str(t.status) || 'pending') as PlanItem['status'],
        }));
        this.emit({ type: 'plan', items });
        continue;
      }
      if (block.name === 'TaskCreate' || block.name === 'TaskUpdate' || block.name === 'TaskList' || block.name === 'TaskGet') {
        continue; // 결과(tool_use_result)를 받은 뒤 처리한다
      }

      this.emit({ type: 'action_start', agent: owner, actionId: block.id, tool: block.name, label: this.describe(block.name, input) });
    }
  }

  private onUser(content: unknown, structured: unknown) {
    if (!Array.isArray(content)) return;

    for (const raw of content) {
      const block = raw as { type: string; tool_use_id?: string; content?: unknown; is_error?: boolean };
      if (block.type !== 'tool_result' || !block.tool_use_id) continue;

      const id = block.tool_use_id;
      const ok = !block.is_error;
      const call = this.calls.get(id);

      const agent = this.subagentCalls.get(id);
      if (agent) {
        const summary = toolResultText(block.content).replace(/agentId:.*$/ms, '').trim();
        this.emit({ type: 'agent_done', agent, callId: id, ok, summary: clip(summary, 1200) });
        // Codex의 답은 총괄에게 돌아가는 메시지이기도 하다
        if (call && this.external?.agentFor(call.name)) {
          this.emit({ type: 'agent_message', from: agent, to: call.owner, mode: modeOf(call.input.mode), text: clip(summary, 1200) });
        }
        continue;
      }
      if (!call) continue;

      if (call.name === 'TaskCreate' || call.name === 'TaskUpdate') {
        if (ok) this.trackTask(call, structured);
        continue;
      }
      if (call.name === 'TodoWrite' || call.name === 'TaskList' || call.name === 'TaskGet') continue;

      this.emit({ type: 'action_done', agent: call.owner, actionId: id, ok });
      if (ok) this.maybeArtifact(call, toolResultText(block.content));
    }
  }

  private trackTask(call: ToolCall, structured: unknown) {
    if (call.name === 'TaskCreate') {
      const task = (structured as { task?: { id?: string; subject?: string } } | undefined)?.task;
      if (!task?.id) return;
      this.tasks.set(task.id, { text: str(task.subject) || str(call.input.subject), status: 'pending' });
    } else {
      const item = this.tasks.get(str(call.input.taskId));
      if (!item) return;
      const status = str(call.input.status);
      if (status === 'deleted') this.tasks.delete(str(call.input.taskId));
      else if (status === 'pending' || status === 'in_progress' || status === 'completed') item.status = status;
      if (call.input.subject) item.text = str(call.input.subject);
    }
    this.emit({ type: 'plan', items: [...this.tasks.values()] });
  }

  private maybeArtifact(call: ToolCall, output: string) {
    const { name, input, owner } = call;

    if (name === 'Write' || name === 'Edit') {
      const path = this.rel(str(input.file_path));
      const byExt = artifactKindOf(path);
      const kind: ArtifactKind = byExt === 'doc' ? 'doc' : owner === 'test' ? 'test' : 'code';
      const text = name === 'Write' ? str(input.content) : `(수정된 부분)\n${str(input.new_string)}`;
      this.emit({ type: 'artifact', kind, key: path, title: path, lang: langOf(path), text: clip(text, 20000) });
      return;
    }

    if (name === 'Bash') {
      const command = str(input.command);
      if (owner !== 'test' && !TEST_COMMAND.test(command)) return;
      this.emit({
        type: 'artifact', kind: 'test', key: `bash:${command}`, title: oneLine(command, 60),
        lang: 'Shell', text: clip(`$ ${command}\n\n${output}`, 20000),
      });
    }
  }

  private rel(path: string) {
    if (!path) return '(알 수 없는 파일)';
    if (!isAbsolute(path)) return path;
    const r = relative(this.workspace, path);
    return r.startsWith('..') ? path : r;
  }

  private describe(tool: string, input: Record<string, unknown>): string {
    const path = () => this.rel(str(input.file_path));
    switch (tool) {
      case 'Read': return `파일 읽기: ${path()}`;
      case 'Write': return `파일 생성: ${path()}`;
      case 'Edit': return `파일 수정: ${path()}`;
      case 'Bash': return `명령 실행: ${oneLine(str(input.command), 80)}`;
      case 'Glob': return `파일 찾기: ${str(input.pattern)}`;
      case 'Grep': return `코드 검색: ${oneLine(str(input.pattern), 60)}`;
      case 'WebSearch': return `웹 검색: ${oneLine(str(input.query), 60)}`;
      case 'WebFetch': return `웹 페이지 읽기: ${oneLine(str(input.url), 60)}`;
      case 'Agent':
      case 'Task': return `서브에이전트 호출: ${oneLine(str(input.description), 60)}`;
      default: {
        const external = this.external?.agentFor(tool);
        if (external) return `${this.external!.labelFor(external)}에게 ${CODEX_MODE_LABEL[modeOf(input.mode)]}: ${oneLine(str(input.message), 60)}`;
        return tool.startsWith('mcp__') ? `외부 도구: ${tool.replace(/^mcp__/, '')}` : tool;
      }
    }
  }

  /** 권한 요청 화면에 보여줄 설명 */
  describeForPermission(tool: string, input: Record<string, unknown>): string {
    if (this.external?.agentFor(tool)) return str(input.message);
    if (tool === 'Bash') return str(input.command);
    if (tool === 'Write') return `${this.rel(str(input.file_path))}\n\n${clip(str(input.content), 1500)}`;
    if (tool === 'Edit') return `${this.rel(str(input.file_path))}\n\n${clip(str(input.new_string), 1500)}`;
    if (tool === 'WebFetch') return str(input.url);
    return clip(JSON.stringify(input, null, 2), 1500);
  }

  label(tool: string, input: Record<string, unknown>) {
    return this.describe(tool, input);
  }
}
