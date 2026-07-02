import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { SessionsService } from './sessions.service';
import { CloseSessionDto } from './dto/close-session.dto';
import { HoldSessionDto } from './dto/hold-session.dto';
import { MergeSessionDto } from './dto/merge-session.dto';
import { SplitSessionDto } from './dto/split-session.dto';
import { FindSessionsDto } from './dto/find-sessions.dto';
import { Roles } from '../../common/decorators/roles.decorator';
import { CurrentUser, CurrentUserPayload } from '../../common/decorators/current-user.decorator';

@Roles('super_admin', 'branch_manager', 'cashier', 'waiter')
@Controller('sessions')
export class SessionsController {
  constructor(private readonly sessionsService: SessionsService) {}

  @Get()
  findAll(@CurrentUser() user: CurrentUserPayload, @Query() filter: FindSessionsDto) {
    return this.sessionsService.findAll(user, filter);
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.sessionsService.findOne(id);
  }

  @Get(':id/kots')
  kots(@Param('id') id: string) {
    return this.sessionsService.kots(id);
  }

  @Post(':id/close')
  close(@Param('id') id: string, @Body() dto: CloseSessionDto) {
    return this.sessionsService.close(id, dto);
  }

  @Post(':id/hold')
  hold(@Param('id') id: string, @Body() dto: HoldSessionDto) {
    return this.sessionsService.hold(id, dto);
  }

  @Post(':id/unhold')
  unhold(@Param('id') id: string) {
    return this.sessionsService.unhold(id);
  }

  @Post(':id/merge')
  merge(@Param('id') id: string, @Body() dto: MergeSessionDto) {
    return this.sessionsService.merge(id, dto);
  }

  @Post(':id/split')
  split(
    @Param('id') id: string,
    @CurrentUser() user: CurrentUserPayload,
    @Body() dto: SplitSessionDto,
  ) {
    return this.sessionsService.split(id, user, dto);
  }
}
