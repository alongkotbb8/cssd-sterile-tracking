import {
  Controller,
  Post,
  Get,
  Body,
  Param,
  Query,
  UseGuards,
  ParseEnumPipe,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags, ApiOperation, ApiQuery } from '@nestjs/swagger';
import { PackageStatus } from '@prisma/client';
import { PackagesService } from './packages.service';
import { CreatePackageDto } from './dto/create-package.dto';
import { ReservePoolDto } from './dto/reserve-pool.dto';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

@ApiTags('packages')
@ApiBearerAuth()
@UseGuards(AuthGuard('jwt'))
@Controller('packages')
export class PackagesController {
  constructor(private svc: PackagesService) {}

  @Post()
  @ApiOperation({ summary: 'สร้างห่ออุปกรณ์ใหม่ + ออกเลขรัน' })
  create(@Body() dto: CreatePackageDto, @CurrentUser() user: { id: string }) {
    return this.svc.create(dto, user.id);
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
}
