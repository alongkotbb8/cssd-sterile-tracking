import { Module } from '@nestjs/common';
import { MasterDataService } from './master-data.service';
import { MasterDataController } from './master-data.controller';
import { AuditService } from '../../common/audit/audit.service';

@Module({
  providers: [MasterDataService, AuditService],
  controllers: [MasterDataController],
})
export class MasterDataModule {}
