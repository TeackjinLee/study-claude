'use client';

import { useEffect, useState } from 'react';
import { CheckIcon, CopyIcon } from './icons';

async function copyText(text: string) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    // 클립보드 API를 못 쓰면(권한 등) 예전 방식으로
    const el = document.createElement('textarea');
    el.value = text;
    el.style.position = 'fixed';
    el.style.opacity = '0';
    document.body.appendChild(el);
    el.select();
    const ok = document.execCommand('copy');
    el.remove();
    return ok;
  }
}

/** 누르면 글을 클립보드에 복사하고 잠깐 "복사됨"으로 바뀌는 작은 버튼 */
export function CopyButton({ text, label = '복사', className = '' }: { text: string; label?: string; className?: string }) {
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    if (!copied) return;
    const t = setTimeout(() => setCopied(false), 1500);
    return () => clearTimeout(t);
  }, [copied]);
  return (
    <button
      type="button"
      onClick={() => void copyText(text).then(setCopied)}
      aria-label={copied ? '복사됨' : label}
      title={copied ? '복사됨' : label}
      className={`inline-flex items-center gap-1 rounded-md border border-line bg-[#0a1428]/90 px-1.5 py-0.5 text-[10px] font-semibold transition ${
        copied ? 'text-emerald-300' : 'text-slate-400 hover:border-accent/60 hover:text-white'
      } ${className}`}
    >
      {copied ? <CheckIcon className="h-3 w-3" /> : <CopyIcon className="h-3 w-3" />}
      {copied ? '복사됨' : label}
    </button>
  );
}
