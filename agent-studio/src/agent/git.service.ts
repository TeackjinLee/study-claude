import { execFile } from 'node:child_process';
import { readFile, rm, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { Injectable, Logger } from '@nestjs/common';
import { query } from '@anthropic-ai/claude-agent-sdk';
import { SettingsService } from './settings.service.js';
import { CostTrackerService } from './cost-tracker.service.js';
import { clip } from './artifact-utils.js';
import { countDiff, looksLikeBranchName, newFileDiff, parsePorcelainZ, stripPrefix, type ChangeStatus, type StatusEntry } from './git-utils.js';

export interface FileChange {
  /** 작업 폴더 기준 경로 (화면 표시 + 되돌리기 요청용) */
  path: string;
  from?: string;
  status: ChangeStatus;
  additions: number;
  deletions: number;
  binary: boolean;
  /** unified diff (너무 크면 잘림) */
  diff: string;
  truncated: boolean;
}

export type ChangesResult =
  | { repo: false; workspace: string; message: string }
  | { repo: true; workspace: string; branch: string; hasHead: boolean; files: FileChange[]; omitted: number };

const MAX_FILES = 200;
const MAX_DIFF_CHARS = 60_000;
const MAX_NEW_FILE_BYTES = 200_000;
/** 명령에 붙인 첨부 파일이 들어가는 폴더. 변경사항 목록에서 뺀다 */
const IGNORED_PREFIXES = ['uploads/'];

class GitError extends Error {}

/**
 * 작업 폴더의 git 변경사항 보기 · 파일별 되돌리기 · 커밋.
 * 작업 폴더가 더 큰 저장소의 하위 폴더일 수 있어서, 명령은 저장소 루트에서 작업 폴더 경로로 범위를 좁혀 실행한다.
 */
@Injectable()
export class GitService {
  private readonly logger = new Logger(GitService.name);

  constructor(
    private readonly settings: SettingsService,
    private readonly cost: CostTrackerService,
  ) {}

  private run(args: string[], cwd: string, timeout = 20_000): Promise<string> {
    return new Promise((resolve, reject) => {
      execFile('git', args, { cwd, timeout, maxBuffer: 32 * 1024 * 1024, env: { ...process.env, GIT_TERMINAL_PROMPT: '0', LC_ALL: 'C' } }, (err, stdout, stderr) => {
        if (err) reject(new GitError((stderr || err.message).trim()));
        else resolve(stdout);
      });
    });
  }

  /** 저장소 루트와, 루트 기준 작업 폴더 경로(prefix). 저장소가 아니면 null */
  private async locate(): Promise<{ workspace: string; root: string; prefix: string } | null> {
    const workspace = this.settings.workspaceDir;
    try {
      const root = (await this.run(['rev-parse', '--show-toplevel'], workspace)).trim();
      const prefix = (await this.run(['rev-parse', '--show-prefix'], workspace)).trim();
      return { workspace, root, prefix };
    } catch {
      return null;
    }
  }

  /** 명령의 범위: 작업 폴더 전체 */
  private scope(prefix: string) {
    return prefix ? prefix : '.';
  }

  async changes(): Promise<ChangesResult> {
    const loc = await this.locate();
    if (!loc) return { repo: false, workspace: this.settings.workspaceDir, message: '작업 폴더가 git 저장소가 아닙니다. 변경사항을 보려면 작업 폴더에서 git init 하세요.' };
    const { workspace, root, prefix } = loc;
    const hasHead = await this.run(['rev-parse', '--verify', '--quiet', 'HEAD'], root).then(() => true, () => false);
    const branch = (await this.run(['symbolic-ref', '--short', '-q', 'HEAD'], root).catch(() => 'HEAD (detached)')).trim() || 'HEAD';

    const entries = parsePorcelainZ(await this.run(['status', '--porcelain=v1', '-z', '--untracked-files=all', '--', this.scope(prefix)], root)).filter(
      (e) => !IGNORED_PREFIXES.some((p) => stripPrefix(e.path, prefix).startsWith(p)),
    );
    const files = await Promise.all(entries.slice(0, MAX_FILES).map((e) => this.fileChange(root, prefix, e, hasHead)));
    return { repo: true, workspace, branch, hasHead, files, omitted: Math.max(0, entries.length - MAX_FILES) };
  }

  private async fileChange(root: string, prefix: string, e: StatusEntry, hasHead: boolean): Promise<FileChange> {
    let diff = '';
    if (e.status === 'untracked') {
      diff = await this.untrackedDiff(root, e.path, stripPrefix(e.path, prefix));
    } else {
      const paths = e.from ? [e.from, e.path] : [e.path];
      // HEAD가 없으면(첫 커밋 전) 스테이지된 내용과 비교
      // --relative: diff 머리글의 경로도 작업 폴더 기준으로
      const flags = ['-M', '--no-color', '--no-ext-diff', ...(prefix ? [`--relative=${prefix}`] : [])];
      const base = hasHead ? ['diff', 'HEAD', ...flags] : ['diff', '--cached', ...flags];
      diff = await this.run([...base, '--', ...paths], root).catch((err: Error) => `(diff를 읽지 못했습니다: ${err.message})`);
    }
    const binary = /^Binary files .* differ$/m.test(diff) || diff.startsWith('(바이너리');
    const counts = binary ? { additions: 0, deletions: 0 } : countDiff(diff);
    return {
      path: stripPrefix(e.path, prefix),
      from: e.from ? stripPrefix(e.from, prefix) : undefined,
      status: e.status,
      ...counts,
      binary,
      diff: clip(diff, MAX_DIFF_CHARS),
      truncated: diff.length > MAX_DIFF_CHARS,
    };
  }

  private async untrackedDiff(root: string, path: string, shown: string) {
    const abs = join(root, path);
    try {
      const st = await stat(abs);
      if (st.size > MAX_NEW_FILE_BYTES) return `(새 파일, ${Math.round(st.size / 1024)}KB — 너무 커서 내용을 표시하지 않습니다)`;
      const buf = await readFile(abs);
      if (buf.includes(0)) return '(바이너리 새 파일)';
      return newFileDiff(shown, buf.toString('utf8'));
    } catch (err) {
      return `(새 파일을 읽지 못했습니다: ${(err as Error).message})`;
    }
  }

  /** 파일 하나를 마지막 커밋 상태로 되돌린다. 새 파일(추적 안 됨/새로 추가)은 지운다 */
  async revert(pathInput: unknown): Promise<{ ok: boolean; error?: string }> {
    const path = typeof pathInput === 'string' ? pathInput : '';
    const loc = await this.locate();
    if (!loc) return { ok: false, error: 'git 저장소가 아닙니다.' };
    const { root, prefix } = loc;
    // 요청 경로는 지금 변경 목록에 있는 것만 받는다 (임의 경로 삭제 방지)
    const entries = parsePorcelainZ(await this.run(['status', '--porcelain=v1', '-z', '--untracked-files=all', '--', this.scope(prefix)], root));
    const entry = entries.find((e) => stripPrefix(e.path, prefix) === path);
    if (!entry) return { ok: false, error: '변경 목록에 없는 파일입니다. 새로고침 후 다시 시도하세요.' };
    const hasHead = await this.run(['rev-parse', '--verify', '--quiet', 'HEAD'], root).then(() => true, () => false);

    try {
      if (entry.status === 'untracked') {
        await rm(join(root, entry.path), { force: true });
      } else if (entry.status === 'added' || !hasHead) {
        await this.run(['rm', '-f', '--', entry.path], root);
      } else if (entry.status === 'renamed' && entry.from) {
        await this.run(['rm', '-f', '--', entry.path], root);
        await this.run(['restore', '--source=HEAD', '--staged', '--worktree', '--', entry.from], root);
      } else {
        await this.run(['restore', '--source=HEAD', '--staged', '--worktree', '--', entry.path], root);
      }
      this.logger.log(`되돌림: ${path}`);
      return { ok: true };
    } catch (err) {
      return { ok: false, error: (err as Error).message };
    }
  }

  /** 작업 폴더의 변경을 커밋. branch를 주면 새 브랜치를 만들어 그 위에 커밋한다. paths가 없으면 작업 폴더 전체 */
  async commit(body: { message?: unknown; branch?: unknown; paths?: unknown }): Promise<{ ok: boolean; error?: string; hash?: string; branch?: string }> {
    const message = typeof body.message === 'string' ? body.message.trim() : '';
    if (!message) return { ok: false, error: '커밋 메시지를 입력하세요.' };
    const branch = typeof body.branch === 'string' ? body.branch.trim() : '';
    const loc = await this.locate();
    if (!loc) return { ok: false, error: 'git 저장소가 아닙니다.' };
    const { root, prefix } = loc;

    let paths = [this.scope(prefix)];
    if (Array.isArray(body.paths) && body.paths.length > 0) {
      const wanted = new Set(body.paths.filter((p): p is string => typeof p === 'string'));
      const entries = parsePorcelainZ(await this.run(['status', '--porcelain=v1', '-z', '--untracked-files=all', '--', this.scope(prefix)], root));
      paths = entries.filter((e) => wanted.has(stripPrefix(e.path, prefix))).flatMap((e) => (e.from ? [e.path, e.from] : [e.path]));
      if (paths.length === 0) return { ok: false, error: '커밋할 파일이 변경 목록에 없습니다.' };
    }

    try {
      if (branch) {
        if (!looksLikeBranchName(branch)) return { ok: false, error: '브랜치 이름에 쓸 수 없는 문자가 있습니다.' };
        await this.run(['check-ref-format', '--branch', branch], root);
        await this.run(['switch', '-c', branch], root);
      }
      await this.run(['add', '-A', '--', ...paths], root);
      await this.run(['commit', '-m', message, '--', ...paths], root);
      const hash = (await this.run(['rev-parse', '--short', 'HEAD'], root)).trim();
      const current = (await this.run(['symbolic-ref', '--short', '-q', 'HEAD'], root).catch(() => '')).trim();
      this.logger.log(`커밋 ${hash} (${current}): ${message.split('\n')[0]}`);
      return { ok: true, hash, branch: current };
    } catch (err) {
      return { ok: false, error: (err as Error).message };
    }
  }

  /** 지금 변경사항을 보고 Claude가 커밋 메시지를 쓴다 (도구 없이 한 번 답하기) */
  async suggestCommitMessage(): Promise<{ ok: boolean; message?: string; error?: string }> {
    const changes = await this.changes();
    if (!changes.repo) return { ok: false, error: changes.message };
    if (changes.files.length === 0) return { ok: false, error: '커밋할 변경사항이 없습니다.' };
    const log = await this.run(['log', '-8', '--pretty=format:%s'], this.settings.workspaceDir).catch(() => '');
    const diff = clip(changes.files.map((f) => `# ${f.status} ${f.path}\n${f.binary ? '(binary)' : f.diff}`).join('\n\n'), 40_000);
    const settings = this.settings.get();
    const prompt = `아래 git 변경사항에 맞는 커밋 메시지를 써라.
- 첫 줄: 72자 이내 요약. 최근 커밋들의 언어와 형식을 따른다 (없으면 한국어).
- 변경이 여러 갈래면 빈 줄 뒤에 "- " 목록으로 3줄 이내 설명.
- 커밋 메시지 본문만 출력한다. 따옴표, 코드 블록, 설명 문장 없이.

## 최근 커밋
${log || '(없음)'}

## 변경사항
${diff}`;
    const started = Date.now();
    try {
      let text = '';
      for await (const msg of query({
        prompt,
        options: { cwd: this.settings.workspaceDir, model: settings.model, tools: [], maxTurns: 1, persistSession: false, settingSources: [] },
      })) {
        if (msg.type !== 'result') continue;
        void this.cost.record({
          at: Date.now(),
          command: '(커밋 메시지 생성)',
          ok: msg.subtype === 'success',
          costUsd: msg.total_cost_usd,
          turns: msg.num_turns,
          durationMs: Date.now() - started,
          apiDurationMs: msg.duration_api_ms,
          models: {},
        });
        if (msg.subtype === 'success') text = msg.result;
      }
      const message = text.replace(/^```\w*\n?|```$/g, '').trim();
      return message ? { ok: true, message } : { ok: false, error: '메시지를 만들지 못했습니다.' };
    } catch (err) {
      return { ok: false, error: (err as Error).message };
    }
  }
}
