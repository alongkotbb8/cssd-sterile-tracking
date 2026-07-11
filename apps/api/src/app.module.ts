import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { PrismaModule } from './common/prisma/prisma.module';
import { AuthModule } from './modules/auth/auth.module';
import { PackagesModule } from './modules/packages/packages.module';
import { ScanModule } from './modules/scan/scan.module';
import { DepartmentsModule } from './modules/departments/departments.module';
import { BatchesModule } from './modules/batches/batches.module';
import { ReportsModule } from './modules/reports/reports.module';
import { MasterDataModule } from './modules/master-data/master-data.module';
import { HealthController } from './health.controller';

@Module({
  imports: [
    ScheduleModule.forRoot(),
    PrismaModule,
    AuthModule,
    PackagesModule,
    ScanModule,
    DepartmentsModule,
    BatchesModule,
    ReportsModule,
    MasterDataModule,
  ],
  controllers: [HealthController],
})
export class AppModule {}
