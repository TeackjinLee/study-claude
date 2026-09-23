import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as sleep } from 'node:timers/promises';
import { InputQueue, RunCompletion } from '../src/agent/input-queue.js';

test('InputQueue: 넣은 순서대로 꺼내고, 닫으면 끝난다', async () => {
  const q = new InputQueue<number>();
  q.push(1);
  const seen: number[] = [];
  const consumer = (async () => {
    for await (const n of q) seen.push(n);
  })();
  await sleep(5);
  q.push(2); // 기다리는 중에 들어온 값
  q.push(3);
  q.close();
  await consumer;
  assert.deepEqual(seen, [1, 2, 3]);
  assert.equal(q.push(4), false);
});

test('RunCompletion: 추가 지시가 없으면 결과에서 바로 끝', () => {
  let finished = 0;
  const c = new RunCompletion(() => finished++, 20);
  c.result();
  assert.equal(finished, 1);
  c.result();
  assert.equal(finished, 1, '두 번 끝나지 않는다');
});

test('RunCompletion: 추가 지시가 이번 턴에 합쳐지면 조용해진 뒤 끝', async () => {
  let finished = 0;
  const c = new RunCompletion(() => finished++, 20);
  c.followUp();
  c.result();
  assert.equal(finished, 0);
  await sleep(40);
  assert.equal(finished, 1);
});

test('RunCompletion: 추가 지시가 다음 턴이 되면 그 결과까지 기다린다', async () => {
  let finished = 0;
  const c = new RunCompletion(() => finished++, 20);
  c.followUp();
  c.result();
  c.activity(); // 새 턴 시작
  await sleep(40);
  assert.equal(finished, 0, '새 턴 중에는 끝나지 않는다');
  c.result();
  assert.equal(finished, 1);
});

test('RunCompletion: 세션 idle 신호면 기다리지 않고 끝', () => {
  let finished = 0;
  const c = new RunCompletion(() => finished++, 10_000);
  c.followUp();
  c.result();
  c.idle();
  assert.equal(finished, 1);
});
