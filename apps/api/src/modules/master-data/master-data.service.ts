import { ConflictException, Injectable } from '@nestjs/common';
import { PrismaService } from '../../common/prisma/prisma.service';
import { AuditService } from '../../common/audit/audit.service';
import { CreateSetTemplateDto } from './dto/create-template.dto';

@Injectable()
export class MasterDataService {
  constructor(
    private prisma: PrismaService,
    private audit: AuditService,
  ) {}

  getTemplates() { return this.prisma.setTemplate.findMany({ where: { isActive: true } }); }
  getSterilizers() { return this.prisma.sterilizer.findMany({ where: { isActive: true } }); }

  // ── Tags (จัดกลุ่ม/ค้นหาห่อ) ──
  getTags() {
    return this.prisma.tag.findMany({ orderBy: { name: 'asc' } });
  }

  async createTag(name: string, colorHex: string | undefined, userId: string) {
    const existing = await this.prisma.tag.findUnique({ where: { name } });
    if (existing) throw new ConflictException('มี tag ชื่อนี้อยู่แล้ว');
    const created = await this.prisma.$transaction(async (tx) => {
      const t = await tx.tag.create({ data: { name, colorHex } });
      await this.audit.logTx(tx, userId, 'TAG_CREATE', t.id, { name });
      return t;
    });
    return created;
  }

  async deleteTag(id: string, userId: string) {
    await this.prisma.$transaction(async (tx) => {
      await tx.tag.delete({ where: { id } });
      await this.audit.logTx(tx, userId, 'TAG_DELETE', id);
    });
    return { deleted: true };
  }

  async createTemplate(dto: CreateSetTemplateDto, userId: string) {
    const existing = await this.prisma.setTemplate.findUnique({ where: { code: dto.code } });
    if (existing) throw new ConflictException('รหัสชุดอุปกรณ์นี้มีอยู่แล้ว');

    const created = await this.prisma.setTemplate.create({
      data: {
        code: dto.code,
        name: dto.name,
        itemList: dto.itemList,
        defaultWrapType: dto.defaultWrapType ?? undefined,
      },
    });
    await this.audit.log(userId, 'TEMPLATE_CREATE', created.id, { code: created.code, name: created.name });
    return created;
  }
}
