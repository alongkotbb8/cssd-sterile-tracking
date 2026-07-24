import {
  Controller,
  Post,
  Put,
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
import { PackageStatus, UserRole } from '@prisma/client';
import { PackagesService } from './packages.service';
import { CreatePackageDto } from './dto/create-package.dto';
import { SetTagsDto } from './dto/set-tags.dto';
import { BulkDeleteDto } from './dto/bulk-delete.dto';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { Roles } from '../../common/decorators/roles.decorator';
import { RolesGuard } from '../../common/guards/roles.guard';
import { IdempotencyService } from '../../common/idempotency/idempotency.service';

@ApiTags('packages')
@ApiBearerAuth()
@UseGuards(AuthGuard('jwt'), RolesGuard)
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
  @ApiOperation({ summary: 'รายการห่อทั้งหมด (กรองตาม status / template / tag / ค้นหา)' })
  @ApiQuery({ name: 'status', enum: PackageStatus, required: false })
  @ApiQuery({ name: 'templateId', required: false })
  @ApiQuery({ name: 'tagId', required: false })
  @ApiQuery({ name: 'search', required: false, description: 'ค้นหา: เลขห่อ / ชื่อชุด / อุปกรณ์ในชุด / คลัง (max 60)' })
  findAll(
    @Query('status', new ParseEnumPipe(PackageStatus, { optional: true }))
    status?: PackageStatus,
    @Query('templateId') templateId?: string,
    @Query('tagId') tagId?: string,
    @Query('search') search?: string,
  ) {
    // trim + จำกัด 60 ตัว (กัน query ยาวผิดปกติ) — ว่าง/ไม่ส่ง = พฤติกรรมเดิม
    const q = typeof search === 'string' ? search.trim().slice(0, 60) : undefined;
    return this.svc.findAll(status, templateId, tagId, q || undefined);
  }

  @Post('bulk-delete')
  @Roles(UserRole.SUPERVISOR, UserRole.ADMIN)
  @ApiOperation({ summary: 'ลบห่อถาวรหลายรายการ — เฉพาะ PACKED ที่ยังไม่มีประวัติ (SUPERVISOR/ADMIN)' })
  @ApiHeader({ name: 'Idempotency-Key', required: true, description: 'บังคับ — กันลบซ้ำจาก retry' })
  bulkDelete(
    @Body() dto: BulkDeleteDto,
    @CurrentUser() user: { id: string },
    @Headers('idempotency-key') idemKey?: string,
  ) {
    return this.idem.run(idemKey, user.id, 'packages/bulk-delete', 'POST', dto, (tx) =>
      this.svc.bulkDelete(dto.packageIds, user.id, tx), { required: true });
  }

  @Get(':id')
  @ApiOperation({ summary: 'ดูรายละเอียดห่อ + ประวัติ movement' })
  findOne(@Param('id') id: string) {
    return this.svc.findOne(id);
  }

  @Put(':id/tags')
  @ApiOperation({ summary: 'ตั้ง tag ของห่อ (แทนที่ทั้งชุด) — ใช้ติด/ถอด tag' })
  setTags(
    @Param('id') id: string,
    @Body() dto: SetTagsDto,
    @CurrentUser() user: { id: string },
  ) {
    return this.svc.setTags(id, dto.tagIds, user.id);
  }

  // หมายเหตุ: เดิมมี POST /reserve-pool (จองเลขรัน pool สำหรับ offline) — ตัดออกแล้ว
  // เพราะระบบเป็น online-only (ออกเลขตอนสร้างจริงเท่านั้น) ไม่มี consumer ฝั่ง client
  // ตาราง NumberPoolReservation ยังคงไว้ใน schema (ไม่ลบแบบ destructive) แต่ไม่มีอะไรเขียนแล้ว

  // หมายเหตุ: เดิมมี POST /:id/printed ให้ client เรียกเองหลังพิมพ์สำเร็จ — ตัด
  // ออกแล้วเพราะขัด AI_DEVELOPMENT_GUARDRAILS.md ข้อ 2 ("ห้ามให้ PWA ตั้งสถานะ
  // Print Job เป็น PRINTED") printedAt/reprintCount อัปเดตผ่าน
  // print-gateway/jobs/:id/ack เท่านั้น (ดู modules/print-jobs)
}
