import { Body, Controller, Param, Post, UseGuards } from '@nestjs/common';
import { ApiHeader, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentGateway } from './current-gateway.decorator';
import { FailPrintJobDto } from './dto/fail-print-job.dto';
import { AuthenticatedGateway, GatewayAuthGuard } from './gateway-auth.guard';
import { PrintJobsService } from './print-jobs.service';

/**
 * Endpoint เฉพาะ Print Gateway — auth ด้วย X-Gateway-Key เท่านั้น (ไม่ใช่ JWT
 * ผู้ใช้) ตาม AI_DEVELOPMENT_GUARDRAILS.md ข้อ 4.3 "Gateway ต้องมี
 * authentication ด้วย credential แยกต่อ Gateway" — ไฟล์นี้คือทางเดียวที่
 * printedAt/reprintCount ของ Package จะถูกอัปเดตได้ (PWA ทำเองไม่ได้)
 */
@ApiTags('print-gateway')
@ApiHeader({ name: 'X-Gateway-Key', required: true, description: 'รูปแบบ {keyId}.{secret}' })
@UseGuards(GatewayAuthGuard)
@Controller('print-gateway')
export class PrintGatewayController {
  constructor(private svc: PrintJobsService) {}

  @Post('heartbeat')
  @ApiOperation({ summary: 'Gateway รายงานตัวว่ายังออนไลน์อยู่' })
  heartbeat(@CurrentGateway() gateway: AuthenticatedGateway) {
    return this.svc.heartbeat(gateway.id);
  }

  @Post('claim')
  @ApiOperation({ summary: 'จองงานพิมพ์ถัดไปแบบ atomic (SELECT FOR UPDATE SKIP LOCKED) — null = ไม่มีงานรอ' })
  claim(@CurrentGateway() gateway: AuthenticatedGateway) {
    return this.svc.claim(gateway.id);
  }

  @Post('jobs/:id/printing')
  @ApiOperation({ summary: 'แจ้งว่ากำลังจะเรียก transport.send() (CLAIMED → PRINTING)' })
  printing(@Param('id') id: string, @CurrentGateway() gateway: AuthenticatedGateway) {
    return this.svc.markPrinting(id, gateway.id);
  }

  @Post('jobs/:id/sent')
  @ApiOperation({
    summary:
      'แจ้งว่า transport.send() คืนผลสำเร็จแล้ว (PRINTING → SENT) — เรียกก่อน ack เสมอ ' +
      'ถ้า network หลุดหลังจุดนี้ job จะกลายเป็น ACK_UNKNOWN ไม่ auto-retry',
  })
  sent(@Param('id') id: string, @CurrentGateway() gateway: AuthenticatedGateway) {
    return this.svc.markSent(id, gateway.id);
  }

  @Post('jobs/:id/maybe-sent')
  @ApiOperation({
    summary:
      'MAYBE_SENT (FIX-04): write() error ที่อาจมี byte ออกไปแล้วบางส่วน → ' +
      'ย้ายเข้า ACK_UNKNOWN ทันที ห้าม auto-retry (ต้องให้ SUPERVISOR/ADMIN ตัดสิน)',
  })
  maybeSent(
    @Param('id') id: string,
    @Body() dto: FailPrintJobDto,
    @CurrentGateway() gateway: AuthenticatedGateway,
  ) {
    return this.svc.reportIndeterminate(id, gateway.id, dto.errorCode, dto.message);
  }

  @Post('jobs/:id/ack')
  @ApiOperation({
    summary:
      'ยืนยันพิมพ์ (SENT → PRINTED/SIMULATED) — backend ตัดสิน PRINTED vs SIMULATED ' +
      'จาก capability ของ gateway เอง (canConfirmRealPrint) ไม่รับ flag จาก request (FIX-05)',
  })
  ack(@Param('id') id: string, @CurrentGateway() gateway: AuthenticatedGateway) {
    return this.svc.ack(id, gateway.id);
  }

  @Post('jobs/:id/fail')
  @ApiOperation({ summary: 'รายงานพิมพ์ไม่สำเร็จ — เข้าคิว retry อัตโนมัติจนครบจำนวนครั้งแล้วเข้า DEAD_LETTER' })
  fail(
    @Param('id') id: string,
    @Body() dto: FailPrintJobDto,
    @CurrentGateway() gateway: AuthenticatedGateway,
  ) {
    return this.svc.fail(id, gateway.id, dto.errorCode, dto.message);
  }
}
