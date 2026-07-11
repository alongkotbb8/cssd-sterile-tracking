import { Controller, Post, Get, Body, Param, Query, UseGuards, ParseEnumPipe } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags, ApiOperation, ApiQuery } from '@nestjs/swagger';
import { BatchStatus, UserRole } from '@prisma/client';
import { BatchesService } from './batches.service';
import { CreateBatchDto } from './dto/create-batch.dto';
import { RecordResultDto } from './dto/record-result.dto';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { Roles } from '../../common/decorators/roles.decorator';
import { RolesGuard } from '../../common/guards/roles.guard';

@ApiTags('batches')
@ApiBearerAuth()
@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('batches')
export class BatchesController {
  constructor(private svc: BatchesService) {}

  @Post()
  @ApiOperation({ summary: 'เปิดรอบนึ่งใหม่' })
  create(@Body() dto: CreateBatchDto, @CurrentUser() user: { id: string }) {
    return this.svc.create(dto, user.id);
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
  @ApiOperation({ summary: 'บันทึกผล CI/BI — ถ้าไม่ผ่านระบบ recall อัตโนมัติ (FR-5)' })
  recordResult(
    @Param('id') id: string,
    @Body() dto: RecordResultDto,
    @CurrentUser() user: { id: string },
  ) {
    return this.svc.recordResult(id, dto.ciResult, dto.biResult ?? null, user.id);
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
