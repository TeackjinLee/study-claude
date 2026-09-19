import type { AgentDef, AgentRole, RoomId } from '@/types/agent';

export interface Point {
  x: number;
  y: number;
}

export interface RoomDef {
  id: RoomId;
  label: string;
  x: number;
  y: number;
  w: number;
  h: number;
  /** 에이전트가 서는 구역 (방 좌상단 기준 상대 좌표). 인원수에 따라 이 안에 격자로 자리를 나눈다 */
  area: { x: number; y: number; w: number; h: number };
  /** 복도로 나가는 문 위치 (월드 절대 좌표). 이동 경로는 항상 문을 거친다. */
  door: Point;
}

/**
 * 배경은 public/office.png(1312x816) 한 장이고, 방 좌표는 그 그림의 픽셀 위치에 맞춘 값이다.
 *  윗줄  회의실 | 개발실 | 휴게실
 *  복도  ───────────────────
 *  아랫줄 입구(로비) | 테스트실 | 문서실 | 서버실
 * 그림을 바꾸면 이 좌표들만 다시 맞추면 된다.
 */
export const WORLD_WIDTH = 1312;
export const WORLD_HEIGHT = 816;
export const OFFICE_IMAGE_URL = '/office.png';

/** 윗줄 방들과 아랫줄 방들 사이 가로 복도의 기준선 (에이전트가 걷는 y) */
export const CORRIDOR_MID_Y = 368;

type Area = RoomDef['area'];

/** 에이전트 한 명이 차지하는 최소 간격 (이름표가 겹치지 않는 정도) */
const SEAT_GAP_X = 92;
const SEAT_GAP_Y = 84;

/** count명을 구역 안에 격자로 고르게 배치했을 때 index번째 자리 (구역 기준 상대 좌표) */
function seatInArea(area: Area, index: number, count: number): Point {
  const n = Math.max(1, count);
  const cols = Math.max(1, Math.min(n, Math.floor(area.w / SEAT_GAP_X) || 1));
  const rows = Math.ceil(n / cols);
  const col = index % cols;
  const row = Math.floor(index / cols);
  const inLastRow = row === rows - 1;
  const colsInRow = inLastRow ? n - (rows - 1) * cols : cols;
  const x = area.x + (area.w * (col + 1)) / (colsInRow + 1);
  const rowH = Math.min(SEAT_GAP_Y, rows > 1 ? area.h / (rows - 1) : area.h);
  const y = rows === 1 ? area.y + area.h / 2 : area.y + area.h / 2 - ((rows - 1) * rowH) / 2 + row * rowH;
  return { x, y };
}

interface RoomInput {
  id: RoomId;
  label: string;
  rect: [x: number, y: number, w: number, h: number];
  /** 에이전트가 서는 구역 (월드 절대 좌표) */
  area: [x: number, y: number, w: number, h: number];
  /** 복도 쪽 문 (월드 절대 좌표) */
  door: Point;
}

const room = ({ id, label, rect, area, door }: RoomInput): RoomDef => ({
  id,
  label,
  x: rect[0],
  y: rect[1],
  w: rect[2],
  h: rect[3],
  area: { x: area[0] - rect[0], y: area[1] - rect[1], w: area[2], h: area[3] },
  door,
});

export const ROOMS: RoomDef[] = [
  room({ id: 'meeting', label: '회의실', rect: [80, 45, 375, 285], area: [120, 240, 300, 70], door: { x: 300, y: 330 } }),
  room({ id: 'dev', label: '개발실', rect: [470, 45, 435, 295], area: [500, 235, 380, 80], door: { x: 690, y: 340 } }),
  room({ id: 'lounge', label: '휴게실', rect: [915, 45, 355, 295], area: [930, 130, 320, 190], door: { x: 1090, y: 340 } }),
  room({ id: 'entrance', label: '입구', rect: [80, 400, 250, 380], area: [100, 470, 210, 200], door: { x: 200, y: 400 } }),
  room({ id: 'test', label: '테스트실', rect: [340, 400, 280, 280], area: [360, 560, 200, 80], door: { x: 480, y: 400 } }),
  room({ id: 'doc', label: '문서실', rect: [680, 400, 240, 280], area: [700, 545, 200, 90], door: { x: 800, y: 400 } }),
  room({ id: 'server', label: '서버실', rect: [985, 400, 285, 265], area: [1000, 555, 250, 70], door: { x: 1130, y: 400 } }),
];

export const ROOM_BY_ID: Record<RoomId, RoomDef> = Object.fromEntries(ROOMS.map((r) => [r.id, r])) as Record<
  RoomId,
  RoomDef
>;

/**
 * 이 에이전트가 해당 방에서 설 자리(월드 절대 좌표).
 * 휴게실/입구는 모든 에이전트가, 작업실은 그 방을 담당하는 에이전트들이 순서대로 자리를 나눠 갖는다.
 * 에이전트를 추가/삭제하면 자리는 자동으로 다시 배치된다.
 */
export function seatFor(role: AgentRole, room: RoomId, defs: AgentDef[]): Point {
  const def = ROOM_BY_ID[room];
  const shared = room === 'lounge' || room === 'entrance';
  const members = shared ? defs : defs.filter((d) => d.room === room);
  let index = members.findIndex((d) => d.id === role);
  let count = members.length;
  if (index < 0) {
    // 담당 방이 아닌 곳으로 보내진 경우(예: 실시간 이벤트가 다른 방을 지정) 끝자리에 세운다
    index = count;
    count += 1;
  }
  const s = seatInArea(def.area, index, count);
  return { x: def.x + s.x, y: def.y + s.y };
}

/**
 * 방에서 방으로 걸어가는 경로. 자기 방 문 → 복도 기준선 → 목적지 문 → 좌석 순으로
 * 꺾이는 폴리라인이라 벽을 통과하지 않고 복도를 따라 이동하는 것처럼 보인다.
 */
export function walkPath(from: Point, fromRoom: RoomId, toRoom: RoomId, to: Point): Point[] {
  const a = ROOM_BY_ID[fromRoom];
  const b = ROOM_BY_ID[toRoom];
  if (fromRoom === toRoom) return [from, to];
  return [
    from,
    { x: a.door.x, y: from.y },
    { x: a.door.x, y: CORRIDOR_MID_Y },
    { x: b.door.x, y: CORRIDOR_MID_Y },
    { x: b.door.x, y: to.y },
    to,
  ];
}

export function pathLength(points: Point[]): number {
  let len = 0;
  for (let i = 1; i < points.length; i++) len += Math.hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y);
  return len;
}

/** 폴리라인 위의 t(0..1) 지점 좌표 */
export function pointAt(points: Point[], t: number): Point {
  const total = pathLength(points);
  if (total === 0) return points[points.length - 1];
  let remaining = Math.max(0, Math.min(1, t)) * total;
  for (let i = 1; i < points.length; i++) {
    const seg = Math.hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y);
    if (remaining <= seg) {
      const r = seg === 0 ? 0 : remaining / seg;
      return { x: points[i - 1].x + (points[i].x - points[i - 1].x) * r, y: points[i - 1].y + (points[i].y - points[i - 1].y) * r };
    }
    remaining -= seg;
  }
  return points[points.length - 1];
}
