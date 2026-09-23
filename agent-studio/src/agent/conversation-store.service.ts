import { randomUUID } from 'node:crypto';
import { mkdir, readdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { config } from '../config.js';
import { clip, oneLine } from './artifact-utils.js';
import type { ContextInfo, RunMode, UiEvent } from './ui-events.js';

/** 목록에 보이는 대화 정보 */
export interface ConversationMeta {
  id: string;
  mode: RunMode;
  workspaceDir: string;
  /** 첫 명령 */
  title: string;
  /** 이어갈 Claude Code 세션. 첫 실행이 시작되면 채워진다 */
  sessionId?: string;
  createdAt: number;
  updatedAt: number;
  runs: number;
  costUsd: number;
  /** 마지막으로 잰 컨텍스트 사용량 */
  context?: ContextInfo;
}

interface ConversationFile extends ConversationMeta {
  /** 대화 화면을 다시 그리기 위한 이벤트 기록 (실행 중 이벤트만) */
  events: UiEvent[];
}

/** 모드별로 지금 이어가는 대화 */
type ActiveMap = Partial<Record<RunMode, string>>;

const DIR = join(dirname(config.costFile), 'conversations');
const ACTIVE_FILE = join(DIR, 'active.json');
/** 대화 하나에 남기는 이벤트 수. 넘으면 오래된 것부터 버린다 */
const MAX_EVENTS = 5000;
/**
 * 저장하지 않는 이벤트. 권한 요청은 다시 그리면 승인 배너가 떠 버리고,
 * 대화 상태(conversation)는 다시 열 때 서버가 따로 알려준다 (기록에 "새 대화"가 남으면 다시 그릴 때 화면이 비워진다)
 */
const SKIP_EVENTS = new Set<UiEvent['type']>(['permission_request', 'permission_resolved', 'settings', 'command_result', 'cleared', 'conversation', 'conversation_loaded', 'assistant_delta', 'context_usage']);
const FLUSH_DELAY_MS = 800;

const isId = (v: unknown): v is string => typeof v === 'string' && /^[0-9a-f-]{36}$/.test(v);

/**
 * 코드·채팅 대화를 data/conversations/<id>.json 에 저장한다.
 * 서버를 재시작해도 이어서 대화하고(세션 id), 지난 대화를 골라 다시 열 수 있게(이벤트 기록) 한다.
 */
@Injectable()
export class ConversationStoreService implements OnModuleInit {
  private readonly logger = new Logger(ConversationStoreService.name);
  private readonly metas = new Map<string, ConversationMeta>();
  /** 열어 둔(최근에 쓴) 대화의 이벤트. 목록만 필요한 대화는 파일에서 읽지 않는다 */
  private readonly events = new Map<string, UiEvent[]>();
  private readonly dirty = new Set<string>();
  private active: ActiveMap = {};
  private flushTimer: ReturnType<typeof setTimeout> | null = null;
  private writing: Promise<void> = Promise.resolve();
  /** 다른 서비스(러너)가 저장된 대화를 읽기 전에 기다린다 */
  readonly ready: Promise<void> = this.load();

  async onModuleInit() {
    await this.ready;
  }

  private async load() {
    await mkdir(DIR, { recursive: true });
    for (const name of await readdir(DIR)) {
      const id = name.replace(/\.json$/, '');
      if (!isId(id)) continue;
      try {
        const { events: _events, ...meta } = JSON.parse(await readFile(join(DIR, name), 'utf8')) as ConversationFile;
        this.metas.set(id, meta);
      } catch (err) {
        this.logger.warn(`대화 파일을 읽지 못했습니다 (${name}): ${(err as Error).message}`);
      }
    }
    try {
      const raw = JSON.parse(await readFile(ACTIVE_FILE, 'utf8')) as ActiveMap;
      for (const [mode, id] of Object.entries(raw)) if (isId(id) && this.metas.has(id)) this.active[mode as RunMode] = id;
    } catch {
      // 처음 실행
    }
    this.logger.log(`저장된 대화 ${this.metas.size}개`);
  }

  list(workspaceDir?: string): ConversationMeta[] {
    return [...this.metas.values()].filter((m) => !workspaceDir || m.workspaceDir === workspaceDir).sort((a, b) => b.updatedAt - a.updatedAt);
  }

  get(id: string) {
    return this.metas.get(id);
  }

  /** 이 모드에서 지금 이어가는 대화 (작업 폴더가 같을 때만) */
  activeFor(mode: RunMode, workspaceDir: string): ConversationMeta | undefined {
    const id = this.active[mode];
    const meta = id ? this.metas.get(id) : undefined;
    return meta?.workspaceDir === workspaceDir ? meta : undefined;
  }

  /** 가장 최근에 쓴 이어가는 대화 — 서버를 켰을 때 화면에 다시 보여줄 대화 */
  latestActive(workspaceDir: string): ConversationMeta | undefined {
    return Object.values(this.active)
      .map((id) => (id ? this.metas.get(id) : undefined))
      .filter((m): m is ConversationMeta => !!m && m.workspaceDir === workspaceDir)
      .sort((a, b) => b.updatedAt - a.updatedAt)[0];
  }

  create(mode: RunMode, workspaceDir: string, firstCommand: string): ConversationMeta {
    const now = Date.now();
    const meta: ConversationMeta = { id: randomUUID(), mode, workspaceDir, title: oneLine(firstCommand, 60) || '(제목 없음)', createdAt: now, updatedAt: now, runs: 0, costUsd: 0 };
    this.metas.set(meta.id, meta);
    this.events.set(meta.id, []);
    this.setActive(mode, meta.id);
    this.markDirty(meta.id);
    return meta;
  }

  setActive(mode: RunMode, id: string | undefined) {
    if (id) this.active[mode] = id;
    else delete this.active[mode];
    this.scheduleFlush();
  }

  setSession(id: string, sessionId: string) {
    const meta = this.metas.get(id);
    if (!meta || meta.sessionId === sessionId) return;
    meta.sessionId = sessionId;
    this.markDirty(id);
  }

  setContext(id: string, context: ContextInfo) {
    const meta = this.metas.get(id);
    if (!meta) return;
    meta.context = context;
    this.markDirty(id);
  }

  /** 실행 중 이벤트를 대화 기록에 붙인다 */
  append(id: string, event: UiEvent) {
    if (SKIP_EVENTS.has(event.type)) return;
    const meta = this.metas.get(id);
    if (!meta) return;
    // 러너가 이어 쓰기 전에 loadEvents로 기존 기록을 불러 둔다
    const list = this.events.get(id) ?? [];
    list.push(event);
    if (list.length > MAX_EVENTS) list.splice(0, list.length - MAX_EVENTS);
    this.events.set(id, list);
    meta.updatedAt = event.at;
    if (event.type === 'run_start') meta.runs++;
    if (event.type === 'run_done') meta.costUsd += event.costUsd;
    this.markDirty(id);
  }

  async loadEvents(id: string): Promise<UiEvent[]> {
    const cached = this.events.get(id);
    if (cached) return cached;
    try {
      const file = JSON.parse(await readFile(join(DIR, `${id}.json`), 'utf8')) as ConversationFile;
      const list = Array.isArray(file.events) ? file.events : [];
      this.events.set(id, list);
      return list;
    } catch {
      return [];
    }
  }

  rename(id: string, title: string) {
    const meta = this.metas.get(id);
    if (!meta) return false;
    meta.title = clip(title.trim(), 80) || meta.title;
    this.markDirty(id);
    return true;
  }

  async remove(id: string) {
    if (!this.metas.delete(id)) return false;
    this.events.delete(id);
    this.dirty.delete(id);
    for (const [mode, activeId] of Object.entries(this.active)) if (activeId === id) delete this.active[mode as RunMode];
    await this.writing;
    await rm(join(DIR, `${id}.json`), { force: true });
    this.scheduleFlush();
    return true;
  }

  /** 모아 둔 변경을 바로 쓴다 (실행이 끝났을 때) */
  flush(): Promise<void> {
    if (this.flushTimer) clearTimeout(this.flushTimer);
    this.flushTimer = null;
    const ids = [...this.dirty];
    this.dirty.clear();
    const active = { ...this.active };
    this.writing = this.writing
      .then(async () => {
        for (const id of ids) {
          const meta = this.metas.get(id);
          if (!meta) continue;
          const file: ConversationFile = { ...meta, events: await this.loadEvents(id) };
          await atomicWrite(join(DIR, `${id}.json`), JSON.stringify(file));
        }
        await atomicWrite(ACTIVE_FILE, JSON.stringify(active));
      })
      .catch((err: unknown) => this.logger.error(`대화 저장 실패: ${(err as Error).message}`));
    return this.writing;
  }

  private markDirty(id: string) {
    this.dirty.add(id);
    this.scheduleFlush();
  }

  private scheduleFlush() {
    if (this.flushTimer) return;
    this.flushTimer = setTimeout(() => void this.flush(), FLUSH_DELAY_MS);
  }
}

/** 쓰는 도중에 서버가 꺼져도 파일이 깨지지 않게 임시 파일에 쓰고 바꿔치기 */
async function atomicWrite(path: string, data: string) {
  const tmp = `${path}.${process.pid}.tmp`;
  await writeFile(tmp, data);
  await rename(tmp, path);
}
