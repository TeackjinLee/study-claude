import { existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';

const require = createRequire(import.meta.url);

/** Codex SDK가 쓰는 것과 같은 플랫폼 → Rust target triple 매핑 */
const TRIPLES: Record<string, string> = {
  'darwin-arm64': 'aarch64-apple-darwin',
  'darwin-x64': 'x86_64-apple-darwin',
  'linux-arm64': 'aarch64-unknown-linux-musl',
  'linux-x64': 'x86_64-unknown-linux-musl',
  'win32-x64': 'x86_64-pc-windows-msvc',
  'win32-arm64': 'aarch64-pc-windows-msvc',
};

export interface CliCommand {
  file: string;
  args: string[];
}

/**
 * @openai/codex-sdk가 함께 설치하는 플랫폼 패키지(@openai/codex-<os>-<arch>)의 네이티브 codex 바이너리 경로.
 * 없으면 null (SDK의 codexPathOverride에 넘기거나, 아래 resolveCodexCommand의 폴백을 쓴다).
 */
export function resolveCodexBinary(): string | null {
  const key = `${process.platform}-${process.arch}`;
  const triple = TRIPLES[key];
  if (!triple) return null;
  try {
    const pkgJson = require.resolve(`@openai/codex-${process.platform}-${process.arch}/package.json`);
    const vendor = join(dirname(pkgJson), 'vendor', triple);
    const bin = process.platform === 'win32' ? 'codex.exe' : 'codex';
    for (const candidate of [join(vendor, 'bin', bin), join(vendor, 'codex', bin)]) {
      if (existsSync(candidate)) return candidate;
    }
  } catch {
    // 플랫폼 패키지가 없으면 아래 폴백
  }
  return null;
}

/**
 * 로그인/로그아웃 같은 CLI 명령을 띄울 때 쓰는 실행 정보.
 * 네이티브 바이너리 → @openai/codex의 Node 런처 → PATH의 codex 순으로 찾는다.
 */
export function resolveCodexCommand(): CliCommand {
  const native = resolveCodexBinary();
  if (native) return { file: native, args: [] };
  try {
    const launcher = require.resolve('@openai/codex/bin/codex.js');
    return { file: process.execPath, args: [launcher] };
  } catch {
    return { file: 'codex', args: [] };
  }
}
