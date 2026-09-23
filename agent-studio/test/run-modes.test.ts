import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseRunMode, runModeProfile } from '../src/agent/run-modes.js';

test('모르는 모드는 기본인 코드 모드', () => {
  assert.equal(parseRunMode(undefined), 'code');
  assert.equal(parseRunMode('nope'), 'code');
  assert.equal(parseRunMode('chat'), 'chat');
  assert.equal(parseRunMode('cowork'), 'cowork');
});

test('코드 모드: 서브에이전트만 막고 수정·실행은 허용, 대화를 이어간다', () => {
  const p = runModeProfile('code');
  assert.equal(p.resumable, true);
  assert.equal(p.subagents, false);
  assert.equal(p.codex, false);
  assert.equal(p.canPlan, true);
  for (const tool of ['Agent', 'Task']) assert.ok(p.disallowedTools?.includes(tool), tool);
  for (const tool of ['Edit', 'Write', 'Bash', 'TodoWrite', 'ExitPlanMode']) assert.ok(!p.disallowedTools?.includes(tool), tool);
});

test('채팅 모드: 읽기 전용, 계획 먼저 불가', () => {
  const p = runModeProfile('chat');
  assert.equal(p.resumable, true);
  assert.equal(p.canPlan, false);
  for (const tool of ['Edit', 'Write', 'Bash', 'Agent', 'ExitPlanMode']) assert.ok(p.disallowedTools?.includes(tool), tool);
  for (const tool of ['Read', 'Grep', 'Glob']) assert.ok(!p.disallowedTools?.includes(tool), tool);
});

test('Cowork 모드: 서브에이전트·Codex, 매번 새 세션', () => {
  const p = runModeProfile('cowork');
  assert.equal(p.resumable, false);
  assert.equal(p.subagents, true);
  assert.equal(p.codex, true);
  assert.equal(p.disallowedTools, undefined);
});
