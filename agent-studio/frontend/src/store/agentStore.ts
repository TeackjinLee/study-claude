import { create } from 'zustand';
import {
  DEFAULT_AGENTS,
  DEFAULT_MASTER,
  defaultAgentState,
  type MasterDef,
  type AgentDef,
  type AgentRole,
  type AgentState,
  type LogEntry,
  type TaskState,
} from '@/types/agent';
import {
  createAgentRepository,
  createEventSource,
  type AgentEventSource,
  type AgentRepository,
  type AgentSimEvent,
  type Artifact,
  type ArtifactKind,
  type CommandChoices,
  type CommandInfo,
  type PermissionRequest,
  type RunResult,
  type RunSettings,
  type RunMode,
  RUN_MODES,
} from '@/lib/ws';
import type { Attachment } from '@/lib/uploads';

const MAX_LOGS = 300;
/** completed/error 상태를 잠깐 보여준 뒤 휴게실로 돌려보내기까지의 시간(ms) */
const SETTLE_DELAY = 4000;

let nextLogId = 0;

export type CenterView = 'office' | 'results';
export type ResultTab = ArtifactKind | 'summary';

export interface RunInfo {
  command: string;
  mode?: RunMode;
  /** 이전 대화를 이어서 실행했는지 */
  continued?: boolean;
  planFirst?: boolean;
  /** 실행 도중 끼워 넣은 추가 지시 */
  followUps: string[];
  attachments: Attachment[];
  workspace?: string;
  model?: string;
  startedAt: number;
  endedAt?: number;
  status: 'running' | 'done' | 'error' | 'aborted';
  result?: RunResult;
  errorMessage?: string;
}

/** 에이전트 편집 모달 상태: null(닫힘) | 'new' | 수정할 id */
export type EditorTarget = null | 'new' | AgentRole;

interface AgentStoreState {
  /** 사용자가 편집하는 에이전트 정의 목록 (표시 순서 그대로) */
  defs: AgentDef[];
  /** id → 정의 (defs에서 파생) */
  defsById: Record<AgentRole, AgentDef>;
  defsLoaded: boolean;
  agents: Record<AgentRole, AgentState>;
  /** 현재 명령에서 에이전트별 담당 작업 진행 상태. 에이전트가 휴게실로 돌아가도 완료 표시는 유지된다. */
  tasks: Record<AgentRole, TaskState>;
  logs: LogEntry[];
  selectedAgent: AgentRole | null;
  editor: EditorTarget;
  /** 가장 최근 실행 정보 (명령, 시작/종료 시각, 비용, 최종 요약) */
  run: RunInfo | null;
  /** 이어지는 대화(코드·채팅)에서 run 이전의 실행들. 새 대화면 비운다 */
  thread: RunInfo[];
  /** 모드별로 서버에 이어갈 대화(세션)가 있는지 */
  conversations: Partial<Record<RunMode, boolean>>;
  /** 실행이 끝날 때마다 올라간다 — 변경사항(git diff) 탭이 다시 불러오는 신호 */
  changesVersion: number;
  /** 에이전트가 만든 결과물. kind별로 key(파일 경로 등) → Artifact */
  artifacts: Record<ArtifactKind, Record<string, Artifact>>;
  /** 응답을 기다리는 승인 요청 */
  permissions: PermissionRequest[];
  /** 결과 미리보기 탭에 아직 안 본 새 결과물이 있는지 */
  freshResults: Partial<Record<ResultTab, boolean>>;
  centerView: CenterView;
  /** /model 등으로 바꾸는 서버 실행 설정 (hello/settings 이벤트로 받음) */
  settings: RunSettings | null;
  /** 슬래시 명령 자동완성 목록 (처음 필요할 때 한 번 받아 캐시) */
  commands: CommandInfo[] | null;
  /** /model 처럼 고를 항목이 돌아왔을 때 띄우는 선택 창 */
  pendingChoice: CommandChoices | null;
  connection: 'connected' | 'connecting' | 'disconnected';
  running: boolean;
  /** /codex 직접 대화가 진행 중 (실행과 별개로 중지 가능) */
  codexBusy: boolean;
  source: AgentEventSource | null;
  repository: AgentRepository | null;
  init: () => void;
  sendCommand: (prompt: string, attachments?: Attachment[], mode?: RunMode) => void;
  /** 실행 도중 추가 지시 */
  sendFollowUp: (prompt: string) => void;
  newConversation: (mode?: RunMode) => void;
  /** 코드 모드에서 계획을 먼저 승인받고 수정할지 (브라우저에 기억) */
  planFirst: boolean;
  setPlanFirst: (on: boolean) => void;
  /** 마지막 실행이 끝나며 총괄이 제안한 다음 추천 명령. 없으면 예시 명령을 보여준다 */
  suggestions: string[];
  /** 명령 입력의 코드/채팅/Cowork 선택 (브라우저에 기억) */
  commandMode: RunMode;
  setCommandMode: (mode: RunMode) => void;
  /** 사용자 자신(Master)의 사무실 캐릭터. 브라우저에 기억 */
  master: MasterDef;
  setMaster: (patch: Partial<MasterDef>) => void;
  /** 명령 입력이 향하는 에이전트 (사무실에서 E/클릭으로 정함). null이면 총괄에게 */
  talkTarget: AgentRole | null;
  setTalkTarget: (id: AgentRole | null) => void;
  /** Master 옆(대화 가능 거리)에 있는 에이전트 — 사무실 씬이 갱신 */
  masterNearby: AgentRole | null;
  setMasterNearby: (id: AgentRole | null) => void;
  /** Master가 마지막으로 한 말 (사무실 말풍선용) */
  masterSay: { to: AgentRole; text: string; at: number } | null;
  interrupt: () => void;
  replyPermission: (id: string, allowed: boolean, always: boolean | 'all') => void;
  selectAgent: (id: AgentRole) => void;
  openEditor: (target: Exclude<EditorTarget, null>) => void;
  closeEditor: () => void;
  saveAgent: (def: AgentDef, isNew: boolean) => Promise<void>;
  deleteAgent: (id: AgentRole) => Promise<void>;
  resetAgents: () => Promise<void>;
  setCenterView: (view: CenterView) => void;
  loadCommands: () => Promise<CommandInfo[]>;
  /** 선택 창에서 고르기 (null이면 취소) */
  resolveChoice: (value: string | null) => void;
  markResultsSeen: (tab: ResultTab) => void;
  applyEvent: (evt: AgentSimEvent) => void;
}

const byId = (defs: AgentDef[]) => Object.fromEntries(defs.map((d) => [d.id, d])) as Record<AgentRole, AgentDef>;

function statesFor(defs: AgentDef[], prev: Record<AgentRole, AgentState>): Record<AgentRole, AgentState> {
  return Object.fromEntries(defs.map((d) => [d.id, prev[d.id] ?? defaultAgentState(d.id)])) as Record<AgentRole, AgentState>;
}

function tasksFor(defs: AgentDef[], prev?: Record<AgentRole, TaskState>): Record<AgentRole, TaskState> {
  return Object.fromEntries(defs.map((d) => [d.id, prev?.[d.id] ?? { status: 'pending' }])) as Record<AgentRole, TaskState>;
}

const MASTER_KEY = 'agent-studio.master';
function loadMaster(): MasterDef {
  try {
    const raw = typeof window !== 'undefined' ? localStorage.getItem(MASTER_KEY) : null;
    if (!raw) return DEFAULT_MASTER;
    const v = JSON.parse(raw) as Partial<MasterDef>;
    return {
      name: typeof v.name === 'string' && v.name.trim() ? v.name.trim().slice(0, 16) : DEFAULT_MASTER.name,
      pokemonId: Number.isInteger(v.pokemonId) && (v.pokemonId as number) > 0 ? (v.pokemonId as number) : DEFAULT_MASTER.pokemonId,
      pokemonName: typeof v.pokemonName === 'string' ? v.pokemonName : DEFAULT_MASTER.pokemonName,
      color: typeof v.color === 'string' && /^#[0-9a-f]{6}$/i.test(v.color) ? v.color : DEFAULT_MASTER.color,
    };
  } catch {
    return DEFAULT_MASTER;
  }
}

const COMMAND_MODE_KEY = 'agent-studio.commandMode';
function loadCommandMode(): RunMode {
  try {
    const saved = typeof window !== 'undefined' ? localStorage.getItem(COMMAND_MODE_KEY) : null;
    return RUN_MODES.find((m) => m === saved) ?? 'code';
  } catch {
    return 'code';
  }
}

const PLAN_FIRST_KEY = 'agent-studio.planFirst';
function loadPlanFirst(): boolean {
  try {
    return typeof window !== 'undefined' && localStorage.getItem(PLAN_FIRST_KEY) === '1';
  } catch {
    return false;
  }
}

function initialArtifacts(): Record<ArtifactKind, Record<string, Artifact>> {
  return { code: {}, test: {}, doc: {}, image: {} };
}

function taskFromAgent(prev: TaskState, next: AgentState): TaskState {
  switch (next.status) {
    case 'idle':
      return prev;
    case 'completed':
      return { status: 'done', progress: 100 };
    case 'error':
      return { status: 'error', progress: next.progress ?? prev.progress };
    default:
      return { status: 'running', progress: next.progress ?? prev.progress };
  }
}

export const useAgentStore = create<AgentStoreState>((set, get) => {
  /** 정의 목록이 바뀔 때 상태/작업/선택을 맞춘다 */
  const applyDefs = (defs: AgentDef[]) =>
    set((s) => {
      const selected = s.selectedAgent && defs.some((d) => d.id === s.selectedAgent) ? s.selectedAgent : (defs[0]?.id ?? null);
      return {
        defs,
        defsById: byId(defs),
        defsLoaded: true,
        agents: statesFor(defs, s.agents),
        tasks: tasksFor(defs, s.tasks),
        selectedAgent: selected,
      };
    });

  return {
    defs: DEFAULT_AGENTS,
    defsById: byId(DEFAULT_AGENTS),
    defsLoaded: false,
    agents: statesFor(DEFAULT_AGENTS, {}),
    tasks: tasksFor(DEFAULT_AGENTS),
    logs: [],
    selectedAgent: DEFAULT_AGENTS[0]?.id ?? null,
    editor: null,
    run: null,
    thread: [],
    conversations: {},
    changesVersion: 0,
    artifacts: initialArtifacts(),
    permissions: [],
    freshResults: {},
    centerView: 'office',
    settings: null,
    commands: null,
    pendingChoice: null,
    connection: 'disconnected',
    running: false,
    codexBusy: false,
    source: null,
    repository: null,

    init: () => {
      if (get().source) return;
      const repository = createAgentRepository();
      const source = createEventSource();
      set({ source, repository });
      void repository
        .list()
        .then((defs) => {
          if (defs.length > 0) applyDefs(defs);
        })
        .catch(() => {
          /* 서버가 아직 안 떠 있으면 기본값으로 시작하고, 접속되면 hello 스냅샷으로 받는다 */
        });
      source.connect((evt) => get().applyEvent(evt));
    },

    sendCommand: (prompt: string, attachments: Attachment[] = [], mode?: RunMode) => {
      const text = prompt.trim();
      if (!text && attachments.length === 0) return;
      const m = mode ?? get().commandMode;
      // 계획 먼저는 코드 모드의 일반 명령에만 (슬래시 명령·/talk 제외)
      const planFirst = m === 'code' && get().planFirst && !text.startsWith('/');
      get().source?.sendCommand(text, get().defs, attachments, m, { planFirst });
    },

    sendFollowUp: (prompt) => {
      const text = prompt.trim();
      if (text) get().source?.followUp(text);
    },

    newConversation: (mode) => get().source?.newConversation(mode),

    planFirst: loadPlanFirst(),
    setPlanFirst: (on) => {
      set({ planFirst: on });
      try {
        localStorage.setItem(PLAN_FIRST_KEY, on ? '1' : '0');
      } catch {
        // 저장 불가면 이번 세션만 유지
      }
    },

    suggestions: [],
    commandMode: loadCommandMode(),
    setCommandMode: (mode) => {
      set({ commandMode: mode });
      try {
        localStorage.setItem(COMMAND_MODE_KEY, mode);
      } catch {
        // 저장 불가(사생활 모드 등)면 이번 세션만 유지
      }
    },

    master: loadMaster(),
    setMaster: (patch) => {
      const master = { ...get().master, ...patch };
      set({ master });
      try {
        localStorage.setItem(MASTER_KEY, JSON.stringify(master));
      } catch {
        // 저장 불가면 이번 세션만 유지
      }
    },
    talkTarget: null,
    setTalkTarget: (id) => set({ talkTarget: id }),
    masterNearby: null,
    setMasterNearby: (id) => {
      if (get().masterNearby !== id) set({ masterNearby: id });
    },
    masterSay: null,

    interrupt: () => get().source?.interrupt(),

    replyPermission: (id, allowed, always) => {
      get().source?.replyPermission(id, allowed, always);
      // 서버 응답(permission_resolved)이 오기 전에도 화면에서 바로 지운다. 범위 허용이면 같은 범위의 다른 배너도 함께 지운다
      set((s) => {
        const target = s.permissions.find((p) => p.id === id);
        return {
          permissions: s.permissions.filter((p) => {
            if (p.id === id) return false;
            if (!allowed || !always) return true;
            return always === 'all' ? false : p.tool !== target?.tool;
          }),
        };
      });
    },

    selectAgent: (id: AgentRole) => set({ selectedAgent: id }),

    openEditor: (target) => set({ editor: target }),
    closeEditor: () => set({ editor: null }),

    saveAgent: async (def, isNew) => {
      const repo = get().repository;
      if (!repo) throw new Error('저장소가 준비되지 않았습니다.');
      const defs = isNew ? await repo.create(def) : await repo.update(def.id, def);
      applyDefs(defs);
    },

    deleteAgent: async (id) => {
      const repo = get().repository;
      if (!repo) throw new Error('저장소가 준비되지 않았습니다.');
      applyDefs(await repo.remove(id));
    },

    resetAgents: async () => {
      const repo = get().repository;
      if (!repo) throw new Error('저장소가 준비되지 않았습니다.');
      applyDefs(await repo.reset());
    },

    setCenterView: (view) => set({ centerView: view }),

    resolveChoice: (value) => {
      const choice = get().pendingChoice;
      set({ pendingChoice: null });
      if (choice && value !== null) get().sendCommand(`${choice.command} ${value}`);
    },

    loadCommands: async () => {
      const cached = get().commands;
      if (cached) return cached;
      const list =
        (await get()
          .source?.listCommands()
          .catch(() => [])) ?? [];
      set({ commands: list });
      return list;
    },

    markResultsSeen: (tab) => set((s) => (s.freshResults[tab] ? { freshResults: { ...s.freshResults, [tab]: false } } : {})),

    applyEvent: (evt: AgentSimEvent) => {
      switch (evt.type) {
        case 'connection':
          set({ connection: evt.status });
          return;

        case 'agents_changed':
          if (evt.agents.length > 0) applyDefs(evt.agents);
          return;

        case 'session':
          set((s) => (s.run ? { run: { ...s.run, model: evt.model } } : {}));
          return;

        case 'run_start':
          set((s) => {
            // 같은 대화를 이어가면 앞의 실행을 대화 목록에 쌓고 결과물도 그대로 둔다
            const continues = !!evt.continued && !!s.run && s.run.mode === evt.mode;
            return {
              running: true,
              agents: statesFor(s.defs, {}),
              tasks: tasksFor(s.defs),
              artifacts: continues ? s.artifacts : initialArtifacts(),
              thread: continues && s.run ? [...s.thread, s.run] : [],
              permissions: [],
              freshResults: {},
              run: {
                command: evt.command,
                mode: evt.mode,
                continued: evt.continued,
                planFirst: evt.planFirst,
                followUps: [],
                attachments: evt.attachments ?? [],
                workspace: evt.workspace,
                startedAt: Date.now(),
                status: 'running',
              },
            };
          });
          return;

        case 'follow_up':
          set((s) => (s.run ? { run: { ...s.run, followUps: [...s.run.followUps, evt.text] } } : {}));
          return;

        case 'conversation':
          set((s) => ({
            conversations: { ...s.conversations, [evt.mode]: evt.active },
            // 새 대화: 화면의 대화 목록도 비운다 (마지막 실행 결과는 남겨 둔다)
            thread: !evt.active && s.run?.mode === evt.mode ? [] : s.thread,
            run: !evt.active && s.run?.mode === evt.mode && !s.running ? { ...s.run, continued: false } : s.run,
          }));
          return;

        case 'conversations':
          set({ conversations: evt.all });
          return;

        case 'agent_status': {
          const def = get().defsById[evt.agent];
          if (!def) return; // 등록되지 않은(삭제된) 에이전트의 이벤트는 무시
          const prev = get().agents[evt.agent] ?? defaultAgentState(evt.agent);
          const room = evt.room === 'work' ? def.room : (evt.room ?? prev.room);
          const next: AgentState = {
            id: evt.agent,
            status: evt.status,
            room,
            message: evt.message ?? prev.message,
            progress: evt.progress,
          };
          set((s) => ({
            agents: { ...s.agents, [evt.agent]: next },
            tasks: { ...s.tasks, [evt.agent]: taskFromAgent(s.tasks[evt.agent] ?? { status: 'pending' }, next) },
          }));

          if (evt.status === 'completed' || evt.status === 'error') {
            setTimeout(() => {
              const current = get().agents[evt.agent];
              if (!current || (current.status !== 'completed' && current.status !== 'error')) return;
              set((s) => ({ agents: { ...s.agents, [evt.agent]: defaultAgentState(evt.agent) } }));
            }, SETTLE_DELAY);
          }
          return;
        }

        case 'log': {
          const entry: LogEntry = { id: `log-${nextLogId++}`, at: Date.now(), agent: evt.agent, text: evt.text };
          set((s) => ({ logs: [...s.logs, entry].slice(-MAX_LOGS) }));
          return;
        }

        case 'command_result': {
          const entry: LogEntry = {
            id: `log-${nextLogId++}`,
            at: Date.now(),
            agent: 'system',
            text: `${evt.command}\n${evt.text}`,
            kind: 'command',
            error: !evt.ok,
          };
          set((s) => ({ logs: [...s.logs, entry].slice(-MAX_LOGS), pendingChoice: evt.choices ?? s.pendingChoice }));
          return;
        }

        case 'settings':
          // 작업 폴더가 바뀌면 서버는 이전 대화를 이어가지 않는다
          set((s) => ({
            settings: evt.settings,
            conversations: s.settings && s.settings.workspaceDir !== evt.settings.workspaceDir ? {} : s.conversations,
            changesVersion: s.settings && s.settings.workspaceDir !== evt.settings.workspaceDir ? s.changesVersion + 1 : s.changesVersion,
          }));
          return;

        case 'cleared':
          set((s) => ({
            logs: [],
            artifacts: initialArtifacts(),
            freshResults: {},
            run: null,
            thread: [],
            conversations: {},
            suggestions: [],
            tasks: tasksFor(s.defs),
            agents: statesFor(s.defs, {}),
          }));
          return;

        case 'artifact': {
          const art: Artifact = { ...evt.artifact, at: Date.now() };
          set((s) => ({
            artifacts: { ...s.artifacts, [art.kind]: { ...s.artifacts[art.kind], [art.key]: art } },
            freshResults: s.centerView === 'results' ? s.freshResults : { ...s.freshResults, [art.kind]: true },
          }));
          return;
        }

        case 'permission_request':
          set((s) => ({ permissions: [...s.permissions.filter((p) => p.id !== evt.request.id), evt.request] }));
          return;

        case 'permission_resolved':
          set((s) => ({ permissions: s.permissions.filter((p) => p.id !== evt.id) }));
          return;

        case 'run_done':
          set((s) => ({
            running: false,
            permissions: [],
            changesVersion: s.changesVersion + 1,
            suggestions: evt.result.suggestions?.length ? evt.result.suggestions : s.suggestions,
            freshResults: { ...s.freshResults, summary: true },
            run: s.run
              ? { ...s.run, endedAt: Date.now(), status: evt.result.ok ? 'done' : 'error', result: evt.result }
              : { command: '', followUps: [], attachments: [], startedAt: Date.now(), endedAt: Date.now(), status: evt.result.ok ? 'done' : 'error', result: evt.result },
          }));
          return;

        case 'run_error':
          set((s) => ({
            running: false,
            permissions: [],
            changesVersion: s.changesVersion + 1,
            run: s.run ? { ...s.run, endedAt: Date.now(), status: 'error', errorMessage: evt.message } : s.run,
          }));
          return;

        case 'codex_direct':
          set({ codexBusy: evt.active });
          return;

        case 'master_say':
          set({ masterSay: { to: evt.to, text: evt.text, at: Date.now() } });
          return;

        case 'run_aborted':
          set((s) => ({
            running: false,
            permissions: [],
            changesVersion: s.changesVersion + 1,
            agents: statesFor(s.defs, {}),
            run: s.run ? { ...s.run, endedAt: Date.now(), status: 'aborted' } : s.run,
          }));
          return;
      }
    },
  };
});
