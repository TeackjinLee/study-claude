import 'dotenv/config';
import 'reflect-metadata';
import { mkdir } from 'node:fs/promises';
import { networkInterfaces } from 'node:os';
import { join } from 'node:path';
import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module.js';
import { SettingsService } from './agent/settings.service.js';
import { config } from './config.js';
import { access } from './access/access.service.js';
import type { NextFunction, Request, Response } from 'express';

async function bootstrap() {
  const logger = new Logger('Bootstrap');

  if (!config.hasAuth()) {
    logger.warn('ANTHROPIC_API_KEY 또는 CLAUDE_CODE_OAUTH_TOKEN이 설정되지 않았습니다. .env 파일을 확인하세요.');
  }

  const app = await NestFactory.create(AppModule);
  // Next.js 대시보드(다른 포트)에서 REST API를 부를 수 있게 로컬 주소(원격 접속이 켜졌으면 같은 네트워크 주소도)에서 오는 요청만 허용한다.
  // 원격 접속은 로그인 쿠키로 확인하므로 쿠키를 같이 보내게 한다.
  app.enableCors({ origin: (origin: string | undefined, cb: (err: Error | null, ok?: boolean) => void) => cb(null, access.originAllowed(origin)), credentials: true });

  // 원격 접속: 이 컴퓨터가 아닌 곳에서 온 API·업로드 파일 요청은 로그인해야 받는다 (로그인 경로와 화면 파일은 그대로)
  app.use((req: Request, res: Response, next: NextFunction) => {
    const guarded = (req.path.startsWith('/api/') && !req.path.startsWith('/api/access/')) || req.path.startsWith('/uploads/');
    if (!guarded) return next();
    // 허용하지 않은 웹사이트에서 온 요청은 CORS가 응답만 막고 실행은 될 수 있어서 여기서 거절한다
    if (!access.originAllowed(req.headers.origin)) return res.status(403).json({ message: '허용하지 않은 출처입니다.', error: 'forbidden' });
    if (access.allows(req.socket.remoteAddress, req.headers.cookie)) return next();
    res.status(401).json({ message: '로그인이 필요합니다.', error: 'unauthorized' });
  });

  // 에이전트는 이 컴퓨터에서 명령을 실행할 수 있으므로, 원격 접속 비밀번호가 없으면 로컬 주소에만 연다.
  const host = access.enabled ? (process.env.HOST ?? '0.0.0.0') : '127.0.0.1';
  await app.listen(config.port, host);
  if (access.tooShort) logger.warn('ACCESS_PASSWORD가 8자보다 짧아 원격 접속을 켜지 않았습니다. 이 컴퓨터에서만 접속됩니다.');

  // 작업 폴더는 /workspace 명령으로 바뀔 수 있어 저장된 설정(data/settings.json)이 우선이다
  const workspaceDir = app.get(SettingsService).workspaceDir;
  await mkdir(join(workspaceDir, 'uploads'), { recursive: true });

  logger.log(`대시보드: http://localhost:${config.port}`);
  if (access.enabled) {
    const ips = Object.values(networkInterfaces())
      .flat()
      .filter((n) => n && n.family === 'IPv4' && !n.internal)
      .map((n) => n!.address);
    logger.log(`원격 접속 켜짐 (비밀번호 로그인). 같은 와이파이의 휴대폰에서: ${ips.map((ip) => `http://${ip}:3100`).join(', ') || '(네트워크 주소 없음)'}`);
  }
  logger.log(`작업 폴더: ${workspaceDir}`);
  logger.log(`권한 모드: ${config.permissionMode}`);
  logger.log(`명령당 비용 한도: $${config.maxBudgetUsd}`);
}

await bootstrap();
