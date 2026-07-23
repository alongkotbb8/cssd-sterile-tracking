import {
  Controller,
  Post,
  Get,
  Body,
  Headers,
  Param,
  Query,
  UseGuards,
  ParseEnumPipe,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags, ApiOperation, ApiQuery, ApiHeader } from '@nestjs/swagger';
import { PackageStatus } from '@prisma/client';
import { PackagesService } from './packages.service';
import { CreatePackageDto } from './dto/create-package.dto';
import { ReservePoolDto } from './dto/reserve-pool.dto';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { IdempotencyService } from '../../common/idempotency/idempotency.service';

@ApiTags('packages')
@ApiBearerAuth()
@UseGuards(AuthGuard('jwt'))
@Controller('packages')
export class PackagesController {
  constructor(
    private svc: PackagesService,
    private idem: IdempotencyService,
  ) {}

  @Post()
  @ApiOperation({ summary: 'สร้างห่ออุปกรณ์ใหม่ + ออกเลขรัน' })
  @ApiHeader({ name: 'Idempotency-Key', required: true, description: 'บังคับ — กันสร้างห่อซ้ำจาก retry/offline sync' })
  create(
    @Body() dto: CreatePackageDto,
    @CurrentUser() user: { id: string },
    @Headers('idempotency-key') idemKey?: string,
  ) {
    return this.idem.run(idemKey, user.id, 'packages/create', 'POST', dto, (tx) =>
      this.svc.create(dto, user.id, tx), { required: true });
  }

  @Get()
  @ApiOperation({ summary: 'รายการห่อทั้งหมด (กรองตาม status / template)' })
  @ApiQuery({ name: 'status', enum: PackageStatus, required: false })
  @ApiQuery({ name: 'templateId', required: false })
  findAll(
    @Query('status', new ParseEnumPipe(PackageStatus, { optional: true }))
    status?: PackageStatus,
    @Query('templateId') templateId?: string,
  ) {
    return this.svc.findAll(status, templateId);
  }

  @Get(':id')
  @ApiOperation({ summary: 'ดูรายละเอียดห่อ + ประวัติ movement' })
  findOne(@Param('id') id: string) {
    return this.svc.findOne(id);
  }

  @Post('reserve-pool')
  @ApiOperation({ summary: 'จองเลขรัน pool สำหรับโหมดออฟไลน์' })
  reservePool(@Body() body: ReservePoolDto, @CurrentUser() user: { id: string }) {
    return this.svc.reservePool(body.setTemplateId, body.count, body.deviceId, user.id);
  }

  // หมายเหตุ: เดิมมี POST /:id/printed ให้ client เรียกเองหลังพิมพ์สำเร็จ — ตัด
  // ออกแล้วเพราะขัด AI_DEVELOPMENT_GUARDRAILS.md ข้อ 2 ("ห้ามให้ PWA ตั้งสถานะ
  // Print Job เป็น PRINTED") printedAt/reprintCount อัปเดตผ่าน
  // print-gateway/jobs/:id/ack เท่านั้น (ดู modules/print-jobs)
}
