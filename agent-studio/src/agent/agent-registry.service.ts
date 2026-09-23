import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { BadRequestException, Injectable, Logger, NotFoundException, OnModuleInit } from '@nestjs/common';
import type { AgentDefinition } from '@anthropic-ai/claude-agent-sdk';
import { config } from '../config.js';
import {
  AVAILABLE_TOOLS,
  CODEX_TOOLS,
  DEFAULT_AGENTS,
  ROOM_IDS,
  buildOrchestratorPrompt,
  type AgentConfig,
  type AgentProvider,
  type RoomId,
  type ToolName,
} from './agents.config.js';

type Listener = (agents: AgentConfig[]) => void;

const ID_PATTERN = /^[a-z][a-z0-9-]{1,30}$/;
const COLOR_PATTERN = /^#[0-9a-fA-F]{6}$/;
const MAX_POKEMON_ID = 1025;
const MIN_AGENTS = 1;
const MAX_AGENTS = 12;

const text = (v: unknown, field: string, max: number, required = true): string => {
  if (typeof v !== 'string') {
    if (required) throw new BadRequestException(`${field} 값이 필요합니다.`);
    return '';
  }
  const t = v.trim();
  if (required && !t) throw new BadRequestException(`${field} 값이 비어 있습니다.`);
  if (t.length > max) throw new BadRequestException(`${field} 값은 ${max}자를 넘을 수 없습니다.`);
  return t;
};

/**
 * 에이전트 목록의 단일 진실 공급원. data/agents.json에 저장하고,
 * 실행 시 SDK 서브에이전트 정의와 총괄 프롬프트를 여기서 만든다.
 */
@Injectable()
export class AgentRegistryService implements OnModuleInit {
  private readonly logger = new Logger(AgentRegistryService.name);
  private readonly listeners = new Set<Listener>();
  private agents: AgentConfig[] = [];

  async onModuleInit() {
    await this.load();
  }

  list(): AgentConfig[] {
    return this.agents.map((a) => ({ ...a, tools: [...a.tools] }));
  }

  get(id: string): AgentConfig {
    const found = this.agents.find((a) => a.id === id);
    if (!found) throw new NotFoundException(`에이전트를 찾을 수 없습니다: ${id}`);
    return found;
  }

  subscribe(listener: Listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** 새 에이전트 추가 (id 중복 불가) */
  async create(input: unknown): Promise<AgentConfig[]> {
    const agent = this.validate(input);
    if (this.agents.some((a) => a.id === agent.id)) throw new BadRequestException(`이미 있는 id입니다: ${agent.id}`);
    if (this.agents.some((a) => a.sdkName === agent.sdkName)) throw new BadRequestException(`이미 있는 SDK 이름입니다: ${agent.sdkName}`);
    if (this.agents.length >= MAX_AGENTS) throw new BadRequestException(`에이전트는 최대 ${MAX_AGENTS}개까지 만들 수 있습니다.`);
    this.agents = [...this.agents, agent];
    await this.persist();
    return this.list();
  }

  /** 기존 에이전트 수정 (id는 바꿀 수 없다) */
  async update(id: string, input: unknown): Promise<AgentConfig[]> {
    const index = this.agents.findIndex((a) => a.id === id);
    if (index < 0) throw new NotFoundException(`에이전트를 찾을 수 없습니다: ${id}`);
    const agent = this.validate({ ...(input as object), id });
    if (this.agents.some((a) => a.id !== id && a.sdkName === agent.sdkName)) {
      throw new BadRequestException(`이미 있는 SDK 이름입니다: ${agent.sdkName}`);
    }
    this.agents = this.agents.map((a, i) => (i === index ? agent : a));
    await this.persist();
    return this.list();
  }

  async remove(id: string): Promise<AgentConfig[]> {
    if (!this.agents.some((a) => a.id === id)) throw new NotFoundException(`에이전트를 찾을 수 없습니다: ${id}`);
    if (this.agents.length <= MIN_AGENTS) throw new BadRequestException('에이전트는 최소 1개는 있어야 합니다.');
    this.agents = this.agents.filter((a) => a.id !== id);
    await this.persist();
    return this.list();
  }

  /** 기본 8개(Claude 7 + Codex 1)로 되돌리기 */
  async reset(): Promise<AgentConfig[]> {
    this.agents = DEFAULT_AGENTS.map((a) => ({ ...a, tools: [...a.tools] }));
    await this.persist();
    return this.list();
  }

  /** query() 옵션의 agents — Claude 서브에이전트만. Codex 협업자는 MCP 도구로 따로 붙는다 */
  sdkAgents(): Record<string, AgentDefinition> {
    return Object.fromEntries(
      this.agents
        .filter((a) => a.provider === 'claude')
        .map((a) => [a.sdkName, { description: a.sdkDescription, tools: [...a.tools], prompt: a.prompt } satisfies AgentDefinition]),
    );
  }

  /** Codex 협업자로 등록된 에이전트 */
  codexAgents(): AgentConfig[] {
    return this.agents.filter((a) => a.provider === 'codex').map((a) => ({ ...a, tools: [...a.tools] }));
  }

  orchestratorPrompt(opts?: { codexAvailable: boolean }): string {
    return buildOrchestratorPrompt(this.agents, opts);
  }

  /** 총괄 에이전트가 호출한 subagent_type → 대시보드 id */
  toUiAgentId(sdkName: unknown): string | null {
    if (typeof sdkName !== 'string') return null;
    return this.agents.find((a) => a.sdkName === sdkName)?.id ?? null;
  }

  private validate(input: unknown): AgentConfig {
    if (!input || typeof input !== 'object') throw new BadRequestException('에이전트 정보가 필요합니다.');
    const v = input as Record<string, unknown>;

    const id = text(v.id, 'id', 31).toLowerCase();
    if (!ID_PATTERN.test(id)) throw new BadRequestException('id는 영문 소문자로 시작하는 2~31자의 영문/숫자/하이픈이어야 합니다.');
    if (id === 'main' || id === 'system') throw new BadRequestException(`'${id}'는 예약된 id입니다.`);

    const sdkNameRaw = text(v.sdkName, 'sdkName', 40, false) || id;
    if (!/^[a-z][a-z0-9-]{1,39}$/.test(sdkNameRaw)) throw new BadRequestException('SDK 이름은 영문 소문자/숫자/하이픈만 쓸 수 있습니다.');

    const room = text(v.room, 'room', 20);
    if (!ROOM_IDS.includes(room as RoomId)) throw new BadRequestException(`room은 ${ROOM_IDS.join(', ')} 중 하나여야 합니다.`);

    const color = text(v.color, 'color', 7);
    if (!COLOR_PATTERN.test(color)) throw new BadRequestException('color는 #rrggbb 형식이어야 합니다.');

    const pokemonId = Number(v.pokemonId);
    if (!Number.isInteger(pokemonId) || pokemonId < 1 || pokemonId > MAX_POKEMON_ID) {
      throw new BadRequestException(`pokemonId는 1~${MAX_POKEMON_ID} 사이의 정수여야 합니다.`);
    }

    // provider가 없는 예전 agents.json 항목은 Claude 서브에이전트로 본다
    const provider: AgentProvider = v.provider === 'codex' ? 'codex' : 'claude';

    const toolsRaw = Array.isArray(v.tools) ? v.tools : [];
    // Codex는 자체 도구를 쓴다. 여기서는 권한(Edit=수정, Write=생성, Bash=명령)만 고른다. 비우면 읽기 전용
    const pool: readonly ToolName[] = provider === 'codex' ? CODEX_TOOLS : AVAILABLE_TOOLS;
    const tools = [...new Set(toolsRaw.filter((t): t is ToolName => pool.includes(t as ToolName)))];
    if (provider === 'claude' && tools.length === 0) throw new BadRequestException('도구를 하나 이상 선택해야 합니다.');

    return {
      id,
      provider,
      sdkName: sdkNameRaw,
      name: text(v.name, 'name', 40),
      shortName: text(v.shortName, 'shortName', 16),
      roleLabel: text(v.roleLabel, 'roleLabel', 40),
      description: text(v.description, 'description', 80),
      taskLabel: text(v.taskLabel, 'taskLabel', 24),
      room: room as RoomId,
      color,
      pokemonId,
      pokemonName: text(v.pokemonName, 'pokemonName', 40, false),
      tools,
      sdkDescription: text(v.sdkDescription, 'sdkDescription', 400),
      prompt: text(v.prompt, 'prompt', 4000),
    };
  }

  private async load() {
    try {
      const raw = await readFile(config.agentsFile, 'utf8');
      const parsed = JSON.parse(raw) as unknown;
      if (!Array.isArray(parsed) || parsed.length === 0) throw new Error('빈 목록');
      this.agents = parsed.map((a) => this.validate(a));
      this.logger.log(`에이전트 ${this.agents.length}개 로드: ${config.agentsFile}`);
    } catch (err) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code !== 'ENOENT') this.logger.warn(`agents.json을 읽지 못해 기본값을 사용합니다: ${(err as Error).message}`);
      this.agents = DEFAULT_AGENTS.map((a) => ({ ...a, tools: [...a.tools] }));
      await this.persist();
    }
  }

  private async persist() {
    await mkdir(dirname(config.agentsFile), { recursive: true });
    await writeFile(config.agentsFile, `${JSON.stringify(this.agents, null, 2)}\n`, 'utf8');
    for (const listener of this.listeners) listener(this.list());
  }
}
