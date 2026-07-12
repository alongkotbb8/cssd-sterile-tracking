import { Body, Controller, Get, Post, Query, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags, ApiOperation, ApiQuery } from '@nestjs/swagger';
import { UserRole } from '@prisma/client';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { Roles } from '../../common/decorators/roles.decorator';
import { RolesGuard } from '../../common/guards/roles.guard';
import { CleanupDto } from './dto/cleanup.dto';
import { ReportsService } from './reports.service';

@ApiTags('reports')
@ApiBearerAuth()
@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('reports')
export class ReportsController {
  constructor(private svc: ReportsService) {}

  @Get('dashboard')
  @ApiOperation({ summary: 'ข้อมูล dashboard (FR-6)' })
  dashboard() { return this.svc.dashboard(); }

  @Get('weekly')
  @ApiOperation({ summary: 'รายงานรายสัปดาห์ (FR-7)' })
  @ApiQuery({ name: 'from', example: '2026-06-01' })
  @ApiQuery({ name: 'to', example: '2026-06-30' })
  @ApiQuery({ name: 'departmentId', required: false })
  weekly(
    @Query('from') from: string,
    @Query('to') to: string,
    @Query('departmentId') dept?: string,
  ) {
    return this.svc.weekly(from, to, dept);
  }

  @Get('unreturned')
  @ApiOperation({ summary: 'ของที่เบิกออกแล้วยังไม่ส่งคืน' })
  @ApiQuery({ name: 'departmentId', required: false })
  unreturned(@Query('departmentId') dept?: string) {
    return this.svc.unreturned(dept);
  }

  @Post('cleanup')
  @Roles(UserRole.ADMIN)
  @ApiOperation({
    summary:
      'ล้างประวัติเก่าหลังพิมพ์รายงานเก็บเข้าแฟ้ม (ไม่แตะสต๊อกคลังปัจจุบัน) — ADMIN เท่านั้น',
  })
  cleanup(@Body() dto: CleanupDto, @CurrentUser() user: { id: string }) {
    return this.svc.cleanup(dto.before, user.id);
  }
}
