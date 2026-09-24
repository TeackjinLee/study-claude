import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { REFERENCE_TOOL, resolveReferenceImage } from '../src/agent/reference-tool.js';

const ws = await mkdtemp(join(tmpdir(), 'ref-tool-'));
await mkdir(join(ws, 'docs/refs'), { recursive: true });
await writeFile(join(ws, 'docs/refs/karaoke-1.png'), 'png');
await writeFile(join(ws, 'docs/refs/notes.txt'), 'x');
after(() => rm(ws, { recursive: true, force: true }));

test('도구 이름은 러너가 가로채는 이름과 같다', () => {
  assert.equal(REFERENCE_TOOL, 'mcp__studio__confirm_reference');
});

test('작업 폴더 안의 실제 이미지만 레퍼런스로 받는다', async () => {
  assert.deepEqual(await resolveReferenceImage(ws, 'docs/refs/karaoke-1.png'), { ok: true, rel: 'docs/refs/karaoke-1.png' });
  assert.deepEqual(await resolveReferenceImage(ws, join(ws, 'docs/refs/karaoke-1.png')), { ok: true, rel: 'docs/refs/karaoke-1.png' }, '절대 경로도 작업 폴더 안이면');
  for (const bad of ['', undefined, 'docs/refs/none.png', 'docs/refs/notes.txt', '../outside.png', '/etc/passwd', 'docs/refs']) {
    const r = await resolveReferenceImage(ws, bad);
    assert.equal(r.ok, false, String(bad));
  }
});
