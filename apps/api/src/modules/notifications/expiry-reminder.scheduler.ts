import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { PackageStatus } from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';
import { NotificationsService } from './notifications.service';

const REMINDER_DAYS_AHEAD = 2;

/** FR: warn CSSD staff about sterile-store packages about to expire so they can use/reprocess FEFO-first. */
@Injectable()
export class ExpiryReminderScheduler {
  private readonly logger = new Logger(ExpiryReminderScheduler.name);

  constructor(
    private prisma: PrismaService,
    private notifications: NotificationsService,
  ) {}

  @Cron('0 8 * * *', { timeZone: 'Asia/Bangkok' })
  async handleCron() {
    const now = new Date();
    const horizon = new Date(now);
    horizon.setDate(horizon.getDate() + REMINDER_DAYS_AHEAD);

    const nearExpiry = await this.prisma.package.findMany({
      where: {
        status: PackageStatus.STERILE,
        expiryDate: { gte: now, lte: horizon },
      },
      select: { id: true, expiryDate: true },
      orderBy: { expiryDate: 'asc' },
    });

    if (nearExpiry.length === 0) return;

    this.logger.log(`${nearExpiry.length} package(s) expiring within ${REMINDER_DAYS_AHEAD} day(s)`);

    await this.notifications.sendToActiveUsers({
      title: 'ใกล้หมดอายุการปลอดเชื้อ',
      body: `มี ${nearExpiry.length} ห่อในคลังใกล้หมดอายุภายใน ${REMINDER_DAYS_AHEAD} วัน — โปรดเบิกใช้ตามลำดับ FEFO`,
      data: { type: 'EXPIRY_REMINDER', count: String(nearExpiry.length) },
    });
  }
}
