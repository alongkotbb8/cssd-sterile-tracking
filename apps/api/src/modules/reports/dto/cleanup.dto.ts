import { ApiProperty } from '@nestjs/swagger';
import { IsDateString } from 'class-validator';

export class CleanupDto {
  @ApiProperty({
    description: 'ลบประวัติที่เกิดก่อนวันที่นี้ (ISO date เช่น 2026-07-01)',
    example: '2026-07-01',
  })
  @IsDateString()
  before: string;
}
