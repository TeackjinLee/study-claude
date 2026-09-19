'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { useAgentStore } from '@/store/agentStore';
import { ACCEPT, MAX_FILES, MAX_FILE_BYTES, formatBytes, isImageFile, uploadFiles, type Attachment } from '@/lib/uploads';
import { ChatIcon, ClaudeMarkIcon, CodexMarkIcon, CoworkIcon, MicIcon, PaperclipIcon, SendIcon, StopIcon, TerminalIcon } from '@/components/ui/icons';
import { CommandControls } from './CommandControls';
import { useSpeechInput } from '@/lib/useSpeechInput';
import type { RunMode } from '@/lib/ws';
import { AttachmentChips } from './AttachmentChips';
import { SlashCommandMenu } from './SlashCommandMenu';

const QUICK_COMMANDS = ['로그인 기능 만들어줘', '회원가입 기능 추가해줘', '배포해줘', '테스트 실행해줘'];

/** 명령을 받는 쪽. /codex 로 시작하면 Codex에게 직접, 아니면 Claude 총괄에게 */
type Target = 'claude' | 'codex';
const CODEX_PREFIX_RE = /^\s*\/codex(?=\s|$)/i;
const targetOf = (text: string): Target => (CODEX_PREFIX_RE.test(text) ? 'codex' : 'claude');

/** 채팅 = 대화만(읽기 전용, 이어서 대화) / Cowork = 총괄이 서브에이전트·Codex와 실제 작업 */
const MODE_STYLE: Record<RunMode, { label: string; hint: string; Icon: typeof ChatIcon }> = {
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
  const pickCommand = useCallback((completed: string) => {
    setValue(completed);
    textarea.current?.focus();
  }, []);
  const sendCommand = useAgentStore((s) => s.sendCommand);
  const running = useAgentStore((s) => s.running);
  const hasCodex = useAgentStore((s) => s.defs.some((d) => d.provider === 'codex'));
  const commandMode = useAgentStore((s) => s.commandMode);
  const setCommandMode = useAgentStore((s) => s.setCommandMode);
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
    sendCommand(prompt, attachments);
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
      <div className="panel-header">
        <h2 className="panel-title">
          <TerminalIcon className="h-4 w-4 text-blue-300" />
          명령 입력
        </h2>
        <div className="flex items-center gap-2">
          {/* 채팅 / Cowork: Claude에게 보낼 때만 의미가 있다 (Codex 직접 대화는 항상 대화) */}
          {target === 'claude' && (
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
                    title={ms.hint}
                    className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-semibold transition ${
                      active ? 'bg-white/10 text-white shadow-[inset_0_0_0_1px_rgba(255,255,255,0.18)]' : 'text-muted hover:text-slate-200'
                    }`}
                  >
                    <ms.Icon className="h-3.5 w-3.5" />
                    {ms.label}
                  </button>
                );
              })}
            </div>
          )}
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
                  {ts.label}
                </button>
              );
            })}
          </div>
          {(running || codexBusy) && (
            <button
              type="button"
              onClick={interrupt}
              className="inline-flex items-center gap-1 rounded-md border border-red-400/40 px-2 py-0.5 text-[11px] font-semibold text-red-300 hover:bg-red-500/10"
            >
              <StopIcon className="h-3.5 w-3.5" />
              중지
            </button>
          )}
        </div>
      </div>

      <div className="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto p-3">
        <div className="relative flex min-h-[56px] flex-1 flex-col">
          <SlashCommandMenu value={value} onPick={pickCommand} registerKeyHandler={registerKeyHandler} />
          <span
            className="pointer-events-none absolute left-2.5 top-2.5 inline-flex h-6 w-6 items-center justify-center rounded-md"
            style={{ backgroundColor: `${style.color}26`, color: style.color }}
            title={`${style.label}에게 보냅니다`}
            aria-hidden
          >
            <style.Icon className="h-4 w-4" />
          </span>
          <textarea
            ref={textarea}
            value={value}
            onChange={(e) => setValue(e.target.value)}
            onKeyDown={(e) => {
              if (menuKeyHandler.current?.(e)) {
                e.preventDefault();
                return;
              }
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                void submit();
              }
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
                : target === 'codex'
                  ? '/codex 뒤에 Codex에게 할 말   ( review / implement / image 모드, @에이전트 지정 가능 )'
                  : commandMode === 'chat'
                    ? '무엇이든 물어보세요   ( 채팅: 파일 읽기만, 이전 대화를 이어갑니다 )'
                    : '로그인 기능 만들어줘   ( / 로 명령, /codex 로 Codex에게 직접, 첨부는 버튼·드래그·붙여넣기 )'
            }
            rows={2}
            className={`min-h-[44px] w-full flex-1 resize-none rounded-xl border border-line bg-[#08101f]/80 py-2.5 pl-10 pr-3 text-[13px] text-slate-100 outline-none placeholder:text-slate-600 ${style.ring}`}
          />
        </div>

        {pending.length > 0 && (
          <div className="max-h-14 shrink-0 overflow-y-auto">
            <AttachmentChips items={pending.map((p) => p.preview)} onRemove={removeAt} />
          </div>
        )}
        {error && <p className="text-[11px] text-red-300">{error}</p>}

        <div className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-2">
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
              className="inline-flex items-center gap-1 rounded-lg border border-line px-2 py-1 text-[11px] font-semibold text-slate-300 hover:border-accent/60 hover:text-white"
            >
              <PaperclipIcon className="h-3.5 w-3.5" />
              첨부
              {pending.length > 0 && <span className="rounded-full bg-accent/30 px-1.5 text-[10px] text-blue-100">{pending.length}</span>}
            </button>
            {speech.supported && (
              <button
                type="button"
                onClick={speech.toggle}
                title={speech.listening ? '음성 입력 중지' : '음성으로 입력 (한국어)'}
                aria-pressed={speech.listening}
                className={`inline-flex items-center gap-1 rounded-lg border px-2 py-1 text-[11px] font-semibold transition ${
                  speech.listening ? 'border-red-400/60 bg-red-500/15 text-red-200' : 'border-line text-slate-300 hover:border-accent/60 hover:text-white'
                }`}
              >
                <MicIcon className={`h-3.5 w-3.5 ${speech.listening ? 'pulse-dot' : ''}`} />
                {speech.listening ? '듣는 중' : '음성'}
              </button>
            )}
            <p className="truncate text-[11px] text-muted">{speech.listening ? speech.interim || '말씀하세요…' : (speech.error ?? 'Shift + Enter 로 줄바꿈')}</p>
          </div>
          <button
            type="button"
            onClick={() => void submit()}
            disabled={uploading}
            className={`inline-flex shrink-0 items-center gap-1.5 rounded-lg px-4 py-1.5 text-[13px] font-semibold text-white disabled:opacity-60 ${style.send}`}
            title={style.hint}
          >
            <SendIcon className="h-4 w-4" />
            {uploading ? '업로드 중...' : target === 'claude' && commandMode === 'chat' ? 'Claude에게 질문' : `${style.label}에게 전송`}
          </button>
        </div>

        <CommandControls />

        <div>
          <p className="mb-1.5 text-[11px] text-muted">예시 명령어</p>
          <div className="no-scrollbar flex gap-1.5 overflow-x-auto">
            {QUICK_COMMANDS.map((cmd) => (
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
