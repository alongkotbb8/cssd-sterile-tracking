import { Controller, Post, Get, Body, Headers, Param, Query, UseGuards, ParseEnumPipe } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags, ApiOperation, ApiQuery, ApiHeader } from '@nestjs/swagger';
import { BatchStatus, UserRole } from '@prisma/client';
import { BatchesService } from './batches.service';
import { CreateBatchDto } from './dto/create-batch.dto';
import { RecordResultDto } from './dto/record-result.dto';
import { RecordBiResultDto } from './dto/record-bi-result.dto';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { Roles } from '../../common/decorators/roles.decorator';
import { RolesGuard } from '../../common/guards/roles.guard';
import { IdempotencyService } from '../../common/idempotency/idempotency.service';

@ApiTags('batches')
@ApiBearerAuth()
@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('batches')
export class BatchesController {
  constructor(
    private svc: BatchesService,
    private idem: IdempotencyService,
  ) {}

  @Post()
  @ApiOperation({ summary: 'เปิดรอบนึ่งใหม่' })
  @ApiHeader({ name: 'Idempotency-Key', required: true, description: 'บังคับ — กันเปิดรอบซ้ำจาก retry' })
  create(
    @Body() dto: CreateBatchDto,
    @CurrentUser() user: { id: string },
    @Headers('idempotency-key') idemKey?: string,
  ) {
    return this.idem.run(idemKey, user.id, 'batches/create', 'POST', dto, (tx) =>
      this.svc.create(dto, user.id, tx), { required: true });
  }

  @Get()
  @ApiOperation({ summary: 'รายการรอบนึ่ง (ล่าสุดก่อน สูงสุด 50 รายการ)' })
  @ApiQuery({ name: 'status', enum: BatchStatus, required: false })
  findAll(
    @Query('status', new ParseEnumPipe(BatchStatus, { optional: true }))
    status?: BatchStatus,
  ) {
    return this.svc.findAll(status);
  }

  @Get(':id')
  @ApiOperation({ summary: 'ดูรายละเอียดรอบนึ่ง' })
  findOne(@Param('id') id: string) { return this.svc.findOne(id); }

  @Post(':id/result')
  @Roles(UserRole.SUPERVISOR, UserRole.ADMIN)
  @ApiOperation({
    summary:
      'บันทึกผล CI/BI (SUPERVISOR/ADMIN เท่านั้น) — ผ่าน: ห่อทั้งรอบเป็น STERILE, ไม่ผ่าน: recall อัตโนมัติ (FR-5)',
  })
  @ApiHeader({ name: 'Idempotency-Key', required: true, description: 'บังคับ — กันบันทึกผลซ้ำจาก retry' })
  recordResult(
    @Param('id') id: string,
    @Body() dto: RecordResultDto,
    @CurrentUser() user: { id: string },
    @Headers('idempotency-key') idemKey?: string,
  ) {
    return this.idem.run(idemKey, user.id, `batches/${id}/result`, 'POST', dto, (tx) =>
      this.svc.recordResult(id, dto.ciResult, dto.biResult ?? null, user.id, tx), { required: true });
  }

  @Post(':id/bi-result')
  @Roles(UserRole.SUPERVISOR, UserRole.ADMIN)
  @ApiOperation({
    summary:
      'บันทึกผล BI ที่มาทีหลัง (เฉพาะรอบ PENDING_BI ที่ early-release แล้ว) — ผ่าน: PASSED, ' +
      'ไม่ผ่าน: FAILED + recall ห่อที่ปล่อยไปแล้ว (SUPERVISOR/ADMIN)',
  })
  @ApiHeader({ name: 'Idempotency-Key', required: true, description: 'บังคับ — กันบันทึกผลซ้ำ' })
  recordBiResult(
    @Param('id') id: string,
    @Body() dto: RecordBiResultDto,
    @CurrentUser() user: { id: string },
    @Headers('idempotency-key') idemKey?: string,
  ) {
    return this.idem.run(idemKey, user.id, `batches/${id}/bi-result`, 'POST', dto, (tx) =>
      this.svc.recordBiResult(id, dto.biResult, user.id, tx), { required: true });
  }

  @Post(':id/recall')
  @Roles(UserRole.SUPERVISOR, UserRole.ADMIN)
  @ApiOperation({ summary: 'Recall ห่อทั้งหมดในรอบนึ่งที่ผลไม่ผ่าน (FR-5) — SUPERVISOR/ADMIN เท่านั้น' })
  recall(@Param('id') id: string, @CurrentUser() user: { id: string }) {
    return this.svc.recall(id, user.id);
  }

  @Get(':id/packages')
  @ApiOperation({ summary: 'รายการห่อในรอบนึ่งพร้อมตำแหน่งปัจจุบัน' })
  getPackages(@Param('id') id: string) { return this.svc.getPackages(id); }
}
