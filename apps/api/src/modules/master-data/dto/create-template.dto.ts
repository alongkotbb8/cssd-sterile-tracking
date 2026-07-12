import { ApiProperty } from '@nestjs/swagger';
import { WrapType } from '@prisma/client';
import {
  ArrayMinSize,
  IsArray,
  IsEnum,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';

export class CreateSetTemplateDto {
  @ApiProperty({ example: 'DELIV', description: 'ใช้เป็น prefix เลขรัน (ห้ามซ้ำ)' })
  @IsString()
  @MinLength(2)
  @MaxLength(30)
  code: string;

  @ApiProperty({ example: 'ชุดทำคลอด' })
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  name: string;

  @ApiProperty({ example: ['กรรไกร', 'คีมคีบ', 'ผ้าคลุม'], type: [String] })
  @IsArray()
  @ArrayMinSize(1)
  @IsString({ each: true })
  itemList: string[];

  @ApiProperty({ enum: WrapType, required: false, default: WrapType.SEAL })
  @IsOptional()
  @IsEnum(WrapType)
  defaultWrapType?: WrapType;
}
