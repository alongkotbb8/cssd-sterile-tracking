import 'dotenv/config';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { requireEnv } from './common/config/env';

async function bootstrap() {
  // Fail fast if security-critical config is missing (no insecure fallback).
  requireEnv('JWT_SECRET');

  const app = await NestFactory.create(AppModule);

  app.setGlobalPrefix('api/v1');
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );
  // CORS: mobile clients don't need it; restrict browser origins via env when set.
  app.enableCors({
    origin: process.env.CORS_ORIGINS ? process.env.CORS_ORIGINS.split(',') : true,
  });

  const config = new DocumentBuilder()
    .setTitle('CSSD Sterile Tracking API')
    .setDescription('ระบบตามรอยอุปกรณ์หัตถการปลอดเชื้อ')
    .setVersion('1.0')
    .addBearerAuth()
    .build();
  SwaggerModule.setup('api/docs', app, SwaggerModule.createDocument(app, config));

  const port = process.env.PORT ?? 3000;
  await app.listen(port, '0.0.0.0');
  console.log(`🚀 API running on http://localhost:${port}/api/v1`);
  console.log(`📖 Swagger   → http://localhost:${port}/api/docs`);
}

bootstrap();
