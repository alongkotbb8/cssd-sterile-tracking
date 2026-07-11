import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags, ApiOperation, ApiQuery } from '@nestjs/swagger';
import { ReportsService } from './reports.service';

@ApiTags('reports')
@ApiBearerAuth()
@UseGuards(AuthGuard('jwt'))
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
}
