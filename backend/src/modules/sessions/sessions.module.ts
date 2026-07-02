import { Module } from '@nestjs/common';
import { SessionsController } from './sessions.controller';
import { SessionsService } from './sessions.service';
import { WebsocketModule } from '../websocket/websocket.module';
import { KotsModule } from '../kots/kots.module';

@Module({
  imports: [WebsocketModule, KotsModule],
  controllers: [SessionsController],
  providers: [SessionsService],
  exports: [SessionsService],
})
export class SessionsModule {}
