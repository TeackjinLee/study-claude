import { test } from 'node:test';
import assert from 'node:assert/strict';
import { LoginLimiter, isAllowedOrigin, isLoopback, passwordMatches, readCookie, signToken, verifyToken } from '../src/access/access.js';

test('isLoopback: 이 컴퓨터 주소만', () => {
  for (const a of ['127.0.0.1', '::1', '::ffff:127.0.0.1']) assert.equal(isLoopback(a), true, a);
  for (const a of ['192.168.0.10', '::ffff:192.168.0.10', '10.0.0.2', undefined, '']) assert.equal(isLoopback(a), false, String(a));
});

test('isAllowedOrigin: localhost는 늘, 사설 네트워크는 원격 접속이 켜졌을 때만, 외부 사이트는 절대 안 됨', () => {
  assert.equal(isAllowedOrigin(undefined, false), true, 'Origin 없음 (curl, 같은 출처 GET)');
  assert.equal(isAllowedOrigin('http://localhost:3100', false), true);
  assert.equal(isAllowedOrigin('http://127.0.0.1:3000', false), true);
  assert.equal(isAllowedOrigin('http://192.168.0.10:3100', false), false, '원격 접속이 꺼져 있으면 같은 와이파이도 안 됨');
  for (const o of ['http://192.168.0.10:3100', 'http://10.1.2.3:3100', 'http://172.20.0.5:3100', 'http://my-mac.local:3100']) assert.equal(isAllowedOrigin(o, true), true, o);
  for (const o of ['https://evil.example', 'http://172.32.0.1:3100', 'http://8.8.8.8', 'http://192.168.0.10.evil.com', 'file://x', 'null', 'chrome-extension://abc']) {
    assert.equal(isAllowedOrigin(o, true), false, o);
  }
});

test('토큰: 같은 비밀번호로만, 만료 전까지만, 조작하면 거절', () => {
  const now = 1_000_000;
  const token = signToken('correct horse', now, 60_000);
  assert.equal(verifyToken(token, 'correct horse', now + 1000), true);
  assert.equal(verifyToken(token, 'correct horse', now + 60_001), false, '만료');
  assert.equal(verifyToken(token, 'other password', now + 1000), false, '비밀번호를 바꾸면 풀린다');
  const [exp, sig] = token.split('.');
  assert.equal(verifyToken(`${Number(exp) + 999_999}.${sig}`, 'correct horse', now), false, '만료시각을 늘리면 서명이 안 맞는다');
  for (const bad of [undefined, '', 'abc', '.', `${exp}.`, 'NaN.x']) assert.equal(verifyToken(bad, 'correct horse', now), false, String(bad));
});

test('passwordMatches', () => {
  assert.equal(passwordMatches('secret-123', 'secret-123'), true);
  assert.equal(passwordMatches('secret-12', 'secret-123'), false);
  assert.equal(passwordMatches('', 'secret-123'), false);
});

test('readCookie', () => {
  assert.equal(readCookie('a=1; as_access=tok%2Bx; b=2', 'as_access'), 'tok+x');
  assert.equal(readCookie('xas_access=1', 'as_access'), undefined);
  assert.equal(readCookie(undefined, 'as_access'), undefined);
});

test('LoginLimiter: 5번 틀리면 잠기고, 시간이 지나거나 성공하면 풀린다', () => {
  const l = new LoginLimiter(5, 60_000);
  for (let i = 0; i < 5; i++) {
    assert.equal(l.check('ip', 1000 + i), 0);
    l.fail('ip', 1000 + i);
  }
  assert.ok(l.check('ip', 2000) > 0, '잠김');
  assert.equal(l.check('other', 2000), 0, '다른 주소는 상관없음');
  assert.equal(l.check('ip', 1000 + 60_001), 0, '시간이 지나면 풀림');
  l.fail('ip2', 0);
  l.reset('ip2');
  assert.equal(l.check('ip2', 1), 0);
});
