import { Module } from '@nestjs/common';
import { NotificationsController } from './notifications.controller';
import { NotificationsService } from './notifications.service';
import { FcmService } from './fcm.service';
import { ExpiryReminderScheduler } from './expiry-reminder.scheduler';
import { DailySummaryReminderScheduler } from './daily-summary-reminder.scheduler';

@Module({
  controllers: [NotificationsController],
  providers: [
    NotificationsService,
    FcmService,
    ExpiryReminderScheduler,
    DailySummaryReminderScheduler,
  ],
  exports: [NotificationsService, FcmService],
})
export class NotificationsModule {}
