/**
 * 백엔드 주소와 요청 도우미.
 * NEXT_PUBLIC_BACKEND_URL이 없으면 화면을 연 주소의 호스트에 백엔드 포트(3000)를 붙인다
 * (휴대폰에서 http://192.168.0.5:3100 으로 열면 백엔드도 192.168.0.5:3000).
 */
const BACKEND_PORT = process.env.NEXT_PUBLIC_BACKEND_PORT ?? '3000';

export const BACKEND_URL =
  process.env.NEXT_PUBLIC_BACKEND_URL ?? (typeof window === 'undefined' ? `http://localhost:${BACKEND_PORT}` : `${window.location.protocol}//${window.location.hostname}:${BACKEND_PORT}`);

/** 백엔드 요청. 원격 접속 로그인 쿠키를 같이 보낸다 */
export function apiFetch(path: string, init: RequestInit = {}): Promise<Response> {
  return fetch(`${BACKEND_URL}${path}`, { credentials: 'include', ...init });
}
