import { IsIn, IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { PACKAGE_ID_MAX_LEN } from '../../scan/package-id.util';

export const BROWSER_PRINT_ORIGINS = ['CREATE_PACKAGE', 'PACKAGE_DETAIL', 'PRINT_JOBS'] as const;
export type BrowserPrintOriginLiteral = (typeof BROWSER_PRINT_ORIGINS)[number];

/**
 * สร้าง Browser Print Request (MACOS_BROWSER_PRINT_DIRECTIVE.md §7)
 * DTO เป็น allowlist เข้ม (global ValidationPipe เปิด whitelist+forbidNonWhitelisted)
 * — client ส่ง isReprint/สถานะ/วันที่มาเองไม่ได้เด็ดขาด
 */
export class CreateBrowserPrintRequestDto {
  @ApiProperty({ description: 'เลขห่อที่จะพิมพ์ label (backend ตรวจรูปแบบซ้ำอีกชั้น)' })
  @IsString()
  @MaxLength(PACKAGE_ID_MAX_LEN)
  packageId: string;

  @ApiProperty({ description: 'จำนวนสำเนา 1–10 (directive §5)', minimum: 1, maximum: 10 })
  @IsInt()
  @Min(1)
  @Max(10)
  copies: number;

  @ApiProperty({ enum: BROWSER_PRINT_ORIGINS, description: 'จุดที่สั่งพิมพ์ (traceability)' })
  @IsIn(BROWSER_PRINT_ORIGINS)
  createdFrom: BrowserPrintOriginLiteral;

  // ต้องปฏิเสธค่า mode ที่ไม่รู้จัก (directive §4) — รับได้เฉพาะ BROWSER_DIALOG
  @ApiPropertyOptional({ enum: ['BROWSER_DIALOG'], description: 'โหมดพิมพ์ — รับเฉพาะ BROWSER_DIALOG' })
  @IsOptional()
  @IsIn(['BROWSER_DIALOG'])
  mode?: 'BROWSER_DIALOG';

  // isReprint คำนวณที่ backend เสมอ — บังคับกรอกเหตุผลเมื่อห่อเคยสั่งพิมพ์แล้วเท่านั้น
  @ApiPropertyOptional({ description: 'เหตุผลที่พิมพ์ซ้ำ — บังคับเมื่อห่อนี้เคยสั่งพิมพ์แล้ว' })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  reprintReason?: string;
}
