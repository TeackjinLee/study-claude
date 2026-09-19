// node-pty가 배포하는 prebuild의 spawn-helper가 실행 권한(+x) 없이 풀리는 경우가 있어
// (tar 추출 환경에 따라 실행 비트가 날아감), postinstall에서 한 번 더 chmod로 보정한다.
// node-pty가 없거나(Windows는 conpty를 쓰므로 spawn-helper가 없음) 실패해도 설치를 막지 않는다.
import { chmodSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const dir = join(process.cwd(), 'node_modules/node-pty/prebuilds');

try {
  for (const platform of readdirSync(dir)) {
    const helper = join(dir, platform, 'spawn-helper');
    if (existsSync(helper)) chmodSync(helper, 0o755);
  }
} catch {
  // node-pty 미설치 등은 조용히 무시
}
