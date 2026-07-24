import { IsBoolean, IsEnum, IsOptional } from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';
import { GatewayEnvironment, GatewayTransportMode } from '@prisma/client';

/** FIX-05: เปลี่ยน capability ของ gateway (ADMIN เท่านั้น) — ส่งเฉพาะฟิลด์ที่ต้องการเปลี่ยน */
export class UpdateGatewayCapabilityDto {
  @ApiPropertyOptional({ enum: GatewayEnvironment })
  @IsOptional()
  @IsEnum(GatewayEnvironment)
  environment?: GatewayEnvironment;

  @ApiPropertyOptional({ enum: GatewayTransportMode })
  @IsOptional()
  @IsEnum(GatewayTransportMode)
  transportMode?: GatewayTransportMode;

  @ApiPropertyOptional({ description: 'อนุญาตให้ ACK ยืนยันพิมพ์จริง' })
  @IsOptional()
  @IsBoolean()
  canConfirmRealPrint?: boolean;
}
