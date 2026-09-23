import { createHmac, timingSafeEqual } from 'node:crypto';

/** 원격 접속 로그인 쿠키 이름 */
export const ACCESS_COOKIE = 'as_access';
/** 로그인 유지 기간 */
export const ACCESS_TTL_MS = 30 * 24 * 60 * 60 * 1000;
/** 원격 접속을 열 수 있는 비밀번호 최소 길이 */
export const MIN_PASSWORD_LENGTH = 8;

/** 이 컴퓨터에서 온 연결인지 (소켓의 실제 주소로 판단한다. Host 헤더는 꾸밀 수 있어서 보지 않는다) */
export function isLoopback(address: string | undefined): boolean {
  return address === '127.0.0.1' || address === '::1' || address === '::ffff:127.0.0.1';
}

/** 사설 네트워크 주소 (집·회사 와이파이) */
const PRIVATE_HOST = /^(10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|[a-z0-9-]+\.local)$/i;

/**
 * 브라우저 요청의 Origin을 받아도 되는지. 이 컴퓨터(localhost)는 늘 허용하고,
 * 원격 접속이 켜져 있을 때만 같은 네트워크(사설 주소)의 화면을 허용한다. Origin이 없으면(서버끼리, curl) 허용한다.
 */
export function isAllowedOrigin(origin: string | undefined, remote: boolean): boolean {
  if (!origin) return true;
  let url: URL;
  try {
    url = new URL(origin);
  } catch {
    return false;
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return false;
  if (url.hostname === 'localhost' || url.hostname === '127.0.0.1' || url.hostname === '[::1]') return true;
  return remote && PRIVATE_HOST.test(url.hostname);
}

const sign = (password: string, exp: number) => createHmac('sha256', password).update(`agent-studio-access:${exp}`).digest('base64url');

/** 로그인 토큰: "만료시각.서명". 비밀번호로 서명하므로 비밀번호를 바꾸면 모든 로그인이 풀린다 */
export function signToken(password: string, now = Date.now(), ttlMs = ACCESS_TTL_MS): string {
  const exp = now + ttlMs;
  return `${exp}.${sign(password, exp)}`;
}

export function verifyToken(token: string | undefined, password: string, now = Date.now()): boolean {
  if (!token) return false;
  const dot = token.indexOf('.');
  const exp = Number(token.slice(0, dot));
  if (dot <= 0 || !Number.isFinite(exp) || exp <= now) return false;
  const given = Buffer.from(token.slice(dot + 1));
  const expected = Buffer.from(sign(password, exp));
  return given.length === expected.length && timingSafeEqual(given, expected);
}

/** 비밀번호 비교 (길이가 달라도 걸리는 시간이 비슷하게) */
export function passwordMatches(given: string, password: string): boolean {
  const a = createHmac('sha256', 'agent-studio-compare').update(given).digest();
  const b = createHmac('sha256', 'agent-studio-compare').update(password).digest();
  return timingSafeEqual(a, b);
}

export function readCookie(header: string | undefined, name: string): string | undefined {
  if (!header) return undefined;
  for (const part of header.split(';')) {
    const eq = part.indexOf('=');
    if (eq > 0 && part.slice(0, eq).trim() === name) {
      try {
        return decodeURIComponent(part.slice(eq + 1).trim());
      } catch {
        return undefined;
      }
    }
  }
  return undefined;
}

/**
 * 로그인 시도 제한: 한 주소에서 window 안에 max번까지. 넘으면 남은 대기 시간(ms)을 돌려준다.
 */
export class LoginLimiter {
  private readonly attempts = new Map<string, number[]>();
  constructor(
    private readonly max = 5,
    private readonly windowMs = 5 * 60 * 1000,
  ) {}

  /** 시도해도 되면 0, 아니면 기다려야 할 시간 */
  check(key: string, now = Date.now()): number {
    const recent = (this.attempts.get(key) ?? []).filter((t) => now - t < this.windowMs);
    this.attempts.set(key, recent);
    return recent.length >= this.max ? this.windowMs - (now - recent[0]) : 0;
  }

  fail(key: string, now = Date.now()) {
    this.attempts.set(key, [...(this.attempts.get(key) ?? []), now]);
  }

  reset(key: string) {
    this.attempts.delete(key);
  }
}
