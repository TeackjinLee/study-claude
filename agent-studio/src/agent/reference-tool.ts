import { stat } from 'node:fs/promises';
import { isAbsolute, join, normalize, relative } from 'node:path';
import { createSdkMcpServer, tool, type McpSdkServerConfigWithInstance } from '@anthropic-ai/claude-agent-sdk';
import { z } from 'zod';
import { isImagePath } from './artifact-utils.js';

/**
 * 레퍼런스 이미지 확인 도구 (Cowork 총괄용 MCP 서버 "studio").
 * Codex(GPT)로 만든 레퍼런스 이미지를 사용자에게 보여 주고 "이걸로 진행 / 다시 생성"을 받는다.
 * 실제 확인은 러너의 권한 처리(canUseTool)에서 이미지 승인 카드로 하고, 도구 본문은 승인됐을 때만 불린다.
 */
export const STUDIO_MCP_SERVER = 'studio';
export const REFERENCE_TOOL = `mcp__${STUDIO_MCP_SERVER}__confirm_reference`;

export function studioMcpServer(): McpSdkServerConfigWithInstance {
  return createSdkMcpServer({
    name: STUDIO_MCP_SERVER,
    version: '1.0.0',
    tools: [
      tool(
        'confirm_reference',
        '레퍼런스 이미지를 사용자에게 보여 주고 이걸로 구현을 진행할지 확인받는다. 구현을 시작하기 전에 반드시 부른다. ' +
          '승인되면 그 이미지를 기준으로 진행하고, 거절되면 구현하지 말고 프롬프트를 고쳐 다른 파일 이름으로 다시 생성한 뒤 다시 부른다.',
        {
          image_path: z.string().min(1).describe('작업 폴더 기준 레퍼런스 이미지 경로 (예: docs/refs/karaoke-1.png)'),
          target: z.string().min(1).describe('무엇을 위한 레퍼런스인지 (예: 노래방 건물 외형 — Building33_karaoke)'),
          summary: z.string().optional().describe('사용자에게 보여 줄 한두 줄 설명 (이미지에서 반영할 요소)'),
        },
        async ({ image_path, target }) => ({
          content: [{ type: 'text' as const, text: `사용자가 레퍼런스를 승인했다: ${image_path} (${target}). 이 이미지를 기준으로 구현하고, 구현 뒤 스크린샷과 나란히 비교해 차이를 줄인다.` }],
        }),
        { alwaysLoad: true },
      ),
    ],
  });
}

/** 작업 폴더 안의 실제 이미지 파일인지 확인하고 작업 폴더 기준 경로를 돌려준다 */
export async function resolveReferenceImage(workspaceDir: string, input: unknown): Promise<{ ok: true; rel: string } | { ok: false; error: string }> {
  const raw = typeof input === 'string' ? input.trim() : '';
  if (!raw) return { ok: false, error: 'image_path가 비어 있습니다.' };
  const rel = normalize(isAbsolute(raw) ? relative(workspaceDir, raw) : raw);
  if (rel.startsWith('..') || isAbsolute(rel)) return { ok: false, error: `작업 폴더 밖의 경로입니다: ${raw}` };
  if (!isImagePath(rel)) return { ok: false, error: `이미지 파일이 아닙니다: ${raw}` };
  try {
    const s = await stat(join(workspaceDir, rel));
    if (!s.isFile()) return { ok: false, error: `파일이 아닙니다: ${raw}` };
  } catch {
    return { ok: false, error: `이미지 파일이 없습니다: ${raw}. Codex 생성이 끝났는지, 저장 경로가 맞는지 확인하세요.` };
  }
  return { ok: true, rel };
}
