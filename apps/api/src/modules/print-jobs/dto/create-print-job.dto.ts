import { IsOptional, IsString, MaxLength } from 'class-validator';
import { ApiPropertyOptional, ApiProperty } from '@nestjs/swagger';

export class CreatePrintJobDto {
  @ApiProperty({ description: 'ห่อที่จะพิมพ์ label' })
  @IsString()
  packageId: string;

  @ApiPropertyOptional({ description: 'ระบุเครื่องพิมพ์เจาะจง (ว่าง = เครื่องไหนก็ claim ได้)' })
  @IsOptional()
  @IsString()
  requestedPrinterId?: string;

  // isReprint คำนวณที่ backend เสมอ (จาก package.printedAt) — client ส่งมาเองไม่ได้
  // (AI_DEVELOPMENT_GUARDRAILS.md ข้อ 2.2) บังคับกรอกเหตุผลเมื่อห่อเคยพิมพ์แล้วเท่านั้น
  @ApiPropertyOptional({ description: 'เหตุผลที่พิมพ์ซ้ำ — บังคับเมื่อห่อนี้เคยพิมพ์แล้ว' })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  reprintReason?: string;
}
