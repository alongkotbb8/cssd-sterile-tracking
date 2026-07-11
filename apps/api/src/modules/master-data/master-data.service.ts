import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../common/prisma/prisma.service';

@Injectable()
export class MasterDataService {
  constructor(private prisma: PrismaService) {}

  getTemplates() { return this.prisma.setTemplate.findMany({ where: { isActive: true } }); }
  getSterilizers() { return this.prisma.sterilizer.findMany({ where: { isActive: true } }); }
}
