import { IsBoolean } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

/** บันทึกผล BI ที่มาทีหลัง สำหรับรอบที่ early-release อยู่ (PENDING_BI) */
export class RecordBiResultDto {
  @ApiProperty({ description: 'ผล Biological Indicator (true=ผ่าน, false=ไม่ผ่าน→recall)' })
  @IsBoolean()
  biResult: boolean;
}
