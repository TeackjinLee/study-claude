import type Phaser from 'phaser';
import type { AgentRole } from '@/types/agent';
import { DEFAULT_GLYPH, ICON_GLYPHS, SPRITE_H, SPRITE_W, paletteFor } from './characterDefs';

/**
 * 외부 이미지나 AI 생성 이미지 없이, 코드로 정의한 픽셀 격자를 런타임에
 * Phaser CanvasTexture로 구워내는 자체 캐릭터 생성기 (14x18px).
 * 포즈 프레임을 여러 장 만드는 대신, 하나의 정적 텍스처를 Phaser 트윈으로 움직여
 * Idle/Working/Testing 등 상태별 모션을 표현한다 (OfficeScene 참고).
 */
export function createCharacterTexture(scene: Phaser.Scene, role: AgentRole, color: string): string {
  const key = `agent-sprite-${role}`;
  if (scene.textures.exists(key)) return key;

  const tex = scene.textures.createCanvas(key, SPRITE_W, SPRITE_H);
  if (!tex) return key;
  const ctx = tex.getContext();
  const palette = paletteFor(color);
  const cx = SPRITE_W / 2 - 0.5;

  const px = (x: number, y: number, c: string) => {
    ctx.fillStyle = c;
    ctx.fillRect(x, y, 1, 1);
  };

  // 몸통 (x:2..11, y:7..15) — 모서리 4칸을 비워 살짝 둥글게
  for (let y = 7; y <= 15; y++) {
    for (let x = 2; x <= 11; x++) {
      if ((x === 2 || x === 11) && (y === 7 || y === 15)) continue;
      px(x, y, x > cx ? palette.bodyShade : palette.body);
    }
  }

  // 머리 (x:4..9, y:0..6)
  for (let y = 0; y <= 6; y++) {
    for (let x = 4; x <= 9; x++) {
      if ((x === 4 || x === 9) && (y === 0 || y === 6)) continue;
      px(x, y, x > cx ? palette.faceShade : palette.face);
    }
  }

  // 눈
  px(5, 3, palette.eye);
  px(8, 3, palette.eye);

  // 신발
  px(3, 16, palette.shoe);
  px(4, 16, palette.shoe);
  px(9, 16, palette.shoe);
  px(10, 16, palette.shoe);

  // 가슴 배지 (역할별 실루엣)
  const glyph = ICON_GLYPHS[role] ?? DEFAULT_GLYPH;
  for (let gy = 0; gy < 4; gy++) {
    for (let gx = 0; gx < 4; gx++) {
      if (glyph[gy][gx]) px(5 + gx, 9 + gy, palette.badge);
    }
  }

  tex.refresh();
  return key;
}
