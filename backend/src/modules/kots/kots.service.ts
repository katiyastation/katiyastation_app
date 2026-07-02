import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { RealtimeService } from '../websocket/realtime.service';
import { CreateKotDto } from './dto/create-kot.dto';
import { UpdateStatusDto } from './dto/update-status.dto';
import { UpdateItemQuantityDto } from './dto/update-item-quantity.dto';
import { FindKotsDto } from './dto/find-kots.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { generateSequenceNumber } from '../../common/utils/sequence.util';

const KOT_INCLUDE = {
  items: true,
  waiter: { select: { fullName: true } },
  table: { select: { tableNumber: true } },
} as const;

/** Flattens the Kot response to match Kot.fromJson in the Flutter client. */
function toKotResponse(kot: any) {
  const { waiter, table, ...rest } = kot;
  return { ...rest, waiterName: waiter?.fullName ?? null, tableNumber: table?.tableNumber ?? null };
}

@Injectable()
export class KotsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
  ) {}

  async findAll(currentUser: CurrentUserPayload, filter: FindKotsDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const statuses = filter.status?.split(',').map((s) => s.trim()).filter(Boolean);

    const kots = await this.prisma.kot.findMany({
      where: {
        ...(branchId ? { branchId } : {}),
        ...(statuses?.length ? { status: { in: statuses } } : {}),
      },
      include: KOT_INCLUDE,
      orderBy: { createdAt: 'asc' },
      take: filter.take,
      skip: filter.skip,
    });
    return kots.map(toKotResponse);
  }

  async findOne(id: string) {
    const kot = await this.prisma.kot.findUnique({ where: { id }, include: KOT_INCLUDE });
    if (!kot) throw new NotFoundException('KOT not found');
    return kot;
  }

  async findOneResponse(id: string) {
    return toKotResponse(await this.findOne(id));
  }

  async items(kotId: string) {
    await this.findOne(kotId);
    return this.prisma.kotItem.findMany({ where: { kotId }, orderBy: { createdAt: 'asc' } });
  }

  async bySession(sessionId: string) {
    const kots = await this.prisma.kot.findMany({
      where: { sessionId },
      include: KOT_INCLUDE,
      orderBy: { createdAt: 'asc' },
    });
    return kots.map(toKotResponse);
  }

  async create(currentUser: CurrentUserPayload, dto: CreateKotDto) {
    const session = await this.prisma.tableSession.findUnique({ where: { id: dto.sessionId } });
    if (!session) throw new NotFoundException('Session not found');

    const menuItems = await this.prisma.menuItem.findMany({
      where: { id: { in: dto.items.map((i) => i.menuItemId) } },
    });
    const priceById = new Map(menuItems.map((m) => [m.id, m.price]));

    const kot = await this.prisma.kot.create({
      data: {
        sessionId: session.id,
        branchId: session.branchId,
        tableId: session.tableId,
        kotNumber: generateSequenceNumber('KOT'),
        waiterId: dto.waiterId ?? currentUser.userId,
        itemsCount: dto.items.length,
        items: {
          create: dto.items.map((item) => ({
            menuItemId: item.menuItemId,
            name: item.name,
            quantity: item.quantity,
            unitPrice: priceById.get(item.menuItemId) ?? 0,
            note: item.note,
          })),
        },
      },
      include: KOT_INCLUDE,
    });

    await this.recalculateSessionTotal(session.id);
    const response = toKotResponse(kot);
    this.realtime.kotNew(session.branchId, response);
    return response;
  }

  async updateStatus(id: string, dto: UpdateStatusDto) {
    const kot = await this.findOne(id);
    const updated = await this.prisma.kot.update({
      where: { id },
      data: { status: dto.status },
    });

    // Bulk-progress child items alongside the parent ticket for the common
    // statuses; individual items can still be advanced independently.
    if (['preparing', 'ready', 'served', 'cancelled'].includes(dto.status)) {
      await this.prisma.kotItem.updateMany({
        where: { kotId: id, status: { notIn: ['cancelled'] } },
        data: { status: dto.status },
      });
    }

    if (dto.status === 'cancelled') {
      await this.recalculateSessionTotal(kot.sessionId);
    }

    const response = await this.findOneResponse(id);
    this.realtime.kotStatusChanged(updated.branchId, response);
    return response;
  }

  async updateItemStatus(kotId: string, itemId: string, dto: UpdateStatusDto) {
    const kot = await this.findOne(kotId);
    const item = kot.items.find((i) => i.id === itemId);
    if (!item) throw new NotFoundException('KOT item not found');

    const updated = await this.prisma.kotItem.update({
      where: { id: itemId },
      data: { status: dto.status },
    });

    this.realtime.kotStatusChanged(kot.branchId, await this.findOneResponse(kotId));
    return updated;
  }

  /** Changes an item's quantity, or cancels it when the new quantity is <= 0. */
  async updateItemQuantity(itemId: string, dto: UpdateItemQuantityDto) {
    const item = await this.prisma.kotItem.findUnique({ where: { id: itemId } });
    if (!item) throw new NotFoundException('KOT item not found');

    const updated =
      dto.quantity <= 0
        ? await this.prisma.kotItem.update({ where: { id: itemId }, data: { status: 'cancelled' } })
        : await this.prisma.kotItem.update({ where: { id: itemId }, data: { quantity: dto.quantity } });

    const kot = await this.findOne(item.kotId);
    if (!kot) throw new BadRequestException('Parent KOT no longer exists');
    await this.recalculateSessionTotal(kot.sessionId);
    this.realtime.kotStatusChanged(kot.branchId, await this.findOneResponse(item.kotId));
    return updated;
  }

  /** Recomputes total_amount from non-cancelled KOT items. Used after any KOT/item mutation. */
  async recalculateSessionTotal(sessionId: string) {
    const items = await this.prisma.kotItem.findMany({
      where: { kot: { sessionId, status: { not: 'cancelled' } }, status: { not: 'cancelled' } },
    });
    const total = items.reduce((sum, item) => sum + Number(item.quantity) * Number(item.unitPrice), 0);
    return this.prisma.tableSession.update({ where: { id: sessionId }, data: { totalAmount: total } });
  }
}
