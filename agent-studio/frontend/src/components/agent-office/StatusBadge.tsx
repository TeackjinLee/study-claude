import { STATUS_COLOR, STATUS_LABEL, TASK_STATUS_LABEL, type AgentStatus, type TaskStatus } from '@/types/agent';

const ACTIVE: AgentStatus[] = ['thinking', 'working', 'testing', 'deploying'];

/** 시안의 "● Working" 같은 알약형 상태 배지 */
export function StatusBadge({ status, className = '' }: { status: AgentStatus; className?: string }) {
  const color = STATUS_COLOR[status];
  const active = ACTIVE.includes(status);
  return (
    <span
      className={`inline-flex shrink-0 items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-[11px] font-semibold ${className}`}
      style={{ color, borderColor: `${color}66`, backgroundColor: `${color}1a` }}
    >
      <span
        className={`inline-block h-1.5 w-1.5 rounded-full ${active ? 'pulse-dot' : ''}`}
        style={{ backgroundColor: color, ...(status === 'idle' ? { transform: 'rotate(45deg)', borderRadius: 1 } : {}) }}
      />
      {STATUS_LABEL[status]}
    </span>
  );
}

const TASK_STYLE: Record<TaskStatus, { color: string; bg: string }> = {
  pending: { color: '#9fb0d6', bg: '#22314f' },
  running: { color: '#93c5fd', bg: '#1e3a8a66' },
  done: { color: '#4ade80', bg: '#14532d66' },
  error: { color: '#f87171', bg: '#7f1d1d66' },
};

/** 작업 진행 현황 / 작업 트리의 "진행 중 / 완료 ✓ / 대기 중" 배지 */
export function TaskStatusBadge({ status, percent }: { status: TaskStatus; percent?: number }) {
  const s = TASK_STYLE[status];
  return (
    <span
      className="inline-flex shrink-0 items-center gap-1 rounded-md px-2 py-0.5 text-[11px] font-semibold"
      style={{ color: s.color, backgroundColor: s.bg }}
    >
      {TASK_STATUS_LABEL[status]}
      {status === 'done' && <CheckIcon className="h-3 w-3" />}
      {status === 'running' && percent !== undefined && <span className="tabular-nums">{Math.round(percent)}%</span>}
    </span>
  );
}

export function CheckIcon({ className = 'h-4 w-4' }: { className?: string }) {
  return (
    <svg viewBox="0 0 20 20" fill="none" className={className} aria-hidden>
      <path d="M4 10.5l4 4 8-9" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
