import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { PrismaService } from '../../common/prisma/prisma.service';
import { NotificationsService } from './notifications.service';

/**
 * ASSUMPTION (see PROGRESS.md): "ลืมสรุปรายวัน" reminder — there is no persisted
 * "daily summary submitted" flag in the domain model yet, so this fires every
 * working day at end-of-shift as a plain reminder to review today's activity,
 * rather than detecting whether a summary was actually produced. Revisit once
 * a real daily-summary/report entity exists.
 */
@Injectable()
export class DailySummaryReminderScheduler {
  private readonly logger = new Logger(DailySummaryReminderScheduler.name);

  constructor(
    private prisma: PrismaService,
    private notifications: NotificationsService,
  ) {}

  @Cron('0 20 * * *', { timeZone: 'Asia/Bangkok' })
  async handleCron() {
    const startOfDay = new Date();
    startOfDay.setHours(0, 0, 0, 0);

    const movementsToday = await this.prisma.movement.count({
      where: { createdAt: { gte: startOfDay } },
    });

    if (movementsToday === 0) return;

    this.logger.log(`Sending daily-summary reminder (${movementsToday} movement(s) today)`);

    await this.notifications.sendToActiveUsers({
      title: 'อย่าลืมสรุปข้อมูลประจำวัน',
      body: `วันนี้มีการสแกนเข้า-ออก ${movementsToday} รายการ — โปรดตรวจสอบและสรุปก่อนเลิกงาน`,
      data: { type: 'DAILY_SUMMARY_REMINDER', movements: String(movementsToday) },
    });
  }
}
