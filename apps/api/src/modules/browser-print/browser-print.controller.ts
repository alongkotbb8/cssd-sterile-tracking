import {
  Body,
  Controller,
  Get,
  Headers,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiHeader, ApiOperation, ApiTags } from '@nestjs/swagger';
import { UserRole } from '@prisma/client';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { RolesGuard } from '../../common/guards/roles.guard';
import { IdempotencyService } from '../../common/idempotency/idempotency.service';
import { BrowserPrintService } from './browser-print.service';
import { BrowserPrintThrottleGuard } from './browser-print-throttle.guard';
import { CreateBrowserPrintRequestDto } from './dto/create-browser-print-request.dto';
import { ListBrowserPrintRequestsQuery } from './dto/list-browser-print-requests.query';

const IDEM_HEADER = {
  name: 'Idempotency-Key',
  required: true,
  description: 'บังคับ — กันสร้าง/เปลี่ยนสถานะซ้ำจาก retry',
};

/**
 * โหมดพิมพ์ `BROWSER_DIALOG` (MACOS_BROWSER_PRINT_DIRECTIVE.md) — เรียกจาก PWA
 * ด้วย JWT ปกติ ทุก endpoint อยู่หลัง feature flag `CSSD_BROWSER_PRINT_ENABLED`
 * (ปิด = 403 BROWSER_PRINT_DISABLED ทุกเส้นทาง) ห้ามแตะ Print Gateway semantics
 */
@ApiTags('browser-print-requests')
@ApiBearerAuth()
@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('browser-print-requests')
export class BrowserPrintController {
  constructor(
    private svc: BrowserPrintService,
    private idem: IdempotencyService,
  ) {}

  @Post()
  @UseGuards(BrowserPrintThrottleGuard)
  @ApiOperation({
    summary:
      'สร้างคำขอพิมพ์ผ่านเบราว์เซอร์ — คืน request + label authoritative + ประวัติการพิมพ์ก่อนหน้า',
  })
  @ApiHeader(IDEM_HEADER)
  create(
    @Body() dto: CreateBrowserPrintRequestDto,
    @CurrentUser() user: { id: string },
    @Headers('idempotency-key') idemKey?: string,
    @Headers('user-agent') userAgent?: string,
  ) {
    // ตรวจ flag ก่อน idempotency — ปิด feature ต้องได้ 403 เสมอ (ไม่ใช่ 400 key หาย)
    this.svc.assertEnabled();
    return this.idem.run(idemKey, user.id, 'browser-print/create', 'POST', dto, (tx) =>
      this.svc.create(dto, user.id, userAgent, idemKey as string, tx), { required: true });
  }

  @Get()
  @ApiOperation({
    summary: 'ประวัติคำขอพิมพ์ผ่านเบราว์เซอร์ (ของตัวเอง; SUPERVISOR/ADMIN เห็นทั้งหมด) — ล่าสุดก่อน',
  })
  list(
    @CurrentUser() user: { id: string; role: UserRole },
    @Query() query: ListBrowserPrintRequestsQuery,
  ) {
    return this.svc.list(user.id, user.role, query);
  }

  @Get(':id')
  @ApiOperation({ summary: 'ดูคำขอพิมพ์ผ่านเบราว์เซอร์ (เจ้าของ หรือ SUPERVISOR/ADMIN)' })
  findOne(@Param('id') id: string, @CurrentUser() user: { id: string; role: UserRole }) {
    return this.svc.findOne(id, user.id, user.role);
  }

  @Post(':id/dialog-opened')
  @UseGuards(BrowserPrintThrottleGuard)
  @ApiOperation({ summary: 'บันทึกว่ากำลังเปิด print dialog (CREATED → DIALOG_OPENED) — เจ้าของคำขอเท่านั้น' })
  @ApiHeader(IDEM_HEADER)
  dialogOpened(
    @Param('id') id: string,
    @CurrentUser() user: { id: string },
    @Headers('idempotency-key') idemKey?: string,
  ) {
    this.svc.assertEnabled();
    return this.idem.run(idemKey, user.id, 'browser-print/dialog-opened', 'POST', { id }, (tx) =>
      this.svc.dialogOpened(id, user.id, tx), { required: true });
  }

  @Post(':id/confirm')
  @UseGuards(BrowserPrintThrottleGuard)
  @ApiOperation({
    summary:
      'ผู้ใช้ยืนยันเองว่ากระดาษออก (DIALOG_OPENED → USER_CONFIRMED) — ไม่ใช่ hardware-confirmed',
  })
  @ApiHeader(IDEM_HEADER)
  confirm(
    @Param('id') id: string,
    @CurrentUser() user: { id: string },
    @Headers('idempotency-key') idemKey?: string,
  ) {
    this.svc.assertEnabled();
    return this.idem.run(idemKey, user.id, 'browser-print/confirm', 'POST', { id }, (tx) =>
      this.svc.confirm(id, user.id, tx), { required: true });
  }

  @Post(':id/cancel')
  @UseGuards(BrowserPrintThrottleGuard)
  @ApiOperation({ summary: 'แจ้งว่าไม่ได้พิมพ์/ยกเลิก (CREATED|DIALOG_OPENED → CANCELLED)' })
  @ApiHeader(IDEM_HEADER)
  cancel(
    @Param('id') id: string,
    @CurrentUser() user: { id: string },
    @Headers('idempotency-key') idemKey?: string,
  ) {
    this.svc.assertEnabled();
    return this.idem.run(idemKey, user.id, 'browser-print/cancel', 'POST', { id }, (tx) =>
      this.svc.cancel(id, user.id, tx), { required: true });
  }
}
