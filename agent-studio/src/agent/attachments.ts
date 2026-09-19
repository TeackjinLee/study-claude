import { readFile, stat } from 'node:fs/promises';
import { extname, isAbsolute, join, normalize, relative, sep } from 'node:path';

/** 대시보드가 명령과 함께 보내는 첨부 파일 (업로드 API가 돌려준 값 그대로) */
export interface Attachment {
  /** 작업 폴더 기준 상대 경로 (예: uploads/20260917-083000-ab12/spec.png) */
  path: string;
  name: string;
  mime: string;
  size: number;
  kind: 'image' | 'file';
}

export const UPLOAD_DIR = 'uploads';
export const MAX_FILES = 10;
export const MAX_FILE_BYTES = 1024 * 1024 * 1024; // 1GB
/** Messages API가 base64 이미지 한 장에 허용하는 크기 (여유 있게) */
export const MAX_IMAGE_EMBED_BYTES = 4.5 * 1024 * 1024;

export const IMAGE_MIME_BY_EXT: Record<string, 'image/jpeg' | 'image/png' | 'image/gif' | 'image/webp'> = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
};

/** 업로드를 허용하는 확장자. 에이전트의 Read 도구가 읽을 수 있는 것 위주 */
export const ALLOWED_EXT = new Set([
  ...Object.keys(IMAGE_MIME_BY_EXT),
  '.pdf', '.txt', '.md', '.mdx', '.csv', '.tsv', '.json', '.yaml', '.yml', '.xml', '.toml', '.ini', '.env.example',
  '.html', '.css', '.scss', '.js', '.jsx', '.ts', '.tsx', '.mjs', '.cjs', '.py', '.java', '.kt', '.go', '.rs', '.rb', '.php',
  '.c', '.h', '.cpp', '.hpp', '.cs', '.swift', '.sql', '.sh', '.bash', '.zsh', '.log', '.svg', '.gradle', '.properties',
]);

export const kindOf = (name: string): Attachment['kind'] => (IMAGE_MIME_BY_EXT[extname(name).toLowerCase()] ? 'image' : 'file');

/** 파일명에서 경로 구분자·제어문자를 걷어내고 길이를 제한한다 */
export function safeFileName(name: string): string {
  const base = name.split(/[\\/]/).pop() ?? 'file';
  const cleaned = base.replace(/[\u0000-\u001f<>:"|?*]/g, '_').replace(/^\.+/, '').trim();
  return (cleaned || 'file').slice(0, 120);
}

/** 클라이언트가 보낸 첨부 목록을 검증한다: 작업 폴더의 uploads/ 아래에 실제로 있는 파일만 통과 */
export async function validateAttachments(workspace: string, input: unknown): Promise<Attachment[]> {
  if (!Array.isArray(input)) return [];
  const out: Attachment[] = [];
  for (const raw of input.slice(0, MAX_FILES)) {
    if (!raw || typeof raw !== 'object') continue;
    const p = (raw as { path?: unknown }).path;
    if (typeof p !== 'string' || !p) continue;
    const rel = normalize(p).replace(/^[\\/]+/, '');
    if (isAbsolute(rel) || rel.split(sep)[0] !== UPLOAD_DIR || rel.includes('..')) continue;
    const abs = join(workspace, rel);
    if (relative(workspace, abs).startsWith('..')) continue;
    try {
      const st = await stat(abs);
      if (!st.isFile()) continue;
      const name = safeFileName(rel.split(sep).pop() ?? 'file');
      out.push({ path: rel.split(sep).join('/'), name, mime: mimeOf(name), size: st.size, kind: kindOf(name) });
    } catch {
      // 없는 파일은 조용히 제외
    }
  }
  return out;
}

export function mimeOf(name: string): string {
  const ext = extname(name).toLowerCase();
  if (IMAGE_MIME_BY_EXT[ext]) return IMAGE_MIME_BY_EXT[ext];
  if (ext === '.pdf') return 'application/pdf';
  if (ext === '.json') return 'application/json';
  if (ext === '.svg') return 'image/svg+xml';
  return 'text/plain';
}

type ContentBlock =
  | { type: 'text'; text: string }
  | { type: 'image'; source: { type: 'base64'; media_type: 'image/jpeg' | 'image/png' | 'image/gif' | 'image/webp'; data: string } };

/**
 * 명령 + 첨부를 Messages API 콘텐츠 블록으로 만든다.
 * 이미지는 총괄 에이전트가 바로 볼 수 있게 base64 블록으로 넣고, 모든 첨부는 경로를 텍스트로도 적어
 * 서브에이전트(이전 대화를 못 봄)가 Read 도구로 읽을 수 있게 한다.
 */
export async function buildPromptContent(workspace: string, prompt: string, attachments: Attachment[]): Promise<string | ContentBlock[]> {
  if (attachments.length === 0) return prompt;

  const blocks: ContentBlock[] = [];
  const lines: string[] = [];
  for (const a of attachments) {
    const ext = extname(a.name).toLowerCase();
    const mediaType = IMAGE_MIME_BY_EXT[ext];
    let embedded = false;
    if (mediaType && a.size <= MAX_IMAGE_EMBED_BYTES) {
      try {
        const data = await readFile(join(workspace, a.path));
        blocks.push({ type: 'image', source: { type: 'base64', media_type: mediaType, data: data.toString('base64') } });
        embedded = true;
      } catch {
        // 읽기 실패 시 경로만 안내
      }
    }
    lines.push(`- ${a.path} (${a.kind === 'image' ? '이미지' : a.mime}, ${formatBytes(a.size)})${embedded ? ' — 위에 첨부된 이미지' : ''}`);
  }

  const text = [
    prompt,
    '',
    '## 첨부 파일',
    '사용자가 명령과 함께 아래 파일을 첨부했다. 작업 폴더 기준 경로이며, 서브에이전트에게 작업을 맡길 때는 이 경로를 그대로 알려줘서 Read 도구로 직접 읽게 해라.',
    ...lines,
  ].join('\n');

  return [...blocks, { type: 'text', text }];
}

function formatBytes(n: number) {
  if (n < 1024) return `${n}B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(0)}KB`;
  if (n < 1024 * 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)}MB`;
  return `${(n / 1024 / 1024 / 1024).toFixed(2)}GB`;
}
