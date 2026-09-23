import type { AgentEventSource } from './types';
import { MockEventSource } from './MockEventSource';
import { SocketIoEventSource } from './SocketIoEventSource';

export type { AgentEventSource, AgentSimEvent, Artifact, ArtifactKind, CommandChoice, CommandChoices, CommandInfo, PermissionRequest, RunMode, RunResult, RunSettings, ToolDetail, TxAgent, TxEvent, CheckpointFile, UndoResult, ContextInfo, ConversationInfo } from './types';
export { RUN_MODES } from './types';
export { createAgentRepository, type AgentRepository } from '@/lib/agents/repository';

/** NEXT_PUBLIC_WS_MODE=live 로 실제 NestJS 백엔드에, 그 외에는 Mock 데모로 동작한다. */
export function createEventSource(): AgentEventSource {
  const mode = process.env.NEXT_PUBLIC_WS_MODE ?? 'mock';
  return mode === 'live' ? new SocketIoEventSource() : new MockEventSource();
}
