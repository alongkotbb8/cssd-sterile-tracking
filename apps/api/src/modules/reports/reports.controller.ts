import { Body, Controller, Get, Post, Query, Res, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags, ApiOperation, ApiQuery } from '@nestjs/swagger';
import { Response } from 'express';
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

  @Get('weekly.xlsx')
  @ApiOperation({ summary: 'ดาวน์โหลดรายงานช่วงวันที่เป็นไฟล์ Excel (.xlsx)' })
  @ApiQuery({ name: 'from', example: '2026-06-01' })
  @ApiQuery({ name: 'to', example: '2026-06-30' })
  @ApiQuery({ name: 'departmentId', required: false })
  async weeklyXlsx(
    @Query('from') from: string,
    @Query('to') to: string,
    @Res() res: Response,
    @Query('departmentId') dept?: string,
  ) {
    const buffer = await this.svc.weeklyXlsx(from, to, dept);
    res
      .set({
        'Content-Type':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'Content-Disposition': `attachment; filename="cssd-report-${from}-${to}.xlsx"`,
      })
      .send(buffer);
  }

  @Get('return-rate')
  @ApiOperation({ summary: 'อัตราการส่งคืนต่อแผนก (OUT เทียบ RETURN)' })
  @ApiQuery({ name: 'from', example: '2026-06-01' })
  @ApiQuery({ name: 'to', example: '2026-06-30' })
  returnRate(@Query('from') from: string, @Query('to') to: string) {
    return this.svc.returnRateByDepartment(from, to);
  }

  @Get('recalls')
  @ApiOperation({ summary: 'รายงาน recall: รอบที่ผลไม่ผ่าน + ห่อ + ตำแหน่งล่าสุด' })
  recalls() {
    return this.svc.recalls();
  }

  @Get('print-history')
  @ApiOperation({ summary: 'ประวัติการพิมพ์ label (จาก AuditLog PRINT_LABEL)' })
  @ApiQuery({ name: 'from', example: '2026-06-01' })
  @ApiQuery({ name: 'to', example: '2026-06-30' })
  printHistory(@Query('from') from: string, @Query('to') to: string) {
    return this.svc.printHistory(from, to);
  }

  @Get('blocked')
  @ApiOperation({ summary: 'เหตุการณ์ถูกบล็อก (สแกนของหมดอายุ ฯลฯ)' })
  @ApiQuery({ name: 'from', example: '2026-06-01' })
  @ApiQuery({ name: 'to', example: '2026-06-30' })
  blocked(@Query('from') from: string, @Query('to') to: string) {
    return this.svc.blockedEvents(from, to);
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
