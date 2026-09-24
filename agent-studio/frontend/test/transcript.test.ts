import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyTx, txNotice, txPermission, txPermissionDone, txResult, txUser, type TxItem } from '../src/store/transcript.ts';
import type { PermissionRequest, TxEvent } from '../src/lib/ws/types.ts';

const run = (events: TxEvent[], start: TxItem[] = []) => events.reduce(applyTx, start);
const kinds = (items: TxItem[]) => items.map((i) => i.kind);
const texts = (items: TxItem[]) => items.flatMap((i) => (i.kind === 'text' ? [i] : []));

test('명령 → 글 → 도구 시작/끝 순서로 쌓이고, 도구 결과는 제자리에서 바뀐다', () => {
  let items = txUser([], '로그인 고쳐줘', { mode: 'code' });
  items = run(
    [
      { t: 'text', agent: 'main', text: '먼저 파일을 볼게요.' },
      { t: 'tool_start', id: 't1', agent: 'main', tool: 'Read', label: '파일 읽기' },
      { t: 'tool_done', id: 't1', ok: true, output: 'ok' },
    ],
    items,
  );
  assert.deepEqual(kinds(items), ['user', 'text', 'tool']);
  const tool = items[2];
  assert.ok(tool.kind === 'tool' && tool.status === 'ok' && tool.output === 'ok');
});

test('같은 id의 도구·에이전트·체크포인트가 다시 와도 한 번만 들어간다 (다시 연결해 재생할 때)', () => {
  const start: TxEvent = { t: 'tool_start', id: 't1', agent: 'main', tool: 'Bash', label: 'npm test' };
  const cp: TxEvent = { t: 'checkpoint', id: 'c1', files: [{ path: 'a.ts', status: 'modified' }] };
  const items = run([start, start, cp, cp]);
  assert.deepEqual(kinds(items), ['tool', 'checkpoint']);
});

test('같은 주인의 글이 연달아 오면 한 덩어리로 붙인다', () => {
  const items = run([
    { t: 'text', agent: 'main', text: '첫째' },
    { t: 'text', agent: 'main', text: '둘째' },
  ]);
  assert.equal(items.length, 1);
  assert.equal(texts(items)[0].text, '첫째\n\n둘째');
});

test('실시간 글: 조각은 draft에 이어 붙고, 완성된 글이 오면 draft를 대체한다', () => {
  let items = run([
    { t: 'text_delta', agent: 'main', text: '파일을 ' },
    { t: 'text_delta', agent: 'main', text: '볼게요' },
  ]);
  assert.equal(items.length, 1);
  assert.deepEqual({ text: texts(items)[0].text, draft: texts(items)[0].draft }, { text: '', draft: '파일을 볼게요' });
  items = run([{ t: 'text', agent: 'main', text: '파일을 볼게요.' }], items);
  assert.deepEqual({ text: texts(items)[0].text, draft: texts(items)[0].draft }, { text: '파일을 볼게요.', draft: undefined });
  // 두 번째 블록은 같은 항목의 draft로 이어지고, 완성되면 앞 글에 붙는다
  items = run(
    [
      { t: 'text_delta', agent: 'main', text: '고쳤어요' },
      { t: 'text', agent: 'main', text: '고쳤어요.' },
    ],
    items,
  );
  assert.equal(items.length, 1);
  assert.equal(texts(items)[0].text, '파일을 볼게요.\n\n고쳤어요.');
});

test('실행이 중단되면 쓰다 만 글은 받은 데까지 남기고, 도는 중이던 도구는 실패로 표시한다', () => {
  let items = run([
    { t: 'tool_start', id: 't1', agent: 'main', tool: 'Bash', label: 'npm test' },
    { t: 'text_delta', agent: 'main', text: '테스트를 돌리는 ' },
  ]);
  items = txNotice(items, 'warn', '사용자가 중단했습니다.');
  assert.deepEqual(kinds(items), ['tool', 'text', 'notice']);
  const [tool, text] = items;
  assert.ok(tool.kind === 'tool' && tool.status === 'error');
  assert.ok(text.kind === 'text' && text.text === '테스트를 돌리는' && text.draft === undefined);
});

test('빈 draft만 남은 글은 실행이 끝나면 지운다', () => {
  const items = txNotice(run([{ t: 'text_delta', agent: 'main', text: '  ' }]), 'error', '오류');
  assert.deepEqual(kinds(items), ['notice']);
});

test('결과: 마지막 글과 같은 요약은 다시 싣지 않고 통계만, 실패면 사유를 싣는다', () => {
  const base = run([{ t: 'text', agent: 'main', text: '완료했습니다.' }]);
  const ok = txResult(base, { ok: true, result: '완료했습니다.', costUsd: 0.1, turns: 3, durationMs: 1000 });
  const last = ok[ok.length - 1];
  assert.ok(last.kind === 'result' && last.text === undefined && last.turns === 3);
  const fail = txResult(base, { ok: false, result: '비용 한도에 도달했습니다.', costUsd: 0.1, turns: 3, durationMs: 1000 });
  const lastFail = fail[fail.length - 1];
  assert.ok(lastFail.kind === 'result' && lastFail.text === '비용 한도에 도달했습니다.');
});

test('할 일 목록은 이번 명령 안에서는 제자리에서 갱신되고, 다음 명령에서는 새로 생긴다', () => {
  const plan = (status: 'pending' | 'completed'): TxEvent => ({ t: 'plan', items: [{ text: '테스트', status }] });
  let items = run([plan('pending'), { t: 'text', agent: 'main', text: '진행 중' }, plan('completed')], txUser([], '첫 명령'));
  assert.deepEqual(kinds(items), ['user', 'plan', 'text']);
  const p = items[1];
  assert.ok(p.kind === 'plan' && p.items[0].status === 'completed');
  items = run([plan('pending')], txUser(items, '두 번째 명령'));
  assert.equal(items.filter((i) => i.kind === 'plan').length, 2);
});

test('reset이면 새 명령에서 대화를 비운다 (이어가지 않는 실행)', () => {
  const items = txUser(txUser([], '예전 명령'), '새 명령', { reset: true });
  assert.equal(items.length, 1);
  assert.ok(items[0].kind === 'user' && items[0].text === '새 명령');
});

test('되돌리기 결과는 복원한 파일을 모아 체크포인트에 반영한다', () => {
  const files = [
    { path: 'a.ts', status: 'modified' as const },
    { path: 'b.ts', status: 'added' as const },
  ];
  let items = run([{ t: 'checkpoint', id: 'c1', files }]);
  items = run([{ t: 'checkpoint_undone', id: 'c1', restored: ['a.ts'], skipped: [{ path: 'b.ts', reason: '다시 바뀜' }], complete: false }], items);
  items = run([{ t: 'checkpoint_undone', id: 'c1', restored: ['b.ts'], skipped: [], complete: true }], items);
  const cp = items[0];
  assert.ok(cp.kind === 'checkpoint');
  assert.deepEqual(cp.restored, ['a.ts', 'b.ts']);
  assert.equal(cp.complete, true);
  assert.deepEqual(cp.skipped, []);
});

test('압축 경계는 대화에 한 줄로 남는다', () => {
  const items = run([{ t: 'compacted', trigger: 'auto', preTokens: 150_000, postTokens: 9_000 }]);
  assert.deepEqual(items.map((i) => (i.kind === 'compact' ? [i.trigger, i.preTokens, i.postTokens] : null)), [['auto', 150_000, 9_000]]);
});

test('승인 요청: 기다리는 중 → 답하면 허용/거부로, 답하지 않고 실행이 끝나면 끝남으로', () => {
  const req = (id: string): PermissionRequest => ({ id, agent: 'system', tool: 'Bash', title: 'npm test', detail: '', canAlwaysAllow: true });
  let items = txPermission(txPermission([], req('p1')), req('p1'));
  assert.equal(items.length, 1, '같은 요청은 한 번만');
  items = txPermission(items, req('p2'));
  items = txPermission(items, req('p3'));
  items = txPermissionDone(items, ['p1'], true);
  items = txPermissionDone(items, ['p2'], false);
  // 이미 답한 요청에 서버 응답이 뒤늦게 와도 그대로
  items = txPermissionDone(items, ['p1'], false);
  items = txNotice(items, 'warn', '중단');
  const status = Object.fromEntries(items.flatMap((i) => (i.kind === 'permission' ? [[i.id, i.status]] : [])));
  assert.deepEqual(status, { p1: 'allowed', p2: 'denied', p3: 'expired' });
});

test('사무실에서 에이전트에게 직접 한 말은 대상이 붙은 사용자 입력으로', () => {
  const items = run([{ t: 'user_to', agent: 'plan', text: '안녕?' }]);
  assert.ok(items[0].kind === 'user' && items[0].to === 'plan' && items[0].text === '안녕?');
});

test('실행 도중 알림(notice)은 도는 중인 도구를 멈춘 것으로 바꾸지 않는다', () => {
  const items = run([
    { t: 'tool_start', id: 't1', agent: 'main', tool: 'Bash', label: 'npm test' },
    { t: 'notice', tone: 'error', text: 'Codex 모델을 쓸 수 없습니다' },
  ]);
  assert.deepEqual(kinds(items), ['tool', 'notice']);
  assert.ok(items[0].kind === 'tool' && items[0].status === 'running');
});
