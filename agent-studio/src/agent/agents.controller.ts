import { Body, Controller, Delete, Get, Param, Post, Put } from '@nestjs/common';
import { AgentRegistryService } from './agent-registry.service.js';
import { AGENT_PROVIDERS, AVAILABLE_TOOLS, ROOM_IDS } from './agents.config.js';

/**
 * 대시보드의 에이전트 관리(추가/수정/삭제) REST API.
 *   GET    /api/agents          목록 (+ 선택 가능한 도구/방/제공자)
 *   POST   /api/agents          추가
 *   PUT    /api/agents/:id      수정
 *   DELETE /api/agents/:id      삭제
 *   POST   /api/agents/reset    기본값으로 되돌리기
 * 변경되면 게이트웨이가 'agents-changed'로 모든 화면에 새 목록을 보낸다.
 */
@Controller('api/agents')
export class AgentsController {
  constructor(private readonly registry: AgentRegistryService) {}

  @Get()
  list() {
    return { agents: this.registry.list(), tools: AVAILABLE_TOOLS, rooms: ROOM_IDS, providers: AGENT_PROVIDERS };
  }

  @Post()
  async create(@Body() body: unknown) {
    return { agents: await this.registry.create(body) };
  }

  @Post('reset')
  async reset() {
    return { agents: await this.registry.reset() };
  }

  @Put(':id')
  async update(@Param('id') id: string, @Body() body: unknown) {
    return { agents: await this.registry.update(id, body) };
  }

  @Delete(':id')
  async remove(@Param('id') id: string) {
    return { agents: await this.registry.remove(id) };
  }
}
