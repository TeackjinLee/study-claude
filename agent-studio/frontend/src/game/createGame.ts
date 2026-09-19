import Phaser from 'phaser';
import { WORLD_HEIGHT, WORLD_WIDTH } from './map/officeMap';
import { OfficeScene } from './scenes/OfficeScene';

export function createGame(parent: HTMLElement): Phaser.Game {
  return new Phaser.Game({
    type: Phaser.AUTO,
    parent,
    // 캔버스는 컨테이너를 꽉 채우고(RESIZE), 씬 카메라가 월드를 FIT 방식으로 맞춘다 (OfficeScene.layoutCamera).
    width: WORLD_WIDTH,
    height: WORLD_HEIGHT,
    backgroundColor: '#08101f',
    // 글자는 부드럽게, 캐릭터/타일 텍스처만 개별적으로 NEAREST 필터를 준다 (OfficeScene 참고).
    antialias: true,
    roundPixels: true,
    // 게임 오디오는 쓰지 않고, 캔버스 우클릭 메뉴도 굳이 필요 없다.
    disableContextMenu: true,
    audio: { noAudio: true },
    scale: {
      mode: Phaser.Scale.RESIZE,
      autoCenter: Phaser.Scale.NO_CENTER,
      width: '100%',
      height: '100%',
    },
    scene: [OfficeScene],
  });
}
