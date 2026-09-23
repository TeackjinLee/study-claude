import { test } from 'node:test';
import assert from 'node:assert/strict';
import { rankFiles, withDirs } from '../src/agent/file-search.js';

const files = ['README.md', 'scripts/vehicle/vehicle_controller.gd', 'scripts/vehicle/vehicle_stats.gd', 'scripts/player.gd', 'data/sedan.tres', 'docs/vehicles.md'];
const all = withDirs(files);
const paths = (q: string) => rankFiles(all, q).map((c) => c.path);

test('폴더도 후보에 넣는다 (끝에 /)', () => {
  assert.ok(all.some((c) => c.dir && c.path === 'scripts/vehicle/'));
  assert.ok(all.some((c) => c.dir && c.path === 'scripts/'));
});

test('검색어가 없으면 맨 위 항목만, 폴더 먼저', () => {
  assert.deepEqual(paths(''), ['data/', 'docs/', 'scripts/', 'README.md']);
});

test('이름이 검색어로 시작하는 것이 먼저, 그다음 포함, 경로, 글자 순서', () => {
  const r = paths('vehicle');
  assert.deepEqual(r.slice(0, 2).sort(), ['docs/vehicles.md', 'scripts/vehicle/'], '이름이 일치하는 얕은 항목이 먼저');
  assert.ok(r.indexOf('scripts/vehicle/vehicle_stats.gd') > r.indexOf('scripts/vehicle/'), '깊은 파일은 뒤');
  assert.deepEqual(paths('sedan'), ['data/sedan.tres']);
  assert.ok(paths('vcon').includes('scripts/vehicle/vehicle_controller.gd'), '글자 순서 일치');
  assert.deepEqual(paths('없는파일'), []);
});

test('검색어에 /가 있으면 경로로 찾는다', () => {
  assert.deepEqual(paths('scripts/p'), ['scripts/player.gd']);
  assert.ok(!paths('scripts/').includes('scripts/'), '다 친 폴더 자신은 빼고 그 안의 항목만');
  assert.ok(paths('scripts/').includes('scripts/vehicle/'));
});
