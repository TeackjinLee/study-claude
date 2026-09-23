import { test } from 'node:test';
import assert from 'node:assert/strict';
import { atQuery } from '../src/lib/atQuery.ts';
import { slashQuery } from '../src/lib/slashQuery.ts';

test('atQuery: 커서 바로 앞의 @검색어', () => {
  assert.deepEqual(atQuery('@', 1), { start: 0, query: '' });
  assert.deepEqual(atQuery('이 파일 봐줘 @veh', 12), { start: 8, query: 'veh' });
  assert.deepEqual(atQuery('@scripts/', 9), { start: 0, query: 'scripts/' });
  // 줄바꿈 뒤도 된다
  assert.deepEqual(atQuery('첫 줄\n@a', 6), { start: 4, query: 'a' });
});

test('atQuery: 이메일·공백 뒤·커서가 다른 곳이면 없음', () => {
  assert.equal(atQuery('a@b.com', 7), null, '@ 앞이 공백이 아니면 이메일로 본다');
  assert.equal(atQuery('@abc 다음', 7), null, '이미 공백을 쳐서 끝난 참조');
  assert.deepEqual(atQuery('@abc 다음', 2), { start: 0, query: 'a' }, '커서 앞까지만 본다');
  assert.equal(atQuery('평범한 글', 5), null);
});

test('slashQuery: 명령 이름 입력 중', () => {
  assert.deepEqual(slashQuery('/'), { query: '', scope: null });
  assert.deepEqual(slashQuery('/Mod'), { query: 'mod', scope: null });
  assert.deepEqual(slashQuery('/codex /re'), { query: 're', scope: 'codex' });
});

test('slashQuery: 인자를 한 토큰 입력 중', () => {
  assert.deepEqual(slashQuery('/model op'), { query: 'model', scope: null, arg: 'op' });
  assert.deepEqual(slashQuery('/model '), { query: 'model', scope: null, arg: '' });
  assert.deepEqual(slashQuery('/codex /model gpt'), { query: 'model', scope: 'codex', arg: 'gpt' });
});

test('slashQuery: 슬래시 명령이 아니거나 인자를 두 개 이상 치면 없음', () => {
  assert.equal(slashQuery('안녕'), null);
  assert.equal(slashQuery('/talk @a 안녕 하세요'), null);
  assert.equal(slashQuery(' /model'), null);
});
