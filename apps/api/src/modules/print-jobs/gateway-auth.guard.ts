import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../../common/prisma/prisma.service';

export interface AuthenticatedGateway {
  id: string;
  name: string;
}

/**
 * Auth เฉพาะ Print Gateway — แยกจาก JWT user โดยสิ้นเชิงตามที่
 * AI_DEVELOPMENT_GUARDRAILS.md ข้อ 4.3 กำหนด ("Authentication ด้วย credential
 * แยกต่อ Gateway") — ไม่ใช้ AuthGuard('jwt') เด็ดขาด
 *
 * รูปแบบ header: `X-Gateway-Key: {keyId}.{secret}` — keyId ใช้ lookup แถวตรงๆ
 * (กันต้อง bcrypt.compare วนทุกเครื่องพิมพ์ในระบบทุก request), secret เทียบ
 * ด้วย bcrypt กับ hash ที่เก็บไว้เท่านั้น (ไม่เก็บ plaintext ที่ไหนเลย)
 */
@Injectable()
export class GatewayAuthGuard implements CanActivate {
  constructor(private prisma: PrismaService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest();
    const header = req.headers['x-gateway-key'];
    const raw = Array.isArray(header) ? header[0] : header;
    if (!raw || typeof raw !== 'string' || !raw.includes('.')) {
      throw new UnauthorizedException('ต้องส่ง X-Gateway-Key');
    }

    const [keyId, secret] = raw.split('.', 2);
    const printer = await this.prisma.printerDevice.findUnique({ where: { keyId } });
    if (!printer || !printer.isActive || printer.revokedAt) {
      throw new UnauthorizedException('Gateway ไม่ถูกต้องหรือถูกเพิกถอนแล้ว');
    }

    const ok = await bcrypt.compare(secret, printer.apiKeyHash);
    if (!ok) throw new UnauthorizedException('Gateway key ไม่ถูกต้อง');

    const gateway: AuthenticatedGateway = { id: printer.id, name: printer.name };
    req.gateway = gateway;
    return true;
  }
}
