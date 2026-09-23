import { randomUUID } from 'node:crypto';
import { copyFile, mkdir, readFile, rename, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { Injectable, Logger } from '@nestjs/common';
import { config } from '../config.js';
import { GitService } from './git.service.js';
import { stripPrefix } from './git-utils.js';
import type { CheckpointFile } from './ui-events.js';

/** 작업 폴더의 한 시점 (저장소 루트 기준 git tree) */
export interface Snapshot {
  root: string;
  prefix: string;
  tree: string;
}

interface Checkpoint {
  id: string;
  at: number;
  command: string;
  conversationId?: string;
  root: string;
  prefix: string;
  /** 실행 전 / 실행 후 작업 폴더 */
  before: string;
  after: string;
  /** 이 실행이 바꾼 파일 (저장소 루트 기준) */
  files: { path: string; status: CheckpointFile['status'] }[];
  /** 되돌린 파일 (저장소 루트 기준). 전부 되돌리면 끝 */
  restored: string[];
}

export interface UndoResult {
  ok: boolean;
  error?: string;
  /** 작업 폴더 기준 경로 */
  restored: string[];
  skipped: { path: string; reason: string }[];
  /** 남은 파일 없이 전부 되돌렸는지 */
  complete: boolean;
}

const FILE = join(dirname(config.costFile), 'checkpoints.json');
const MAX_CHECKPOINTS = 50;
const STATUS: Record<string, CheckpointFile['status']> = { A: 'added', M: 'modified', D: 'deleted', T: 'modified' };

/**
 * 실행 단위 되돌리기.
 * 실행 시작·끝에 작업 폴더를 git tree로 찍어 두고(임시 인덱스라 사용자의 스테이징은 건드리지 않는다),
 * 되돌릴 때는 그 실행이 바꾼 파일만 실행 전 내용으로 돌린다. 그 뒤에 다시 바뀐 파일은 덮어쓰지 않고 건너뛴다.
 * 작업 폴더가 git 저장소가 아니면 쓰지 않는다. .gitignore에 걸린 파일은 대상이 아니다.
 */
@Injectable()
export class CheckpointService {
  private readonly logger = new Logger(CheckpointService.name);
  private checkpoints: Checkpoint[] = [];
  private readonly ready: Promise<void>;

  constructor(private readonly git: GitService) {
    this.ready = this.load();
  }

  private async load() {
    try {
      const raw = JSON.parse(await readFile(FILE, 'utf8')) as Checkpoint[];
      if (Array.isArray(raw)) this.checkpoints = raw;
    } catch {
      // 처음 실행
    }
  }

  private async save() {
    await mkdir(dirname(FILE), { recursive: true });
    const tmp = `${FILE}.${process.pid}.tmp`;
    await writeFile(tmp, JSON.stringify(this.checkpoints));
    await rename(tmp, FILE);
  }

  /** 지금 작업 폴더를 tree로 찍는다. 저장소가 아니거나 실패하면 null (실행은 그대로 진행) */
  async capture(): Promise<Snapshot | null> {
    const loc = await this.git.locate();
    if (!loc) return null;
    const { root, prefix } = loc;
    const index = join(tmpdir(), `agent-studio-index-${randomUUID()}`);
    try {
      // 실제 인덱스를 복사해 시작하면 이미 해시한 파일의 stat 정보를 재사용해 빠르다
      const real = resolve(root, (await this.git.exec(['rev-parse', '--git-path', 'index'], root)).trim());
      await copyFile(real, index).catch(() => undefined);
      const env = { GIT_INDEX_FILE: index };
      await this.git.exec(['add', '-A', '--', this.git.scope(prefix)], root, { env, timeout: 120_000 });
      const tree = (await this.git.exec(['write-tree'], root, { env, timeout: 60_000 })).trim();
      return { root, prefix, tree };
    } catch (err) {
      this.logger.warn(`작업 폴더 스냅샷 실패 (이 실행은 되돌릴 수 없음): ${(err as Error).message}`);
      return null;
    } finally {
      await rm(index, { force: true });
    }
  }

  /** 실행 전·후를 비교해 바뀐 파일이 있으면 체크포인트로 남긴다 */
  async record(before: Snapshot, after: Snapshot, info: { command: string; conversationId?: string }): Promise<{ id: string; files: CheckpointFile[] } | null> {
    if (before.tree === after.tree || before.root !== after.root) return null;
    const out = await this.git.exec(['diff-tree', '-r', '-z', '--no-renames', '--name-status', before.tree, after.tree, '--', this.git.scope(before.prefix)], before.root);
    const parts = out.split('\0').filter(Boolean);
    const files: Checkpoint['files'] = [];
    for (let i = 0; i + 1 < parts.length; i += 2) files.push({ status: STATUS[parts[i][0]] ?? 'modified', path: parts[i + 1] });
    if (files.length === 0) return null;
    await this.ready;
    const cp: Checkpoint = { id: randomUUID(), at: Date.now(), ...info, root: before.root, prefix: before.prefix, before: before.tree, after: after.tree, files, restored: [] };
    this.checkpoints = [...this.checkpoints, cp].slice(-MAX_CHECKPOINTS);
    await this.save();
    return { id: cp.id, files: files.map((f) => ({ path: stripPrefix(f.path, cp.prefix), status: f.status })) };
  }

  get(id: string) {
    return this.checkpoints.find((c) => c.id === id);
  }

  /**
   * 되돌리기. 파일이 실행 직후 상태 그대로면 실행 전 내용으로 돌리고(새로 만든 파일은 지운다),
   * 그 뒤에 바뀌었으면 건너뛴다. force면 그런 파일도 실행 전 내용으로 덮어쓴다.
   */
  async undo(id: string, force = false): Promise<UndoResult> {
    await this.ready;
    const cp = this.get(id);
    const fail = (error: string): UndoResult => ({ ok: false, error, restored: [], skipped: [], complete: false });
    if (!cp) return fail('되돌릴 기록을 찾을 수 없습니다. (오래된 기록은 50개까지만 보관합니다)');
    const pending = cp.files.filter((f) => !cp.restored.includes(f.path));
    if (pending.length === 0) return { ok: true, restored: [], skipped: [], complete: true };

    const [beforeBlobs, afterBlobs] = await Promise.all([this.blobs(cp.root, cp.before, pending), this.blobs(cp.root, cp.after, pending)]);
    const skipped: UndoResult['skipped'] = [];
    const ready: Checkpoint['files'] = [];
    for (const f of pending) {
      const current = await this.currentBlob(cp.root, f.path);
      if (!force && current !== (afterBlobs.get(f.path) ?? null)) {
        skipped.push({ path: stripPrefix(f.path, cp.prefix), reason: current === null ? '실행 뒤에 지워졌습니다' : '실행 뒤에 다시 바뀌었습니다' });
      } else {
        ready.push(f);
      }
    }

    const toWrite = ready.filter((f) => beforeBlobs.has(f.path)).map((f) => f.path);
    const toDelete = ready.filter((f) => !beforeBlobs.has(f.path)).map((f) => f.path);
    try {
      if (toWrite.length > 0) {
        // 실행 전 tree를 임시 인덱스에 읽어 들여 그 파일들만 작업 폴더로 꺼낸다 (실제 인덱스는 그대로)
        const index = join(tmpdir(), `agent-studio-index-${randomUUID()}`);
        try {
          const env = { GIT_INDEX_FILE: index };
          await this.git.exec(['read-tree', cp.before], cp.root, { env });
          await this.git.exec(['checkout-index', '-f', '--', ...toWrite], cp.root, { env });
        } finally {
          await rm(index, { force: true });
        }
      }
      for (const path of toDelete) await rm(join(cp.root, path), { force: true });
    } catch (err) {
      return { ...fail(`되돌리지 못했습니다: ${(err as Error).message}`), skipped };
    }

    cp.restored = [...cp.restored, ...ready.map((f) => f.path)];
    await this.save();
    const restored = ready.map((f) => stripPrefix(f.path, cp.prefix));
    this.logger.log(`실행 되돌리기: ${restored.length}개 복원${skipped.length ? `, ${skipped.length}개 건너뜀` : ''} (${cp.command.slice(0, 40)})`);
    return { ok: true, restored, skipped, complete: cp.restored.length === cp.files.length };
  }

  /** tree 안에서 파일들의 blob id (없는 파일은 빠진다) */
  private async blobs(root: string, tree: string, files: { path: string }[]): Promise<Map<string, string>> {
    const out = await this.git.exec(['ls-tree', '-r', '-z', tree, '--', ...files.map((f) => f.path)], root);
    const map = new Map<string, string>();
    for (const line of out.split('\0').filter(Boolean)) {
      const tab = line.indexOf('\t');
      const [, , hash] = line.slice(0, tab).split(' ');
      map.set(line.slice(tab + 1), hash);
    }
    return map;
  }

  /** 작업 폴더의 지금 파일 내용 blob id (없으면 null) */
  private async currentBlob(root: string, path: string): Promise<string | null> {
    try {
      await stat(join(root, path));
    } catch {
      return null;
    }
    return (await this.git.exec(['hash-object', '--', path], root)).trim();
  }
}
