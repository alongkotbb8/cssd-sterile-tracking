import { IsIn, IsString, MaxLength, MinLength } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class ResolveAckUnknownDto {
  @ApiProperty({
    enum: ['CONFIRM_PRINTED', 'REQUEUE'],
    description: 'CONFIRM_PRINTED = ยืนยันว่าพิมพ์จริงแล้ว, REQUEUE = ไม่ยืนยัน ให้เปิดงานพิมพ์ใหม่',
  })
  @IsIn(['CONFIRM_PRINTED', 'REQUEUE'])
  decision: 'CONFIRM_PRINTED' | 'REQUEUE';

  @ApiProperty({ description: 'หมายเหตุการตัดสินใจ (บังคับ) เช่น ตรวจกับเครื่องพิมพ์แล้วพบว่า...' })
  @IsString()
  @MinLength(1)
  @MaxLength(300)
  note: string;
}
