import { Logger } from '@nestjs/common';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayInit,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import type { Server, Socket } from 'socket.io';
import { AgentRunnerService } from './agent-runner.service.js';
import { AgentRegistryService } from './agent-registry.service.js';
import { access } from '../access/access.service.js';

/**
 * 화면 → 서버
 *   command            { prompt, mode, planFirst, attachments }  작업 시작 (ack로 성공/실패 응답)
 *   follow-up          { prompt }            실행 도중 추가 지시 끼워 넣기
 *   new-conversation   { mode? }             코드·채팅의 이어갈 대화를 비우고 새로 시작
 *   undo-checkpoint    { id, force? }        실행 되돌리기 (그 실행이 바꾼 파일을 실행 전으로)
 *   interrupt                                  작업 중지
 *   permission-reply   { id, allowed, always } 권한 요청에 대한 답
 *
 * 서버 → 화면
 *   hello        접속 직후 현재 상태 스냅샷
 *   agent-event  UiEvent (ui-events.ts)
 */
@WebSocketGateway({
  cors: {
    origin: (origin: string | undefined, cb: (err: Error | null, ok?: boolean) => void) => cb(null, access.originAllowed(origin)),
    credentials: true,
  },
})
export class AgentGateway implements OnGatewayInit, OnGatewayConnection {
  private readonly logger = new Logger(AgentGateway.name);

  @WebSocketServer()
  server: Server;

  constructor(
    private readonly runner: AgentRunnerService,
    private readonly registry: AgentRegistryService,
  ) {}

  afterInit(server: Server) {
    // 웹소켓은 CORS 검사를 받지 않으므로 Origin을 직접 본다 (이 컴퓨터에서 연 다른 웹사이트가 localhost로 붙지 못하게).
    // 원격 접속: 이 컴퓨터가 아니면 로그인 쿠키가 있어야 연결된다 (화면은 connect_error 'unauthorized'로 로그인 창을 띄운다)
    server.use((socket, next) => {
      const { address, headers } = socket.handshake;
      if (!access.originAllowed(headers.origin)) return next(new Error('forbidden origin'));
      return access.allows(address, headers.cookie) ? next() : next(new Error('unauthorized'));
    });
    this.runner.subscribe((event) => this.server.emit('agent-event', event));
    this.registry.subscribe((agents) => this.server.emit('agents-changed', { agents }));
  }

  handleConnection(client: Socket) {
    this.logger.log(`대시보드 연결: ${client.id}`);
    client.emit('hello', this.runner.snapshot());
  }

  @SubscribeMessage('command')
  handleCommand(@MessageBody() body: { prompt?: unknown; attachments?: unknown; mode?: unknown; planFirst?: unknown } | undefined) {
    return this.runner.start(body?.prompt, body?.attachments, body?.mode, body?.planFirst);
  }

  @SubscribeMessage('follow-up')
  handleFollowUp(@MessageBody() body: { prompt?: unknown } | undefined) {
    return this.runner.followUp(body?.prompt);
  }

  @SubscribeMessage('new-conversation')
  handleNewConversation(@MessageBody() body: { mode?: unknown } | undefined) {
    return this.runner.newConversation(body?.mode);
  }

  @SubscribeMessage('undo-checkpoint')
  handleUndo(@MessageBody() body: { id?: unknown; force?: unknown } | undefined) {
    return this.runner.undoCheckpoint(body?.id, body?.force);
  }

  @SubscribeMessage('interrupt')
  handleInterrupt() {
    return { ok: this.runner.interrupt() };
  }

  @SubscribeMessage('permission-reply')
  handlePermission(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: { id?: unknown; allowed?: unknown; always?: unknown } | undefined,
  ) {
    const ok = this.runner.replyPermission(body?.id, body?.allowed, body?.always);
    if (!ok) this.logger.warn(`처리할 수 없는 권한 응답 (${client.id})`);
    return { ok };
  }
}
