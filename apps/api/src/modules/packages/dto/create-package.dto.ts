import { IsString, IsOptional, IsEnum } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { WrapType } from '@prisma/client';

export class CreatePackageDto {
  @ApiProperty({ description: 'ID ของ SetTemplate' })
  @IsString()
  setTemplateId: string;

  @ApiPropertyOptional({ enum: WrapType, description: 'ชนิดห่อ (SEAL=180วัน, CLOTH=7วัน) ถ้าไม่ส่งใช้ default ของ template' })
  @IsOptional()
  @IsEnum(WrapType)
  wrapType?: WrapType;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  notes?: string;
}
