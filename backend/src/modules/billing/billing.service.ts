import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { RealtimeService } from '../websocket/realtime.service';
import { GenerateBillDto } from './dto/generate-bill.dto';
import { UpdateBillDto } from './dto/update-bill.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { buildPaginationMeta } from '../../common/dto/pagination.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';
import { generateSequenceNumber } from '../../common/utils/sequence.util';

@Injectable()
export class BillingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
  ) {}

  async findAll(currentUser: CurrentUserPayload, filter: BranchFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = branchId ? { branchId } : {};

    const [items, total] = await Promise.all([
      this.prisma.bill.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: filter.skip,
        take: filter.take,
      }),
      this.prisma.bill.count({ where }),
    ]);

    return { data: items, meta: buildPaginationMeta(total, filter.page ?? 1, filter.take) };
  }

  async findOne(id: string) {
    const bill = await this.prisma.bill.findUnique({ where: { id } });
    if (!bill) throw new NotFoundException('Bill not found');
    return bill;
  }

  /**
   * "Settle Bill": creates the Bill (and a CreditRecord for credit sales),
   * then closes the session and frees the table — all as one atomic action,
   * matching the cashier screen's single "Settle Bill" button.
   */
  async generate(sessionId: string, currentUser: CurrentUserPayload, dto: GenerateBillDto) {
    const session = await this.prisma.tableSession.findUnique({ where: { id: sessionId } });
    if (!session) throw new NotFoundException('Session not found');
    if (session.status === 'billed') {
      throw new BadRequestException('This session has already been billed');
    }

    const branch = await this.prisma.branch.findUniqueOrThrow({ where: { id: session.branchId } });
    const cashier = await this.prisma.user.findUnique({ where: { id: currentUser.userId } });

    const kotItems = await this.prisma.kotItem.findMany({
      where: { kot: { sessionId }, status: { not: 'cancelled' } },
    });

    const subTotal = kotItems.reduce(
      (sum, item) => sum + Number(item.unitPrice) * item.quantity,
      0,
    );
    const discount = dto.discount ?? 0;

    // Matches the cashier screen's exact math: service charge is on the
    // full subtotal (before discount), discount is subtracted after, and
    // VAT applies to the post-service, post-discount amount. Both are
    // opt-in per bill (cashier toggles), off by default.
    const serviceCharge = dto.applyServiceCharge
      ? (subTotal * Number(branch.serviceChargeRate)) / 100
      : 0;
    const afterService = subTotal + serviceCharge - discount;
    const vatAmount = dto.applyVat ? (afterService * Number(branch.vatRate)) / 100 : 0;
    const totalAmount = afterService + vatAmount;
    const paymentMethod = dto.paymentMethod ?? 'cash';
    const amountPaid = dto.amountPaid ?? totalAmount;

    const bill = await this.prisma.$transaction(async (tx) => {
      const created = await tx.bill.create({
        data: {
          branchId: session.branchId,
          sessionId: session.id,
          tableId: session.tableId,
          billNumber: generateSequenceNumber('BILL'),
          invoiceNumber: generateSequenceNumber('INV'),
          subTotal,
          discount,
          serviceCharge,
          vatAmount,
          totalAmount,
          amountPaid,
          changeAmount: paymentMethod === 'cash' ? Math.max(0, amountPaid - totalAmount) : 0,
          paymentMethod,
          paymentStatus: paymentMethod === 'credit' ? 'credit' : 'paid',
          cashierId: currentUser.userId,
          cashierName: cashier?.fullName,
          customerName: dto.customerName,
          customerPhone: dto.customerPhone,
        },
      });

      if (paymentMethod === 'credit') {
        await tx.creditRecord.create({
          data: {
            branchId: session.branchId,
            billId: created.id,
            customerId: session.customerId ?? session.id, // no separate customer record required for walk-in credit
            customerName: dto.customerName ?? 'Unknown',
            customerPhone: dto.customerPhone,
            creditAmount: totalAmount,
            paidAmount: 0,
            status: 'pending',
          },
        });
      }

      await tx.tableSession.update({
        where: { id: session.id },
        data: { status: 'billed', totalAmount, closedAt: new Date() },
      });

      await tx.restaurantTable.update({
        where: { id: session.tableId },
        data: { status: 'available', currentSessionId: null, billRequested: false, billRequestedAt: null },
      });

      return created;
    });

    this.realtime.billGenerated(session.branchId, bill);
    this.realtime.tableStatusChanged(session.branchId, session.tableId, { status: 'available' });
    return bill;
  }

  async update(id: string, dto: UpdateBillDto) {
    const bill = await this.findOne(id);
    const updated = await this.prisma.bill.update({ where: { id }, data: dto });
    if (dto.paymentStatus === 'paid') {
      this.realtime.billPaid(bill.branchId, updated);
    }
    return updated;
  }

  paymentHistory(currentUser: CurrentUserPayload, filter: BranchFilterDto) {
    return this.findAll(currentUser, filter);
  }
}
