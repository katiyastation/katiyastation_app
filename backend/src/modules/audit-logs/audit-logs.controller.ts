import { Controller, Get, Query } from '@nestjs/common';
import { AuditLogsService } from './audit-logs.service';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';
import { Roles } from '../../common/decorators/roles.decorator';
import { CurrentUser, CurrentUserPayload } from '../../common/decorators/current-user.decorator';

@Roles('super_admin', 'branch_manager')
@Controller('audit-logs')
export class AuditLogsController {
  constructor(private readonly auditLogsService: AuditLogsService) {}

  @Get()
  findAll(@CurrentUser() user: CurrentUserPayload, @Query() filter: BranchFilterDto) {
    return this.auditLogsService.findAll(user, filter);
  }
}
