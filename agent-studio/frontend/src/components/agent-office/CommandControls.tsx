'use client';

import { useEffect, useRef, useState, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { useAgentStore } from '@/store/agentStore';
import { ChevronDownIcon, CpuIcon, GaugeIcon, ShieldIcon } from '@/components/ui/icons';
import { WorkspaceChip } from '@/components/layout/WorkspaceChip';

const BACKEND_URL = process.env.NEXT_PUBLIC_BACKEND_URL ?? 'http://localhost:3000';

interface Option {
  value: string;
  label: string;
  description?: string;
}

/**
 * 명령 입력창 아래의 작은 드롭다운 하나 (모델 / 추론 노력 / 권한). 위로 열린다.
 * 값을 고르면 기존 슬래시 명령(/model 등)을 서버로 보내 헤더 칩과 같은 설정을 바꾼다.
 */
function ControlMenu({
  icon,
  label,
  value,
  options,
  onPick,
  disabled,
  title,
}: {
  icon: ReactNode;
  label: string;
  value: string;
  options: Option[];
  onPick: (value: string) => void;
  disabled?: boolean;
  title?: string;
}) {
  const [open, setOpen] = useState(false);
  // 컨트롤 바가 스크롤 컨테이너 안에 있어 absolute 팝업이 잘린다 → body 포털 + fixed 좌표로 버튼 위에 띄운다
  const [pos, setPos] = useState<{ left: number; bottom: number } | null>(null);
  const rootRef = useRef<HTMLDivElement>(null);
  const listRef = useRef<HTMLUListElement>(null);

  useEffect(() => {
    if (!open) return;
    const place = () => {
      const r = rootRef.current?.getBoundingClientRect();
      if (r) setPos({ left: Math.min(r.left, window.innerWidth - 276), bottom: window.innerHeight - r.top + 6 });
    };
    place();
    window.addEventListener('resize', place);
    const onDown = (e: MouseEvent) => {
      const t = e.target as Node;
      if (!rootRef.current?.contains(t) && !listRef.current?.contains(t)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    document.addEventListener('mousedown', onDown);
    document.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('resize', place);
      document.removeEventListener('mousedown', onDown);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  return (
    <div ref={rootRef} className="relative">
      <button
        type="button"
        disabled={disabled}
        onClick={() => setOpen((o) => !o)}
        aria-haspopup="listbox"
        aria-expanded={open}
        title={title}
        className="inline-flex items-center gap-1 rounded-md border border-transparent px-1.5 py-0.5 text-[11px] text-slate-300 hover:border-line hover:text-white disabled:cursor-not-allowed disabled:opacity-40"
      >
        <span className="text-muted">{icon}</span>
        <span className="text-muted">{label}</span>
        <span className="max-w-[120px] truncate font-semibold text-slate-100">{value}</span>
        <ChevronDownIcon className={`h-3 w-3 text-muted transition-transform ${open ? '' : 'rotate-180'}`} />
      </button>
      {open &&
        pos &&
        createPortal(
          <ul
            ref={listRef}
            role="listbox"
            style={{ position: 'fixed', left: pos.left, bottom: pos.bottom }}
            className="z-50 max-h-72 w-[260px] overflow-y-auto rounded-lg border border-line bg-[#0a1428] p-1 shadow-[0_10px_30px_rgba(0,0,0,0.5)]"
          >
            {options.map((o) => {
              const active = o.label === value || o.value === value;
              return (
                <li key={o.value}>
                  <button
                    type="button"
                    role="option"
                    aria-selected={active}
                    onClick={() => {
                      onPick(o.value);
                      setOpen(false);
                    }}
                    className={`flex w-full flex-col items-start rounded-md px-2 py-1.5 text-left hover:bg-white/[0.06] ${active ? 'bg-accent/15' : ''}`}
                  >
                    <span className={`text-[12px] ${active ? 'font-semibold text-white' : 'text-slate-200'}`}>{o.label}</span>
                    {o.description && <span className="text-[10.5px] text-muted">{o.description}</span>}
                  </button>
                </li>
              );
            })}
          </ul>,
          document.body,
        )}
    </div>
  );
}

const EFFORT_OPTIONS: Option[] = [
  { value: 'off', label: '기본값', description: '모델 기본 설정' },
  { value: 'low', label: '낮음', description: '빠르고 저렴' },
  { value: 'medium', label: '중간', description: '균형' },
  { value: 'high', label: '높음', description: '더 깊게 생각' },
  { value: 'xhigh', label: '매우 높음', description: '매우 깊게' },
  { value: 'max', label: '최대', description: '가장 깊게, 가장 느림' },
];
const EFFORT_LABEL: Record<string, string> = Object.fromEntries(EFFORT_OPTIONS.map((o) => [o.value, o.label]));

const PERMISSION_OPTIONS: Option[] = [
  { value: 'acceptEdits', label: '자동', description: '작업 폴더 안 파일 수정은 자동 허용. 명령 실행만 확인' },
  { value: 'default', label: '확인', description: '파일 수정도 매번 승인' },
];

type ModelInfo = { value: string; displayName: string; description?: string; resolvedModel?: string };

/** /api/commands 의 models (Claude Code가 아는 모델 목록). 한 번만 받아서 재사용 */
let modelsCache: Promise<ModelInfo[]> | null = null;
function loadModels(): Promise<ModelInfo[]> {
  if (!modelsCache) {
    modelsCache = fetch(`${BACKEND_URL}/api/commands`)
      .then(async (res) => ((await res.json()) as { models?: ModelInfo[] }).models ?? [])
      .catch(() => []);
  }
  return modelsCache;
}

/**
 * 명령 입력창 아래 컨트롤 바: 작업 폴더 · 모델 · 추론 노력 · 권한 모드.
 * Claude 데스크톱 앱의 입력창(폴더 / 모델·노력 / 자동)을 본떴다. 값은 서버 설정이라 헤더 칩과 항상 같다.
 */
export function CommandControls() {
  const settings = useAgentStore((s) => s.settings);
  const running = useAgentStore((s) => s.running);
  const sendCommand = useAgentStore((s) => s.sendCommand);
  const [models, setModels] = useState<ModelInfo[]>([]);

  useEffect(() => {
    void loadModels().then(setModels);
  }, []);

  // Claude Code 목록에 'default'가 이미 있으면 그걸 쓰고, 없을 때만 우리 기본값 항목을 앞에 둔다
  const listed: Option[] = models.length
    ? models.map((m) => ({
        value: m.value,
        label: m.value === 'default' ? `기본값 · ${m.displayName}` : m.displayName,
        description: m.description ?? (m.resolvedModel && m.resolvedModel !== m.value ? m.resolvedModel : undefined),
      }))
    : ['opus', 'sonnet', 'haiku'].map((v) => ({ value: v, label: v }));
  const modelOptions: Option[] = listed.some((o) => o.value === 'default')
    ? listed
    : [{ value: 'default', label: '기본값', description: 'Claude Code 설정을 따름' }, ...listed];
  const currentModel = settings?.model ?? 'default';
  const modelLabel = modelOptions.find((o) => o.value === currentModel)?.label ?? currentModel;

  return (
    <div className="no-scrollbar flex items-center gap-x-1 overflow-x-auto whitespace-nowrap">
      <WorkspaceChip placement="top" compact />
      <span className="text-line">|</span>
      <ControlMenu
        icon={<CpuIcon className="h-3.5 w-3.5" />}
        label="모델"
        value={modelLabel}
        options={modelOptions}
        onPick={(v) => sendCommand(`/model ${v}`)}
        disabled={running}
        title="총괄 에이전트 모델 (/model)"
      />
      <ControlMenu
        icon={<GaugeIcon className="h-3.5 w-3.5" />}
        label="노력"
        value={EFFORT_LABEL[settings?.effort ?? 'off'] ?? settings?.effort ?? '기본값'}
        options={EFFORT_OPTIONS}
        onPick={(v) => sendCommand(`/effort ${v}`)}
        disabled={running}
        title="추론 노력 (/effort)"
      />
      <ControlMenu
        icon={<ShieldIcon className="h-3.5 w-3.5" />}
        label="권한"
        value={settings?.permissionMode === 'default' ? '확인' : '자동'}
        options={PERMISSION_OPTIONS}
        onPick={(v) => sendCommand(`/permission-mode ${v}`)}
        disabled={running}
        title="권한 모드 (/permission-mode)"
      />
    </div>
  );
}
