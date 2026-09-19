import type { AgentRole } from '@/types/agent';

export const SPRITE_W = 14;
export const SPRITE_H = 18;

/** 기본 7종 외의 에이전트(사용자 추가, Codex 등)에 쓰는 배지 */
export const DEFAULT_GLYPH: number[][] = [
  [0, 1, 1, 0],
  [1, 0, 0, 1],
  [1, 0, 0, 1],
  [0, 1, 1, 0],
];

/** 가슴에 새기는 4x4 역할 배지 패턴 (1 = 흰색 배지 픽셀). 실제 아이콘이라기보단 역할별로 다른 실루엣을 주기 위한 장식. */
export const ICON_GLYPHS: Record<AgentRole, number[][]> = {
  plan: [
    [0, 1, 1, 0],
    [1, 1, 1, 1],
    [0, 1, 1, 0],
    [0, 1, 1, 0],
  ],
  research: [
    [1, 1, 0, 0],
    [1, 1, 0, 0],
    [0, 0, 1, 1],
    [0, 0, 0, 1],
  ],
  code: [
    [1, 0, 0, 1],
    [0, 1, 1, 0],
    [0, 1, 1, 0],
    [1, 0, 0, 1],
  ],
  frontend: [
    [1, 1, 1, 1],
    [1, 0, 0, 1],
    [1, 0, 0, 1],
    [1, 1, 1, 1],
  ],
  test: [
    [0, 0, 0, 1],
    [0, 0, 1, 0],
    [1, 1, 0, 0],
    [1, 0, 0, 0],
  ],
  doc: [
    [1, 1, 1, 1],
    [1, 0, 0, 0],
    [1, 1, 1, 0],
    [1, 0, 0, 0],
  ],
  deploy: [
    [0, 1, 1, 0],
    [1, 1, 1, 1],
    [1, 0, 0, 1],
    [0, 1, 1, 0],
  ],
};

function darken(hex: string, amount: number): string {
  const n = parseInt(hex.slice(1), 16);
  const r = Math.max(0, ((n >> 16) & 0xff) - amount);
  const g = Math.max(0, ((n >> 8) & 0xff) - amount);
  const b = Math.max(0, (n & 0xff) - amount);
  return `#${((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1)}`;
}

export interface RolePalette {
  body: string;
  bodyShade: string;
  face: string;
  faceShade: string;
  eye: string;
  shoe: string;
  badge: string;
}

export function paletteFor(color: string): RolePalette {
  return {
    body: color,
    bodyShade: darken(color, 45),
    face: '#f2d9b8',
    faceShade: '#d9bd94',
    eye: '#1b1b2e',
    shoe: '#20202c',
    badge: '#ffffff',
  };
}
