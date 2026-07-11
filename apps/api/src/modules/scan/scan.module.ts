import { Module } from '@nestjs/common';
import { ScanService } from './scan.service';
import { ScanController } from './scan.controller';
import { AuditService } from '../../common/audit/audit.service';

@Module({
  providers: [ScanService, AuditService],
  controllers: [ScanController],
})
export class ScanModule {}
