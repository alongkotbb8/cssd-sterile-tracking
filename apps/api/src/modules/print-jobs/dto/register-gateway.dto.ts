import { IsBoolean, IsEnum, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { GatewayEnvironment, GatewayTransportMode } from '@prisma/client';

export class RegisterGatewayDto {
  @ApiProperty({ description: 'ชื่อ/ตำแหน่งของเครื่องพิมพ์-gateway เช่น "CSSD ชั้น 2 - XP-420B"' })
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  name: string;

  @ApiPropertyOptional({ enum: GatewayEnvironment, description: 'default DEVELOPMENT' })
  @IsOptional()
  @IsEnum(GatewayEnvironment)
  environment?: GatewayEnvironment;

  @ApiPropertyOptional({ enum: GatewayTransportMode, description: 'default CONSOLE' })
  @IsOptional()
  @IsEnum(GatewayTransportMode)
  transportMode?: GatewayTransportMode;

  // FIX-05: ตั้งเป็น true เท่านั้นที่ ACK ทำให้ Package เป็น PRINTED จริงได้ (default false)
  @ApiPropertyOptional({ description: 'อนุญาตให้ ACK ยืนยันพิมพ์จริง (default false)' })
  @IsOptional()
  @IsBoolean()
  canConfirmRealPrint?: boolean;
}
