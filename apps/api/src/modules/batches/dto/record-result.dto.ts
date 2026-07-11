import { IsBoolean, IsOptional } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class RecordResultDto {
  @ApiProperty({ description: 'ผล Chemical Indicator' })
  @IsBoolean()
  ciResult: boolean;

  @ApiPropertyOptional({ description: 'ผล Biological Indicator (อาจมาทีหลัง)' })
  @IsOptional()
  @IsBoolean()
  biResult?: boolean;
}
