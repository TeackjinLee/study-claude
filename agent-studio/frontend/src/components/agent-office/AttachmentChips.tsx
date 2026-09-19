'use client';

/* eslint-disable @next/next/no-img-element -- 로컬/서버 미리보기 이미지 */
import type { Attachment } from '@/lib/uploads';
import { formatBytes } from '@/lib/uploads';
import { FileIcon, XIcon } from '@/components/ui/icons';

interface Props {
  items: Attachment[];
  onRemove?: (index: number) => void;
  size?: 'sm' | 'md';
}

/** 명령에 붙은 첨부 파일 칩 목록. 이미지는 썸네일, 그 외는 파일 아이콘 + 이름 */
export function AttachmentChips({ items, onRemove, size = 'md' }: Props) {
  if (items.length === 0) return null;
  const thumb = size === 'md' ? 44 : 28;
  return (
    <ul className="flex flex-wrap gap-1.5">
      {items.map((a, i) => (
        <li
          key={`${a.path}-${i}`}
          className="group relative flex items-center gap-2 rounded-lg border border-line bg-[#08101f]/70 pr-2"
          title={`${a.name} (${formatBytes(a.size)})`}
        >
          {a.kind === 'image' && a.url ? (
            <img src={a.url} alt={a.name} className="rounded-l-lg object-cover" style={{ width: thumb, height: thumb }} />
          ) : (
            <span className="flex items-center justify-center rounded-l-lg bg-white/5 text-slate-300" style={{ width: thumb, height: thumb }}>
              <FileIcon className={size === 'md' ? 'h-5 w-5' : 'h-3.5 w-3.5'} />
            </span>
          )}
          <span className="max-w-[140px] truncate text-[11px] text-slate-200">{a.name}</span>
          {size === 'md' && <span className="text-[10px] text-muted">{formatBytes(a.size)}</span>}
          {onRemove && (
            <button
              type="button"
              onClick={() => onRemove(i)}
              aria-label={`${a.name} 제거`}
              className="absolute -right-1.5 -top-1.5 hidden h-4 w-4 items-center justify-center rounded-full bg-slate-700 text-white group-hover:flex hover:bg-red-500"
            >
              <XIcon className="h-2.5 w-2.5" />
            </button>
          )}
        </li>
      ))}
    </ul>
  );
}
