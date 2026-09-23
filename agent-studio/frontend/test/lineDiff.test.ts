import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lineDiff } from '../src/lib/lineDiff.ts';

const show = (a: string, b: string) => lineDiff(a, b).map((l) => `${l.op}${l.text}`);

test('바뀐 줄만 -/+로, 같은 줄은 그대로', () => {
  assert.deepEqual(show('a\nb\nc', 'a\nB\nc'), [' a', '-b', '+B', ' c']);
});

test('추가·삭제만 있는 경우', () => {
  assert.deepEqual(show('a\nc', 'a\nb\nc'), [' a', '+b', ' c']);
  assert.deepEqual(show('a\nb\nc', 'a\nc'), [' a', '-b', ' c']);
});

test('빈 글에서 새로 쓰기 / 전부 지우기', () => {
  assert.deepEqual(show('', 'x\ny'), ['+x', '+y']);
  assert.deepEqual(show('x', ''), ['-x']);
  assert.deepEqual(show('', ''), []);
});

test('아주 긴 글은 LCS 없이 지운 줄 전체 → 넣은 줄 전체', () => {
  const big = Array.from({ length: 700 }, (_, i) => `line ${i}`).join('\n');
  const out = lineDiff(big, `${big}\nmore`);
  assert.equal(out.length, 700 + 701);
  assert.ok(out.slice(0, 700).every((l) => l.op === '-'));
  assert.ok(out.slice(700).every((l) => l.op === '+'));
});
