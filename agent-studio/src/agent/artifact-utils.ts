import { extname } from 'node:path';
import type { ArtifactKind } from './ui-events.js';

/** 결과 미리보기에 올릴 산출물 판별/표시용 헬퍼. MessageMapper(Claude)와 CodexBridge(Codex)가 같이 쓴다. */

export const TEST_COMMAND = /\b(test|tests|vitest|jest|pytest|mocha|gradle|mvn|go test|cargo test)\b/i;

export const LANG_BY_EXT: Record<string, string> = {
  '.ts': 'TypeScript', '.tsx': 'TSX', '.js': 'JavaScript', '.jsx': 'JSX', '.mjs': 'JavaScript',
  '.java': 'Java', '.kt': 'Kotlin', '.py': 'Python', '.go': 'Go', '.rs': 'Rust',
  '.json': 'JSON', '.html': 'HTML', '.css': 'CSS', '.sql': 'SQL', '.yml': 'YAML', '.yaml': 'YAML',
  '.sh': 'Shell', '.md': 'Markdown', '.gradle': 'Gradle', '.xml': 'XML',
};

export const DOC_EXT = new Set(['.md', '.mdx', '.txt']);

/** 결과 텍스트 최대 길이 (결과 미리보기 한 항목) */
export const ARTIFACT_MAX_CHARS = 20000;

export const str = (v: unknown) => (typeof v === 'string' ? v : '');
export const clip = (text: string, max: number) => (text.length > max ? `${text.slice(0, max)}…` : text);
export const oneLine = (text: string, max = 120) => clip(text.replace(/\s+/g, ' ').trim(), max);

/** 파일 경로로 산출물 종류를 정한다. 문서 확장자면 doc, 아니면 code (테스트 여부는 호출자가 판단) */
export const IMAGE_EXT = new Set(['.png', '.jpg', '.jpeg', '.webp', '.gif', '.svg']);
export const isImagePath = (path: string) => IMAGE_EXT.has(extname(path).toLowerCase());
/** 대시보드가 작업 폴더의 이미지를 받아 보는 주소 (uploads.controller) */
export const workspaceFileUrl = (rel: string) => `/api/workspace-files/${rel.split('/').map(encodeURIComponent).join('/')}`;

/**
 * 총괄 요약 끝의 <next-steps> 블록을 떼어낸다. 본문은 블록을 뺀 텍스트, suggestions는 '- ' 줄들(최대 5개).
 * 블록이 없으면 원문 그대로, 빈 목록.
 */
export function splitNextSteps(text: string): { body: string; suggestions: string[] } {
  const m = /<next-steps>([\s\S]*?)<\/next-steps>/i.exec(text);
  if (!m) return { body: text, suggestions: [] };
  const suggestions = m[1]
    .split('\n')
    .map((l) => l.replace(/^\s*(?:[-*•]|\d+[.)])\s*/, '').trim())
    .filter((l) => l.length > 0 && l.length <= 80)
    .slice(0, 5);
  const body = (text.slice(0, m.index) + text.slice(m.index + m[0].length)).replace(/\n{3,}/g, '\n\n').trim();
  return { body, suggestions };
}

export const artifactKindOf = (path: string): ArtifactKind => (isImagePath(path) ? 'image' : DOC_EXT.has(extname(path).toLowerCase()) ? 'doc' : 'code');

export const langOf = (path: string) => {
  const ext = extname(path).toLowerCase();
  return LANG_BY_EXT[ext] ?? (ext.slice(1).toUpperCase() || 'Text');
};
