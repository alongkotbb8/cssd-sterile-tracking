import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { UserStatus } from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';
import * as bcrypt from 'bcrypt';

const LOGIN_FAILED_MESSAGE = 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง';

// Account lockout: fail ติดกันครบ N ครั้ง → ล็อกชั่วคราว (กัน brute-force ต่อบัญชี
// ที่ per-IP throttle กันไม่ได้เมื่อผู้โจมตีสลับ IP)
const MAX_FAILED_ATTEMPTS = 5;
const LOCKOUT_MS = 15 * 60_000; // 15 นาที

@Injectable()
export class AuthService {
  // Compared against when the user doesn't exist, so response time doesn't
  // reveal whether an employeeCode is registered (timing attack).
  private readonly dummyHash = bcrypt.hashSync('timing-equalizer-not-a-password', 10);

  constructor(
    private prisma: PrismaService,
    private jwt: JwtService,
  ) {}

  async login(employeeCode: string, password: string) {
    const user = await this.prisma.user.findUnique({ where: { employeeCode } });

    if (user?.lockedUntil && user.lockedUntil > new Date()) {
      const minsLeft = Math.ceil((user.lockedUntil.getTime() - Date.now()) / 60_000);
      throw new UnauthorizedException(
        `บัญชีถูกล็อกชั่วคราวจากการใส่รหัสผิดหลายครั้ง — ลองใหม่ใน ${minsLeft} นาที`,
      );
    }

    // Always run bcrypt.compare, even for unknown users (same message + timing).
    const ok = await bcrypt.compare(password, user?.passwordHash ?? this.dummyHash);
    if (!user || !ok || user.status !== UserStatus.ACTIVE) {
      if (user) {
        // นับ fail และล็อกเมื่อครบเพดาน (best-effort — ห้ามเปลี่ยน error ที่ผู้ใช้เห็น)
        const failed = user.failedLoginCount + 1;
        await this.prisma.user.update({
          where: { id: user.id },
          data: {
            failedLoginCount: failed,
            lockedUntil:
              failed >= MAX_FAILED_ATTEMPTS ? new Date(Date.now() + LOCKOUT_MS) : null,
          },
        });
      }
      throw new UnauthorizedException(LOGIN_FAILED_MESSAGE);
    }

    // สำเร็จ → reset ตัวนับ
    if (user.failedLoginCount > 0 || user.lockedUntil) {
      await this.prisma.user.update({
        where: { id: user.id },
        data: { failedLoginCount: 0, lockedUntil: null },
      });
    }

    const payload = { sub: user.id, role: user.role, name: user.name };
    return {
      accessToken: this.jwt.sign(payload),
      user: { id: user.id, name: user.name, role: user.role, employeeCode: user.employeeCode },
    };
  }
}
