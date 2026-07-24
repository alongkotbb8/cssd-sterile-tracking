import { Type } from 'class-transformer';
import {
  IsIn,
  IsISO8601,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';
import { BrowserPrintStatus } from '@prisma/client';
import { PACKAGE_ID_MAX_LEN } from '../../scan/package-id.util';

export const BROWSER_PRINT_LIST_DEFAULT_PAGE_SIZE = 20;
export const BROWSER_PRINT_LIST_MAX_PAGE_SIZE = 100;

/**
 * Query ของ GET /browser-print-requests (directive §7: filter ตาม package/ผู้ใช้/
 * status/ช่วงเวลา + pagination + sort ล่าสุดก่อน)
 * ผู้ใช้ non-privileged ถูกบังคับให้เห็นเฉพาะของตัวเอง (service enforce)
 */
export class ListBrowserPrintRequestsQuery {
  @ApiPropertyOptional({ description: 'filter ตามเลขห่อ' })
  @IsOptional()
  @IsString()
  @MaxLength(PACKAGE_ID_MAX_LEN)
  packageId?: string;

  @ApiPropertyOptional({ description: 'filter ตามผู้สั่ง (non-privileged ระบุได้เฉพาะตัวเอง)' })
  @IsOptional()
  @IsString()
  @MaxLength(60)
  userId?: string;

  @ApiPropertyOptional({ enum: BrowserPrintStatus })
  @IsOptional()
  @IsIn(Object.values(BrowserPrintStatus))
  status?: BrowserPrintStatus;

  @ApiPropertyOptional({ description: 'createdAt >= from (ISO8601)' })
  @IsOptional()
  @IsISO8601()
  from?: string;

  @ApiPropertyOptional({ description: 'createdAt <= to (ISO8601)' })
  @IsOptional()
  @IsISO8601()
  to?: string;

  @ApiPropertyOptional({ minimum: 1, default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number;

  @ApiPropertyOptional({
    minimum: 1,
    maximum: BROWSER_PRINT_LIST_MAX_PAGE_SIZE,
    default: BROWSER_PRINT_LIST_DEFAULT_PAGE_SIZE,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(BROWSER_PRINT_LIST_MAX_PAGE_SIZE)
  pageSize?: number;
}
