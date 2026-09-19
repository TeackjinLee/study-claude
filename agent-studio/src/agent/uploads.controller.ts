import { randomBytes } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { rm } from 'node:fs/promises';
import { extname, isAbsolute, join, normalize, relative } from 'node:path';
import { BadRequestException, Controller, Delete, Get, NotFoundException, Param, Post, Query, Res, UploadedFiles, UseInterceptors } from '@nestjs/common';
import { FilesInterceptor } from '@nestjs/platform-express';
import type { Response } from 'express';
import { diskStorage } from 'multer';
import { config } from '../config.js';
import { SettingsService } from './settings.service.js';
import { UploadCleanupService } from './upload-cleanup.service.js';
import { ALLOWED_EXT, MAX_FILES, MAX_FILE_BYTES, UPLOAD_DIR, kindOf, mimeOf, safeFileName, type Attachment } from './attachments.js';
import { IMAGE_EXT } from './artifact-utils.js';

const stamp = () => {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}-${randomBytes(2).toString('hex')}`;
};

/** multer는 originalname을 latin1로 넘기는 경우가 있어 한글 파일명을 복원한다 */
function decodeName(name: string) {
  try {
    const fixed = Buffer.from(name, 'latin1').toString('utf8');
    return fixed.includes('�') ? name : fixed;
  } catch {
    return name;
  }
}

/**
 * 명령에 첨부할 파일 업로드. 작업 폴더의 uploads/<시각-난수>/ 아래에 저장하고,
 * 명령 전송 시 그대로 넘길 수 있는 Attachment 목록을 돌려준다.
 * 파일이 최대 1GB라 메모리에 담지 않고 디스크로 바로 스트리밍한다.
 *   POST /api/uploads  (multipart/form-data, field: files)
 */
/** multer의 destination 콜백은 클래스 밖에서 만들어져 DI를 못 받으므로, 모듈이 뜰 때 설정 서비스를 여기에 꽂아준다 */
let settingsRef: SettingsService | null = null;

@Controller('api/uploads')
export class UploadsController {
  constructor(
    private readonly cleanup: UploadCleanupService,
    settings: SettingsService,
  ) {
    settingsRef = settings;
  }

  /**
   * 오래된 업로드를 지금 바로 정리한다. ?days=N 으로 기준을 바꿀 수 있고(기본: 설정값), days=0이면 실행 중이 아닌 것 전부.
   *   DELETE /api/uploads/old[?days=N]
   */
  @Delete('old')
  async removeOld(@Query('days') days?: string) {
    const n = days === undefined ? config.uploadRetentionDays : Number(days);
    if (!Number.isFinite(n) || n < 0) throw new BadRequestException('days는 0 이상의 숫자여야 합니다.');
    return this.cleanup.cleanup(n * 24 * 60 * 60 * 1000);
  }

  @Post()
  @UseInterceptors(
    FilesInterceptor('files', MAX_FILES, {
      limits: { fileSize: MAX_FILE_BYTES, files: MAX_FILES },
      storage: diskStorage({
        // 요청 하나의 파일들은 같은 폴더에 모은다 (요청 객체에 폴더명을 붙여 재사용)
        destination: (req, _file, cb) => {
          const r = req as { uploadFolder?: string };
          r.uploadFolder ??= stamp();
          const dir = join(settingsRef?.workspaceDir ?? config.workspaceDir, UPLOAD_DIR, r.uploadFolder);
          try {
            mkdirSync(dir, { recursive: true });
            cb(null, dir);
          } catch (err) {
            cb(err as Error, dir);
          }
        },
        filename: (req, file, cb) => {
          const r = req as { usedNames?: Set<string> };
          r.usedNames ??= new Set();
          let name = safeFileName(decodeName(file.originalname));
          const ext = extname(name).toLowerCase();
          // 같은 이름이 두 번 오면 뒤에 번호를 붙인다
          let i = 1;
          while (r.usedNames.has(name)) name = `${name.slice(0, name.length - ext.length)}-${i++}${ext}`;
          r.usedNames.add(name);
          cb(null, name);
        },
      }),
      fileFilter: (_req, file, cb) => {
        const ext = extname(safeFileName(decodeName(file.originalname))).toLowerCase();
        if (!ALLOWED_EXT.has(ext)) {
          cb(new BadRequestException(`허용하지 않는 파일 형식입니다: ${decodeName(file.originalname)}`), false);
          return;
        }
        cb(null, true);
      },
    }),
  )
  async upload(@UploadedFiles() files: Express.Multer.File[] | undefined) {
    if (!files || files.length === 0) throw new BadRequestException('업로드할 파일이 없습니다.');
    const out: Attachment[] = [];
    for (const f of files) {
      const folder = f.destination.split(/[\\/]/).pop() ?? '';
      const name = f.filename;
      if (f.size === 0) {
        await rm(f.path, { force: true });
        continue;
      }
      out.push({ path: `${UPLOAD_DIR}/${folder}/${name}`, name, mime: mimeOf(name), size: f.size, kind: kindOf(name) });
    }
    if (out.length === 0) throw new BadRequestException('빈 파일은 첨부할 수 없습니다.');
    return { files: out };
  }
}

const FOLDER_RE = /^\d{8}-\d{6}-[0-9a-f]{4}$/;

/**
 * 첨부 파일 미리보기. 작업 폴더가 /workspace 로 바뀔 수 있어서 정적 서빙 대신 요청 시점의 폴더에서 찾는다.
 *   GET /uploads/<시각-난수>/<파일명>
 */
@Controller('uploads')
export class UploadFilesController {
  constructor(private readonly settings: SettingsService) {}

  @Get(':folder/:name')
  serve(@Param('folder') folder: string, @Param('name') name: string, @Res() res: Response) {
    const safe = safeFileName(name);
    if (!FOLDER_RE.test(folder) || safe !== name) throw new NotFoundException();
    const file = join(this.settings.workspaceDir, UPLOAD_DIR, folder, safe);
    res.sendFile(file, (err) => {
      if (err && !res.headersSent) res.status(404).end();
    });
  }
}

/**
 * 결과 미리보기의 이미지 탭용: 작업 폴더 안의 이미지 파일을 읽기 전용으로 준다 (Codex가 만든 그림 등).
 *   GET /api/workspace-files/<작업 폴더 기준 경로>
 * 이미지 확장자만 허용하고, 작업 폴더 밖으로 나가는 경로는 거부한다.
 */
@Controller('api/workspace-files')
export class WorkspaceFilesController {
  constructor(private readonly settings: SettingsService) {}

  @Get('*path')
  serve(@Param('path') path: string | string[], @Res() res: Response) {
    const rel = normalize(Array.isArray(path) ? path.join('/') : path);
    if (!rel || rel.startsWith('..') || isAbsolute(rel) || !IMAGE_EXT.has(extname(rel).toLowerCase())) throw new NotFoundException();
    const root = this.settings.workspaceDir;
    const file = join(root, rel);
    if (relative(root, file).startsWith('..')) throw new NotFoundException();
    res.sendFile(file, (err) => {
      if (err && !res.headersSent) res.status(404).end();
    });
  }
}
