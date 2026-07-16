import { Module } from '@nestjs/common';
import { AuditService } from '../../common/audit/audit.service';
import { DepartmentsService } from './departments.service';
import { DepartmentsController } from './departments.controller';

@Module({
  providers: [DepartmentsService, AuditService],
  controllers: [DepartmentsController],
  exports: [DepartmentsService],
})
export class DepartmentsModule {}
