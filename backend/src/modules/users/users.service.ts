import { ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import * as argon2 from 'argon2';
import { PrismaService } from '../../prisma/prisma.service';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';
import { buildPaginationMeta } from '../../common/dto/pagination.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { AuditLogsService } from '../audit-logs/audit-logs.service';

const SAFE_SELECT = {
  id: true,
  email: true,
  fullName: true,
  role: true,
  branchId: true,
  phone: true,
  avatarUrl: true,
  isActive: true,
  createdAt: true,
  updatedAt: true,
  branch: { select: { name: true } },
};

function toResponse(user: any) {
  const { branch, ...rest } = user;
  return { ...rest, branchName: branch?.name ?? null };
}

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLogs: AuditLogsService,
  ) {}

  async findAll(currentUser: CurrentUserPayload, filter: BranchFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = {
      ...(branchId ? { branchId } : {}),
      ...(filter.search
        ? {
            OR: [
              { fullName: { contains: filter.search, mode: 'insensitive' as const } },
              { email: { contains: filter.search, mode: 'insensitive' as const } },
            ],
          }
        : {}),
    };

    const [rows, total] = await Promise.all([
      this.prisma.user.findMany({
        where,
        select: SAFE_SELECT,
        skip: filter.skip,
        take: filter.take,
        orderBy: { fullName: 'asc' },
      }),
      this.prisma.user.count({ where }),
    ]);

    return { data: rows.map(toResponse), meta: buildPaginationMeta(total, filter.page ?? 1, filter.take) };
  }

  async findOne(id: string) {
    const user = await this.prisma.user.findUnique({ where: { id }, select: SAFE_SELECT });
    if (!user) throw new NotFoundException('User not found');
    return toResponse(user);
  }

  async create(currentUser: CurrentUserPayload, dto: CreateUserDto) {
    const existing = await this.prisma.user.findUnique({ where: { email: dto.email.trim().toLowerCase() } });
    if (existing) throw new ConflictException('A user with this email already exists');

    const passwordHash = await argon2.hash(dto.password);
    const user = await this.prisma.user.create({
      data: {
        email: dto.email.trim().toLowerCase(),
        passwordHash,
        fullName: dto.fullName,
        role: dto.role,
        branchId: dto.branchId,
        phone: dto.phone,
        avatarUrl: dto.avatarUrl,
        isActive: dto.isActive ?? true,
      },
      select: SAFE_SELECT,
    });

    await this.auditLogs.record({
      branchId: dto.branchId,
      userId: currentUser.userId,
      action: 'created',
      tableName: 'users',
      rowId: user.id,
      newValues: { fullName: user.fullName, role: user.role },
    });

    return toResponse(user);
  }

  async update(id: string, currentUser: CurrentUserPayload, dto: UpdateUserDto) {
    const before = await this.findOne(id);
    const updated = await this.prisma.user.update({ where: { id }, data: dto, select: SAFE_SELECT });

    if (dto.role && dto.role !== before.role) {
      await this.auditLogs.record({
        branchId: updated.branchId ?? undefined,
        userId: currentUser.userId,
        action: 'role_changed',
        tableName: 'users',
        rowId: id,
        oldValues: { role: before.role },
        newValues: { role: dto.role },
      });
    }

    return toResponse(updated);
  }

  async toggleActive(id: string, currentUser: CurrentUserPayload) {
    const user = await this.findOne(id);
    const updated = await this.prisma.user.update({
      where: { id },
      data: { isActive: !user.isActive },
      select: SAFE_SELECT,
    });

    await this.auditLogs.record({
      branchId: updated.branchId ?? undefined,
      userId: currentUser.userId,
      action: updated.isActive ? 'unblocked' : 'blocked',
      tableName: 'users',
      rowId: id,
    });

    return toResponse(updated);
  }

  /**
   * Admin password reset — no current password required. super_admin may
   * target any user; branch_manager may only target users in their own
   * branch (also true for super_admins, whose branchId is null and so
   * never matches, keeping them out of a manager's reach).
   */
  async resetPassword(id: string, currentUser: CurrentUserPayload, dto: ResetPasswordDto) {
    const target = await this.findOne(id);

    if (currentUser.role !== 'super_admin' && target.branchId !== currentUser.branchId) {
      throw new ForbiddenException('You can only reset passwords for users in your own branch');
    }

    const passwordHash = await argon2.hash(dto.newPassword);
    await this.prisma.user.update({ where: { id }, data: { passwordHash } });

    // Force re-login everywhere, same as a self-service password change.
    await this.prisma.refreshToken.updateMany({
      where: { userId: id, revoked: false },
      data: { revoked: true },
    });

    await this.auditLogs.record({
      branchId: target.branchId ?? undefined,
      userId: currentUser.userId,
      action: 'password_reset',
      tableName: 'users',
      rowId: id,
    });

    return { success: true };
  }
}
