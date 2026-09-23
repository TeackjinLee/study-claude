import { Body, Controller, Get, HttpException, Post, Req, Res } from '@nestjs/common';
import type { Request, Response } from 'express';
import { isLoopback } from './access.js';
import { access } from './access.service.js';

/**
 * 원격 접속 로그인 (이 경로들은 로그인 없이 부를 수 있다).
 *   GET  /api/access/status   { remote, required, authed }  화면이 로그인 창을 띄울지 판단
 *   POST /api/access/login    { password }                  성공하면 로그인 쿠키
 *   POST /api/access/logout
 */
@Controller('api/access')
export class AccessController {
  @Get('status')
  status(@Req() req: Request) {
    const address = req.socket.remoteAddress;
    return { remote: access.enabled, required: access.enabled && !isLoopback(address), authed: access.allows(address, req.headers.cookie) };
  }

  @Post('login')
  login(@Req() req: Request, @Res({ passthrough: true }) res: Response, @Body() body: { password?: unknown } | undefined) {
    const result = access.login(req.socket.remoteAddress, body?.password);
    if (!result.ok) throw new HttpException({ ok: false, error: result.error }, result.status);
    res.setHeader('Set-Cookie', result.cookie);
    return { ok: true };
  }

  @Post('logout')
  logout(@Res({ passthrough: true }) res: Response) {
    res.setHeader('Set-Cookie', access.logoutCookie());
    return { ok: true };
  }
}
