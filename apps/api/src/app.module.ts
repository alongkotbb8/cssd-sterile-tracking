import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { PrismaModule } from './common/prisma/prisma.module';
import { IdempotencyModule } from './common/idempotency/idempotency.module';
import { AuthModule } from './modules/auth/auth.module';
import { PackagesModule } from './modules/packages/packages.module';
import { ScanModule } from './modules/scan/scan.module';
import { DepartmentsModule } from './modules/departments/departments.module';
import { BatchesModule } from './modules/batches/batches.module';
import { ReportsModule } from './modules/reports/reports.module';
import { MasterDataModule } from './modules/master-data/master-data.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { PrintJobsModule } from './modules/print-jobs/print-jobs.module';
import { HealthController } from './health.controller';

@Module({
  imports: [
    ScheduleModule.forRoot(),
    PrismaModule,
    IdempotencyModule,
    AuthModule,
    PackagesModule,
    ScanModule,
    DepartmentsModule,
    BatchesModule,
    ReportsModule,
    MasterDataModule,
    NotificationsModule,
    PrintJobsModule,
  ],
  controllers: [HealthController],
})
export class AppModule {}
