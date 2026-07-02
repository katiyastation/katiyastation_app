import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { RealtimeService } from '../websocket/realtime.service';
import { CreateTableDto } from './dto/create-table.dto';
import { UpdateTableDto } from './dto/update-table.dto';
import { OpenSessionDto } from './dto/open-session.dto';
import { TransferSessionDto } from './dto/transfer-session.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { generateSequenceNumber } from '../../common/utils/sequence.util';

@Injectable()
export class TablesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
  ) {}

  async findAll(currentUser: CurrentUserPayload, requestedBranchId?: string) {
    const branchId = resolveBranchScope(currentUser, requestedBranchId);
    return this.prisma.restaurantTable.findMany({
      where: branchId ? { branchId } : {},
      orderBy: [{ section: 'asc' }, { tableNumber: 'asc' }],
    });
  }

  async findOne(id: string) {
    const table = await this.prisma.restaurantTable.findUnique({ where: { id } });
    if (!table) throw new NotFoundException('Table not found');
    return table;
  }

  create(dto: CreateTableDto) {
    return this.prisma.restaurantTable.create({
      data: {
        branchId: dto.branchId,
        tableNumber: dto.tableNumber,
        section: dto.section ?? 'Main',
        capacity: dto.capacity ?? 4,
      },
    });
  }

  async update(id: string, dto: UpdateTableDto) {
    await this.findOne(id);
    const table = await this.prisma.restaurantTable.update({ where: { id }, data: dto });
    if (dto.status) {
      this.realtime.tableStatusChanged(table.branchId, table.id, table);
    }
    return table;
  }

  async remove(id: string) {
    await this.findOne(id);
    await this.prisma.restaurantTable.delete({ where: { id } });
    return { deleted: true };
  }

  async sessions(tableId: string) {
    await this.findOne(tableId);
    return this.prisma.tableSession.findMany({
      where: { tableId },
      orderBy: { openedAt: 'desc' },
    });
  }

  async currentSession(tableId: string) {
    const table = await this.findOne(tableId);
    if (!table.currentSessionId) return null;
    return this.prisma.tableSession.findUnique({ where: { id: table.currentSessionId } });
  }

  async openSession(tableId: string, currentUser: CurrentUserPayload, dto: OpenSessionDto) {
    const table = await this.findOne(tableId);

    if (table.status === 'occupied' && table.currentSessionId) {
      throw new BadRequestException('This table already has an open session');
    }

    const session = await this.prisma.$transaction(async (tx) => {
      const created = await tx.tableSession.create({
        data: {
          tableId: table.id,
          branchId: table.branchId,
          sessionNumber: generateSequenceNumber('SESS'),
          waiterId: currentUser.role === 'waiter' ? currentUser.userId : undefined,
          customerId: dto.customerId,
          guestCount: dto.guestCount ?? 1,
        },
      });

      await tx.restaurantTable.update({
        where: { id: table.id },
        data: { status: 'occupied', currentSessionId: created.id },
      });

      return created;
    });

    this.realtime.sessionOpened(table.branchId, session);
    this.realtime.tableStatusChanged(table.branchId, table.id, { ...table, status: 'occupied' });

    return session;
  }

  async requestBill(tableId: string) {
    const table = await this.findOne(tableId);
    if (!table.currentSessionId) {
      throw new BadRequestException('This table has no active session');
    }

    const now = new Date();
    const [updatedTable] = await this.prisma.$transaction([
      this.prisma.restaurantTable.update({
        where: { id: tableId },
        data: { status: 'ready_for_billing', billRequested: true, billRequestedAt: now },
      }),
      this.prisma.tableSession.update({
        where: { id: table.currentSessionId },
        data: { billRequested: true, billRequestedAt: now },
      }),
    ]);

    this.realtime.tableStatusChanged(table.branchId, tableId, updatedTable);
    return updatedTable;
  }

  async transferSession(fromTableId: string, dto: TransferSessionDto) {
    const fromTable = await this.findOne(fromTableId);
    const toTable = await this.findOne(dto.toTableId);
    if (!fromTable.currentSessionId) {
      throw new BadRequestException('Source table has no active session to transfer');
    }
    if (toTable.currentSessionId) {
      throw new BadRequestException('Destination table already has an active session');
    }

    const sessionId = fromTable.currentSessionId;
    await this.prisma.$transaction([
      this.prisma.tableSession.update({ where: { id: sessionId }, data: { tableId: toTable.id } }),
      this.prisma.kot.updateMany({ where: { sessionId }, data: { tableId: toTable.id } }),
      this.prisma.restaurantTable.update({
        where: { id: fromTableId },
        data: { status: 'available', currentSessionId: null, billRequested: false, billRequestedAt: null },
      }),
      this.prisma.restaurantTable.update({
        where: { id: toTable.id },
        data: { status: fromTable.status, currentSessionId: sessionId },
      }),
    ]);

    this.realtime.tableStatusChanged(fromTable.branchId, fromTableId, { status: 'available' });
    this.realtime.tableStatusChanged(fromTable.branchId, toTable.id, { status: fromTable.status });
    return { transferred: true };
  }
}
