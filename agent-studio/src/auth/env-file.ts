import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const ENV_PATH = join(process.cwd(), '.env');
const KEY = 'CLAUDE_CODE_OAUTH_TOKEN';

/** 로그인으로 받은 토큰을 .env의 CLAUDE_CODE_OAUTH_TOKEN 줄에 쓴다 (있으면 교체, 없으면 추가) */
export async function persistOAuthToken(token: string): Promise<void> {
  let content: string;
  try {
    content = await readFile(ENV_PATH, 'utf8');
  } catch {
    content = '';
  }

  const line = `${KEY}=${token}`;
  const linePattern = new RegExp(`^${KEY}=.*$`, 'm');

  if (linePattern.test(content)) {
    content = content.replace(linePattern, line);
  } else if (content.length === 0) {
    content = `${line}\n`;
  } else {
    content = content.endsWith('\n') ? `${content}${line}\n` : `${content}\n${line}\n`;
  }

  await writeFile(ENV_PATH, content, 'utf8');
}

/** 로그아웃: .env에서 CLAUDE_CODE_OAUTH_TOKEN 줄을 지운다. 파일이나 줄이 없으면 아무것도 하지 않는다 */
export async function removeOAuthToken(): Promise<void> {
  let content: string;
  try {
    content = await readFile(ENV_PATH, 'utf8');
  } catch {
    return;
  }

  const linePattern = new RegExp(`^${KEY}=.*(?:\r?\n|$)`, 'm');
  if (!linePattern.test(content)) return;

  await writeFile(ENV_PATH, content.replace(linePattern, ''), 'utf8');
}
