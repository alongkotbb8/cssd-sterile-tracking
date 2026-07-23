import { Module } from '@nestjs/common';
import { AuditService } from '../../common/audit/audit.service';
import { GatewayAuthGuard } from './gateway-auth.guard';
import { PrintGatewayController } from './print-gateway.controller';
import { PrintJobsController } from './print-jobs.controller';
import { PrintJobsService } from './print-jobs.service';

@Module({
  providers: [PrintJobsService, AuditService, GatewayAuthGuard],
  controllers: [PrintJobsController, PrintGatewayController],
})
export class PrintJobsModule {}
