import { config } from '../config.js';
import { ACCESS_COOKIE, ACCESS_TTL_MS, LoginLimiter, MIN_PASSWORD_LENGTH, isAllowedOrigin, isLoopback, passwordMatches, readCookie, signToken, verifyToken } from './access.js';

const password = config.accessPassword && config.accessPassword.length >= MIN_PASSWORD_LENGTH ? config.accessPassword : undefined;
const limiter = new LoginLimiter();

/**
 * 원격 접속(휴대폰 등). ACCESS_PASSWORD가 있을 때만 켜진다.
 * 이 컴퓨터에서 온 요청은 로그인 없이, 다른 기기는 비밀번호로 로그인한 쿠키가 있어야 쓸 수 있다.
 * main.ts의 HTTP 미들웨어와 AgentGateway의 소켓 미들웨어가 같이 쓴다 (둘 다 Nest DI 밖이라 모듈 하나로 둔다).
 */
export const access = {
  /** 원격 접속이 켜졌는지 */
  enabled: Boolean(password),
  /** ACCESS_PASSWORD를 넣었는데 너무 짧아서 켜지 못했는지 */
  tooShort: Boolean(config.accessPassword) && !password,

  originAllowed: (origin: string | undefined) => isAllowedOrigin(origin, Boolean(password)),

  /** 이 요청을 받아도 되는지 (주소와 쿠키 헤더로) */
  allows(address: string | undefined, cookieHeader: string | undefined): boolean {
    if (!password) return isLoopback(address);
    return isLoopback(address) || verifyToken(readCookie(cookieHeader, ACCESS_COOKIE), password);
  },

  /** 로그인. 성공하면 Set-Cookie 값을, 실패하면 이유를 */
  login(address: string | undefined, given: unknown): { ok: true; cookie: string } | { ok: false; status: number; error: string } {
    if (!password) return { ok: false, status: 400, error: '원격 접속이 꺼져 있습니다. 서버 .env에 ACCESS_PASSWORD를 설정하세요.' };
    const key = address ?? 'unknown';
    const wait = limiter.check(key);
    if (wait > 0) return { ok: false, status: 429, error: `로그인 시도가 너무 많습니다. ${Math.ceil(wait / 60000)}분 뒤에 다시 시도하세요.` };
    if (typeof given !== 'string' || !passwordMatches(given, password)) {
      limiter.fail(key);
      return { ok: false, status: 401, error: '비밀번호가 맞지 않습니다.' };
    }
    limiter.reset(key);
    return { ok: true, cookie: `${ACCESS_COOKIE}=${signToken(password)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${Math.floor(ACCESS_TTL_MS / 1000)}` };
  },

  logoutCookie: () => `${ACCESS_COOKIE}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0`,
};
