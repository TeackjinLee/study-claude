import { test } from 'node:test';
import assert from 'node:assert/strict';
import { addToHistory, onFirstLine, onLastLine, stepHistory } from '../src/lib/inputHistory.ts';

test('addToHistory: 빈 글·바로 앞과 같은 글은 넣지 않고, 최대 개수를 넘으면 오래된 것부터 버린다', () => {
  let list: string[] = [];
  list = addToHistory(list, '  첫 명령  ');
  list = addToHistory(list, '첫 명령');
  list = addToHistory(list, '   ');
  list = addToHistory(list, '둘째');
  list = addToHistory(list, '첫 명령');
  assert.deepEqual(list, ['첫 명령', '둘째', '첫 명령'], '바로 앞만 아니면 같은 글도 다시 넣는다');
  assert.deepEqual(addToHistory(['a', 'b', 'c'], 'd', 3), ['b', 'c', 'd']);
});

test('stepHistory: ↑는 가장 최근부터 오래된 쪽으로 가다 끝에서 멈추고, ↓는 초안(-1)까지 돌아온다', () => {
  assert.equal(stepHistory(3, -1, 'up'), 0);
  assert.equal(stepHistory(3, 0, 'up'), 1);
  assert.equal(stepHistory(3, 2, 'up'), 2, '가장 오래된 것에서 멈춤');
  assert.equal(stepHistory(3, 1, 'down'), 0);
  assert.equal(stepHistory(3, 0, 'down'), -1, '초안으로 돌아옴');
  assert.equal(stepHistory(3, -1, 'down'), -1);
  assert.equal(stepHistory(0, -1, 'up'), -1, '기록이 없으면 그대로');
});

test('커서가 첫 줄·마지막 줄에 있을 때만 ↑/↓가 기록을 부른다 (여러 줄 글에서는 줄 이동)', () => {
  const text = '첫 줄\n둘째 줄';
  assert.equal(onFirstLine(text, 2), true);
  assert.equal(onFirstLine(text, text.length), false);
  assert.equal(onLastLine(text, text.length), true);
  assert.equal(onLastLine(text, 1), false);
  assert.equal(onFirstLine('', 0) && onLastLine('', 0), true);
});
