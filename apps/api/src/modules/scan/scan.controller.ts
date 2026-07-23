import { Controller, Post, Get, Body, Headers, Param, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags, ApiOperation, ApiHeader } from '@nestjs/swagger';
import {
  IsString,
  IsArray,
  IsOptional,
  IsBoolean,
  ArrayNotEmpty,
  ArrayMaxSize,
  MaxLength,
} from 'class-validator';
import { ScanService } from './scan.service';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { IdempotencyService } from '../../common/idempotency/idempotency.service';

class ScanInDto {
  @IsArray() @ArrayNotEmpty() @ArrayMaxSize(200) @IsString({ each: true }) packageIds: string[];
  @IsString() batchId: string;
  // ผู้ใช้พิมพ์เลขห่อเอง (กล้องใช้ไม่ได้) — ต้องติด flag ไว้ตรวจสอบย้อนหลังได้เสมอ
  @IsOptional() @IsBoolean() manualEntry?: boolean;
}

class ScanOutDto {
  @IsArray() @ArrayNotEmpty() @ArrayMaxSize(200) @IsString({ each: true }) packageIds: string[];
  @IsString() departmentId: string;
  @IsOptional() @IsString() @MaxLength(100) receiverName?: string;
  @IsOptional() @IsBoolean() manualEntry?: boolean;
}

class ScanReturnDto {
  @IsArray() @ArrayNotEmpty() @ArrayMaxSize(200) @IsString({ each: true }) packageIds: string[];
  @IsString() departmentId: string;
  @IsOptional() @IsBoolean() manualEntry?: boolean;
}

class ReprocessDto {
  @IsArray() @ArrayNotEmpty() @ArrayMaxSize(200) @IsString({ each: true }) packageIds: string[];
  @IsOptional() @IsBoolean() manualEntry?: boolean;
}

@ApiTags('scan')
@ApiBearerAuth()
@UseGuards(AuthGuard('jwt'))
@Controller('scan')
export class ScanController {
  constructor(
    private svc: ScanService,
    private idem: IdempotencyService,
  ) {}

  @Post('in')
  @ApiOperation({ summary: 'สแกนห่อเข้ารอบนึ่ง PENDING (batch scan)' })
  @ApiHeader({ name: 'Idempotency-Key', required: true, description: 'บังคับ — กันยิงซ้ำจาก offline sync/retry' })
  scanIn(
    @Body() dto: ScanInDto,
    @CurrentUser() user: { id: string },
    @Headers('idempotency-key') idemKey?: string,
  ) {
    return this.idem.run(idemKey, user.id, 'scan/in', 'POST', dto, (tx) =>
      this.svc.scanIn(dto.packageIds, dto.batchId, user.id, !!dto.manualEntry, tx), { required: true });
  }

  @Post('out')
  @ApiOperation({ summary: 'สแกนเบิกออก → แผนกปลายทาง (FR-2, FR-4)' })
  @ApiHeader({ name: 'Idempotency-Key', required: true, description: 'บังคับ — กันยิงซ้ำจาก offline sync/retry' })
  scanOut(
    @Body() dto: ScanOutDto,
    @CurrentUser() user: { id: string },
    @Headers('idempotency-key') idemKey?: string,
  ) {
    return this.idem.run(idemKey, user.id, 'scan/out', 'POST', dto, (tx) =>
      this.svc.scanOut(
        dto.packageIds,
        dto.departmentId,
        dto.receiverName,
        user.id,
        !!dto.manualEntry,
        tx,
      ), { required: true });
  }

  @Post('return')
  @ApiOperation({ summary: 'สแกนรับของส่งคืน → รอ reprocess (FR-3)' })
  @ApiHeader({ name: 'Idempotency-Key', required: true, description: 'บังคับ — กันยิงซ้ำจาก offline sync/retry' })
  scanReturn(
    @Body() dto: ScanReturnDto,
    @CurrentUser() user: { id: string },
    @Headers('idempotency-key') idemKey?: string,
  ) {
    return this.idem.run(idemKey, user.id, 'scan/return', 'POST', dto, (tx) =>
      this.svc.scanReturn(dto.packageIds, dto.departmentId, user.id, !!dto.manualEntry, tx), { required: true });
  }

  @Post('reprocess')
  @ApiOperation({ summary: 'Reprocess: ห่อที่ส่งคืน (RETURNED) → PACKED เพื่อเข้ารอบนึ่งใหม่' })
  @ApiHeader({ name: 'Idempotency-Key', required: true, description: 'บังคับ — กันยิงซ้ำ' })
  reprocess(
    @Body() dto: ReprocessDto,
    @CurrentUser() user: { id: string },
    @Headers('idempotency-key') idemKey?: string,
  ) {
    return this.idem.run(idemKey, user.id, 'scan/reprocess', 'POST', dto, (tx) =>
      this.svc.scanReprocess(dto.packageIds, user.id, !!dto.manualEntry, tx), { required: true });
  }

  @Get('lookup/:id')
  @ApiOperation({ summary: 'ดูข้อมูลห่อจาก QR code (พร้อมสถานะหมดอายุ)' })
  lookup(@Param('id') id: string) {
    return this.svc.lookup(id);
  }
}
