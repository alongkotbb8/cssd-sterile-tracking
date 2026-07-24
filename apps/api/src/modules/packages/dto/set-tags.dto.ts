import { IsArray, IsString, ArrayMaxSize } from 'class-validator';

/** ตั้ง tag ของห่อ (แทนที่ทั้งชุด) — ส่งรายการ tagId ที่ต้องการให้ห่อนี้มี */
export class SetTagsDto {
  @IsArray()
  @ArrayMaxSize(20)
  @IsString({ each: true })
  tagIds: string[];
}
