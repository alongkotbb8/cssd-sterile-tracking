import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { UserStatus } from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';
import * as bcrypt from 'bcrypt';

const LOGIN_FAILED_MESSAGE = 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง';

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

    // Always run bcrypt.compare, even for unknown users (same message + timing).
    const ok = await bcrypt.compare(password, user?.passwordHash ?? this.dummyHash);
    if (!user || !ok || user.status !== UserStatus.ACTIVE) {
      throw new UnauthorizedException(LOGIN_FAILED_MESSAGE);
    }

    const payload = { sub: user.id, role: user.role, name: user.name };
    return {
      accessToken: this.jwt.sign(payload),
      user: { id: user.id, name: user.name, role: user.role, employeeCode: user.employeeCode },
    };
  }
}
