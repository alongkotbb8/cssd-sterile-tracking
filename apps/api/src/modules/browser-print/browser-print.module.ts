import { Module } from '@nestjs/common';
import { AuditService } from '../../common/audit/audit.service';
import { BrowserPrintController } from './browser-print.controller';
import { BrowserPrintService } from './browser-print.service';
import { BrowserPrintThrottleGuard } from './browser-print-throttle.guard';

@Module({
  providers: [BrowserPrintService, AuditService, BrowserPrintThrottleGuard],
  controllers: [BrowserPrintController],
})
export class BrowserPrintModule {}
