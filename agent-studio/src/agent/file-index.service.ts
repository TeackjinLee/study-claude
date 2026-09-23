import { readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { Injectable } from '@nestjs/common';
import { SettingsService } from './settings.service.js';
import { GitService } from './git.service.js';
import { rankFiles, withDirs, type FileSuggestion } from './file-search.js';

/** 목록을 다시 읽기 전까지 쓰는 시간 (입력하는 동안 매번 git을 부르지 않게) */
const CACHE_MS = 15_000;
const MAX_FILES = 50_000;
/** git 저장소가 아닐 때 훑지 않는 폴더 */
const SKIP_DIRS = new Set(['.git', 'node_modules', '.godot', '.next', 'dist', 'build', '.venv', '__pycache__', '.idea', '.vscode']);
/** 명령에 붙인 첨부 파일 폴더 */
const IGNORED_PREFIXES = ['uploads/'];

/**
 * 입력창의 @파일 자동완성용 작업 폴더 파일 목록.
 * git 저장소면 .gitignore를 따르는 `git ls-files`로, 아니면 폴더를 직접 훑는다.
 */
@Injectable()
export class FileIndexService {
  private cache: { dir: string; at: number; items: FileSuggestion[] } | null = null;
  private loading: Promise<FileSuggestion[]> | null = null;

  constructor(
    private readonly settings: SettingsService,
    private readonly git: GitService,
  ) {}

  async suggest(query: string): Promise<FileSuggestion[]> {
    return rankFiles(await this.list(), query.replace(/^\.\//, ''));
  }

  private async list(): Promise<FileSuggestion[]> {
    const dir = this.settings.workspaceDir;
    if (this.cache?.dir === dir && Date.now() - this.cache.at < CACHE_MS) return this.cache.items;
    if (!this.loading) {
      this.loading = this.read(dir)
        .then((files) => {
          const items = withDirs(files.filter((f) => !IGNORED_PREFIXES.some((p) => f.startsWith(p))).slice(0, MAX_FILES));
          this.cache = { dir, at: Date.now(), items };
          return items;
        })
        .finally(() => (this.loading = null));
    }
    return this.loading;
  }

  private async read(dir: string): Promise<string[]> {
    try {
      // 하위 폴더에서 실행하면 경로가 그 폴더 기준으로 나온다
      const out = await this.git.exec(['ls-files', '-z', '--cached', '--others', '--exclude-standard'], dir, { timeout: 10_000 });
      return [...new Set(out.split('\0').filter(Boolean))];
    } catch {
      return this.walk(dir);
    }
  }

  private async walk(root: string): Promise<string[]> {
    const files: string[] = [];
    const queue = [''];
    while (queue.length > 0 && files.length < MAX_FILES) {
      const rel = queue.shift() as string;
      let entries;
      try {
        entries = await readdir(join(root, rel), { withFileTypes: true });
      } catch {
        continue;
      }
      for (const e of entries) {
        const path = rel ? `${rel}/${e.name}` : e.name;
        if (e.isDirectory()) {
          if (!SKIP_DIRS.has(e.name) && !e.name.startsWith('.')) queue.push(path);
        } else if (e.isFile()) {
          files.push(path);
        }
      }
    }
    return files;
  }
}
