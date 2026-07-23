import { IsOptional, IsString, MaxLength } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class FailPrintJobDto {
  @ApiProperty({ description: 'รหัส error จากเครื่องพิมพ์/gateway เช่น PAPER_OUT, BT_DISCONNECTED' })
  @IsString()
  @MaxLength(100)
  errorCode: string;

  @ApiPropertyOptional({ description: 'รายละเอียดเพิ่มเติม (ไม่ต้อง log secret/token)' })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  message?: string;
}
