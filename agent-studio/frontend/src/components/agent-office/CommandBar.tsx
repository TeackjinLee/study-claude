'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { useAgentStore } from '@/store/agentStore';
import { ACCEPT, MAX_FILES, MAX_FILE_BYTES, formatBytes, isImageFile, uploadFiles, type Attachment } from '@/lib/uploads';
import { ChatIcon, ClaudeMarkIcon, CodeIcon, CodexMarkIcon, CoworkIcon, ListChecksIcon, MicIcon, PaperclipIcon, PlusIcon, SendIcon, StopIcon, TerminalIcon, XIcon } from '@/components/ui/icons';
import { AgentAvatar } from './AgentAvatar';
import { CommandControls } from './CommandControls';
import { useSpeechInput } from '@/lib/useSpeechInput';
import type { RunMode } from '@/lib/ws';
import { AttachmentChips } from './AttachmentChips';
import { SlashCommandMenu } from './SlashCommandMenu';
import { FileMentionMenu } from './FileMentionMenu';

const QUICK_COMMANDS = ['택시 차종 추가해줘', '트럭 제동 거리 튜닝해줘', '헤드리스 검증 4종 돌려줘', '도시에 신호등 교차로 추가해줘'];

/** 명령을 받는 쪽. /codex 로 시작하면 Codex에게 직접, 아니면 Claude 총괄에게 */
type Target = 'claude' | 'codex';
const CODEX_PREFIX_RE = /^\s*\/codex(?=\s|$)/i;
const targetOf = (text: string): Target => (CODEX_PREFIX_RE.test(text) ? 'codex' : 'claude');

/** 코드 = Claude Code처럼 직접 코딩(기본) / 채팅 = 대화만(읽기 전용) / Cowork = 총괄이 서브에이전트·Codex와 팀 작업 */
const MODE_STYLE: Record<RunMode, { label: string; hint: string; Icon: typeof ChatIcon }> = {
  code: { label: '코드', hint: 'Claude Code처럼 직접 코드를 읽고 고치고 명령을 실행합니다. 서브에이전트 없이 혼자 작업하며 이전 대화를 이어갑니다', Icon: CodeIcon },
  chat: { label: '채팅', hint: '대화만 합니다. 파일은 읽기만, 수정·명령 실행·서브에이전트 없음. 이전 대화를 이어갑니다', Icon: ChatIcon },
  cowork: { label: 'Cowork', hint: '총괄이 계획을 세우고 서브에이전트·Codex와 함께 실제로 작업합니다', Icon: CoworkIcon },
};

const TARGET_STYLE: Record<Target, { label: string; hint: string; color: string; Icon: typeof ClaudeMarkIcon; send: string; ring: string }> = {
  claude: {
    label: 'Claude',
    hint: 'Claude 총괄이 받아서 서브에이전트와 Codex에게 일을 나눕니다',
    color: '#d97757',
    Icon: ClaudeMarkIcon,
    send: 'bg-accent shadow-[0_4px_14px_rgba(59,130,246,0.35)] hover:bg-blue-500',
    ring: 'focus:border-accent/70 focus:shadow-[0_0_0_3px_rgba(59,130,246,0.15)]',
  },
  codex: {
    label: 'Codex',
    hint: 'Claude를 거치지 않고 Codex에게 직접 말합니다 (/codex)',
    color: '#10a37f',
    Icon: CodexMarkIcon,
    send: 'bg-[#10a37f] shadow-[0_4px_14px_rgba(16,163,127,0.35)] hover:bg-[#13b38c]',
    ring: 'focus:border-[#10a37f]/70 focus:shadow-[0_0_0_3px_rgba(16,163,127,0.15)]',
  },
};

/** 아직 업로드 전인 로컬 파일 + 미리보기 */
interface Pending {
  file: File;
  preview: Attachment;
}

export function CommandBar() {
  const [value, setValue] = useState('');
  const [pending, setPending] = useState<Pending[]>([]);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [dragging, setDragging] = useState(false);
  const fileInput = useRef<HTMLInputElement | null>(null);
  const textarea = useRef<HTMLTextAreaElement | null>(null);
  const pendingRef = useRef<Pending[]>([]);
  /** 슬래시 메뉴가 열려 있을 때 키 입력을 먼저 처리하는 핸들러 */
  const menuKeyHandler = useRef<((e: React.KeyboardEvent) => boolean) | null>(null);
  const registerKeyHandler = useCallback((h: ((e: React.KeyboardEvent) => boolean) | null) => {
    menuKeyHandler.current = h;
  }, []);
  /** @파일 메뉴가 열려 있을 때의 키 핸들러 (슬래시 메뉴보다 먼저) */
  const fileKeyHandler = useRef<((e: React.KeyboardEvent) => boolean) | null>(null);
  const registerFileKeyHandler = useCallback((h: ((e: React.KeyboardEvent) => boolean) | null) => {
    fileKeyHandler.current = h;
  }, []);
  /** 입력창 커서 위치 (@파일 자동완성이 커서 앞의 @검색어를 본다) */
  const [caret, setCaret] = useState(0);
  const pickFile = useCallback((next: string, pos: number) => {
    setValue(next);
    setCaret(pos);
    requestAnimationFrame(() => {
      textarea.current?.focus();
      textarea.current?.setSelectionRange(pos, pos);
    });
  }, []);
  const pickCommand = useCallback((completed: string) => {
    setValue(completed);
    textarea.current?.focus();
  }, []);
  const sendCommand = useAgentStore((s) => s.sendCommand);
  const running = useAgentStore((s) => s.running);
  const hasCodex = useAgentStore((s) => s.defs.some((d) => d.provider === 'codex'));
  const commandMode = useAgentStore((s) => s.commandMode);
  const suggestions = useAgentStore((s) => s.suggestions);
  const setCommandMode = useAgentStore((s) => s.setCommandMode);
  const sendFollowUp = useAgentStore((s) => s.sendFollowUp);
  const planFirst = useAgentStore((s) => s.planFirst);
  const setPlanFirst = useAgentStore((s) => s.setPlanFirst);
  const newConversation = useAgentStore((s) => s.newConversation);
  const continuing = useAgentStore((s) => s.commandMode !== 'cowork' && !!s.conversations[s.commandMode]);
  const target = targetOf(value);
  // 음성 입력: 확정된 문장을 입력창 끝에 이어 붙인다
  const speech = useSpeechInput((text) => setValue((v) => (v && !/\s$/.test(v) ? `${v} ${text}` : `${v}${text}`)));
  const style = TARGET_STYLE[target];
  /** 대상 토글: Codex를 고르면 /codex 를 앞에 붙이고, Claude를 고르면 뗀다 */
  const switchTarget = (next: Target) => {
    if (next === target) return;
    setValue((v) => (next === 'codex' ? `/codex ${v.replace(/^\s+/, '')}` : v.replace(CODEX_PREFIX_RE, '').replace(/^\s+/, '')));
    textarea.current?.focus();
  };
  const codexBusy = useAgentStore((s) => s.codexBusy);
  const interrupt = useAgentStore((s) => s.interrupt);
  // 사무실에서 Master가 에이전트 옆에 서서 E(또는 클릭)를 누르면 이 입력이 그 에이전트에게 간다 (/talk)
  const talkTarget = useAgentStore((s) => s.talkTarget);
  const setTalkTarget = useAgentStore((s) => s.setTalkTarget);
  const talkDef = useAgentStore((s) => (s.talkTarget ? s.defsById[s.talkTarget] : undefined));
  const talking = !!talkDef && !value.trim().startsWith('/');
  /** 실행 중에 Claude에게 보내는 일반 입력은 새 명령이 아니라 추가 지시로 끼워 넣는다 */
  const followingUp = running && !talking && target === 'claude' && !value.trim().startsWith('/');
  useEffect(() => {
    const focus = () => textarea.current?.focus();
    window.addEventListener('agent-studio:focus-command', focus);
    return () => window.removeEventListener('agent-studio:focus-command', focus);
  }, []);
  // 대상 에이전트가 삭제되면 해제
  useEffect(() => {
    if (talkTarget && !talkDef) setTalkTarget(null);
  }, [talkTarget, talkDef, setTalkTarget]);

  pendingRef.current = pending;
  // 언마운트 시 object URL 정리
  useEffect(() => {
    return () => {
      for (const p of pendingRef.current) if (p.preview.url) URL.revokeObjectURL(p.preview.url);
    };
  }, []);

  const addFiles = (files: FileList | File[]) => {
    const list = Array.from(files);
    if (list.length === 0) return;
    setError(null);
    setPending((prev) => {
      const next = [...prev];
      for (const file of list) {
        if (next.length >= MAX_FILES) {
          setError(`첨부는 최대 ${MAX_FILES}개까지 가능합니다.`);
          break;
        }
        if (file.size > MAX_FILE_BYTES) {
          setError(`${file.name}: ${formatBytes(MAX_FILE_BYTES)}를 넘는 파일은 첨부할 수 없습니다.`);
          continue;
        }
        const image = isImageFile(file);
        next.push({
          file,
          preview: {
            path: '',
            name: file.name || (image ? `clipboard-${Date.now()}.png` : 'file'),
            mime: file.type,
            size: file.size,
            kind: image ? 'image' : 'file',
            url: image ? URL.createObjectURL(file) : undefined,
          },
        });
      }
      return next;
    });
  };

  const removeAt = (i: number) =>
    setPending((prev) => {
      const target = prev[i];
      if (target?.preview.url) URL.revokeObjectURL(target.preview.url);
      return prev.filter((_, idx) => idx !== i);
    });

  const submit = async (text?: string) => {
    const prompt = (text ?? value).trim();
    if (!prompt && pending.length === 0) return;
    if (uploading) return;
    setError(null);
    if (running && !talkDef && targetOf(prompt) === 'claude' && !prompt.startsWith('/')) {
      if (pending.length > 0) {
        setError('실행 중 추가 지시에는 첨부를 넣을 수 없습니다. 첨부를 빼거나 실행이 끝난 뒤 보내세요.');
        return;
      }
      if (!prompt) return;
      sendFollowUp(prompt);
      setValue('');
      return;
    }
    let attachments: Attachment[] = [];
    if (pending.length > 0) {
      setUploading(true);
      try {
        // 클립보드 이미지는 이름이 없어서 붙여준다
        const files = pending.map((p) => (p.file.name ? p.file : new File([p.file], p.preview.name, { type: p.file.type })));
        attachments = await uploadFiles(files);
      } catch (err) {
        setError(err instanceof Error ? err.message : '파일 업로드에 실패했습니다.');
        setUploading(false);
        return;
      }
      setUploading(false);
    }
    // 에이전트에게 직접 말하기: 슬래시 명령이 아니면 /talk 로 감싼다
    if (talkDef && !prompt.startsWith('/')) sendCommand(`/talk @${talkDef.sdkName} ${prompt}`, attachments);
    else sendCommand(prompt, attachments);
    setValue('');
    setPending([]);
  };

  return (
    <section
      className={`panel flex min-h-0 flex-col transition ${dragging ? 'ring-2 ring-accent/70' : ''}`}
      onDragOver={(e) => {
        if (e.dataTransfer.types.includes('Files')) {
          e.preventDefault();
          setDragging(true);
        }
      }}
      onDragLeave={() => setDragging(false)}
      onDrop={(e) => {
        e.preventDefault();
        setDragging(false);
        addFiles(e.dataTransfer.files);
      }}
    >
      <div className="panel-header @container min-h-[52px]">
        <h2 className="panel-title whitespace-nowrap">
          <TerminalIcon className="h-4 w-4 text-blue-300" />
          명령 입력
        </h2>
        <div className="flex shrink-0 items-center gap-2">
          {/* 누가 이 명령을 받는지: Claude 총괄 / Codex 직접 */}
          <div className="flex rounded-full border border-line bg-panel p-0.5" role="radiogroup" aria-label="명령 대상" title={style.hint}>
            {(Object.keys(TARGET_STYLE) as Target[]).map((t) => {
              const ts = TARGET_STYLE[t];
              const active = t === target;
              const disabled = t === 'codex' && !hasCodex;
              return (
                <button
                  key={t}
                  type="button"
                  role="radio"
                  aria-checked={active}
                  disabled={disabled}
                  onClick={() => switchTarget(t)}
                  title={disabled ? 'Codex 에이전트를 먼저 추가하세요' : ts.hint}
                  className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-semibold transition ${
                    active ? 'text-white' : 'text-muted hover:text-slate-200'
                  } disabled:cursor-not-allowed disabled:opacity-40`}
                  style={active ? { backgroundColor: `${ts.color}33`, boxShadow: `inset 0 0 0 1px ${ts.color}88` } : undefined}
                >
                  <ts.Icon className="h-3.5 w-3.5" style={{ color: ts.color }} />
                  {/* 좁은 패널: 고르지 않은 쪽(실행 중이면 둘 다)은 로고만 (이름은 title로) */}
                  <span className={active && !(running || codexBusy) ? '' : 'hidden @[300px]:inline'}>{ts.label}</span>
                </button>
              );
            })}
          </div>
          {(running || codexBusy) && (
            <button
              type="button"
              onClick={interrupt}
              title="중지"
              aria-label="중지"
              className="inline-flex shrink-0 items-center gap-1 rounded-md border border-red-400/40 px-2 py-0.5 text-[11px] font-semibold text-red-300 hover:bg-red-500/10"
            >
              <StopIcon className="h-3.5 w-3.5" />
              <span className="hidden @[300px]:inline">중지</span>
            </button>
          )}
        </div>
      </div>

      <div className="flex min-h-0 flex-1 flex-col gap-2 p-3">
        {/* 명령 옵션: 모드 · 계획 먼저 · 이어서 대화 · 에이전트에게 말하기. 좁은 폭에서는 줄바꿈 */}
        <div className="@container -mb-0.5 flex shrink-0 items-center gap-1 overflow-hidden whitespace-nowrap">
          {/* 코드 / 채팅 / Cowork: Claude에게 보낼 때만 의미가 있다 (Codex 직접 대화, 에이전트에게 말하기는 항상 대화) */}
          {target === 'claude' && !talking && (
            <div className="flex rounded-full border border-line bg-panel p-0.5" role="radiogroup" aria-label="명령 종류">
              {(Object.keys(MODE_STYLE) as RunMode[]).map((m) => {
                const ms = MODE_STYLE[m];
                const active = m === commandMode;
                return (
                  <button
                    key={m}
                    type="button"
                    role="radio"
                    aria-checked={active}
                    onClick={() => setCommandMode(m)}
                    title={active && continuing && !talking ? `${ms.hint}\n지금 이전 대화를 이어가는 중입니다` : ms.hint}
                    className={`inline-flex items-center gap-1 rounded-full px-1.5 py-0.5 text-[11px] font-semibold transition ${
                      active ? 'bg-white/10 text-white shadow-[inset_0_0_0_1px_rgba(255,255,255,0.18)]' : 'text-muted hover:text-slate-200'
                    }`}
                  >
                    <ms.Icon className="h-3.5 w-3.5" />
                    {/* 좁은 패널에서는 고르지 않은 모드의 이름을 숨기고 아이콘만 (이름은 title로) */}
                    <span className={active ? '' : 'hidden @[320px]:inline'}>{ms.label}</span>
                    {/* 이어서 대화 중 표시 */}
                    {active && continuing && !talking && <span className="pulse-dot h-1.5 w-1.5 rounded-full bg-emerald-400" aria-label="이어서 대화 중" />}
                  </button>
                );
              })}
            </div>
          )}
          {target === 'claude' && !talking && commandMode === 'code' && (
            <button
              type="button"
              role="switch"
              aria-checked={planFirst}
              onClick={() => setPlanFirst(!planFirst)}
              title="계획 먼저: 켜면 Claude가 먼저 계획을 보여주고, 승인한 뒤에 파일을 고칩니다"
              aria-label="계획 먼저"
              className={`inline-flex items-center gap-1 rounded-full border px-1.5 py-0.5 text-[11px] font-semibold transition ${
                planFirst ? 'border-amber-300/60 bg-amber-400/15 text-amber-100' : 'border-line text-muted hover:text-slate-200'
              }`}
            >
              <ListChecksIcon className="h-3.5 w-3.5" />
              <span className="hidden @[220px]:inline">계획</span>
            </button>
          )}
          {target === 'claude' && !talking && continuing && (
            <button
              type="button"
              onClick={() => newConversation(commandMode)}
              disabled={running}
              title={running ? '실행이 끝난 뒤 새 대화를 시작할 수 있습니다' : '지금은 이전 대화를 이어갑니다. 누르면 잊고 새로 시작합니다'}
              className="inline-flex items-center gap-0.5 rounded-full border border-line px-1.5 py-0.5 text-[11px] font-semibold text-slate-300 transition hover:border-emerald-400/60 hover:text-emerald-100 disabled:cursor-not-allowed disabled:opacity-50"
            >
              <PlusIcon className="h-3 w-3" />새 대화
            </button>
          )}
          {talkDef && (
            <span
              className="inline-flex min-w-0 items-center gap-1.5 rounded-full border px-2 py-0.5 text-[11px] font-semibold text-white"
              style={{ borderColor: `${talkDef.color}88`, backgroundColor: `${talkDef.color}22` }}
              title="사무실에서 Master가 이 에이전트에게 말하는 중입니다 (/talk). Esc 또는 ✕ 로 해제"
            >
              <AgentAvatar role={talkDef.id} size={16} />
              <span className="truncate">{talkDef.shortName}에게 말하기</span>
              <button
                type="button"
                onClick={() => setTalkTarget(null)}
                className="rounded-full p-0.5 text-slate-300 hover:bg-white/10 hover:text-white"
                aria-label="대화 대상 해제"
              >
                <XIcon className="h-3 w-3" />
              </button>
            </span>
          )}
        </div>
        <div className="relative flex min-h-[56px] flex-1 flex-col">
          <SlashCommandMenu value={value} onPick={pickCommand} onSubmit={(text) => void submit(text)} registerKeyHandler={registerKeyHandler} />
          <FileMentionMenu value={value} caret={caret} onPick={pickFile} registerKeyHandler={registerFileKeyHandler} />
          {talking && talkDef ? (
            <span className="pointer-events-none absolute left-2 top-2 inline-flex items-center" aria-hidden>
              <AgentAvatar role={talkDef.id} size={26} />
            </span>
          ) : (
            <span
              className="pointer-events-none absolute left-2.5 top-2.5 inline-flex h-6 w-6 items-center justify-center rounded-md"
              style={{ backgroundColor: `${style.color}26`, color: style.color }}
              title={`${style.label}에게 보냅니다`}
              aria-hidden
            >
              <style.Icon className="h-4 w-4" />
            </span>
          )}
          <textarea
            ref={textarea}
            value={value}
            onChange={(e) => {
              setValue(e.target.value);
              setCaret(e.target.selectionStart);
            }}
            onSelect={(e) => setCaret(e.currentTarget.selectionStart)}
            onKeyDown={(e) => {
              if (fileKeyHandler.current?.(e) || menuKeyHandler.current?.(e)) {
                e.preventDefault();
                return;
              }
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                void submit();
              }
              // 빈 입력에서 Esc: 에이전트 대화 대상 해제 → 다시 총괄에게
              if (e.key === 'Escape' && talkTarget && !value.trim()) setTalkTarget(null);
            }}
            onPaste={(e) => {
              // 스크린샷 붙여넣기(Ctrl/Cmd+V) → 이미지 첨부
              const files = Array.from(e.clipboardData.files);
              if (files.length > 0) {
                e.preventDefault();
                addFiles(files);
              }
            }}
            placeholder={
              dragging
                ? '여기에 놓으면 첨부됩니다'
                : talking && talkDef
                  ? `${talkDef.shortName}에게 할 말   ( Esc 로 해제, / 로 시작하면 일반 명령 )`
                  : followingUp
                    ? '실행 중 — 추가 지시를 입력하면 다음 단계에 반영됩니다   ( 예: 테스트도 같이 고쳐줘 )'
                    : target === 'codex'
                      ? '/codex 뒤에 Codex에게 할 말   ( / 로 모드·모델 선택, @에이전트 지정, 첨부 이미지·파일도 함께 보냄 )'
                      : commandMode === 'chat'
                        ? '무엇이든 물어보세요   ( 채팅: 파일 읽기만, 이전 대화를 이어갑니다 )'
                        : commandMode === 'code'
                          ? '로그인 API에 입력 검증 추가해줘   ( 코드: 직접 수정·실행, 이전 대화를 이어갑니다 )'
                          : '로그인 기능 만들어줘   ( / 로 명령, /codex 로 Codex에게 직접, 첨부는 버튼·드래그·붙여넣기 )'
            }
            rows={2}
            className={`min-h-[44px] w-full flex-1 resize-none rounded-xl border border-line bg-[#08101f]/80 py-2.5 pl-10 pr-3 text-[13px] text-slate-100 outline-none placeholder:text-slate-600 ${style.ring}`}
            style={talking && talkDef ? { borderColor: `${talkDef.color}88`, boxShadow: `0 0 0 3px ${talkDef.color}22` } : undefined}
          />
        </div>

        {pending.length > 0 && (
          <div className="max-h-14 shrink-0 overflow-y-auto">
            <AttachmentChips items={pending.map((p) => p.preview)} onRemove={removeAt} />
          </div>
        )}
        {error && <p className="text-[11px] text-red-300">{error}</p>}

        {/* 좁은 패널에서는 첨부·음성을 아이콘만, 줄바꿈 안내는 숨긴다 */}
        <div className="@container flex items-center justify-between gap-2">
          <div className="flex min-w-0 items-center gap-1.5">
            <input
              ref={fileInput}
              type="file"
              multiple
              accept={ACCEPT}
              className="hidden"
              onChange={(e) => {
                if (e.target.files) addFiles(e.target.files);
                e.target.value = '';
              }}
            />
            <button
              type="button"
              onClick={() => fileInput.current?.click()}
              title="이미지 / 파일 첨부"
              aria-label="첨부"
              className="inline-flex shrink-0 items-center gap-1 rounded-lg border border-line px-2 py-1 text-[11px] font-semibold text-slate-300 hover:border-accent/60 hover:text-white"
            >
              <PaperclipIcon className="h-3.5 w-3.5" />
              <span className="hidden @[360px]:inline">첨부</span>
              {pending.length > 0 && <span className="rounded-full bg-accent/30 px-1.5 text-[10px] text-blue-100">{pending.length}</span>}
            </button>
            {speech.supported && (
              <button
                type="button"
                onClick={speech.toggle}
                title={speech.listening ? '음성 입력 중지' : '음성으로 입력 (한국어)'}
                aria-pressed={speech.listening}
                aria-label={speech.listening ? '음성 입력 중지' : '음성 입력'}
                className={`inline-flex shrink-0 items-center gap-1 rounded-lg border px-2 py-1 text-[11px] font-semibold transition ${
                  speech.listening ? 'border-red-400/60 bg-red-500/15 text-red-200' : 'border-line text-slate-300 hover:border-accent/60 hover:text-white'
                }`}
              >
                <MicIcon className={`h-3.5 w-3.5 ${speech.listening ? 'pulse-dot' : ''}`} />
                <span className="hidden @[360px]:inline">{speech.listening ? '듣는 중' : '음성'}</span>
              </button>
            )}
            <p className={`min-w-0 truncate text-[11px] text-muted ${speech.listening || speech.error ? '' : 'hidden @[420px]:block'}`}>{speech.listening ? speech.interim || '말씀하세요…' : (speech.error ?? 'Shift + Enter 로 줄바꿈')}</p>
          </div>
          <button
            type="button"
            onClick={() => void submit()}
            disabled={uploading}
            className={`inline-flex min-w-0 shrink-0 items-center gap-1.5 rounded-lg px-3.5 py-1.5 text-[13px] font-semibold text-white disabled:opacity-60 ${style.send}`}
            title={style.hint}
          >
            <SendIcon className="h-4 w-4" />
            <span className="max-w-[9rem] truncate">
              {uploading
                ? '업로드 중...'
                : talking && talkDef
                  ? `${talkDef.shortName}에게 말하기`
                  : followingUp
                    ? '추가 지시'
                    : target === 'claude' && commandMode === 'chat'
                      ? '질문하기'
                      : target === 'claude' && commandMode === 'code'
                        ? '실행'
                        : `${style.label}에게 전송`}
            </span>
          </button>
        </div>

        <CommandControls />

        <div>
          <p className="mb-1.5 text-[11px] text-muted">{suggestions.length ? '다음 추천 작업 — 누르면 입력창에 채워집니다' : '예시 명령어'}</p>
          <div className="no-scrollbar flex gap-1.5 overflow-x-auto">
            {suggestions.length
              ? suggestions.map((cmd) => (
                  <button
                    key={cmd}
                    type="button"
                    onClick={() => {
                      // 추천은 바로 보내지 않고 입력창에 넣어 고칠 수 있게 한다 (/codex 접두어는 유지)
                      setValue((v) => (CODEX_PREFIX_RE.test(v) ? `/codex ${cmd}` : cmd));
                      textarea.current?.focus();
                    }}
                    title={cmd}
                    className="shrink-0 max-w-[260px] truncate rounded-md border border-emerald-400/30 bg-emerald-500/10 px-2 py-1 text-[11px] text-emerald-100 hover:border-emerald-400/60 hover:text-white"
                  >
                    → {cmd}
                  </button>
                ))
              : QUICK_COMMANDS.map((cmd) => (
                  <button
                    key={cmd}
                    type="button"
                    onClick={() => void submit(cmd)}
                    className="shrink-0 rounded-md border border-line bg-panel-2 px-2 py-1 text-[11px] text-slate-300 hover:border-accent/60 hover:text-white"
                  >
                    {cmd}
                  </button>
                ))}
          </div>
        </div>
      </div>
    </section>
  );
}
