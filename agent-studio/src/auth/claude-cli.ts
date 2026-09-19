import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';

const require = createRequire(import.meta.url);

/**
 * claude-agent-sdk가 플랫폼별 패키지(@anthropic-ai/claude-agent-sdk-<os>-<arch>)로 함께 설치하는
 * 실제 claude CLI 바이너리 경로를 찾는다. 못 찾으면 PATH에 설치된 claude로 폴백한다.
 */
export function resolveClaudeBinary(): string {
  const pkgName = `@anthropic-ai/claude-agent-sdk-${process.platform}-${process.arch}`;
  try {
    const pkgJsonPath = require.resolve(`${pkgName}/package.json`);
    const bin = process.platform === 'win32' ? 'claude.exe' : 'claude';
    return join(dirname(pkgJsonPath), bin);
  } catch {
    return 'claude';
  }
}
