'use client';

import { Fragment, useMemo, type ReactNode } from 'react';

/**
 * Claude 답을 읽기 좋게 보여주는 작은 마크다운 렌더러 (의존성 없이).
 * 지원: 코드 블록(```), 제목(#), 목록(- * 1.), 인용(>), 표는 그대로 등폭 글꼴, 인라인 `코드`·**굵게**.
 * HTML은 해석하지 않고 전부 글자로 보여준다.
 */
type Block =
  | { t: 'code'; lang: string; text: string }
  | { t: 'heading'; level: number; text: string }
  | { t: 'list'; ordered: boolean; items: string[] }
  | { t: 'quote'; text: string }
  | { t: 'table'; text: string }
  | { t: 'para'; text: string };

function parse(src: string): Block[] {
  const lines = src.replace(/\r\n/g, '\n').split('\n');
  const blocks: Block[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const fence = /^\s*```(\S*)/.exec(line);
    if (fence) {
      const body: string[] = [];
      i++;
      while (i < lines.length && !/^\s*```/.test(lines[i])) body.push(lines[i++]);
      i++; // 닫는 ```
      blocks.push({ t: 'code', lang: fence[1], text: body.join('\n') });
      continue;
    }
    const heading = /^(#{1,4})\s+(.*)$/.exec(line);
    if (heading) {
      blocks.push({ t: 'heading', level: heading[1].length, text: heading[2] });
      i++;
      continue;
    }
    if (/^\s*([-*•]|\d+[.)])\s+/.test(line)) {
      const ordered = /^\s*\d+[.)]\s+/.test(line);
      const items: string[] = [];
      while (i < lines.length && /^\s*([-*•]|\d+[.)])\s+/.test(lines[i])) {
        items.push(lines[i].replace(/^\s*([-*•]|\d+[.)])\s+/, ''));
        i++;
        // 들여쓴 이어지는 줄은 같은 항목으로
        while (i < lines.length && /^\s{2,}\S/.test(lines[i]) && !/^\s*([-*•]|\d+[.)])\s+/.test(lines[i])) items[items.length - 1] += ` ${lines[i++].trim()}`;
      }
      blocks.push({ t: 'list', ordered, items });
      continue;
    }
    if (/^\s*>/.test(line)) {
      const body: string[] = [];
      while (i < lines.length && /^\s*>/.test(lines[i])) body.push(lines[i++].replace(/^\s*>\s?/, ''));
      blocks.push({ t: 'quote', text: body.join('\n') });
      continue;
    }
    if (/^\s*\|.*\|\s*$/.test(line)) {
      const body: string[] = [];
      while (i < lines.length && /^\s*\|.*\|\s*$/.test(lines[i])) body.push(lines[i++]);
      blocks.push({ t: 'table', text: body.join('\n') });
      continue;
    }
    if (!line.trim()) {
      i++;
      continue;
    }
    const body: string[] = [];
    while (i < lines.length && lines[i].trim() && !/^\s*(```|#{1,4}\s|>|\|)/.test(lines[i]) && !/^\s*([-*•]|\d+[.)])\s+/.test(lines[i])) body.push(lines[i++]);
    blocks.push({ t: 'para', text: body.join('\n') });
  }
  return blocks;
}

/** 인라인: `코드`, **굵게** */
function inline(text: string): ReactNode {
  const parts = text.split(/(`[^`\n]+`|\*\*[^*\n]+\*\*)/g);
  return parts.map((p, i) => {
    if (p.startsWith('`') && p.endsWith('`') && p.length > 2) {
      return (
        <code key={i} className="rounded bg-white/10 px-1 py-px font-mono text-[0.92em] text-sky-200">
          {p.slice(1, -1)}
        </code>
      );
    }
    if (p.startsWith('**') && p.endsWith('**') && p.length > 4) {
      return (
        <strong key={i} className="font-semibold text-white">
          {p.slice(2, -2)}
        </strong>
      );
    }
    return <Fragment key={i}>{p}</Fragment>;
  });
}

export function Markdown({ text, className = '' }: { text: string; className?: string }) {
  const blocks = useMemo(() => parse(text), [text]);
  return (
    <div className={`flex flex-col gap-2 text-[13px] leading-relaxed text-slate-200 ${className}`}>
      {blocks.map((b, i) => {
        switch (b.t) {
          case 'code':
            return (
              <pre key={i} className="overflow-x-auto rounded-lg border border-line bg-[#060d1a] px-3 py-2 font-mono text-[12px] leading-5 text-slate-200">
                {b.text}
              </pre>
            );
          case 'heading':
            return (
              <p key={i} className={`font-bold text-white ${b.level <= 2 ? 'text-[14px]' : 'text-[13px]'}`}>
                {inline(b.text)}
              </p>
            );
          case 'list': {
            const Tag = b.ordered ? 'ol' : 'ul';
            return (
              <Tag key={i} className={`flex flex-col gap-0.5 pl-5 ${b.ordered ? 'list-decimal' : 'list-disc'} marker:text-slate-500`}>
                {b.items.map((item, n) => (
                  <li key={n}>{inline(item)}</li>
                ))}
              </Tag>
            );
          }
          case 'quote':
            return (
              <blockquote key={i} className="whitespace-pre-wrap border-l-2 border-line-strong pl-3 text-slate-400">
                {inline(b.text)}
              </blockquote>
            );
          case 'table':
            return (
              <pre key={i} className="overflow-x-auto font-mono text-[12px] leading-5 text-slate-300">
                {b.text}
              </pre>
            );
          default:
            return (
              <p key={i} className="whitespace-pre-wrap break-words">
                {inline(b.text)}
              </p>
            );
        }
      })}
    </div>
  );
}
