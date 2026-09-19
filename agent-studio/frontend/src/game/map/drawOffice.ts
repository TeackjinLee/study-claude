import Phaser from 'phaser';
import { ROOMS, WORLD_HEIGHT, WORLD_WIDTH, type RoomDef } from './officeMap';

/** public/office.png 를 로더에 등록할 때 쓰는 텍스처 키 */
export const OFFICE_TEXTURE_KEY = 'office-map';

const FONT = '"Pretendard", "Apple SD Gothic Neo", "Noto Sans KR", system-ui, sans-serif';

/** 방 이름표: 흰 알약 + 그림자. 방 윗벽 위에 얹는다 */
function label(scene: Phaser.Scene, room: RoomDef) {
  const cx = room.x + room.w / 2;
  const cy = room.y + 14;
  const text = scene.add
    .text(cx, cy, room.label, { fontFamily: FONT, fontSize: '17px', fontStyle: '700', color: '#0f172a' })
    .setOrigin(0.5)
    .setDepth(6);
  const w = text.width + 30;
  const h = 30;
  const g = scene.add.graphics().setDepth(5);
  g.fillStyle(0x0b0f1e, 0.5);
  g.fillRoundedRect(cx - w / 2 + 2, cy - h / 2 + 3, w, h, 8);
  g.fillStyle(0xf4f6ff, 1);
  g.fillRoundedRect(cx - w / 2, cy - h / 2, w, h, 8);
  g.lineStyle(2, 0x1e2a4a, 1);
  g.strokeRoundedRect(cx - w / 2, cy - h / 2, w, h, 8);
}

/**
 * 사무실 배경. 그림 한 장(office.png)을 깔고 그 위에 방 이름표만 얹는다.
 * 텍스처(OFFICE_TEXTURE_KEY)는 씬이 먼저 로더로 받아 두어야 한다. 못 받았으면 어두운 바닥만 깐다.
 */
export function drawOffice(scene: Phaser.Scene) {
  if (scene.textures.exists(OFFICE_TEXTURE_KEY)) {
    scene.add.image(0, 0, OFFICE_TEXTURE_KEY).setOrigin(0, 0).setDepth(0).setDisplaySize(WORLD_WIDTH, WORLD_HEIGHT);
  } else {
    const g = scene.add.graphics().setDepth(0);
    g.fillStyle(0x1a1f33, 1);
    g.fillRect(0, 0, WORLD_WIDTH, WORLD_HEIGHT);
    for (const room of ROOMS) {
      g.fillStyle(0x2a3352, 1);
      g.fillRoundedRect(room.x, room.y, room.w, room.h, 12);
    }
  }
  for (const room of ROOMS) label(scene, room);
}
