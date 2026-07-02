import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { RealtimeService } from '../websocket/realtime.service';
import { FcmService } from './fcm.service';
import { CreateNotificationDto } from './dto/create-notification.dto';
import { RegisterDeviceTokenDto } from './dto/register-device-token.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { buildPaginationMeta } from '../../common/dto/pagination.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';

@Injectable()
export class NotificationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
    private readonly fcm: FcmService,
  ) {}

  async findAll(currentUser: CurrentUserPayload, filter: BranchFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = branchId ? { branchId } : {};

    const [items, total] = await Promise.all([
      this.prisma.notification.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: filter.skip,
        take: filter.take,
      }),
      this.prisma.notification.count({ where }),
    ]);

    return { data: items, meta: buildPaginationMeta(total, filter.page ?? 1, filter.take) };
  }

  async create(dto: CreateNotificationDto) {
    const notification = await this.prisma.notification.create({ data: dto });
    this.realtime.notification(dto.branchId, notification);

    const tokens = await this.prisma.deviceToken.findMany({
      where: { user: { branchId: dto.branchId } },
      select: { token: true },
    });
    await this.fcm.sendToTokens(tokens.map((t) => t.token), dto.title, dto.body);

    return notification;
  }

  async markRead(id: string) {
    const notification = await this.prisma.notification.findUnique({ where: { id } });
    if (!notification) throw new NotFoundException('Notification not found');
    return this.prisma.notification.update({ where: { id }, data: { isRead: true } });
  }

  async markAllRead(currentUser: CurrentUserPayload, branchId?: string) {
    const scopedBranchId = resolveBranchScope(currentUser, branchId);
    await this.prisma.notification.updateMany({
      where: { ...(scopedBranchId ? { branchId: scopedBranchId } : {}), isRead: false },
      data: { isRead: true },
    });
    return { updated: true };
  }

  async registerDeviceToken(userId: string, dto: RegisterDeviceTokenDto) {
    return this.prisma.deviceToken.upsert({
      where: { token: dto.token },
      update: { userId, platform: dto.platform },
      create: { userId, token: dto.token, platform: dto.platform },
    });
  }
}
