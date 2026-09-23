import { dataDir } from './helpers/temp-data-dir.js';
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdir, mkdtemp, readFile, rm, unlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { CheckpointService } from '../src/agent/checkpoint.service.js';
import { GitService } from '../src/agent/git.service.js';
import type { SettingsService } from '../src/agent/settings.service.js';
import type { CostTrackerService } from '../src/agent/cost-tracker.service.js';

let root = '';
let ws = '';
let cps: CheckpointService;
const sh = (...args: string[]) => execFileSync('git', args, { cwd: root, encoding: 'utf8' });
const read = (p: string) => readFile(join(ws, p), 'utf8');

before(async () => {
  root = await mkdtemp(join(tmpdir(), 'agent-studio-cp-'));
  ws = join(root, 'ws');
  await mkdir(ws);
  sh('init', '-q', '-b', 'main');
  sh('config', 'user.email', 't@example.com');
  sh('config', 'user.name', 't');
  await writeFile(join(ws, 'a.txt'), 'a1\n');
  await writeFile(join(ws, 'b.txt'), 'b1\n');
  await writeFile(join(ws, '.gitignore'), 'cache/\n');
  sh('add', '-A');
  sh('commit', '-q', '-m', 'init');
  const settings = { workspaceDir: ws } as unknown as SettingsService;
  cps = new CheckpointService(new GitService(settings, {} as CostTrackerService));
});

after(async () => {
  await rm(root, { recursive: true, force: true });
  await rm(dataDir, { recursive: true, force: true });
});

test('실행이 바꾼 파일(수정·새 파일·삭제)을 실행 전으로 되돌리고, 스테이징은 그대로 둔다', async () => {
  // 실행 전부터 있던 사용자 변경: 커밋 안 한 수정 + 스테이징
  await writeFile(join(ws, 'b.txt'), 'b-user\n');
  sh('add', 'ws/b.txt');
  const staged = sh('diff', '--cached', '--name-only');

  const start = await cps.capture();
  assert.ok(start);
  await writeFile(join(ws, 'a.txt'), 'a-agent\n');
  await writeFile(join(ws, 'new.txt'), 'new\n');
  await unlink(join(ws, 'b.txt'));
  await mkdir(join(ws, 'cache'));
  await writeFile(join(ws, 'cache', 'x.bin'), 'ignored');
  const end = await cps.capture();
  const cp = await cps.record(start, end!, { command: 'test' });
  assert.ok(cp);
  assert.deepEqual(
    cp.files.map((f) => `${f.status}:${f.path}`).sort(),
    ['added:new.txt', 'deleted:b.txt', 'modified:a.txt'],
    '.gitignore에 걸린 파일은 대상이 아니다',
  );

  const res = await cps.undo(cp.id);
  assert.equal(res.ok, true, res.error);
  assert.equal(res.complete, true);
  assert.equal(await read('a.txt'), 'a1\n');
  assert.equal(await read('b.txt'), 'b-user\n', '실행 전의 (커밋 안 한) 사용자 내용으로 돌아온다');
  assert.equal(existsSync(join(ws, 'new.txt')), false);
  assert.equal(sh('diff', '--cached', '--name-only'), staged, '실제 인덱스(스테이징)는 건드리지 않는다');
});

test('실행 뒤에 다시 바뀐 파일은 건너뛰고, force면 덮어쓴다', async () => {
  const start = await cps.capture();
  await writeFile(join(ws, 'a.txt'), 'a-run\n');
  await writeFile(join(ws, 'c.txt'), 'c-run\n');
  const cp = await cps.record(start!, (await cps.capture())!, { command: 'run2' });
  assert.ok(cp);
  // 실행 뒤 사용자가 a.txt를 또 고침
  await writeFile(join(ws, 'a.txt'), 'a-later\n');

  const first = await cps.undo(cp.id);
  assert.equal(first.ok, true);
  assert.equal(first.complete, false);
  assert.deepEqual(first.restored, ['c.txt']);
  assert.deepEqual(first.skipped.map((s) => s.path), ['a.txt']);
  assert.equal(await read('a.txt'), 'a-later\n');
  assert.equal(existsSync(join(ws, 'c.txt')), false);

  const forced = await cps.undo(cp.id, true);
  assert.equal(forced.complete, true);
  assert.deepEqual(forced.restored, ['a.txt']);
  assert.equal(await read('a.txt'), 'a1\n');
});

test('바뀐 파일이 없으면 체크포인트를 만들지 않는다', async () => {
  const a = await cps.capture();
  const b = await cps.capture();
  assert.equal(await cps.record(a!, b!, { command: 'noop' }), null);
});
