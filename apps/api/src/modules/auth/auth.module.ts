import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';
import { JwtStrategy } from './jwt.strategy';
import { requireEnv } from '../../common/config/env';

@Module({
  imports: [
    PassportModule,
    JwtModule.registerAsync({
      // No hardcoded fallback secret — requireEnv throws if JWT_SECRET is missing.
      useFactory: () => ({
        secret: requireEnv('JWT_SECRET'),
        signOptions: { expiresIn: process.env.JWT_EXPIRES_IN ?? '8h' },
      }),
    }),
  ],
  providers: [AuthService, JwtStrategy],
  controllers: [AuthController],
  exports: [AuthService],
})
export class AuthModule {}
