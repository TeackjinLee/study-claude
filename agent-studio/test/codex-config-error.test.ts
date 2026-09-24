import { test } from 'node:test';
import assert from 'node:assert/strict';
import { codexConfigError } from '../src/agent/codex-bridge.service.js';

test('쓸 수 없는 모델 오류는 설정 오류로 알아보고 /codex-model 안내를 준다', () => {
  const real = `{"type":"error","status":400,"error":{"type":"invalid_request_error","message":"The 'gpt-6-astra' model is not supported when using Codex with a ChatGPT account."}}`;
  const msg = codexConfigError(real, 'gpt-6-astra');
  assert.ok(msg && msg.includes('gpt-6-astra') && msg.includes('/codex-model'), String(msg));
  assert.ok(codexConfigError(real)?.includes('gpt-6-astra'), '설정값이 없어도 메시지에서 모델 이름을 뽑는다');
  assert.ok(codexConfigError('model_not_found: The model `foo-1` does not exist'));
});

test('다른 오류(네트워크, 한도, 인증)는 설정 오류가 아니다 — 재시도 판단은 총괄에게 맡긴다', () => {
  for (const m of ['stream disconnected before completion', 'rate limit reached, retry in 20s', '401 Unauthorized']) {
    assert.equal(codexConfigError(m), null, m);
  }
});
