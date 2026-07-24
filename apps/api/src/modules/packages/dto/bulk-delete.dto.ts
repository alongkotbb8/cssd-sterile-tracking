import { ArrayNotEmpty, ArrayMaxSize, IsString } from 'class-validator';

/** ลบห่อถาวรหลายรายการพร้อมกัน — เฉพาะห่อ PACKED ที่ยังไม่มีประวัติการใช้งาน (ดู service) */
export class BulkDeleteDto {
  @ArrayNotEmpty()
  @ArrayMaxSize(100)
  @IsString({ each: true })
  packageIds: string[];
}
