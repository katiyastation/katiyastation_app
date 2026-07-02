import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { ReportFilterDto } from './dto/report-filter.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';

function dateRange(filter: ReportFilterDto) {
  return {
    ...(filter.from || filter.to
      ? {
          createdAt: {
            ...(filter.from ? { gte: new Date(filter.from) } : {}),
            ...(filter.to ? { lte: new Date(filter.to) } : {}),
          },
        }
      : {}),
  };
}

@Injectable()
export class ReportsService {
  constructor(private readonly prisma: PrismaService) {}

  async dashboard(currentUser: CurrentUserPayload, filter: ReportFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = branchId ? { branchId } : {};

    const [billsAgg, openSessions, activeKots, inventoryItems, todaysBillCount] = await Promise.all([
      this.prisma.bill.aggregate({ where, _sum: { totalAmount: true } }),
      this.prisma.tableSession.count({ where: { ...where, status: 'open' } }),
      this.prisma.kot.count({ where: { ...where, status: { in: ['pending', 'preparing', 'ready'] } } }),
      this.prisma.inventoryItem.findMany({ where, select: { currentStock: true, reorderLevel: true } }),
      this.prisma.bill.count({
        where: { ...where, createdAt: { gte: new Date(new Date().toISOString().slice(0, 10)) } },
      }),
    ]);

    const lowStockCount = inventoryItems.filter(
      (item) => Number(item.currentStock) <= Number(item.reorderLevel),
    ).length;

    return {
      totalRevenue: Number(billsAgg._sum.totalAmount ?? 0),
      openSessions,
      activeKots,
      lowStockCount,
      todaysBillCount,
    };
  }

  async sales(currentUser: CurrentUserPayload, filter: ReportFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = { ...(branchId ? { branchId } : {}), ...dateRange(filter) };

    const [totals, byPaymentMethod] = await Promise.all([
      this.prisma.bill.aggregate({
        where,
        _sum: { subTotal: true, discount: true, serviceCharge: true, vatAmount: true, totalAmount: true },
        _count: true,
      }),
      this.prisma.bill.groupBy({
        by: ['paymentMethod'],
        where,
        _sum: { totalAmount: true },
        _count: true,
      }),
    ]);

    return {
      billCount: totals._count,
      subTotal: Number(totals._sum.subTotal ?? 0),
      discount: Number(totals._sum.discount ?? 0),
      serviceCharge: Number(totals._sum.serviceCharge ?? 0),
      vatAmount: Number(totals._sum.vatAmount ?? 0),
      totalAmount: Number(totals._sum.totalAmount ?? 0),
      byPaymentMethod: byPaymentMethod.map((row) => ({
        paymentMethod: row.paymentMethod,
        count: row._count,
        totalAmount: Number(row._sum.totalAmount ?? 0),
      })),
    };
  }

  async inventory(currentUser: CurrentUserPayload, filter: ReportFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = branchId ? { branchId } : {};

    const items = await this.prisma.inventoryItem.findMany({ where });
    const lowStock = items.filter((item) => Number(item.currentStock) <= Number(item.reorderLevel));

    return {
      totalItems: items.length,
      lowStockCount: lowStock.length,
      lowStockItems: lowStock,
      totalValue: items.reduce(
        (sum, item) => sum + Number(item.currentStock) * Number(item.costPerUnit ?? 0),
        0,
      ),
    };
  }

  async staff(currentUser: CurrentUserPayload, filter: ReportFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = branchId ? { branchId } : {};

    const [staffCount, byRole, byStatus] = await Promise.all([
      this.prisma.staffMember.count({ where }),
      this.prisma.staffMember.groupBy({ by: ['role'], where, _count: true }),
      this.prisma.staffMember.groupBy({ by: ['status'], where, _count: true }),
    ]);

    return {
      staffCount,
      byRole: byRole.map((row) => ({ role: row.role, count: row._count })),
      byStatus: byStatus.map((row) => ({ status: row.status, count: row._count })),
    };
  }

  async revenue(currentUser: CurrentUserPayload, filter: ReportFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = { ...(branchId ? { branchId } : {}), ...dateRange(filter) };

    const [billsAgg, expensesAgg] = await Promise.all([
      this.prisma.bill.aggregate({ where, _sum: { totalAmount: true } }),
      this.prisma.expense.aggregate({ where, _sum: { amount: true } }),
    ]);

    const revenue = Number(billsAgg._sum.totalAmount ?? 0);
    const expenses = Number(expensesAgg._sum.amount ?? 0);

    return { revenue, expenses, netProfit: revenue - expenses };
  }
}
