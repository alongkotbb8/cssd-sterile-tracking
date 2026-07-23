import { ConflictException, Injectable } from '@nestjs/common';
import { PrismaService } from '../../common/prisma/prisma.service';
import { AuditService } from '../../common/audit/audit.service';
import { CreateDepartmentDto } from './dto/create-department.dto';

@Injectable()
export class DepartmentsService {
  constructor(
    private prisma: PrismaService,
    private audit: AuditService,
  ) {}

  findAll() {
    return this.prisma.department.findMany({ where: { isActive: true }, orderBy: { name: 'asc' } });
  }

  async create(dto: CreateDepartmentDto, userId: string) {
    const existing = await this.prisma.department.findUnique({ where: { code: dto.code } });
    if (existing) throw new ConflictException('รหัสแผนก/สถานที่นี้มีอยู่แล้ว');

    return this.prisma.$transaction(async (tx) => {
      const created = await tx.department.create({
        data: { code: dto.code, name: dto.name, type: dto.type ?? null },
      });
      await this.audit.logTx(tx, userId, 'DEPARTMENT_CREATE', created.id, {
        code: created.code,
        name: created.name,
        type: created.type,
      });
      return created;
    });
  }
}
