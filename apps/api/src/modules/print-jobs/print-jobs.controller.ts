import {
  Body,
  Controller,
  Get,
  Headers,
  Param,
  ParseEnumPipe,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiHeader, ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
import { PrintJobStatus, UserRole } from '@prisma/client';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { Roles } from '../../common/decorators/roles.decorator';
import { RolesGuard } from '../../common/guards/roles.guard';
import { IdempotencyService } from '../../common/idempotency/idempotency.service';
import { CreatePrintJobDto } from './dto/create-print-job.dto';
import { RegisterGatewayDto } from './dto/register-gateway.dto';
import { ResolveAckUnknownDto } from './dto/resolve-ack-unknown.dto';
import { UpdateGatewayCapabilityDto } from './dto/update-gateway-capability.dto';
import { PrintJobsService } from './print-jobs.service';

/** สร้าง/ดู/ยกเลิก print job — เรียกจาก PWA ด้วย JWT ปกติ ห้ามตั้งสถานะ PRINTED เอง */
@ApiTags('print-jobs')
@ApiBearerAuth()
@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('print-jobs')
export class PrintJobsController {
  constructor(
    private svc: PrintJobsService,
    private idem: IdempotencyService,
  ) {}

  // ── Static routes ก่อนเสมอ — กัน ':id' จับ path ผิด (เช่น 'gateways') ──

  @Get('gateways/list')
  @Roles(UserRole.SUPERVISOR, UserRole.ADMIN)
  @ApiOperation({ summary: 'รายการ Print Gateway ที่ลงทะเบียนไว้' })
  listGateways() {
    return this.svc.listGateways();
  }

  @Post('gateways')
  @Roles(UserRole.ADMIN)
  @ApiOperation({ summary: 'ลงทะเบียน Print Gateway ใหม่ — คืน API key เต็มครั้งเดียว (เก็บให้ดี)' })
  registerGateway(@Body() dto: RegisterGatewayDto, @CurrentUser() user: { id: string }) {
    return this.svc.registerGateway(dto.name, user.id, {
      environment: dto.environment,
      transportMode: dto.transportMode,
      canConfirmRealPrint: dto.canConfirmRealPrint,
    });
  }

  @Post('gateways/:id/capability')
  @Roles(UserRole.ADMIN)
  @ApiOperation({
    summary: 'เปลี่ยน capability ของ Gateway (environment/transport/canConfirmRealPrint) — ADMIN + AuditLog',
  })
  updateGatewayCapability(
    @Param('id') id: string,
    @Body() dto: UpdateGatewayCapabilityDto,
    @CurrentUser() user: { id: string },
  ) {
    return this.svc.updateGatewayCapability(id, user.id, dto);
  }

  @Post('gateways/:id/rotate-key')
  @Roles(UserRole.ADMIN)
  @ApiOperation({
    summary: 'หมุน API key ของ Gateway — คืน key ใหม่ครั้งเดียว, key เดิมใช้ไม่ได้ทันที (ADMIN + AuditLog)',
  })
  rotateGatewayKey(@Param('id') id: string, @CurrentUser() user: { id: string }) {
    return this.svc.rotateGatewayKey(id, user.id);
  }

  @Post('gateways/:id/revoke')
  @Roles(UserRole.ADMIN)
  @ApiOperation({ summary: 'เพิกถอน Print Gateway (เช่น เครื่องหาย/เปลี่ยนเครื่อง)' })
  revokeGateway(@Param('id') id: string, @CurrentUser() user: { id: string }) {
    return this.svc.revokeGateway(id, user.id);
  }

  @Post()
  @ApiOperation({ summary: 'สร้าง print job ให้ label ของห่อ — gateway จะมา claim/พิมพ์ทีหลัง' })
  @ApiHeader({ name: 'Idempotency-Key', required: true, description: 'บังคับ — กันสร้างงานพิมพ์ซ้ำจาก retry' })
  create(
    @Body() dto: CreatePrintJobDto,
    @CurrentUser() user: { id: string },
    @Headers('idempotency-key') idemKey?: string,
  ) {
    return this.idem.run(idemKey, user.id, 'print-jobs/create', 'POST', dto, (tx) =>
      this.svc.createJob(dto.packageId, user.id, {
        requestedPrinterId: dto.requestedPrinterId,
        reprintReason: dto.reprintReason,
      }, tx), { required: true });
  }

  @Get()
  @ApiOperation({ summary: 'รายการ print job ของตัวเอง (SUPERVISOR/ADMIN เห็นทั้งหมด) — ใช้ poll สถานะ' })
  @ApiQuery({ name: 'status', enum: PrintJobStatus, required: false })
  @ApiQuery({ name: 'packageId', required: false })
  list(
    @CurrentUser() user: { id: string; role: UserRole },
    @Query('status', new ParseEnumPipe(PrintJobStatus, { optional: true })) status?: PrintJobStatus,
    @Query('packageId') packageId?: string,
  ) {
    return this.svc.listJobs(user.id, user.role, { status, packageId });
  }

  @Get(':id')
  @ApiOperation({ summary: 'ดูสถานะ print job ล่าสุด (poll หน้านี้แทนการเชื่อว่าเปิด print dialog = พิมพ์แล้ว)' })
  findOne(@Param('id') id: string, @CurrentUser() user: { id: string; role: UserRole }) {
    return this.svc.findOne(id, user.id, user.role);
  }

  @Post(':id/cancel')
  @ApiOperation({ summary: 'ยกเลิกงานพิมพ์ (เจ้าของงาน หรือ SUPERVISOR/ADMIN) — เฉพาะยังไม่ถูก claim (QUEUED)' })
  cancel(@Param('id') id: string, @CurrentUser() user: { id: string; role: UserRole }) {
    return this.svc.cancel(id, user.id, user.role);
  }

  @Post(':id/resolve')
  @Roles(UserRole.SUPERVISOR, UserRole.ADMIN)
  @ApiOperation({ summary: 'ตัดสินใจงานที่ค้าง ACK_UNKNOWN (ยืนยันว่าพิมพ์จริง หรือเปิดงานพิมพ์ใหม่)' })
  resolveAckUnknown(
    @Param('id') id: string,
    @Body() dto: ResolveAckUnknownDto,
    @CurrentUser() user: { id: string },
  ) {
    return this.svc.resolveAckUnknown(id, user.id, dto.decision, dto.note);
  }
}
