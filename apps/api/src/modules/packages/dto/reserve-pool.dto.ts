import { IsInt, IsString, Max, MaxLength, Min } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class ReservePoolDto {
  @ApiProperty({ description: 'ID ของ SetTemplate' })
  @IsString()
  setTemplateId: string;

  @ApiProperty({ description: 'จำนวนเลขรันที่ต้องการจอง (1-200)', example: 20 })
  @IsInt()
  @Min(1)
  @Max(200)
  count: number;

  @ApiProperty({ description: 'รหัสอุปกรณ์มือถือที่ขอจอง' })
  @IsString()
  @MaxLength(100)
  deviceId: string;
}
