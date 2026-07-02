import { Body, Controller, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { KotsService } from './kots.service';
import { CreateKotDto } from './dto/create-kot.dto';
import { UpdateStatusDto } from './dto/update-status.dto';
import { UpdateItemQuantityDto } from './dto/update-item-quantity.dto';
import { FindKotsDto } from './dto/find-kots.dto';
import { Roles } from '../../common/decorators/roles.decorator';
import { CurrentUser, CurrentUserPayload } from '../../common/decorators/current-user.decorator';

@Controller('kots')
export class KotsController {
  constructor(private readonly kotsService: KotsService) {}

  @Get()
  findAll(@CurrentUser() user: CurrentUserPayload, @Query() filter: FindKotsDto) {
    return this.kotsService.findAll(user, filter);
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.kotsService.findOneResponse(id);
  }

  @Get(':id/items')
  items(@Param('id') id: string) {
    return this.kotsService.items(id);
  }

  @Roles('super_admin', 'branch_manager', 'cashier', 'waiter')
  @Post()
  create(@CurrentUser() user: CurrentUserPayload, @Body() dto: CreateKotDto) {
    return this.kotsService.create(user, dto);
  }

  @Roles('super_admin', 'branch_manager', 'cashier', 'waiter', 'kitchen')
  @Patch(':id/status')
  updateStatus(@Param('id') id: string, @Body() dto: UpdateStatusDto) {
    return this.kotsService.updateStatus(id, dto);
  }

  @Roles('super_admin', 'branch_manager', 'cashier', 'waiter', 'kitchen')
  @Patch(':kotId/items/:itemId/status')
  updateItemStatus(
    @Param('kotId') kotId: string,
    @Param('itemId') itemId: string,
    @Body() dto: UpdateStatusDto,
  ) {
    return this.kotsService.updateItemStatus(kotId, itemId, dto);
  }

  @Roles('super_admin', 'branch_manager', 'cashier', 'waiter')
  @Patch('items/:itemId/quantity')
  updateItemQuantity(@Param('itemId') itemId: string, @Body() dto: UpdateItemQuantityDto) {
    return this.kotsService.updateItemQuantity(itemId, dto);
  }
}
