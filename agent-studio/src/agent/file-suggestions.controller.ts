import { Controller, Get, Query } from '@nestjs/common';
import { FileIndexService } from './file-index.service.js';

/**
 * 입력창의 @파일 자동완성.
 *   GET /api/file-suggestions?q=<검색어>   작업 폴더의 파일·폴더 (최대 30개, 순위순)
 */
@Controller('api/file-suggestions')
export class FileSuggestionsController {
  constructor(private readonly files: FileIndexService) {}

  @Get()
  async suggest(@Query('q') q?: string) {
    return { items: await this.files.suggest(typeof q === 'string' ? q.slice(0, 200) : '') };
  }
}
