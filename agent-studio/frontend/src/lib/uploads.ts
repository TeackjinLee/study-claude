/** 명령에 첨부하는 파일. 백엔드 /api/uploads 응답(Attachment)과 같은 모양 + 미리보기 URL */
export interface Attachment {
  /** 작업 폴더 기준 상대 경로 (uploads/...) */
  path: string;
  name: string;
  mime: string;
  size: number;
  kind: 'image' | 'file';
  /** 썸네일/미리보기용 URL (Live: 서버 /uploads/..., Mock: 브라우저 object URL) */
  url?: string;
}

export const MAX_FILES = 10;
export const MAX_FILE_BYTES = 1024 * 1024 * 1024; // 1GB
export const ACCEPT =
  '.png,.jpg,.jpeg,.gif,.webp,.pdf,.txt,.md,.mdx,.csv,.tsv,.json,.yaml,.yml,.xml,.toml,.html,.css,.scss,.js,.jsx,.ts,.tsx,.mjs,.cjs,.py,.java,.kt,.go,.rs,.rb,.php,.c,.h,.cpp,.hpp,.cs,.swift,.sql,.sh,.log,.svg';

const BACKEND_URL = process.env.NEXT_PUBLIC_BACKEND_URL ?? 'http://localhost:3000';
const isLive = (process.env.NEXT_PUBLIC_WS_MODE ?? 'mock') === 'live';

export const isImageFile = (f: File) => /^image\/(png|jpeg|gif|webp)$/.test(f.type);

export function formatBytes(n: number) {
  if (n < 1024) return `${n}B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(0)}KB`;
  if (n < 1024 * 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)}MB`;
  return `${(n / 1024 / 1024 / 1024).toFixed(2)}GB`;
}

/**
 * 파일을 서버에 올리고 명령에 붙일 Attachment 목록을 돌려준다.
 * Mock 모드는 서버가 없으니 올리지 않고 브라우저 안에서만 쓰는 가짜 경로를 만든다.
 */
export async function uploadFiles(files: File[]): Promise<Attachment[]> {
  if (files.length === 0) return [];
  if (!isLive) {
    return files.map((f) => ({
      path: `uploads/mock/${f.name}`,
      name: f.name,
      mime: f.type || 'application/octet-stream',
      size: f.size,
      kind: isImageFile(f) ? 'image' : 'file',
      url: URL.createObjectURL(f),
    }));
  }

  const form = new FormData();
  for (const f of files) form.append('files', f, f.name);
  const res = await fetch(`${BACKEND_URL}/api/uploads`, { method: 'POST', body: form });
  const body = (await res.json().catch(() => ({}))) as { files?: Attachment[]; message?: string | string[] };
  if (!res.ok) {
    const msg = Array.isArray(body.message) ? body.message.join(', ') : body.message;
    throw new Error(msg ?? `업로드 실패 (${res.status})`);
  }
  return (body.files ?? []).map((a) => ({ ...a, url: `${BACKEND_URL}/${a.path}` }));
}

/** 서버 이벤트(run_start)에 실려 온 첨부에 미리보기 URL을 붙인다 */
export function withUrls(list: Attachment[] | undefined): Attachment[] {
  return (list ?? []).map((a) => ({ ...a, url: a.url ?? (isLive ? `${BACKEND_URL}/${a.path}` : undefined) }));
}
