import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { SDKMessage } from '@anthropic-ai/claude-agent-sdk';
import { MessageMapper, visibleDraft } from '../src/agent/message-mapper.js';
import type { UiEventBody } from '../src/agent/ui-events.js';

function setup() {
  const events: UiEventBody[] = [];
  const mapper = new MessageMapper((e) => events.push(e), '/tmp/ws', () => null);
  const send = (msg: unknown) => mapper.handle(msg as SDKMessage);
  const stream = (event: unknown) => send({ type: 'stream_event', event, parent_tool_use_id: null });
  const texts = (type: 'assistant_delta' | 'assistant_text') => events.filter((e) => e.type === type).map((e) => (e as { text: string }).text);
  return { events, send, stream, texts };
}

const assistant = (id: string, text: string) => ({ type: 'assistant', parent_tool_use_id: null, message: { id, content: [{ type: 'text', text }] } });

test('visibleDraft: <next-steps> 뒤와 태그의 앞부분은 보내지 않는다', () => {
  assert.equal(visibleDraft('안녕하세요'), '안녕하세요');
  assert.equal(visibleDraft('끝났습니다.\n\n<next-st'), '끝났습니다.\n\n');
  assert.equal(visibleDraft('끝났습니다.\n\n<next-steps>\n- 테스트'), '끝났습니다.');
  assert.equal(visibleDraft('a < b 입니다'), 'a < b 입니다');
  assert.equal(visibleDraft('<div>'), '<div>');
});

test('글 조각을 바로 보내고, 블록이 끝나면 전체 글을 한 번만 보낸다', () => {
  const { stream, send, texts } = setup();
  stream({ type: 'message_start', message: { id: 'm1' } });
  stream({ type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } });
  stream({ type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: '파일을 ' } });
  stream({ type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: '살펴볼게요.' } });
  assert.deepEqual(texts('assistant_delta'), ['파일을 ', '살펴볼게요.']);
  assert.deepEqual(texts('assistant_text'), []);
  stream({ type: 'content_block_stop', index: 0 });
  assert.deepEqual(texts('assistant_text'), ['파일을 살펴볼게요.']);
  // 완성된 메시지가 뒤에 와도 같은 글을 다시 내보내지 않는다
  send(assistant('m1', '파일을 살펴볼게요.'));
  assert.deepEqual(texts('assistant_text'), ['파일을 살펴볼게요.']);
});

test('완성된 메시지가 블록 끝보다 먼저 오면 그쪽만 내보낸다', () => {
  const { stream, send, texts } = setup();
  stream({ type: 'message_start', message: { id: 'm2' } });
  stream({ type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } });
  stream({ type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: '완료' } });
  send(assistant('m2', '완료'));
  stream({ type: 'content_block_stop', index: 0 });
  assert.deepEqual(texts('assistant_text'), ['완료']);
});

test('<next-steps>는 조각으로도 보내지 않고 전체 글에서도 뗀다', () => {
  const { stream, texts } = setup();
  stream({ type: 'message_start', message: { id: 'm3' } });
  stream({ type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } });
  for (const part of ['고쳤습니다.', '\n\n<next', '-steps>\n- 테스트 실행\n</next-steps>']) {
    stream({ type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: part } });
  }
  stream({ type: 'content_block_stop', index: 0 });
  assert.equal(texts('assistant_delta').join(''), '고쳤습니다.\n\n');
  assert.deepEqual(texts('assistant_text'), ['고쳤습니다.']);
});

test('스트리밍 없이 온 메시지는 전처럼 글을 내보낸다', () => {
  const { send, texts } = setup();
  send(assistant('m4', '안녕'));
  send(assistant('m5', '안녕'));
  assert.deepEqual(texts('assistant_text'), ['안녕', '안녕']);
});

test('압축 경계(compact_boundary)를 compacted 이벤트로', () => {
  const { send, events } = setup();
  send({ type: 'system', subtype: 'compact_boundary', compact_metadata: { trigger: 'auto', pre_tokens: 150_000, post_tokens: 12_000 } });
  assert.deepEqual(events, [{ type: 'compacted', trigger: 'auto', preTokens: 150_000, postTokens: 12_000 }]);
});
