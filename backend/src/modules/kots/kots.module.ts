import { Module } from '@nestjs/common';
import { KotsController } from './kots.controller';
import { KotsService } from './kots.service';
import { WebsocketModule } from '../websocket/websocket.module';

@Module({
  imports: [WebsocketModule],
  controllers: [KotsController],
  providers: [KotsService],
  exports: [KotsService],
})
export class KotsModule {}
