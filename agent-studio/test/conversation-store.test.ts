import { dataDir } from './helpers/temp-data-dir.js';
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { rm } from 'node:fs/promises';
import { join } from 'node:path';
import { ConversationStoreService } from '../src/agent/conversation-store.service.js';
import type { UiEvent } from '../src/agent/ui-events.js';

after(async () => {
  await rm(dataDir, { recursive: true, force: true });
});

const ev = (e: Record<string, unknown>, at = Date.now()) => ({ ...e, at }) as UiEvent;

test('대화를 만들고 기록하면 재시작 뒤에도 이어갈 대화·기록이 남는다', async () => {
  const a = new ConversationStoreService();
  await a.ready;
  const c = a.create('code', '/ws', '로그인 API에 검증 추가해줘');
  a.setSession(c.id, 'session-1');
  a.append(c.id, ev({ type: 'run_start', command: '로그인 API에 검증 추가해줘', workspace: '/ws', mode: 'code' }));
  a.append(c.id, ev({ type: 'permission_request', id: 'p', agent: 'main', tool: 'Bash', title: '', detail: '', canAlwaysAllow: true }));
  a.append(c.id, ev({ type: 'run_done', ok: true, result: '완료', costUsd: 0.5, turns: 3, durationMs: 1000 }));
  await a.flush();

  const b = new ConversationStoreService();
  await b.ready;
  const active = b.activeFor('code', '/ws');
  assert.equal(active?.id, c.id);
  assert.equal(active?.sessionId, 'session-1');
  assert.equal(active?.runs, 1);
  assert.equal(active?.costUsd, 0.5);
  assert.equal(b.activeFor('code', '/other'), undefined, '다른 작업 폴더에서는 이어가지 않는다');
  assert.equal(b.activeFor('chat', '/ws'), undefined);
  const events = await b.loadEvents(c.id);
  assert.deepEqual(events.map((e) => e.type), ['run_start', 'run_done'], '승인 요청은 저장하지 않는다');
});

test('새 대화(setActive undefined)는 목록에 남기고, 지우면 파일도 사라진다', async () => {
  const s = new ConversationStoreService();
  await s.ready;
  const c = s.create('chat', '/ws', '질문');
  s.setActive('chat', undefined);
  await s.flush();
  assert.equal(s.activeFor('chat', '/ws'), undefined);
  assert.ok(s.list('/ws').some((m) => m.id === c.id));
  assert.ok(existsSync(join(dataDir, 'conversations', `${c.id}.json`)));
  assert.equal(await s.remove(c.id), true);
  await s.flush();
  assert.ok(!s.list().some((m) => m.id === c.id));
  assert.ok(!existsSync(join(dataDir, 'conversations', `${c.id}.json`)));
});

test('목록은 최근에 쓴 순서', async () => {
  const s = new ConversationStoreService();
  await s.ready;
  const old = s.create('code', '/ws2', '먼저');
  const recent = s.create('chat', '/ws2', '나중');
  s.append(old.id, ev({ type: 'run_start', command: 'x', workspace: '/ws2' }, 1000));
  s.append(recent.id, ev({ type: 'run_start', command: 'y', workspace: '/ws2' }, 2000));
  assert.deepEqual(s.list('/ws2').map((m) => m.title), ['나중', '먼저']);
  assert.equal(s.latestActive('/ws2')?.id, recent.id);
});

test('대화 상태 이벤트는 기록에 남기지 않는다 (다시 열 때 화면이 비워지지 않게)', async () => {
  const s = new ConversationStoreService();
  await s.ready;
  const c = s.create('code', '/ws3', '명령');
  s.append(c.id, ev({ type: 'run_start', command: '명령', workspace: '/ws3', mode: 'code' }));
  s.append(c.id, ev({ type: 'conversation', mode: 'code', active: false }));
  assert.deepEqual((await s.loadEvents(c.id)).map((e) => e.type), ['run_start']);
});

test('컨텍스트 사용량은 대화 정보로 저장되고, 압축 경계는 기록에 남는다', async () => {
  const a = new ConversationStoreService();
  await a.ready;
  const c = a.create('chat', '/ws-ctx', '구조 설명해줘');
  a.setContext(c.id, { tokens: 90_000, max: 200_000, pct: 45, at: 1 });
  a.append(c.id, ev({ type: 'context_usage', mode: 'chat', conversationId: c.id, context: { tokens: 1, max: 2, pct: 50, at: 1 } }));
  a.append(c.id, ev({ type: 'compacted', trigger: 'manual', preTokens: 90_000, postTokens: 9_000 }));
  await a.flush();

  const b = new ConversationStoreService();
  await b.ready;
  assert.deepEqual(b.get(c.id)?.context, { tokens: 90_000, max: 200_000, pct: 45, at: 1 });
  assert.deepEqual((await b.loadEvents(c.id)).map((e) => e.type), ['compacted']);
});
