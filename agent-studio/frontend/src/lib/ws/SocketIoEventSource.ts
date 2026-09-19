import { io, type Socket } from 'socket.io-client';
import type { AgentEventSource, AgentSimEvent, ArtifactKind, CommandChoices, CommandInfo, RunMode, RunSettings } from './types';
import type { AgentDef, AgentRole, AgentStatus } from '@/types/agent';
import { withUrls, type Attachment } from '@/lib/uploads';

/**
 * 백엔드(src/agent/ui-events.ts)의 UiEvent를 최소한으로 본뜬 타입.
 * 서버 스키마 전체를 복제하지 않고, 이 어댑터가 실제로 쓰는 필드만 느슨하게 기술한다.
 */
type BackendUiEvent = { type: string; at: number; [key: string]: unknown };

const BACKEND_URL = process.env.NEXT_PUBLIC_BACKEND_URL ?? 'http://localhost:3000';

/** 백엔드가 에이전트 id를 문자열로 보낸다. 등록 여부는 스토어가 판단한다. */
const isAgentRole = (v: unknown): v is AgentRole => typeof v === 'string' && v.length > 0 && v !== 'main';

/** test/deploy 에이전트가 도구를 실행 중일 때는 Testing/Deploying으로 보여준다. */
function workingStatusFor(agent: AgentRole): AgentStatus {
  if (agent === 'test') return 'testing';
  if (agent === 'deploy') return 'deploying';
  return 'working';
}

function mapUiEvent(evt: BackendUiEvent): AgentSimEvent[] {
  switch (evt.type) {
    case 'run_start': {
      return [
        {
          type: 'run_start',
          command: String(evt.command ?? ''),
          workspace: typeof evt.workspace === 'string' ? evt.workspace : undefined,
          attachments: withUrls(Array.isArray(evt.attachments) ? (evt.attachments as Attachment[]) : undefined),
          mode: evt.mode === 'chat' ? 'chat' : 'cowork',
        },
        { type: 'log', agent: 'system', text: `${evt.mode === 'chat' ? '채팅' : '명령'} 접수: ${String(evt.command ?? '')}` },
      ];
    }
    case 'agent_start': {
      if (!isAgentRole(evt.agent)) return [];
      const task = String(evt.task ?? '작업 시작');
      return [
        { type: 'agent_status', agent: evt.agent, status: 'thinking', room: 'work', message: task },
        { type: 'log', agent: evt.agent, text: task },
      ];
    }
    case 'agent_progress': {
      if (!isAgentRole(evt.agent)) return [];
      const text = String(evt.text ?? '');
      return [
        { type: 'agent_status', agent: evt.agent, status: workingStatusFor(evt.agent), message: text },
        { type: 'log', agent: evt.agent, text },
      ];
    }
    case 'agent_note': {
      if (!isAgentRole(evt.agent)) return [];
      return [{ type: 'log', agent: evt.agent, text: String(evt.text ?? '') }];
    }
    case 'action_start': {
      if (!isAgentRole(evt.agent)) return [];
      const label = String(evt.label ?? evt.tool ?? '작업 실행');
      return [
        { type: 'agent_status', agent: evt.agent, status: workingStatusFor(evt.agent), message: label },
        { type: 'log', agent: evt.agent, text: label },
      ];
    }
    case 'action_done': {
      if (!isAgentRole(evt.agent)) return [];
      return [{ type: 'log', agent: evt.agent, text: evt.ok ? '완료' : '실패' }];
    }
    // 에이전트 사이의 대화 (총괄 ↔ Codex, 사용자 → Codex). 보낸 쪽 로그로 남기고, 받는 쪽 말풍선은 뒤따르는 agent_start가 채운다
    case 'codex_direct':
      return [{ type: 'codex_direct', active: evt.active === true }];
    case 'agent_message': {
      const MODE: Record<string, string> = { discuss: '토론', review: '리뷰', implement: '구현 요청', image: '이미지 생성' };
      const from = evt.from === 'main' || evt.from === 'user' ? 'system' : isAgentRole(evt.from) ? evt.from : 'system';
      const who = evt.from === 'user' ? '사용자' : evt.from === 'main' ? '총괄' : String(evt.from);
      const to = evt.to === 'main' ? '총괄' : String(evt.to);
      return [{ type: 'log', agent: from, text: `${who} → ${to} [${MODE[String(evt.mode)] ?? String(evt.mode)}]: ${String(evt.text ?? '')}` }];
    }
    case 'agent_done': {
      if (!isAgentRole(evt.agent)) return [];
      const ok = Boolean(evt.ok);
      const summary = String(evt.summary ?? (ok ? '작업 완료' : '작업 실패'));
      return [
        { type: 'agent_status', agent: evt.agent, status: ok ? 'completed' : 'error', message: summary, progress: 100 },
        { type: 'log', agent: evt.agent, text: summary },
      ];
    }
    case 'command_result': {
      return [
        {
          type: 'command_result',
          command: String(evt.command ?? ''),
          ok: Boolean(evt.ok),
          text: String(evt.text ?? ''),
          choices: evt.choices && typeof evt.choices === 'object' ? (evt.choices as CommandChoices) : undefined,
        },
      ];
    }
    case 'settings': {
      return evt.settings && typeof evt.settings === 'object' ? [{ type: 'settings', settings: evt.settings as RunSettings }] : [];
    }
    case 'cleared': {
      return [{ type: 'cleared' }];
    }
    case 'session': {
      return [{ type: 'session', model: String(evt.model ?? '') }];
    }
    case 'artifact': {
      const kind = String(evt.kind);
      if (kind !== 'code' && kind !== 'test' && kind !== 'doc' && kind !== 'image') return [];
      return [
        {
          type: 'artifact',
          artifact: {
            kind: kind as ArtifactKind,
            key: String(evt.key ?? evt.title ?? ''),
            title: String(evt.title ?? evt.key ?? ''),
            lang: String(evt.lang ?? ''),
            text: String(evt.text ?? ''),
            url: typeof evt.url === 'string' ? evt.url : undefined,
          },
        },
      ];
    }
    case 'permission_request': {
      const agent = isAgentRole(evt.agent) ? evt.agent : 'system';
      const title = String(evt.title ?? evt.tool ?? '');
      return [
        {
          type: 'permission_request',
          request: {
            id: String(evt.id),
            agent,
            tool: String(evt.tool ?? ''),
            title,
            detail: String(evt.detail ?? ''),
            canAlwaysAllow: Boolean(evt.canAlwaysAllow),
          },
        },
        { type: 'log', agent, text: `승인 요청: ${title}` },
      ];
    }
    case 'permission_resolved': {
      const allowed = Boolean(evt.allowed);
      return [
        { type: 'permission_resolved', id: String(evt.id), allowed },
        { type: 'log', agent: 'system', text: allowed ? '요청을 허용했습니다.' : '요청을 거부했습니다.' },
      ];
    }
    case 'main_note': {
      return [{ type: 'log', agent: 'system', text: String(evt.text ?? '') }];
    }
    case 'run_done': {
      const ok = Boolean(evt.ok);
      const durationMs = Number(evt.durationMs ?? 0);
      const costUsd = Number(evt.costUsd ?? 0);
      const turns = Number(evt.turns ?? 0);
      return [
        { type: 'run_done', result: { ok, result: typeof evt.result === 'string' ? evt.result : '', costUsd, turns, durationMs } },
        {
          type: 'log',
          agent: 'system',
          text: `${ok ? '모든 작업이 완료되었습니다' : '작업이 실패로 끝났습니다'}. (${turns}턴, $${costUsd.toFixed(4)}, ${Math.round(durationMs / 1000)}초)`,
        },
      ];
    }
    case 'run_error': {
      return [
        { type: 'run_error', message: String(evt.message ?? '알 수 없는 오류') },
        { type: 'log', agent: 'system', text: `오류: ${String(evt.message ?? '')}` },
      ];
    }
    case 'run_aborted': {
      return [{ type: 'run_aborted' }, { type: 'log', agent: 'system', text: '작업이 중단되었습니다.' }];
    }
    default:
      return [];
  }
}

/** 기존 NestJS Socket.IO 게이트웨이(src/agent/agent.gateway.ts)에 실제로 연결하는 소스. */
export class SocketIoEventSource implements AgentEventSource {
  private socket: Socket | null = null;
  private onEvent: ((evt: AgentSimEvent) => void) | null = null;

  connect(onEvent: (evt: AgentSimEvent) => void) {
    this.onEvent = onEvent;
    onEvent({ type: 'connection', status: 'connecting' });

    const socket = io(BACKEND_URL, { transports: ['websocket'] });
    this.socket = socket;

    socket.on('connect', () => onEvent({ type: 'connection', status: 'connected' }));
    socket.on('disconnect', () => onEvent({ type: 'connection', status: 'disconnected' }));

    socket.on('hello', (snapshot: { events?: BackendUiEvent[]; agents?: AgentDef[]; settings?: RunSettings }) => {
      if (Array.isArray(snapshot.agents)) onEvent({ type: 'agents_changed', agents: snapshot.agents });
      if (snapshot.settings) onEvent({ type: 'settings', settings: snapshot.settings });
      for (const evt of snapshot.events ?? []) {
        for (const simEvt of mapUiEvent(evt)) {
          // 예전 /model 응답을 다시 재생할 때 선택 창이 또 뜨지 않게 선택지는 뺀다
          onEvent(simEvt.type === 'command_result' ? { ...simEvt, choices: undefined } : simEvt);
        }
      }
    });

    socket.on('agents-changed', (payload: { agents?: AgentDef[] }) => {
      if (Array.isArray(payload.agents)) onEvent({ type: 'agents_changed', agents: payload.agents });
    });

    socket.on('agent-event', (evt: BackendUiEvent) => {
      for (const simEvt of mapUiEvent(evt)) onEvent(simEvt);
    });
  }

  disconnect() {
    this.socket?.disconnect();
    this.socket = null;
  }

  sendCommand(prompt: string, _agents: AgentDef[], attachments: Attachment[] = [], mode: RunMode = 'cowork') {
    // 에이전트 목록은 서버가 이미 알고 있으므로 prompt와 첨부(경로), 모드만 보낸다.
    // 게이트웨이는 ack로 { ok, error }를 돌려준다 (이미 실행 중, 인증 없음 등).
    const payload = { prompt, mode, attachments: attachments.map(({ path, name, mime, size, kind }) => ({ path, name, mime, size, kind })) };
    this.socket?.emit('command', payload, (res: { ok?: boolean; error?: string } | undefined) => {
      if (res && res.ok === false) {
        this.onEvent?.({ type: 'run_error', message: res.error ?? '명령을 시작하지 못했습니다.' });
        this.onEvent?.({ type: 'log', agent: 'system', text: `오류: ${res.error ?? '명령을 시작하지 못했습니다.'}` });
      }
    });
  }

  interrupt() {
    this.socket?.emit('interrupt');
  }

  replyPermission(id: string, allowed: boolean, always: boolean) {
    this.socket?.emit('permission-reply', { id, allowed, always });
  }

  async listCommands(): Promise<CommandInfo[]> {
    const res = await fetch(`${BACKEND_URL}/api/commands`);
    if (!res.ok) return [];
    const body = (await res.json()) as { commands?: CommandInfo[] };
    return body.commands ?? [];
  }
}
