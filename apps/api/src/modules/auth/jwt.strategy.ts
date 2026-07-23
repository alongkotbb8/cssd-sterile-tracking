import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { UserStatus } from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';
import { requireEnv } from '../../common/config/env';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(private prisma: PrismaService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      // No hardcoded fallback secret — requireEnv throws if JWT_SECRET is missing.
      secretOrKey: requireEnv('JWT_SECRET'),
    });
  }

  async validate(payload: { sub: string; role: string; name: string; ver?: number }) {
    // Re-check the user on every request so deactivated users / changed roles
    // lose access immediately instead of only when the token expires.
    const user = await this.prisma.user.findUnique({ where: { id: payload.sub } });
    if (!user || user.status !== UserStatus.ACTIVE) {
      throw new UnauthorizedException();
    }
    // Session revocation: token ฝัง ver ตอน sign — ถ้าไม่ตรง tokenVersion ปัจจุบัน
    // แปลว่า session ถูกเพิกถอน (logout-all / ADMIN revoke) → ปฏิเสธทันที
    // (token เก่าก่อนมีฟีเจอร์นี้ไม่มี ver → ถือว่าถูกเพิกถอน ต้อง login ใหม่)
    if ((payload.ver ?? -1) !== user.tokenVersion) {
      throw new UnauthorizedException('เซสชันถูกเพิกถอน กรุณาเข้าสู่ระบบใหม่');
    }
    return { id: user.id, role: user.role, name: user.name };
  }
}
