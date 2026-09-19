import 'dotenv/config';
import 'reflect-metadata';
import { mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module.js';
import { SettingsService } from './agent/settings.service.js';
import { config } from './config.js';

async function bootstrap() {
  const logger = new Logger('Bootstrap');

  if (!config.hasAuth()) {
    logger.warn('ANTHROPIC_API_KEY 또는 CLAUDE_CODE_OAUTH_TOKEN이 설정되지 않았습니다. .env 파일을 확인하세요.');
  }

  const app = await NestFactory.create(AppModule);
  // Next.js 대시보드(다른 포트)에서 REST API를 부를 수 있게, 로컬 주소에서 오는 요청만 허용한다.
  app.enableCors({ origin: /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/ });

  // 에이전트는 이 컴퓨터에서 명령을 실행할 수 있으므로, 외부에서 접속하지 못하게 로컬 주소에만 연다.
  await app.listen(config.port, '127.0.0.1');

  // 작업 폴더는 /workspace 명령으로 바뀔 수 있어 저장된 설정(data/settings.json)이 우선이다
  const workspaceDir = app.get(SettingsService).workspaceDir;
  await mkdir(join(workspaceDir, 'uploads'), { recursive: true });

  logger.log(`대시보드: http://localhost:${config.port}`);
  logger.log(`작업 폴더: ${workspaceDir}`);
  logger.log(`권한 모드: ${config.permissionMode}`);
  logger.log(`명령당 비용 한도: $${config.maxBudgetUsd}`);
}

await bootstrap();
