import { Module } from '@nestjs/common';
import { PackagesService } from './packages.service';
import { PackagesController } from './packages.controller';
import { RunningNumberService } from './running-number.service';
import { AuditService } from '../../common/audit/audit.service';

@Module({
  providers: [PackagesService, RunningNumberService, AuditService],
  controllers: [PackagesController],
  exports: [PackagesService],
})
export class PackagesModule {}
