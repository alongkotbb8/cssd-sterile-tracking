import 'dotenv/config';
import { NestFactory } from '@nestjs/core';
import { Logger, ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import * as express from 'express';
import helmet from 'helmet';
import { AppModule } from './app.module';
import { requireEnv } from './common/config/env';

async function bootstrap() {
  // Fail fast if security-critical config is missing (no insecure fallback).
  requireEnv('JWT_SECRET');

  const isProd = process.env.NODE_ENV === 'production';
  const app = await NestFactory.create(AppModule, { bodyParser: false });

  // Security headers (ตาม AI_DEVELOPMENT_GUARDRAILS.md ข้อ 9) + จำกัดขนาด
  // request body (กัน large-payload DoS) — API นี้เป็น JSON ล้วน ไม่เสิร์ฟ HTML
  // เอง แต่ตั้ง CSP/frame-ancestors ไว้เผื่อ Swagger UI และเพื่อความครบถ้วน
  app.use(
    helmet({
      contentSecurityPolicy: {
        directives: {
          defaultSrc: ["'self'"],
          frameAncestors: ["'none'"], // กัน clickjacking
          objectSrc: ["'none'"],
        },
      },
      frameguard: { action: 'deny' },
      hsts: { maxAge: 31_536_000, includeSubDomains: true }, // 1 ปี — มีผลจริงเฉพาะบน HTTPS
      referrerPolicy: { policy: 'no-referrer' },
    }),
  );
  // Permissions-Policy ไม่ได้อยู่ใน helmet default — เปิด camera เฉพาะ origin ตัวเอง
  app.use((_req: express.Request, res: express.Response, next: express.NextFunction) => {
    res.setHeader('Permissions-Policy', 'camera=(self), microphone=(), geolocation=()');
    next();
  });
  app.use(express.json({ limit: '1mb' }));
  app.use(express.urlencoded({ extended: true, limit: '1mb' }));

  app.setGlobalPrefix('api/v1');
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  // CORS: mobile apps ไม่ใช้ CORS; browser origins คุมด้วย allowlist จาก env
  // production ที่ไม่ตั้ง CORS_ORIGINS = ปฏิเสธ browser origin ทั้งหมด (ปลอดภัยไว้ก่อน)
  const corsOrigins = process.env.CORS_ORIGINS?.split(',').map(s => s.trim()).filter(Boolean);
  if (isProd && !corsOrigins?.length) {
    new Logger('Bootstrap').warn(
      'CORS_ORIGINS not set in production — all browser origins will be rejected. ' +
        'Set CORS_ORIGINS to your web app URL(s) to allow the PWA.',
    );
  }
  app.enableCors({ origin: corsOrigins?.length ? corsOrigins : !isProd });

  // Swagger: dev เปิดเสมอ, production ต้อง opt-in ด้วย ENABLE_SWAGGER=true
  const enableSwagger = !isProd || process.env.ENABLE_SWAGGER === 'true';
  if (enableSwagger) {
    const config = new DocumentBuilder()
      .setTitle('CSSD Sterile Tracking API')
      .setDescription('ระบบตามรอยอุปกรณ์หัตถการปลอดเชื้อ')
      .setVersion('1.0')
      .addBearerAuth()
      .build();
    SwaggerModule.setup('api/docs', app, SwaggerModule.createDocument(app, config));
  }

  const port = process.env.PORT ?? 3000;
  await app.listen(port, '0.0.0.0');
  console.log(`🚀 API running on http://localhost:${port}/api/v1`);
  if (enableSwagger) console.log(`📖 Swagger   → http://localhost:${port}/api/docs`);
}

bootstrap();
