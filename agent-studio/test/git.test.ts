import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { countDiff, looksLikeBranchName, newFileDiff, parsePorcelainZ, stripPrefix } from '../src/agent/git-utils.js';
import { GitService } from '../src/agent/git.service.js';
import type { SettingsService } from '../src/agent/settings.service.js';
import type { CostTrackerService } from '../src/agent/cost-tracker.service.js';

test('parsePorcelainZ: 수정·새 파일·삭제·이름 바꿈', () => {
  const out = [' M src/a.ts', '?? new.txt', 'D  old.ts', 'R  b2.ts', 'b.ts', 'A  added.ts', ''].join('\0');
  assert.deepEqual(parsePorcelainZ(out), [
    { path: 'src/a.ts', code: ' M', status: 'modified' },
    { path: 'new.txt', code: '??', status: 'untracked' },
    { path: 'old.ts', code: 'D ', status: 'deleted' },
    { path: 'b2.ts', from: 'b.ts', code: 'R ', status: 'renamed' },
    { path: 'added.ts', code: 'A ', status: 'added' },
  ]);
});

test('countDiff: 머리글(+++/---)은 세지 않는다', () => {
  const diff = ['diff --git a/x b/x', '--- a/x', '+++ b/x', '@@ -1,2 +1,2 @@', ' same', '-old', '+new', '+more'].join('\n');
  assert.deepEqual(countDiff(diff), { additions: 2, deletions: 1 });
  assert.deepEqual(countDiff(newFileDiff('n.txt', 'a\nb\n')), { additions: 2, deletions: 0 });
});

test('stripPrefix / looksLikeBranchName', () => {
  assert.equal(stripPrefix('ws/src/a.ts', 'ws/'), 'src/a.ts');
  assert.equal(stripPrefix('src/a.ts', ''), 'src/a.ts');
  assert.ok(looksLikeBranchName('feature/login-check'));
  assert.ok(!looksLikeBranchName('-rf'));
  assert.ok(!looksLikeBranchName('a..b'));
  assert.ok(!looksLikeBranchName('has space'));
});

// ── 실제 git 저장소로 GitService 확인 (작업 폴더가 저장소의 하위 폴더인 경우) ──
let root = '';
let workspace = '';
let git: GitService;
const sh = (...args: string[]) => execFileSync('git', args, { cwd: root, encoding: 'utf8' });

before(async () => {
  root = await mkdtemp(join(tmpdir(), 'agent-studio-git-'));
  workspace = join(root, 'ws');
  await mkdir(join(workspace, 'uploads'), { recursive: true });
  sh('init', '-q', '-b', 'main');
  sh('config', 'user.email', 'test@example.com');
  sh('config', 'user.name', 'test');
  await writeFile(join(workspace, 'a.txt'), 'one\ntwo\n');
  await writeFile(join(root, 'outside.txt'), 'x\n');
  sh('add', '-A');
  sh('commit', '-q', '-m', 'init');
  const settings = { workspaceDir: workspace, get: () => ({ workspaceDir: workspace }) } as unknown as SettingsService;
  const cost = { record: async () => undefined } as unknown as CostTrackerService;
  git = new GitService(settings, cost);
});

after(async () => {
  await rm(root, { recursive: true, force: true });
});

test('GitService: 작업 폴더 안의 변경만, 작업 폴더 기준 경로로 보여준다', async () => {
  await writeFile(join(workspace, 'a.txt'), 'one\nTWO\n');
  await writeFile(join(workspace, 'b.txt'), 'new\n');
  await writeFile(join(workspace, 'uploads', 'shot.png'), 'png');
  await writeFile(join(root, 'outside.txt'), 'changed\n');
  const res = await git.changes();
  assert.equal(res.repo, true);
  if (!res.repo) return;
  assert.equal(res.branch, 'main');
  const byPath = Object.fromEntries(res.files.map((f) => [f.path, f]));
  assert.deepEqual(Object.keys(byPath).sort(), ['a.txt', 'b.txt'], '저장소의 다른 폴더와 uploads/는 빠진다');
  assert.equal(byPath['a.txt'].status, 'modified');
  assert.deepEqual([byPath['a.txt'].additions, byPath['a.txt'].deletions], [1, 1]);
  assert.equal(byPath['b.txt'].status, 'untracked');
  assert.equal(byPath['b.txt'].additions, 1);
});

test('GitService: 되돌리기 — 수정은 복원, 새 파일은 삭제, 목록에 없는 경로는 거절', async () => {
  assert.equal((await git.revert('../outside.txt')).ok, false);
  assert.equal((await git.revert('a.txt')).ok, true);
  assert.equal(await readFile(join(workspace, 'a.txt'), 'utf8'), 'one\ntwo\n');
  assert.equal((await git.revert('b.txt')).ok, true);
  assert.equal(existsSync(join(workspace, 'b.txt')), false);
});

test('GitService: 새 브랜치에 고른 파일만 커밋', async () => {
  await writeFile(join(workspace, 'c.txt'), 'c\n');
  await writeFile(join(workspace, 'd.txt'), 'd\n');
  assert.equal((await git.commit({ message: 'x', branch: 'bad name' })).ok, false);
  const res = await git.commit({ message: 'c만 커밋', branch: 'feature/c', paths: ['c.txt'] });
  assert.equal(res.ok, true, res.error);
  assert.equal(res.branch, 'feature/c');
  assert.equal(sh('log', '-1', '--pretty=%s').trim(), 'c만 커밋');
  const left = await git.changes();
  assert.ok(left.repo && left.files.map((f) => f.path).includes('d.txt'));
  assert.ok(left.repo && !left.files.map((f) => f.path).includes('c.txt'));
});
