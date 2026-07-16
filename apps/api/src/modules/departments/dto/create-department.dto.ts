import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class CreateDepartmentDto {
  @ApiProperty({ example: 'EXT-PYT', description: 'รหัสแผนก/สถานที่ (ห้ามซ้ำ)' })
  @IsString()
  @MinLength(2)
  @MaxLength(20)
  code: string;

  @ApiProperty({ example: 'รพ.พญาไท' })
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  name: string;

  @ApiPropertyOptional({
    example: 'external',
    description: "ประเภท เช่น clinic / ward / er / external (สถานที่นอกโรงพยาบาล)",
  })
  @IsOptional()
  @IsString()
  @MaxLength(50)
  type?: string;
}
