import { DEFAULT_AGENTS, type AgentDef } from '@/types/agent';

/** 에이전트 목록의 저장소. Mock 모드는 브라우저 localStorage, Live 모드는 NestJS REST API. */
export interface AgentRepository {
  list(): Promise<AgentDef[]>;
  create(def: AgentDef): Promise<AgentDef[]>;
  update(id: string, def: AgentDef): Promise<AgentDef[]>;
  remove(id: string): Promise<AgentDef[]>;
  reset(): Promise<AgentDef[]>;
}

const STORAGE_KEY = 'agent-office.agents.v1';

const clone = (defs: AgentDef[]) => defs.map((d) => ({ ...d, tools: [...d.tools] }));

export class LocalStorageAgentRepository implements AgentRepository {
  private read(): AgentDef[] {
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY);
      if (raw) {
        const parsed = JSON.parse(raw) as AgentDef[];
        if (Array.isArray(parsed) && parsed.length > 0) return parsed;
      }
    } catch {
      // 사생활 보호 모드 등에서 localStorage가 막혀 있으면 기본값으로
    }
    return clone(DEFAULT_AGENTS);
  }

  private write(defs: AgentDef[]) {
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(defs));
    } catch {
      // 저장이 안 되면 이번 세션 동안만 유지된다
    }
    return clone(defs);
  }

  async list() {
    return this.read();
  }

  async create(def: AgentDef) {
    const defs = this.read();
    if (defs.some((d) => d.id === def.id)) throw new Error(`이미 있는 id입니다: ${def.id}`);
    return this.write([...defs, def]);
  }

  async update(id: string, def: AgentDef) {
    const defs = this.read();
    if (!defs.some((d) => d.id === id)) throw new Error(`에이전트를 찾을 수 없습니다: ${id}`);
    return this.write(defs.map((d) => (d.id === id ? { ...def, id } : d)));
  }

  async remove(id: string) {
    const defs = this.read();
    if (defs.length <= 1) throw new Error('에이전트는 최소 1개는 있어야 합니다.');
    return this.write(defs.filter((d) => d.id !== id));
  }

  async reset() {
    return this.write(clone(DEFAULT_AGENTS));
  }
}

export class HttpAgentRepository implements AgentRepository {
  constructor(private readonly baseUrl: string) {}

  private async call(path: string, init?: RequestInit): Promise<AgentDef[]> {
    const res = await fetch(`${this.baseUrl}/api/agents${path}`, {
      ...init,
      headers: { 'Content-Type': 'application/json', ...(init?.headers ?? {}) },
    });
    const body = (await res.json().catch(() => ({}))) as { agents?: AgentDef[]; message?: string | string[] };
    if (!res.ok) {
      const msg = Array.isArray(body.message) ? body.message.join(', ') : body.message;
      throw new Error(msg ?? `요청 실패 (${res.status})`);
    }
    return body.agents ?? [];
  }

  list() {
    return this.call('');
  }

  create(def: AgentDef) {
    return this.call('', { method: 'POST', body: JSON.stringify(def) });
  }

  update(id: string, def: AgentDef) {
    return this.call(`/${encodeURIComponent(id)}`, { method: 'PUT', body: JSON.stringify(def) });
  }

  remove(id: string) {
    return this.call(`/${encodeURIComponent(id)}`, { method: 'DELETE' });
  }

  reset() {
    return this.call('/reset', { method: 'POST' });
  }
}

export function createAgentRepository(): AgentRepository {
  const mode = process.env.NEXT_PUBLIC_WS_MODE ?? 'mock';
  if (mode === 'live') return new HttpAgentRepository(process.env.NEXT_PUBLIC_BACKEND_URL ?? 'http://localhost:3000');
  return new LocalStorageAgentRepository();
}
