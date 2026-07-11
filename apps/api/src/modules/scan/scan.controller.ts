import { Controller, Post, Get, Body, Param, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags, ApiOperation } from '@nestjs/swagger';
import {
  IsString,
  IsArray,
  IsOptional,
  ArrayNotEmpty,
  ArrayMaxSize,
  MaxLength,
} from 'class-validator';
import { ScanService } from './scan.service';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

class ScanInDto {
  @IsArray() @ArrayNotEmpty() @ArrayMaxSize(200) @IsString({ each: true }) packageIds: string[];
  @IsString() batchId: string;
}

class ScanOutDto {
  @IsArray() @ArrayNotEmpty() @ArrayMaxSize(200) @IsString({ each: true }) packageIds: string[];
  @IsString() departmentId: string;
  @IsOptional() @IsString() @MaxLength(100) receiverName?: string;
}

class ScanReturnDto {
  @IsArray() @ArrayNotEmpty() @ArrayMaxSize(200) @IsString({ each: true }) packageIds: string[];
  @IsString() departmentId: string;
}

@ApiTags('scan')
@ApiBearerAuth()
@UseGuards(AuthGuard('jwt'))
@Controller('scan')
export class ScanController {
  constructor(private svc: ScanService) {}

  @Post('in')
  @ApiOperation({ summary: 'สแกนเข้าคลังปลอดเชื้อ (batch scan)' })
  scanIn(@Body() dto: ScanInDto, @CurrentUser() user: { id: string }) {
    return this.svc.scanIn(dto.packageIds, dto.batchId, user.id);
  }

  @Post('out')
  @ApiOperation({ summary: 'สแกนเบิกออก → แผนกปลายทาง (FR-2, FR-4)' })
  scanOut(@Body() dto: ScanOutDto, @CurrentUser() user: { id: string }) {
    return this.svc.scanOut(dto.packageIds, dto.departmentId, dto.receiverName, user.id);
  }

  @Post('return')
  @ApiOperation({ summary: 'สแกนรับของส่งคืน → รอ reprocess (FR-3)' })
  scanReturn(@Body() dto: ScanReturnDto, @CurrentUser() user: { id: string }) {
    return this.svc.scanReturn(dto.packageIds, dto.departmentId, user.id);
  }

  @Get('lookup/:id')
  @ApiOperation({ summary: 'ดูข้อมูลห่อจาก QR code (พร้อมสถานะหมดอายุ)' })
  lookup(@Param('id') id: string) {
    return this.svc.lookup(id);
  }
}
