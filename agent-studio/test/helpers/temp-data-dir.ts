// config.ts가 환경변수를 읽기 전에 데이터 폴더를 임시 폴더로 돌린다 (이 파일을 가장 먼저 import)
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export const dataDir = mkdtempSync(join(tmpdir(), 'agent-studio-data-'));
process.env.COST_FILE = join(dataDir, 'cost.json');
