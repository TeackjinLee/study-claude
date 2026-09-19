import Phaser from 'phaser';
import { STATUS_COLOR, type AgentDef, type AgentRole, type AgentState, type AgentStatus, type RoomId } from '@/types/agent';
import { OFFICE_IMAGE_URL, WORLD_HEIGHT, WORLD_WIDTH, pathLength, pointAt, seatFor, walkPath, type Point } from '../map/officeMap';
import { OFFICE_TEXTURE_KEY, drawOffice } from '../map/drawOffice';
import { createCharacterTexture } from '../sprites/spriteFactory';
import { pokemonSpriteUrl } from '../pokemon/fetchSprite';
import { useAgentStore } from '@/store/agentStore';

/** PokeAPI 스프라이트(96x96)를 사무실 캐릭터 크기로 줄이는 배율. 자체 픽셀 캐릭터(14x18)는 반대로 키운다. */
const POKEMON_SCALE = 0.85;
const FALLBACK_SCALE = 4.5;
const WALK_SPEED = 220; // px/s
const BUBBLE_Y = -92;
const FONT = '"Pretendard", "Apple SD Gothic Neo", "Noto Sans KR", system-ui, sans-serif';

const hex = (c: string) => Phaser.Display.Color.HexStringToColor(c).color;

interface AgentVisual {
  container: Phaser.GameObjects.Container;
  sprite: Phaser.GameObjects.Sprite;
  baseScale: number;
  shadow: Phaser.GameObjects.Ellipse;
  statusDot: Phaser.GameObjects.Arc;
  nameBg: Phaser.GameObjects.Graphics;
  nameText: Phaser.GameObjects.Text;
  bubbleBg: Phaser.GameObjects.Graphics;
  bubbleText: Phaser.GameObjects.Text;
  progressBg: Phaser.GameObjects.Graphics;
  progressText: Phaser.GameObjects.Text;
  /** 이동 경로를 점선으로 그리는 레이어 (컨테이너 밖, 바닥 위) */
  trail: Phaser.GameObjects.Graphics;
  /** 이 비주얼을 만들 때 쓴 정의의 외형 키 (캐릭터/색/이름이 바뀌면 다시 만든다) */
  lookKey: string;
  room: RoomId;
  status: AgentStatus;
  moveTween: Phaser.Tweens.Tween | null;
  loopTween: Phaser.Tweens.Tween | null;
  trailTween: Phaser.Tweens.Tween | null;
}

export class OfficeScene extends Phaser.Scene {
  private visuals = new Map<AgentRole, AgentVisual>();
  private unsubscribe: (() => void) | null = null;
  /** 현재 씬이 알고 있는 에이전트 정의 (자리 배치 계산용) */
  private defs: AgentDef[] = [];
  /** 같은 텍스처를 동시에 두 번 로드하지 않도록 진행 중인 로드를 기억 */
  private textureLoads = new Map<string, Promise<boolean>>();
  /** 개발 모드에서 React StrictMode가 씬을 두 번 만들었다가 하나를 바로 destroy할 때,
   *  먼저 만든 씬의 비동기 boot()가 destroy 이후에도 계속 돌지 않도록 막는 플래그. */
  private destroyed = false;

  constructor() {
    super('OfficeScene');
  }

  create() {
    this.destroyed = false;
    this.events.once(Phaser.Scenes.Events.SHUTDOWN, () => {
      this.destroyed = true;
    });
    this.events.once(Phaser.Scenes.Events.DESTROY, () => {
      this.destroyed = true;
    });

    this.layoutCamera(this.scale.width, this.scale.height);
    this.scale.on(Phaser.Scale.Events.RESIZE, this.onResize, this);
    this.events.once(Phaser.Scenes.Events.SHUTDOWN, () => this.scale.off(Phaser.Scale.Events.RESIZE, this.onResize, this));

    const loadingText = this.add
      .text(WORLD_WIDTH / 2, WORLD_HEIGHT / 2, '사무실을 불러오는 중...', {
        fontFamily: FONT,
        fontSize: '18px',
        color: '#e8ecff',
        backgroundColor: '#0b0f1ecc',
        padding: { x: 14, y: 8 },
      })
      .setOrigin(0.5)
      .setDepth(50);

    void this.boot(loadingText);
  }

  private onResize(gameSize: Phaser.Structs.Size) {
    this.layoutCamera(gameSize.width, gameSize.height);
  }

  /** 캔버스 크기에 맞춰 월드 전체가 보이도록 줌을 잡고 가운데 정렬한다 (FIT + 바깥은 복도 타일로 채움). */
  private layoutCamera(width: number, height: number) {
    if (width <= 0 || height <= 0) return;
    const zoom = Math.min(width / WORLD_WIDTH, height / WORLD_HEIGHT);
    const cam = this.cameras.main;
    cam.setZoom(zoom);
    cam.centerOn(WORLD_WIDTH / 2, WORLD_HEIGHT / 2);
  }

  private async boot(loadingText: Phaser.GameObjects.Text) {
    // 배경 그림을 먼저 받아 깔고(실패해도 단색 바닥으로 진행), 그 다음 에이전트를 올린다
    await this.loadTexture(OFFICE_TEXTURE_KEY, OFFICE_IMAGE_URL, false);
    if (this.destroyed) return;
    drawOffice(this);
    loadingText.setText('에이전트를 불러오는 중...');

    await this.syncDefs(useAgentStore.getState().defs);
    if (this.destroyed) return;
    loadingText.destroy();

    // 텍스처를 받는 동안 이벤트가 먼저 왔을 수 있으니 로드가 끝난 시점의 상태로 맞춘다
    const initial = useAgentStore.getState();
    if (initial.defs !== this.defs) await this.syncDefs(initial.defs);
    if (this.destroyed) return;
    for (const def of this.defs) {
      const st = initial.agents[def.id];
      if (st) this.syncAgent(def.id, st);
    }

    let lastDefs = initial.defs;
    this.unsubscribe = useAgentStore.subscribe((s) => {
      if (s.defs !== lastDefs) {
        lastDefs = s.defs;
        void this.syncDefs(s.defs);
      }
      for (const def of s.defs) {
        const st = s.agents[def.id];
        if (st) this.syncAgent(def.id, st);
      }
    });

    this.events.once(Phaser.Scenes.Events.SHUTDOWN, () => this.unsubscribe?.());
    this.events.once(Phaser.Scenes.Events.DESTROY, () => this.unsubscribe?.());
  }

  private lookKeyOf(def: AgentDef) {
    return `${def.pokemonId}|${def.color}|${def.shortName}`;
  }

  /**
   * 에이전트 정의 목록이 바뀌면 비주얼을 맞춘다: 새 에이전트는 만들고, 삭제된 건 지우고,
   * 캐릭터/색/이름이 바뀐 건 다시 만들고, 자리 배치가 달라졌으니 모두 제자리로 옮긴다.
   */
  private async syncDefs(defs: AgentDef[]) {
    this.defs = defs;
    const ids = new Set(defs.map((d) => d.id));

    for (const [role, v] of this.visuals) {
      if (!ids.has(role)) {
        this.destroyVisual(v);
        this.visuals.delete(role);
      }
    }

    await Promise.all(defs.map((d) => this.loadPokemonTexture(d.pokemonId)));
    if (this.destroyed) return;

    for (const def of defs) {
      const existing = this.visuals.get(def.id);
      if (existing && existing.lookKey === this.lookKeyOf(def)) continue;
      const keep = existing ? { room: existing.room, status: existing.status } : null;
      if (existing) {
        this.destroyVisual(existing);
        this.visuals.delete(def.id);
      }
      this.createAgentVisual(def, keep?.room ?? 'lounge');
      if (keep && keep.status !== 'idle') {
        const st = useAgentStore.getState().agents[def.id];
        if (st) this.syncAgent(def.id, st);
      }
    }

    // 인원이 바뀌면 같은 방 안에서도 자리가 밀리므로 모두 제자리로
    for (const [role, v] of this.visuals) this.settle(role, v.room);
  }

  private destroyVisual(v: AgentVisual) {
    v.moveTween?.stop();
    v.loopTween?.stop();
    v.trailTween?.stop();
    v.trail.destroy();
    v.container.destroy();
  }

  /** PokeAPI 스프라이트를 로더로 받는다. 실패하면 false (자체 픽셀 캐릭터로 대체). */
  private loadPokemonTexture(pokemonId: number): Promise<boolean> {
    return this.loadTexture(`pokemon-${pokemonId}`, pokemonSpriteUrl(pokemonId), true);
  }

  /** 이미지를 런타임에 로더로 받는다. 같은 키를 동시에 요청하면 진행 중인 로드를 함께 기다린다. */
  private loadTexture(key: string, url: string, pixelated: boolean): Promise<boolean> {
    if (this.textures.exists(key)) return Promise.resolve(true);
    const pending = this.textureLoads.get(key);
    if (pending) return pending;

    const promise = new Promise<boolean>((resolve) => {
      const done = (ok: boolean) => {
        this.textureLoads.delete(key);
        if (ok && pixelated && !this.destroyed && this.textures.exists(key)) {
          // 도트 스프라이트는 확대/축소해도 뭉개지지 않게
          this.textures.get(key).setFilter(Phaser.Textures.FilterMode.NEAREST);
        }
        resolve(ok);
      };
      this.load.once(`${Phaser.Loader.Events.FILE_COMPLETE}-image-${key}`, () => done(true));
      this.load.once(Phaser.Loader.Events.FILE_LOAD_ERROR, (file: { key: string }) => {
        if (file.key === key) done(false);
      });
      this.load.image(key, url);
      if (!this.load.isLoading()) this.load.start();
    });
    this.textureLoads.set(key, promise);
    return promise;
  }

  private textureFor(def: AgentDef): { key: string; scale: number } {
    const key = `pokemon-${def.pokemonId}`;
    if (this.textures.exists(key)) return { key, scale: POKEMON_SCALE };
    const fallback = createCharacterTexture(this, def.id, def.color);
    this.textures.get(fallback).setFilter(Phaser.Textures.FilterMode.NEAREST);
    return { key: fallback, scale: FALLBACK_SCALE };
  }

  private createAgentVisual(def: AgentDef, room: RoomId) {
    const role = def.id;
    const { key, scale } = this.textureFor(def);
    const pos = seatFor(role, room, this.defs);

    const shadow = this.add.ellipse(0, 6, 50, 14, 0x000000, 0.35);
    const sprite = this.add.sprite(0, 0, key).setScale(scale).setOrigin(0.5, 0.85);

    const nameBg = this.add.graphics();
    const nameText = this.add
      .text(0, 26, def.shortName, { fontFamily: FONT, fontSize: '13px', fontStyle: '700', color: '#ffffff' })
      .setOrigin(0.5);
    const statusDot = this.add.circle(0, 0, 4, hex(STATUS_COLOR.idle)).setStrokeStyle(1.5, 0x0b0f1e);

    const progressBg = this.add.graphics();
    const progressText = this.add
      .text(0, 50, '', { fontFamily: FONT, fontSize: '12px', fontStyle: '700', color: '#ffffff' })
      .setOrigin(0, 0.5);

    const bubbleBg = this.add.graphics();
    const bubbleText = this.add
      .text(0, BUBBLE_Y, '', {
        fontFamily: FONT,
        fontSize: '14px',
        fontStyle: '600',
        color: '#0f172a',
        align: 'center',
        wordWrap: { width: 180 },
      })
      .setOrigin(0.5, 1);

    const trail = this.add.graphics().setDepth(2);

    const container = this.add.container(pos.x, pos.y, [
      shadow,
      sprite,
      nameBg,
      nameText,
      statusDot,
      progressBg,
      progressText,
      bubbleBg,
      bubbleText,
    ]);
    container.setDepth(10 + pos.y / 1000);

    this.visuals.set(role, {
      container,
      sprite,
      baseScale: scale,
      shadow,
      statusDot,
      nameBg,
      nameText,
      bubbleBg,
      bubbleText,
      progressBg,
      progressText,
      trail,
      lookKey: this.lookKeyOf(def),
      room,
      status: 'idle',
      moveTween: null,
      loopTween: null,
      trailTween: null,
    });

    this.drawNameTag(role, def.color);
    this.playLoop(role, 'idle');
    this.updateBubble(role, '대기중');
  }

  /** 자취 없이 현재 방의 제자리로 살짝 이동 (인원 변경으로 자리가 바뀌었을 때) */
  private settle(role: AgentRole, room: RoomId) {
    const v = this.visuals.get(role);
    if (!v || v.moveTween?.isPlaying()) return;
    const to = seatFor(role, room, this.defs);
    if (Math.abs(v.container.x - to.x) < 1 && Math.abs(v.container.y - to.y) < 1) return;
    v.moveTween = this.tweens.add({
      targets: v.container,
      x: to.x,
      y: to.y,
      duration: 500,
      ease: 'Sine.easeInOut',
      onComplete: () => v.container.setDepth(10 + to.y / 1000),
    });
  }

  private drawNameTag(role: AgentRole, color: string) {
    const v = this.visuals.get(role);
    if (!v) return;
    const w = v.nameText.width + 26;
    const h = 22;
    const y = 26;
    v.nameBg.clear();
    v.nameBg.fillStyle(0x0b0f1e, 0.85);
    v.nameBg.fillRoundedRect(-w / 2, y - h / 2, w, h, 5);
    v.nameBg.lineStyle(1, hex(color), 0.9);
    v.nameBg.strokeRoundedRect(-w / 2, y - h / 2, w, h, 5);
    v.nameText.setX(4);
    v.statusDot.setPosition(-w / 2 + 9, y);
  }

  private syncAgent(role: AgentRole, state: AgentState) {
    const v = this.visuals.get(role);
    if (!v) return;

    if (state.room !== v.room) {
      const fromRoom = v.room;
      v.room = state.room;
      this.moveTo(role, fromRoom, state.room);
    }

    if (state.status !== v.status) {
      v.status = state.status;
      this.playLoop(role, state.status);
      v.statusDot.setFillStyle(hex(STATUS_COLOR[state.status]));
    }

    this.updateBubble(role, state.message);
    this.updateProgress(role, state.progress);
  }

  private moveTo(role: AgentRole, fromRoom: RoomId, toRoom: RoomId) {
    const v = this.visuals.get(role);
    if (!v) return;
    const from: Point = { x: v.container.x, y: v.container.y };
    const to = seatFor(role, toRoom, this.defs);
    const path = walkPath(from, fromRoom, toRoom, to);
    const duration = Math.max(400, (pathLength(path) / WALK_SPEED) * 1000);

    this.drawTrail(role, path);

    v.moveTween?.stop();
    const progress = { t: 0 };
    v.moveTween = this.tweens.add({
      targets: progress,
      t: 1,
      duration,
      ease: 'Sine.easeInOut',
      onUpdate: () => {
        const p = pointAt(path, progress.t);
        // 걷는 동안 살짝 통통 튀게
        const hop = Math.abs(Math.sin(progress.t * duration * 0.012)) * 4;
        v.container.setPosition(p.x, p.y - hop);
        v.container.setDepth(10 + p.y / 1000);
      },
      onComplete: () => {
        v.container.setPosition(to.x, to.y);
        v.container.setDepth(10 + to.y / 1000);
        this.fadeTrail(role);
      },
    });
  }

  /** 시안의 색 점선처럼, 에이전트 색으로 이동 경로를 바닥에 그린다. */
  private drawTrail(role: AgentRole, path: Point[]) {
    const v = this.visuals.get(role);
    if (!v) return;
    v.trailTween?.stop();
    v.trail.clear().setAlpha(1);
    const color = hex(this.defs.find((d) => d.id === role)?.color ?? '#ffffff');
    const dash = 8;
    const gap = 6;
    v.trail.fillStyle(color, 0.9);
    for (let i = 1; i < path.length; i++) {
      const a = path[i - 1];
      const b = path[i];
      const len = Math.hypot(b.x - a.x, b.y - a.y);
      if (len === 0) continue;
      const ux = (b.x - a.x) / len;
      const uy = (b.y - a.y) / len;
      for (let d = 0; d < len; d += dash + gap) {
        const l = Math.min(dash, len - d);
        const sx = a.x + ux * d;
        const sy = a.y + uy * d;
        if (Math.abs(ux) > Math.abs(uy)) v.trail.fillRect(Math.min(sx, sx + ux * l), sy - 1.5, l, 3);
        else v.trail.fillRect(sx - 1.5, Math.min(sy, sy + uy * l), 3, l);
      }
    }
    // 도착 지점 표시
    const end = path[path.length - 1];
    v.trail.fillStyle(color, 0.9);
    v.trail.fillCircle(end.x, end.y + 2, 5);
    v.trail.lineStyle(2, 0xffffff, 0.8);
    v.trail.strokeCircle(end.x, end.y + 2, 5);
  }

  private fadeTrail(role: AgentRole) {
    const v = this.visuals.get(role);
    if (!v) return;
    v.trailTween = this.tweens.add({ targets: v.trail, alpha: 0, duration: 1800, delay: 800 });
  }

  private playLoop(role: AgentRole, status: AgentStatus) {
    const v = this.visuals.get(role);
    if (!v) return;
    v.loopTween?.stop();
    const s = v.baseScale;
    v.sprite.setAngle(0).setPosition(0, 0).setScale(s, s);

    switch (status) {
      case 'idle':
        v.loopTween = this.tweens.add({ targets: v.sprite, y: -3, duration: 1200, yoyo: true, repeat: -1, ease: 'Sine.easeInOut' });
        break;
      case 'thinking':
        v.loopTween = this.tweens.add({
          targets: v.sprite,
          angle: { from: -5, to: 5 },
          duration: 520,
          yoyo: true,
          repeat: -1,
          ease: 'Sine.easeInOut',
        });
        break;
      case 'working':
        v.loopTween = this.tweens.add({ targets: v.sprite, y: -2, duration: 180, yoyo: true, repeat: -1, ease: 'Sine.easeInOut' });
        break;
      case 'testing':
      case 'deploying':
        v.loopTween = this.tweens.add({
          targets: v.sprite,
          scaleX: s * 1.08,
          scaleY: s * 0.92,
          duration: 280,
          yoyo: true,
          repeat: -1,
          ease: 'Sine.easeInOut',
        });
        break;
      case 'completed':
        v.loopTween = this.tweens.add({ targets: v.sprite, scale: s * 1.25, y: -10, duration: 240, yoyo: true, ease: 'Back.easeOut' });
        break;
      case 'error':
        v.loopTween = this.tweens.add({ targets: v.sprite, x: 4, duration: 60, yoyo: true, repeat: 5 });
        break;
    }
  }

  /** 흰색 말풍선 + 꼬리. 테두리 색은 현재 상태색. */
  private updateBubble(role: AgentRole, text: string) {
    const v = this.visuals.get(role);
    if (!v) return;
    if (!text || v.status === 'idle') {
      v.bubbleBg.clear();
      v.bubbleText.setText('');
      return;
    }
    v.bubbleText.setText(text);
    const w = Math.max(v.bubbleText.width + 20, 40);
    const h = v.bubbleText.height + 12;
    const color = hex(STATUS_COLOR[v.status]);
    const top = BUBBLE_Y - h - 6;

    v.bubbleBg.clear();
    v.bubbleBg.fillStyle(0x0b0f1e, 0.35);
    v.bubbleBg.fillRoundedRect(-w / 2 + 2, top + 3, w, h, 8);
    v.bubbleBg.fillStyle(0xffffff, 1);
    v.bubbleBg.fillRoundedRect(-w / 2, top, w, h, 8);
    v.bubbleBg.lineStyle(2, color, 1);
    v.bubbleBg.strokeRoundedRect(-w / 2, top, w, h, 8);
    // 꼬리
    v.bubbleBg.fillStyle(0xffffff, 1);
    v.bubbleBg.fillTriangle(-6, top + h - 1, 6, top + h - 1, 0, top + h + 7);
    v.bubbleBg.lineStyle(2, color, 1);
    v.bubbleBg.lineBetween(-6, top + h, 0, top + h + 7);
    v.bubbleBg.lineBetween(6, top + h, 0, top + h + 7);
    v.bubbleText.setY(top + h - 6);
  }

  /** 이름표 아래 진행률 막대 + 퍼센트 */
  private updateProgress(role: AgentRole, progress?: number) {
    const v = this.visuals.get(role);
    if (!v) return;
    v.progressBg.clear();
    if (progress === undefined || v.status === 'idle') {
      v.progressText.setText('');
      return;
    }
    const pct = Math.min(100, Math.max(0, progress));
    const barW = 64;
    const h = 8;
    const y = 50;
    const totalW = barW + 42;
    const x = -totalW / 2;
    const color = hex(STATUS_COLOR[v.status]);

    v.progressBg.fillStyle(0x0b0f1e, 0.85);
    v.progressBg.fillRoundedRect(x - 4, y - 8, totalW + 8, 16, 8);
    v.progressBg.fillStyle(0x2a3352, 1);
    v.progressBg.fillRoundedRect(x, y - h / 2, barW, h, 4);
    v.progressBg.fillStyle(color, 1);
    v.progressBg.fillRoundedRect(x, y - h / 2, Math.max(6, (barW * pct) / 100), h, 4);
    v.progressText.setText(`${Math.round(pct)}%`).setPosition(x + barW + 6, y);
  }
}
