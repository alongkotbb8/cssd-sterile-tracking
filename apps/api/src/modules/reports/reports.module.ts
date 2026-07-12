import { Module } from '@nestjs/common';
import { AuditService } from '../../common/audit/audit.service';
import { ReportsService } from './reports.service';
import { ReportsController } from './reports.controller';

@Module({
  providers: [ReportsService, AuditService],
  controllers: [ReportsController],
})
export class ReportsModule {}
