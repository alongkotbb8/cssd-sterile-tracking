import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../common/prisma/prisma.service';
import { FcmService, PushMessage } from './fcm.service';

@Injectable()
export class NotificationsService {
  constructor(
    private prisma: PrismaService,
    private fcm: FcmService,
  ) {}

  async registerToken(userId: string, token: string, deviceId?: string) {
    return this.prisma.fcmToken.upsert({
      where: { token },
      create: { userId, token, deviceId },
      update: { userId, deviceId },
    });
  }

  /** ลบเฉพาะ token ของเจ้าของเอง (กันผู้ใช้อื่นลบ token คนอื่น — owner-bound) */
  async unregisterToken(userId: string, token: string) {
    await this.prisma.fcmToken.deleteMany({ where: { token, userId } });
  }

  /** Push to every active user's registered devices, pruning tokens Firebase reports as dead. */
  async sendToActiveUsers(message: PushMessage) {
    const tokens = await this.prisma.fcmToken.findMany({
      where: { user: { status: 'ACTIVE' } },
      select: { token: true },
    });
    if (tokens.length === 0) return;

    const { invalidTokens } = await this.fcm.sendToTokens(tokens.map(t => t.token), message);
    if (invalidTokens.length > 0) {
      await this.prisma.fcmToken.deleteMany({ where: { token: { in: invalidTokens } } });
    }
  }
}
