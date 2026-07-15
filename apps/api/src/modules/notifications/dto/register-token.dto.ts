import { IsOptional, IsString, MaxLength } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class RegisterTokenDto {
  @ApiProperty({ description: 'FCM registration token จากมือถือ' })
  @IsString()
  @MaxLength(300) // ต้องตรงกับ FcmToken.token VARCHAR(300) ไม่งั้น Prisma throw 500 แทน 400
  token: string;

  @ApiPropertyOptional({ description: 'ตัวระบุอุปกรณ์ (ถ้ามี)' })
  @IsOptional()
  @IsString()
  @MaxLength(100) // ตรงกับ FcmToken.deviceId VARCHAR(100)
  deviceId?: string;
}
