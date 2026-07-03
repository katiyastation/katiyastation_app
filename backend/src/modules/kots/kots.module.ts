import { Module } from '@nestjs/common';
import { KotsController } from './kots.controller';
import { KotsService } from './kots.service';
import { WebsocketModule } from '../websocket/websocket.module';
import { AuditLogsModule } from '../audit-logs/audit-logs.module';

@Module({
  imports: [WebsocketModule, AuditLogsModule],
  controllers: [KotsController],
  providers: [KotsService],
  exports: [KotsService],
})
export class KotsModule {}
