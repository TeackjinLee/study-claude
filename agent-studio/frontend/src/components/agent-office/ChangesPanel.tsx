'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useAgentStore } from '@/store/agentStore';
import { gitApi, type ChangeStatus, type ChangesResult, type FileChange, type FileDiff } from '@/lib/git';
import { BranchIcon } from '@/components/ui/icons';

const STATUS: Record<ChangeStatus, { letter: string; label: string; color: string }> = {
  modified: { letter: 'M', label: '수정', color: '#fbbf24' },
  added: { letter: 'A', label: '추가', color: '#4ade80' },
  untracked: { letter: 'U', label: '새 파일', color: '#4ade80' },
  deleted: { letter: 'D', label: '삭제', color: '#f87171' },
  renamed: { letter: 'R', label: '이름 변경', color: '#60a5fa' },
  conflicted: { letter: '!', label: '충돌', color: '#f472b6' },
};

/**
 * 결과 미리보기의 "변경사항" 탭 — 작업 폴더의 git diff.
 * 실행이 끝날 때마다 다시 불러오고, 파일별 되돌리기와 커밋(새 브랜치 선택, 메시지는 Claude가 제안)을 할 수 있다.
 */
export function ChangesPanel() {
  const version = useAgentStore((s) => s.changesVersion);
  const running = useAgentStore((s) => s.running);
  const [data, setData] = useState<ChangesResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [picked, setPicked] = useState<string | null>(null);
  /** 커밋에서 뺄 파일 (기본은 전부 포함) */
  const [excluded, setExcluded] = useState<Set<string>>(new Set());
  const [message, setMessage] = useState('');
  const [branch, setBranch] = useState('');
  const [busy, setBusy] = useState<'revert' | 'commit' | 'message' | null>(null);

  /** 받은 diff 캐시. 목록을 다시 불러오면(파일이 바뀌었을 수 있으니) 비운다 */
  const diffCache = useRef(new Map<string, Promise<FileDiff>>());
  const [stamp, setStamp] = useState(0);
  const loadDiff = useCallback((path: string) => {
    let p = diffCache.current.get(path);
    if (!p) {
      p = gitApi.diff(path).catch((err: unknown) => ({ ok: false, error: err instanceof Error ? err.message : 'diff를 불러오지 못했습니다.', diff: '', truncated: false }));
      diffCache.current.set(path, p);
    }
    return p;
  }, []);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const next = await gitApi.changes();
      diffCache.current = new Map();
      setStamp((n) => n + 1);
      setData(next);
    } catch (err) {
      setError(err instanceof Error ? `변경사항을 불러오지 못했습니다: ${err.message}` : '변경사항을 불러오지 못했습니다.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load, version]);

  const files = useMemo(() => (data?.repo ? data.files : []), [data]);
  const current = files.find((f) => f.path === picked) ?? files[0];
  const included = files.filter((f) => !excluded.has(f.path));
  const totals = files.reduce((t, f) => ({ add: t.add + f.additions, del: t.del + f.deletions }), { add: 0, del: 0 });

  const revert = async (f: FileChange) => {
    const what = f.status === 'untracked' || f.status === 'added' ? '새 파일을 삭제합니다' : '마지막 커밋 상태로 되돌립니다';
    if (!window.confirm(`${f.path}\n\n${what}. 되돌린 내용은 복구할 수 없습니다. 계속할까요?`)) return;
    setBusy('revert');
    setNotice(null);
    try {
      const res = await gitApi.revert(f.path);
      if (!res.ok) setError(res.error ?? '되돌리지 못했습니다.');
      else setNotice(`${f.path} 을(를) 되돌렸습니다.`);
    } catch (err) {
      setError(err instanceof Error ? err.message : '되돌리지 못했습니다.');
    } finally {
      setBusy(null);
      void load();
    }
  };

  const suggest = async () => {
    setBusy('message');
    setError(null);
    try {
      const res = await gitApi.suggestMessage();
      if (res.ok && res.message) setMessage(res.message);
      else setError(res.error ?? '메시지를 만들지 못했습니다.');
    } catch (err) {
      setError(err instanceof Error ? err.message : '메시지를 만들지 못했습니다.');
    } finally {
      setBusy(null);
    }
  };

  const commit = async () => {
    if (!message.trim() || included.length === 0) return;
    setBusy('commit');
    setError(null);
    setNotice(null);
    try {
      const all = included.length === files.length;
      const res = await gitApi.commit(message.trim(), { branch: branch.trim() || undefined, paths: all ? undefined : included.map((f) => f.path) });
      if (!res.ok) {
        setError(res.error ?? '커밋하지 못했습니다.');
      } else {
        setNotice(`커밋했습니다: ${res.hash}${res.branch ? ` (${res.branch})` : ''}`);
        setMessage('');
        setBranch('');
        setExcluded(new Set());
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : '커밋하지 못했습니다.');
    } finally {
      setBusy(null);
      void load();
    }
  };

  if (data && !data.repo) {
    return (
      <div className="flex flex-1 flex-col items-center justify-center gap-2 bg-[#08101f] px-6 text-center">
        <p className="text-[13px] text-slate-400">{data.message}</p>
        <p className="font-mono text-[11px] text-slate-600">{data.workspace}</p>
      </div>
    );
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col bg-[#08101f]">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1 border-b border-line px-3 py-1.5 text-[12px]">
        {data?.repo && (
          <span className="inline-flex items-center gap-1 font-mono text-slate-200" title="현재 브랜치">
            <BranchIcon className="h-3.5 w-3.5 text-muted" />
            {data.branch}
          </span>
        )}
        <span className="text-muted">
          파일 {files.length}개{data?.repo && data.omitted > 0 ? ` (+${data.omitted}개 생략)` : ''} · <span className="text-emerald-400">+{totals.add}</span>{' '}
          <span className="text-red-400">−{totals.del}</span>
        </span>
        <button
          type="button"
          onClick={() => void load()}
          disabled={loading}
          className="ml-auto rounded-md border border-line px-2 py-0.5 text-[11px] font-semibold text-slate-300 hover:border-accent/60 hover:text-white disabled:opacity-50"
        >
          {loading ? '불러오는 중…' : '새로고침'}
        </button>
      </div>
      {(error || notice) && (
        <p className={`border-b px-3 py-1.5 text-[12px] ${error ? 'border-red-500/30 bg-red-500/10 text-red-300' : 'border-emerald-500/30 bg-emerald-500/10 text-emerald-200'}`}>
          {error ?? notice}
        </p>
      )}

      {files.length === 0 ? (
        <p className="flex flex-1 items-center justify-center px-6 text-center text-[13px] text-slate-500">
          {loading || !data ? '변경사항을 불러오는 중…' : '마지막 커밋 이후 바뀐 파일이 없습니다.'}
        </p>
      ) : (
        <div className="grid min-h-0 flex-1 md:grid-cols-[240px_minmax(0,1fr)]">
          <ul className="min-h-0 max-h-40 overflow-y-auto border-b border-line py-1 md:max-h-none md:border-b-0 md:border-r">
            {files.map((f) => {
              const st = STATUS[f.status];
              const active = f.path === current?.path;
              return (
                <li key={f.path} className={`flex items-center gap-1.5 px-2 ${active ? 'bg-accent/15' : 'hover:bg-white/[0.04]'}`}>
                  <input
                    type="checkbox"
                    checked={!excluded.has(f.path)}
                    onChange={(e) =>
                      setExcluded((prev) => {
                        const next = new Set(prev);
                        if (e.target.checked) next.delete(f.path);
                        else next.add(f.path);
                        return next;
                      })
                    }
                    title="커밋에 포함"
                    aria-label={`${f.path} 커밋에 포함`}
                    className="h-3 w-3 shrink-0 accent-blue-500"
                  />
                  <button type="button" onClick={() => setPicked(f.path)} className="flex min-w-0 flex-1 items-center gap-1.5 py-1 text-left text-[12px]" title={f.from ? `${f.from} → ${f.path}` : f.path}>
                    <span className="w-3 shrink-0 text-center font-mono text-[11px] font-bold" style={{ color: st.color }} title={st.label}>
                      {st.letter}
                    </span>
                    <span className={`min-w-0 flex-1 truncate font-mono ${active ? 'text-white' : 'text-slate-300'}`}>{f.path}</span>
                    {!f.binary && (
                      <span className="shrink-0 font-mono text-[10px]">
                        <span className="text-emerald-400">+{f.additions}</span> <span className="text-red-400">−{f.deletions}</span>
                      </span>
                    )}
                  </button>
                </li>
              );
            })}
          </ul>
          {current && <DiffView key={`${stamp}:${current.path}`} file={current} load={loadDiff} disabled={running || busy !== null} onRevert={() => void revert(current)} />}
        </div>
      )}

      {files.length > 0 && (
        <div className="flex flex-col gap-1.5 border-t border-line px-3 py-2">
          <textarea
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            rows={2}
            placeholder="커밋 메시지   ( '메시지 생성'을 누르면 Claude가 변경사항을 보고 써 줍니다 )"
            className="w-full resize-none rounded-lg border border-line bg-[#0b1426] px-2.5 py-1.5 font-mono text-[12px] text-slate-100 outline-none placeholder:font-sans placeholder:text-slate-600 focus:border-accent/60"
          />
          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              onClick={() => void suggest()}
              disabled={busy !== null}
              className="rounded-md border border-line px-2.5 py-1 text-[11px] font-semibold text-slate-200 hover:border-accent/60 hover:text-white disabled:opacity-50"
            >
              {busy === 'message' ? '생성 중…' : '메시지 생성'}
            </button>
            <input
              value={branch}
              onChange={(e) => setBranch(e.target.value)}
              placeholder="새 브랜치 (선택)"
              aria-label="새 브랜치 이름"
              className="w-40 rounded-md border border-line bg-[#0b1426] px-2 py-1 font-mono text-[11px] text-slate-100 outline-none placeholder:font-sans placeholder:text-slate-600 focus:border-accent/60"
            />
            <span className="text-[11px] text-muted">
              {included.length}/{files.length}개 파일
            </span>
            <button
              type="button"
              onClick={() => void commit()}
              disabled={running || busy !== null || !message.trim() || included.length === 0}
              title={running ? '에이전트 작업이 끝난 뒤 커밋할 수 있습니다' : undefined}
              className="ml-auto rounded-lg bg-accent px-3.5 py-1 text-[12px] font-semibold text-white hover:bg-blue-500 disabled:opacity-50"
            >
              {busy === 'commit' ? '커밋 중…' : branch.trim() ? `${branch.trim()} 브랜치에 커밋` : '커밋'}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

function lineClass(line: string) {
  if (line.startsWith('@@')) return 'bg-blue-500/10 text-blue-300';
  if (line.startsWith('+') && !line.startsWith('+++')) return 'bg-emerald-500/10 text-emerald-200';
  if (line.startsWith('-') && !line.startsWith('---')) return 'bg-red-500/10 text-red-200';
  if (/^(diff --git|index |--- |\+\+\+ |new file|deleted file|similarity|rename )/.test(line)) return 'text-slate-500';
  return 'text-slate-300';
}

function DiffView({ file, load, disabled, onRevert }: { file: FileChange; load: (path: string) => Promise<FileDiff>; disabled: boolean; onRevert: () => void }) {
  // 파일을 고를 때 그 파일의 diff만 받는다 (목록에는 줄 수만 있다)
  const [diff, setDiff] = useState<FileDiff | null>(null);
  useEffect(() => {
    let alive = true;
    void load(file.path).then((d) => alive && setDiff(d));
    return () => {
      alive = false;
    };
  }, [file.path, load]);
  const lines = useMemo(() => (diff?.diff ?? '').replace(/\n$/, '').split('\n'), [diff]);
  const st = STATUS[file.status];
  return (
    <div className="flex min-h-0 flex-col">
      <div className="flex items-center gap-2 border-b border-line px-3 py-1.5">
        <span className="shrink-0 rounded px-1.5 py-0.5 text-[10px] font-semibold" style={{ color: st.color, backgroundColor: `${st.color}1a` }}>
          {st.label}
        </span>
        <span className="min-w-0 flex-1 truncate font-mono text-[12px] text-slate-200">{file.from ? `${file.from} → ${file.path}` : file.path}</span>
        <button
          type="button"
          onClick={onRevert}
          disabled={disabled || file.status === 'conflicted'}
          title={disabled ? '에이전트 작업이 끝난 뒤 되돌릴 수 있습니다' : '이 파일의 변경을 버리고 마지막 커밋 상태로 되돌립니다'}
          className="shrink-0 rounded-md border border-line px-2 py-0.5 text-[11px] font-semibold text-slate-300 hover:border-red-400/60 hover:text-red-300 disabled:opacity-40"
        >
          되돌리기
        </button>
      </div>
      <div className="min-h-0 flex-1 overflow-auto">
        {!diff ? (
          <p className="px-3 py-2 text-[12px] text-slate-500">diff를 불러오는 중…</p>
        ) : !diff.ok ? (
          <p className="px-3 py-2 text-[12px] text-red-300">{diff.error}</p>
        ) : (
          <pre className="min-w-max font-mono text-[12px] leading-5">
            {lines.map((line, i) => (
              <div key={i} className={`px-3 ${lineClass(line)}`}>
                {line || ' '}
              </div>
            ))}
          </pre>
        )}
        {diff?.truncated && <p className="px-3 py-2 text-[11px] text-amber-300">diff가 길어 일부만 표시합니다.</p>}
      </div>
    </div>
  );
}
