import { Module } from '@nestjs/common';
import { BatchesService } from './batches.service';
import { BatchesController } from './batches.controller';
import { AuditService } from '../../common/audit/audit.service';

@Module({
  providers: [BatchesService, AuditService],
  controllers: [BatchesController],
})
export class BatchesModule {}
