import { join } from 'node:path';
import { Module } from '@nestjs/common';
import { ServeStaticModule } from '@nestjs/serve-static';
import { AgentModule } from './agent/agent.module.js';
import { AuthModule } from './auth/auth.module.js';

@Module({
  imports: [
    ServeStaticModule.forRoot({
      rootPath: join(process.cwd(), 'public'),
      // 없는 경로는 index.html로 돌려주는데, API와 업로드 파일(UploadFilesController) 경로는 거기서 빼야 한다
      exclude: ['/api/{*path}', '/uploads/{*path}'],
    }),
    AgentModule,
    AuthModule,
  ],
})
export class AppModule {}
