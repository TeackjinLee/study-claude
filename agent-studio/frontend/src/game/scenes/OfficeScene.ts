import Phaser from 'phaser';
import { MASTER_ID, STATUS_COLOR, type AgentDef, type AgentRole, type AgentState, type AgentStatus, type MasterDef, type RoomId } from '@/types/agent';
import { CORRIDOR_MID_Y, OFFICE_IMAGE_URL, ROOMS, ROOM_BY_ID, WORLD_HEIGHT, WORLD_WIDTH, pathLength, pointAt, seatFor, type Point } from '../map/officeMap';
import { OFFICE_TEXTURE_KEY, drawOffice } from '../map/drawOffice';
import { createCharacterTexture } from '../sprites/spriteFactory';
import { pokemonSpriteUrl } from '../pokemon/fetchSprite';
import { useAgentStore } from '@/store/agentStore';

/** PokeAPI 스프라이트(96x96)를 사무실 캐릭터 크기로 줄이는 배율. 자체 픽셀 캐릭터(14x18)는 반대로 키운다. */
const POKEMON_SCALE = 0.85;
const FALLBACK_SCALE = 4.5;
const WALK_SPEED = 220; // px/s
/** Master(사용자)가 방향키로 걷는 속도 */
const MASTER_SPEED = 230; // px/s
/** 이 거리(px) 안이면 에이전트에게 말을 걸 수 있다 */
const TALK_RANGE = 100;
/** Master 말풍선 유지 시간 */
const MASTER_SAY_MS = 7000;
/** 복도(윗줄 방과 아랫줄 방 사이) 걷기 가능 구간 */
const CORRIDOR = { x: 60, y: 336, w: WORLD_WIDTH - 120, h: 68 };
/** 방 안에서 벽으로 치는 여백과 문 통로 폭 */
const WALL = 10;
const DOOR_HALF_W = 26;
const BUBBLE_Y = -92;

/** 지금 글자를 입력하는 중이면 방향키/E 를 캐릭터 조작으로 쓰지 않는다 */
function isTyping(): boolean {
  const el = typeof document !== 'undefined' ? document.activeElement : null;
  if (!el) return false;
  const tag = el.tagName;
  return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || (el as HTMLElement).isContentEditable;
}

/** 이 점이 어느 방 안인지 (복도/벽이면 null) */
function roomAt(p: Point): RoomId | null {
  for (const r of ROOMS) {
    if (p.x >= r.x + WALL && p.x <= r.x + r.w - WALL && p.y >= r.y + WALL && p.y <= r.y + r.h - WALL) return r.id;
  }
  return null;
}

/** 문 통로 안인지 (방 아래/위 벽을 뚫고 복도로 이어지는 짧은 구간) */
function inDoorway(p: Point): boolean {
  for (const r of ROOMS) {
    if (Math.abs(p.x - r.door.x) > DOOR_HALF_W) continue;
    const top = r.y + r.h <= CORRIDOR.y + 10; // 윗줄 방이면 문이 방 아래쪽
    const y0 = top ? r.y + r.h - WALL - 8 : CORRIDOR.y;
    const y1 = top ? CORRIDOR.y + CORRIDOR.h : r.y + WALL + 8;
    if (p.y >= y0 && p.y <= y1) return true;
  }
  return false;
}

function inCorridor(p: Point): boolean {
  return p.x >= CORRIDOR.x && p.x <= CORRIDOR.x + CORRIDOR.w && p.y >= CORRIDOR.y && p.y <= CORRIDOR.y + CORRIDOR.h;
}

/** Master가 설 수 있는 자리인지: 방 안, 복도, 문 통로 */
function canStand(p: Point): boolean {
  return roomAt(p) !== null || inCorridor(p) || inDoorway(p);
}

/** 문과 복도를 거쳐 가는 폴리라인. 같은 구역이면 직선. */
function routeTo(from: Point, to: Point): Point[] {
  const a = roomAt(from);
  const b = roomAt(to);
  if (a === b) return [from, to];
  const path: Point[] = [from];
  if (a) {
    const ra = ROOM_BY_ID[a];
    path.push({ x: ra.door.x, y: from.y }, { x: ra.door.x, y: CORRIDOR_MID_Y });
  }
  if (b) {
    const rb = ROOM_BY_ID[b];
    path.push({ x: rb.door.x, y: CORRIDOR_MID_Y }, { x: rb.door.x, y: to.y });
  }
  path.push(to);
  return path;
}
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
  /** Master(사용자) 캐릭터 정의 — 비주얼은 visuals[MASTER_ID] */
  private masterDef: MasterDef | null = null;
  private keys: Record<'up' | 'down' | 'left' | 'right' | 'w' | 'a' | 's' | 'd' | 'e' | 'enter', Phaser.Input.Keyboard.Key> | null = null;
  /** 대화 가능 거리 안의 에이전트 발밑에 그리는 표시 */
  private nearRing: Phaser.GameObjects.Graphics | null = null;
  private hintText: Phaser.GameObjects.Text | null = null;
  private nearby: AgentRole | null = null;
  private sayTimer: Phaser.Time.TimerEvent | null = null;
  /** 지금 Master와 대화 중인 에이전트 — 답하는 동안 자기 방으로 걸어가지 않고 제자리에서 말한다 */
  private talkingWith: AgentRole | null = null;

  constructor() {
    super('OfficeScene');
  }

  create() {
    this.destroyed = false;
    // 개발 중 콘솔에서 씬을 들여다볼 수 있게 (프로덕션 빌드에서는 빠진다)
    if (process.env.NODE_ENV !== 'production') (window as unknown as { __officeScene?: OfficeScene }).__officeScene = this;
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

    await this.syncMaster(initial.master);
    if (this.destroyed) return;
    this.setupMasterControls();

    let lastDefs = initial.defs;
    let lastMaster = initial.master;
    let lastSay = initial.masterSay;
    this.unsubscribe = useAgentStore.subscribe((s) => {
      if (s.defs !== lastDefs) {
        lastDefs = s.defs;
        void this.syncDefs(s.defs);
      }
      if (s.master !== lastMaster) {
        lastMaster = s.master;
        void this.syncMaster(s.master);
      }
      if (s.masterSay !== lastSay) {
        lastSay = s.masterSay;
        if (s.masterSay) this.onMasterSay(s.masterSay.to, s.masterSay.text);
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
      if (!ids.has(role) && role !== MASTER_ID) {
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

    // 인원이 바뀌면 같은 방 안에서도 자리가 밀리므로 모두 제자리로 (Master는 자기 마음대로 움직이니 제외)
    for (const [role, v] of this.visuals) if (role !== MASTER_ID) this.settle(role, v.room);
  }

  /** Master 캐릭터를 만들거나(처음), 캐릭터/이름/색이 바뀌면 그 자리에 다시 만든다 */
  private async syncMaster(master: MasterDef) {
    this.masterDef = master;
    const def = this.masterAsDef(master);
    await this.loadPokemonTexture(master.pokemonId);
    if (this.destroyed) return;
    const existing = this.visuals.get(MASTER_ID);
    if (existing && existing.lookKey === this.lookKeyOf(def)) return;
    const pos = existing ? { x: existing.container.x, y: existing.container.y } : { x: ROOM_BY_ID.entrance.x + 125, y: ROOM_BY_ID.entrance.y + 200 };
    if (existing) {
      this.destroyVisual(existing);
      this.visuals.delete(MASTER_ID);
    }
    this.createAgentVisual(def, 'entrance');
    const v = this.visuals.get(MASTER_ID);
    if (!v) return;
    v.container.setPosition(pos.x, pos.y).setDepth(10 + pos.y / 1000);
    v.container.disableInteractive();
    // 상태 점 대신 왕관 느낌의 밝은 점: Master는 작업 상태가 없다
    v.statusDot.setFillStyle(hex(master.color));
    this.updateBubble(MASTER_ID, '');
  }

  private masterAsDef(master: MasterDef): AgentDef {
    return {
      id: MASTER_ID,
      sdkName: MASTER_ID,
      name: master.name,
      shortName: master.name,
      roleLabel: '사용자',
      description: '',
      taskLabel: '',
      room: 'entrance',
      color: master.color,
      pokemonId: master.pokemonId,
      pokemonName: master.pokemonName,
      tools: [],
      sdkDescription: '',
      prompt: '',
    };
  }

  /** 방향키/WASD 이동, E·Enter 로 옆 에이전트에게 말 걸기, 바닥 클릭으로 걸어가기, 에이전트 클릭으로 다가가기 */
  private setupMasterControls() {
    const kb = this.input.keyboard;
    if (!kb) return;
    const K = Phaser.Input.Keyboard.KeyCodes;
    // 두 번째 인자 false: 브라우저 기본 동작을 막지 않는다 (입력창 타이핑에 방해되지 않게). 타이핑 중 여부는 update()에서 본다
    const key = (code: number) => kb.addKey(code, false);
    this.keys = {
      up: key(K.UP),
      down: key(K.DOWN),
      left: key(K.LEFT),
      right: key(K.RIGHT),
      w: key(K.W),
      a: key(K.A),
      s: key(K.S),
      d: key(K.D),
      e: key(K.E),
      enter: key(K.ENTER),
    };
    this.nearRing = this.add.graphics().setDepth(3);
    this.hintText = this.add
      .text(0, 0, '', { fontFamily: FONT, fontSize: '12px', fontStyle: '700', color: '#0b0f1e', backgroundColor: '#ffe066', padding: { x: 6, y: 2 } })
      .setOrigin(0.5, 1)
      .setDepth(40)
      .setVisible(false);

    this.input.on(Phaser.Input.Events.POINTER_DOWN, (pointer: Phaser.Input.Pointer, over: Phaser.GameObjects.GameObject[]) => {
      if (over.length > 0) return; // 에이전트를 클릭한 경우는 컨테이너 핸들러가 처리
      const target = { x: pointer.worldX, y: pointer.worldY };
      if (!canStand(target)) return;
      this.walkMasterTo(target);
    });
    for (const [role, v] of this.visuals) if (role !== MASTER_ID) this.makeApproachable(role, v);
  }

  /** 에이전트 컨테이너를 클릭하면 Master가 옆으로 걸어가 말을 걸 준비를 한다 */
  private makeApproachable(role: AgentRole, v: AgentVisual) {
    // 히트 영역은 스프라이트가 그려지는 곳(발 위쪽)에 맞춘다. 발 기준으로 잡으면 아래 줄 에이전트의 영역과 겹쳐 잘못 클릭된다
    v.container.setInteractive(new Phaser.Geom.Rectangle(-30, -82, 60, 96), Phaser.Geom.Rectangle.Contains);
    if (v.container.input) v.container.input.cursor = 'pointer';
    v.container.on(Phaser.Input.Events.GAMEOBJECT_POINTER_DOWN, () => this.approach(role));
  }

  private approach(role: AgentRole) {
    const target = this.visuals.get(role);
    const me = this.visuals.get(MASTER_ID);
    if (!target || !me) return;
    // 다른 에이전트가 서 있지 않은 빈 옆자리를 고른다 (왼쪽 → 오른쪽 → 앞)
    const candidates = [
      { x: target.container.x - 62, y: target.container.y + 6 },
      { x: target.container.x + 62, y: target.container.y + 6 },
      { x: target.container.x, y: target.container.y + 48 },
    ];
    const occupied = (p: Point) =>
      [...this.visuals].some(([r, o]) => r !== MASTER_ID && r !== role && Phaser.Math.Distance.Between(p.x, p.y, o.container.x, o.container.y) < 40);
    const spot = candidates.find((p) => canStand(p) && !occupied(p)) ?? candidates.find((p) => canStand(p)) ?? candidates[0];
    this.walkMasterTo(spot, () => this.startTalk(role));
  }

  private startTalk(role: AgentRole) {
    const store = useAgentStore.getState();
    store.setTalkTarget(role);
    window.dispatchEvent(new CustomEvent('agent-studio:focus-command'));
  }

  /** Master를 목적지까지 걷게 한다 (문·복도 경유). 방향키를 누르면 멈춘다 */
  private walkMasterTo(to: Point, onArrive?: () => void) {
    const v = this.visuals.get(MASTER_ID);
    if (!v) return;
    const from: Point = { x: v.container.x, y: v.container.y };
    const path = routeTo(from, to);
    const duration = Math.max(200, (pathLength(path) / MASTER_SPEED) * 1000);
    this.drawTrail(MASTER_ID, path);
    v.moveTween?.stop();
    const progress = { t: 0 };
    v.moveTween = this.tweens.add({
      targets: progress,
      t: 1,
      duration,
      ease: 'Sine.easeInOut',
      onUpdate: () => {
        const p = pointAt(path, progress.t);
        const hop = Math.abs(Math.sin(progress.t * duration * 0.012)) * 4;
        v.container.setPosition(p.x, p.y - hop);
        v.container.setDepth(10 + p.y / 1000);
      },
      onComplete: () => {
        v.container.setPosition(to.x, to.y);
        v.container.setDepth(10 + to.y / 1000);
        this.fadeTrail(MASTER_ID);
        onArrive?.();
      },
    });
  }

  /** 사용자가 에이전트에게 한 말: Master 말풍선으로 띄우고, 멀리 있으면 그 에이전트 옆으로 걸어간다 */
  private onMasterSay(to: AgentRole, text: string) {
    const me = this.visuals.get(MASTER_ID);
    const target = this.visuals.get(to);
    if (!me) return;
    this.talkingWith = to;
    this.updateBubble(MASTER_ID, text, this.masterDef?.color ?? '#ffffff');
    this.sayTimer?.remove(false);
    this.sayTimer = this.time.delayedCall(MASTER_SAY_MS, () => this.updateBubble(MASTER_ID, ''));
    if (target && Phaser.Math.Distance.Between(me.container.x, me.container.y, target.container.x, target.container.y) > TALK_RANGE) {
      this.approach(to);
    }
  }

  update(_time: number, delta: number) {
    const v = this.visuals.get(MASTER_ID);
    if (!v || !this.keys) return;
    const k = this.keys;

    if (!isTyping()) {
      const dx = (k.right.isDown || k.d.isDown ? 1 : 0) - (k.left.isDown || k.a.isDown ? 1 : 0);
      const dy = (k.down.isDown || k.s.isDown ? 1 : 0) - (k.up.isDown || k.w.isDown ? 1 : 0);
      if (dx !== 0 || dy !== 0) {
        if (v.moveTween?.isPlaying()) {
          v.moveTween.stop();
          this.fadeTrail(MASTER_ID);
        }
        const step = (MASTER_SPEED * delta) / 1000;
        const len = Math.hypot(dx, dy);
        const nx = v.container.x + (dx / len) * step;
        const ny = v.container.y + (dy / len) * step;
        // 벽에 닿으면 한 축만 미끄러진다
        if (canStand({ x: nx, y: ny })) v.container.setPosition(nx, ny);
        else if (canStand({ x: nx, y: v.container.y })) v.container.setX(nx);
        else if (canStand({ x: v.container.x, y: ny })) v.container.setY(ny);
        v.container.setDepth(10 + v.container.y / 1000);
        v.sprite.setFlipX(dx < 0);
      }
      if (this.nearby && (Phaser.Input.Keyboard.JustDown(k.e) || Phaser.Input.Keyboard.JustDown(k.enter))) this.startTalk(this.nearby);
    }

    // 대화 가능 거리 안의 가장 가까운 에이전트. 이미 말하는 상대가 거리 안에 있으면 그쪽을 우선한다
    let nearest: AgentRole | null = null;
    let best = TALK_RANGE;
    for (const [role, other] of this.visuals) {
      if (role === MASTER_ID) continue;
      const d = Phaser.Math.Distance.Between(v.container.x, v.container.y, other.container.x, other.container.y);
      if (d < best) {
        best = d;
        nearest = role;
      }
    }
    const current = useAgentStore.getState().talkTarget;
    if (current && current !== nearest) {
      const o = this.visuals.get(current);
      if (o && Phaser.Math.Distance.Between(v.container.x, v.container.y, o.container.x, o.container.y) < TALK_RANGE) nearest = current;
    }
    if (nearest !== this.nearby) {
      this.nearby = nearest;
      useAgentStore.getState().setMasterNearby(nearest);
    }
    this.nearRing?.clear();
    if (nearest && this.nearRing && this.hintText) {
      const o = this.visuals.get(nearest)!;
      const color = hex(this.defs.find((d) => d.id === nearest)?.color ?? '#ffffff');
      this.nearRing.lineStyle(3, color, 0.9).strokeEllipse(o.container.x, o.container.y + 6, 62, 22);
      const name = this.defs.find((d) => d.id === nearest)?.shortName ?? nearest;
      this.hintText
        .setText(`E · ${name}에게 말하기`)
        .setPosition(v.container.x, v.container.y - 104)
        .setVisible(true);
    } else {
      this.hintText?.setVisible(false);
    }
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
    const nameText = this.add.text(0, 26, def.shortName, { fontFamily: FONT, fontSize: '13px', fontStyle: '700', color: '#ffffff' }).setOrigin(0.5);
    const statusDot = this.add.circle(0, 0, 4, hex(STATUS_COLOR.idle)).setStrokeStyle(1.5, 0x0b0f1e);

    const progressBg = this.add.graphics();
    const progressText = this.add.text(0, 50, '', { fontFamily: FONT, fontSize: '12px', fontStyle: '700', color: '#ffffff' }).setOrigin(0, 0.5);

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

    const container = this.add.container(pos.x, pos.y, [shadow, sprite, nameBg, nameText, statusDot, progressBg, progressText, bubbleBg, bubbleText]);
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
    if (role !== MASTER_ID && this.keys) this.makeApproachable(role, this.visuals.get(role)!);
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
      v.room = state.room;
      // Master와 대화 중인 에이전트는 답하는 동안 제자리에서 말한다. 끝나서 휴게실로 갈 때 대화도 끝난 것으로 본다
      const stay = this.talkingWith === role && state.status !== 'idle';
      if (!stay) {
        if (this.talkingWith === role) this.talkingWith = null;
        this.moveTo(role, state.room);
      }
    }

    if (state.status !== v.status) {
      v.status = state.status;
      this.playLoop(role, state.status);
      v.statusDot.setFillStyle(hex(STATUS_COLOR[state.status]));
    }

    this.updateBubble(role, state.message);
    this.updateProgress(role, state.progress);
  }

  private moveTo(role: AgentRole, toRoom: RoomId) {
    const v = this.visuals.get(role);
    if (!v) return;
    const from: Point = { x: v.container.x, y: v.container.y };
    const to = seatFor(role, toRoom, this.defs);
    const path = routeTo(from, to);
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
    const color = hex(role === MASTER_ID ? (this.masterDef?.color ?? '#ffffff') : (this.defs.find((d) => d.id === role)?.color ?? '#ffffff'));
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
  private updateBubble(role: AgentRole, text: string, colorOverride?: string) {
    const v = this.visuals.get(role);
    if (!v) return;
    if (!text || (v.status === 'idle' && !colorOverride)) {
      v.bubbleBg.clear();
      v.bubbleText.setText('');
      return;
    }
    v.bubbleText.setText(text);
    const w = Math.max(v.bubbleText.width + 20, 40);
    const h = v.bubbleText.height + 12;
    const color = hex(colorOverride ?? STATUS_COLOR[v.status]);
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
