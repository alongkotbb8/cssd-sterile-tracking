import { IsDateString, IsInt, IsString, Min } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class CreateBatchDto {
  @ApiProperty({ description: 'ID ของเครื่องนึ่ง' })
  @IsString()
  sterilizerId: string;

  @ApiProperty({ description: 'รอบที่ของวัน', example: 1 })
  @IsInt()
  @Min(1)
  roundNo: number;

  @ApiProperty({ description: 'เวลาเริ่มรอบนึ่ง (ISO 8601)', example: '2026-06-30T08:00:00Z' })
  @IsDateString()
  startedAt: string;
}
