'use client';

import { useEffect, useState } from 'react';
import { useAgentStore } from '@/store/agentStore';
import {
  AVAILABLE_TOOLS,
  PROVIDER_LABEL,
  ROOM_LABEL,
  TOOL_DESCRIPTION,
  WORK_ROOMS,
  newAgentTemplate,
  providerOf,
  type AgentDef,
  type AgentProvider,
  type RoomId,
  type ToolName,
} from '@/types/agent';
import { TrashIcon, XIcon } from '@/components/ui/icons';
import { AgentAvatar } from './AgentAvatar';
import { PokemonPicker } from './PokemonPicker';

const ID_PATTERN = /^[a-z][a-z0-9-]{1,30}$/;
const isLive = (process.env.NEXT_PUBLIC_WS_MODE ?? 'mock') === 'live';

const slugify = (text: string) =>
  text
    .toLowerCase()
    .replace(/agent/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 30);

const inputCls =
  'w-full rounded-lg border border-line bg-[#08101f]/80 px-3 py-1.5 text-[13px] text-slate-100 outline-none placeholder:text-slate-600 focus:border-accent/70';
const labelCls = 'mb-1 block text-[11px] font-semibold text-muted';

/** 에이전트 추가/수정/삭제 모달. 캐릭터(포켓몬), 색, 방, 도구, 프롬프트를 편집한다. */
export function AgentEditorDialog() {
  const target = useAgentStore((s) => s.editor);
  const defsById = useAgentStore((s) => s.defsById);
  const defs = useAgentStore((s) => s.defs);
  const close = useAgentStore((s) => s.closeEditor);
  const saveAgent = useAgentStore((s) => s.saveAgent);
  const deleteAgent = useAgentStore((s) => s.deleteAgent);
  const resetAgents = useAgentStore((s) => s.resetAgents);

  const isNew = target === 'new';
  const original = target && !isNew ? defsById[target] : undefined;

  const [form, setForm] = useState<AgentDef>(newAgentTemplate());
  const [idTouched, setIdTouched] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);

  // 모달이 열릴 때마다 폼을 대상에 맞게 초기화
  useEffect(() => {
    if (!target) return;
    setForm(original ? { ...original, tools: [...original.tools] } : newAgentTemplate());
    setIdTouched(false);
    setError(null);
    setConfirmDelete(false);
  }, [target, original]);

  // Esc로 닫기
  useEffect(() => {
    if (!target) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') close();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [target, close]);

  if (!target) return null;

  const update = (patch: Partial<AgentDef>) => setForm((f) => ({ ...f, ...patch }));

  const onNameChange = (name: string) => {
    const patch: Partial<AgentDef> = { name };
    if (isNew && !idTouched) {
      const slug = slugify(name);
      patch.id = slug;
      patch.sdkName = slug;
    }
    if (!form.shortName || form.shortName === form.name.replace(/\s*Agent$/i, '')) {
      patch.shortName = name.replace(/\s*Agent$/i, '').slice(0, 16);
    }
    update(patch);
  };

  const toggleTool = (tool: ToolName) =>
    update({ tools: form.tools.includes(tool) ? form.tools.filter((t) => t !== tool) : [...form.tools, tool] });

  const isCodex = providerOf(form) === 'codex';
  const setProvider = (provider: AgentProvider) => {
    // Codex는 Claude 도구를 쓰지 않는다. Claude로 되돌리면 기본 읽기 도구를 다시 채운다
    update({ provider, tools: provider === 'codex' ? [] : form.tools.length ? form.tools : ['Read', 'Glob', 'Grep'] });
  };

  const validate = (): string | null => {
    if (!form.name.trim()) return '이름을 입력하세요.';
    if (!form.shortName.trim()) return '짧은 이름을 입력하세요.';
    if (!ID_PATTERN.test(form.id)) return 'id는 영문 소문자로 시작하는 2~31자의 영문/숫자/하이픈이어야 합니다.';
    if (isNew && defsById[form.id]) return `이미 있는 id입니다: ${form.id}`;
    if (!form.roleLabel.trim()) return '역할을 입력하세요.';
    if (!form.taskLabel.trim()) return '담당 작업명을 입력하세요.';
    if (!isCodex && form.tools.length === 0) return '도구를 하나 이상 선택하세요.';
    if (!form.sdkDescription.trim()) return '총괄 에이전트에게 보여줄 설명을 입력하세요.';
    if (!form.prompt.trim()) return isCodex ? 'Codex에게 줄 역할 설명을 입력하세요.' : '시스템 프롬프트를 입력하세요.';
    return null;
  };

  const submit = async () => {
    const msg = validate();
    if (msg) {
      setError(msg);
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await saveAgent(
        {
          ...form,
          provider: providerOf(form),
          tools: isCodex ? [] : form.tools,
          id: form.id.trim(),
          sdkName: (form.sdkName.trim() || form.id.trim()).toLowerCase(),
          name: form.name.trim(),
          shortName: form.shortName.trim(),
          description: form.description.trim() || form.roleLabel.trim(),
        },
        isNew,
      );
      close();
    } catch (err) {
      setError(err instanceof Error ? err.message : '저장하지 못했습니다.');
    } finally {
      setBusy(false);
    }
  };

  const remove = async () => {
    if (!original) return;
    setBusy(true);
    setError(null);
    try {
      await deleteAgent(original.id);
      close();
    } catch (err) {
      setError(err instanceof Error ? err.message : '삭제하지 못했습니다.');
    } finally {
      setBusy(false);
    }
  };

  const reset = async () => {
    if (!window.confirm('에이전트 목록을 기본 8종(Claude 7 + Codex 1)으로 되돌릴까요? 직접 만든 에이전트는 삭제됩니다.')) return;
    setBusy(true);
    try {
      await resetAgents();
      close();
    } catch (err) {
      setError(err instanceof Error ? err.message : '되돌리지 못했습니다.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm" onMouseDown={(e) => e.target === e.currentTarget && close()}>
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="agent-editor-title"
        className="panel flex max-h-[92vh] w-full max-w-3xl flex-col overflow-hidden"
      >
        <div className="panel-header">
          <h2 id="agent-editor-title" className="panel-title">
            <AgentAvatar def={form} size={34} />
            {isNew ? '에이전트 추가' : `${original?.name ?? ''} 설정`}
          </h2>
          <button type="button" onClick={close} aria-label="닫기" className="rounded-md p-1 text-muted hover:bg-white/10 hover:text-white">
            <XIcon className="h-4 w-4" />
          </button>
        </div>

        <form
          className="grid min-h-0 flex-1 gap-4 overflow-y-auto p-4 md:grid-cols-[1fr_1.1fr]"
          onSubmit={(e) => {
            e.preventDefault();
            void submit();
          }}
        >
          {/* 왼쪽: 기본 정보 */}
          <div className="flex flex-col gap-3">
            <div>
              <span className={labelCls}>제공자</span>
              <div className="grid grid-cols-2 gap-1.5" role="radiogroup" aria-label="제공자">
                {(Object.keys(PROVIDER_LABEL) as AgentProvider[]).map((p) => {
                  const on = providerOf(form) === p;
                  return (
                    <button
                      key={p}
                      type="button"
                      role="radio"
                      aria-checked={on}
                      onClick={() => setProvider(p)}
                      className={`rounded-lg border px-2.5 py-1.5 text-[12px] font-semibold ${
                        on ? 'border-accent/60 bg-accent/10 text-white' : 'border-line text-slate-400 hover:border-line-strong'
                      }`}
                    >
                      {PROVIDER_LABEL[p]}
                    </button>
                  );
                })}
              </div>
              {isCodex && (
                <p className="mt-1 text-[11px] leading-snug text-muted">
                  총괄 Claude가 대화 상대로 부릅니다. 토론/리뷰는 읽기 전용, 구현 요청일 때만 파일을 수정합니다. Codex 로그인이 필요합니다.
                </p>
              )}
            </div>
            <div className="grid grid-cols-[1fr_auto] gap-2">
              <div>
                <label className={labelCls} htmlFor="ag-name">
                  이름
                </label>
                <input id="ag-name" className={inputCls} value={form.name} onChange={(e) => onNameChange(e.target.value)} placeholder="예: Reviewer Agent" />
              </div>
              <div>
                <label className={labelCls} htmlFor="ag-color">
                  색
                </label>
                <input
                  id="ag-color"
                  type="color"
                  value={form.color}
                  onChange={(e) => update({ color: e.target.value })}
                  className="h-[34px] w-12 cursor-pointer rounded-lg border border-line bg-transparent p-0.5"
                />
              </div>
            </div>

            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className={labelCls} htmlFor="ag-short">
                  짧은 이름 <span className="font-normal">(맵 이름표)</span>
                </label>
                <input id="ag-short" className={inputCls} value={form.shortName} maxLength={16} onChange={(e) => update({ shortName: e.target.value })} />
              </div>
              <div>
                <label className={labelCls} htmlFor="ag-id">
                  id {isNew ? '' : '(변경 불가)'}
                </label>
                <input
                  id="ag-id"
                  className={`${inputCls} font-mono disabled:opacity-60`}
                  value={form.id}
                  disabled={!isNew}
                  onChange={(e) => {
                    setIdTouched(true);
                    update({ id: e.target.value.toLowerCase(), sdkName: e.target.value.toLowerCase() });
                  }}
                  placeholder="reviewer"
                />
              </div>
            </div>

            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className={labelCls} htmlFor="ag-role">
                  역할
                </label>
                <input id="ag-role" className={inputCls} value={form.roleLabel} onChange={(e) => update({ roleLabel: e.target.value })} placeholder="예: 코드 리뷰" />
              </div>
              <div>
                <label className={labelCls} htmlFor="ag-task">
                  담당 작업명 <span className="font-normal">(작업 트리)</span>
                </label>
                <input id="ag-task" className={inputCls} value={form.taskLabel} maxLength={24} onChange={(e) => update({ taskLabel: e.target.value })} placeholder="예: 코드 리뷰" />
              </div>
            </div>

            <div>
              <label className={labelCls} htmlFor="ag-desc">
                한 줄 설명 <span className="font-normal">(목록 카드)</span>
              </label>
              <input id="ag-desc" className={inputCls} value={form.description} onChange={(e) => update({ description: e.target.value })} placeholder="예: PR 리뷰 및 개선 제안" />
            </div>

            <div>
              <label className={labelCls} htmlFor="ag-room">
                작업실
              </label>
              <select id="ag-room" className={inputCls} value={form.room} onChange={(e) => update({ room: e.target.value as RoomId })}>
                {WORK_ROOMS.map((r) => (
                  <option key={r} value={r}>
                    {ROOM_LABEL[r]}
                  </option>
                ))}
              </select>
            </div>

            {!isCodex && (
              <div>
                <span className={labelCls}>사용 도구</span>
                <div className="grid grid-cols-2 gap-1.5">
                  {AVAILABLE_TOOLS.map((tool) => {
                    const on = form.tools.includes(tool);
                    return (
                      <label
                        key={tool}
                        className={`flex cursor-pointer items-center gap-2 rounded-lg border px-2.5 py-1.5 text-[12px] ${
                          on ? 'border-accent/60 bg-accent/10 text-white' : 'border-line text-slate-400 hover:border-line-strong'
                        }`}
                      >
                        <input type="checkbox" className="accent-blue-500" checked={on} onChange={() => toggleTool(tool)} />
                        <span className="font-mono">{tool}</span>
                        <span className="ml-auto text-[11px] text-muted">{TOOL_DESCRIPTION[tool]}</span>
                      </label>
                    );
                  })}
                </div>
              </div>
            )}
          </div>

          {/* 오른쪽: 캐릭터 + 프롬프트 */}
          <div className="flex min-h-0 flex-col gap-3">
            <div>
              <span className={labelCls}>캐릭터 (PokeAPI)</span>
              <PokemonPicker value={form.pokemonId} color={form.color} onChange={(p) => update({ pokemonId: p.id, pokemonName: p.name })} />
            </div>

            <div>
              <label className={labelCls} htmlFor="ag-sdkdesc">
                총괄 에이전트용 설명 <span className="font-normal">{isCodex ? '(언제 Codex에게 물을지)' : '(언제 이 에이전트를 부를지)'}</span>
              </label>
              <textarea
                id="ag-sdkdesc"
                rows={2}
                className={`${inputCls} resize-none`}
                value={form.sdkDescription}
                onChange={(e) => update({ sdkDescription: e.target.value })}
                placeholder="예: 작성된 코드를 리뷰하고 개선점을 제안한다. 코드 작성이 끝난 뒤 호출한다."
              />
            </div>

            <div className="flex min-h-0 flex-1 flex-col">
              <label className={labelCls} htmlFor="ag-prompt">
                {isCodex ? 'Codex에게 줄 역할 설명' : '시스템 프롬프트'}
              </label>
              <textarea
                id="ag-prompt"
                rows={5}
                className={`${inputCls} min-h-[110px] flex-1 resize-y font-mono text-[12px]`}
                value={form.prompt}
                onChange={(e) => update({ prompt: e.target.value })}
                placeholder={
                  isCodex
                    ? '너는 Claude 총괄과 협업하는 시니어 엔지니어다.\n솔직하게 리뷰하고, 동의하지 않으면 근거를 들어 반대한다.\n구현 요청일 때만 파일을 고친다.'
                    : '너는 코드 리뷰 에이전트다.\n작업 폴더의 변경 내용을 읽고 버그, 보안 문제, 개선점을 한국어로 보고한다.\n파일은 수정하지 않는다.'
                }
              />
              {!isLive && <p className="mt-1 text-[11px] text-muted">Mock 모드에서는 이 브라우저(localStorage)에만 저장됩니다. Live 모드에서는 서버의 data/agents.json에 저장되어 실제 실행에 쓰입니다.</p>}
            </div>
          </div>

          {error && <p className="md:col-span-2 rounded-lg border border-red-500/40 bg-red-500/10 px-3 py-2 text-[12px] text-red-300">{error}</p>}

          <div className="flex items-center gap-2 md:col-span-2">
            {!isNew && (
              <>
                {confirmDelete ? (
                  <span className="flex items-center gap-2 text-[12px] text-red-300">
                    정말 삭제할까요?
                    <button type="button" disabled={busy || defs.length <= 1} onClick={() => void remove()} className="rounded-md bg-red-500 px-2.5 py-1 font-semibold text-white hover:bg-red-400 disabled:opacity-50">
                      삭제
                    </button>
                    <button type="button" onClick={() => setConfirmDelete(false)} className="rounded-md border border-line px-2.5 py-1 text-slate-300">
                      취소
                    </button>
                  </span>
                ) : (
                  <button
                    type="button"
                    disabled={busy || defs.length <= 1}
                    onClick={() => setConfirmDelete(true)}
                    title={defs.length <= 1 ? '에이전트는 최소 1개는 있어야 합니다' : undefined}
                    className="inline-flex items-center gap-1 rounded-md border border-red-500/40 px-2.5 py-1 text-[12px] font-semibold text-red-300 hover:bg-red-500/10 disabled:opacity-50"
                  >
                    <TrashIcon className="h-3.5 w-3.5" />
                    삭제
                  </button>
                )}
              </>
            )}
            <button type="button" onClick={() => void reset()} disabled={busy} className="text-[11px] text-muted hover:text-white">
              기본 8종으로 되돌리기
            </button>
            <div className="ml-auto flex gap-2">
              <button type="button" onClick={close} className="rounded-lg border border-line px-3 py-1.5 text-[13px] text-slate-300 hover:text-white">
                취소
              </button>
              <button type="submit" disabled={busy} className="rounded-lg bg-accent px-4 py-1.5 text-[13px] font-semibold text-white hover:bg-blue-500 disabled:opacity-60">
                {busy ? '저장 중...' : isNew ? '추가' : '저장'}
              </button>
            </div>
          </div>
        </form>
      </div>
    </div>
  );
}
