import 'reflect-metadata';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { CreateBrowserPrintRequestDto } from '../dto/create-browser-print-request.dto';
import { ListBrowserPrintRequestsQuery } from '../dto/list-browser-print-requests.query';

/**
 * MACOS_BROWSER_PRINT_DIRECTIVE.md §14 กรณี 6–7 (copies นอกช่วง 1–10) + §13
 * DTO allowlist/length limit — validate ด้วย class-validator ตัวจริง
 * (ValidationPipe global เปิด whitelist + forbidNonWhitelisted + transform อยู่แล้ว)
 */
async function errorsOf(cls: any, payload: Record<string, unknown>) {
  const dto = plainToInstance(cls, payload) as object;
  return validate(dto, { whitelist: true, forbidNonWhitelisted: true });
}

const validBody = {
  packageId: 'DELIV-20260724-0001',
  copies: 2,
  createdFrom: 'PACKAGE_DETAIL',
};

describe('CreateBrowserPrintRequestDto', () => {
  it('payload ถูกต้องผ่าน validation', async () => {
    expect(await errorsOf(CreateBrowserPrintRequestDto, validBody)).toHaveLength(0);
    expect(
      await errorsOf(CreateBrowserPrintRequestDto, {
        ...validBody,
        mode: 'BROWSER_DIALOG',
        reprintReason: 'label ชำรุด',
      }),
    ).toHaveLength(0);
  });

  it('§14.6 copies ต่ำกว่า 1 ถูกปฏิเสธ', async () => {
    const errors = await errorsOf(CreateBrowserPrintRequestDto, { ...validBody, copies: 0 });
    expect(errors.some((e) => e.property === 'copies')).toBe(true);
  });

  it('§14.7 copies มากกว่า 10 ถูกปฏิเสธ', async () => {
    const errors = await errorsOf(CreateBrowserPrintRequestDto, { ...validBody, copies: 11 });
    expect(errors.some((e) => e.property === 'copies')).toBe(true);
  });

  it('copies ต้องเป็น integer (ทศนิยม/สตริงถูกปฏิเสธ)', async () => {
    expect(
      (await errorsOf(CreateBrowserPrintRequestDto, { ...validBody, copies: 2.5 })).some(
        (e) => e.property === 'copies',
      ),
    ).toBe(true);
    expect(
      (await errorsOf(CreateBrowserPrintRequestDto, { ...validBody, copies: '3' })).some(
        (e) => e.property === 'copies',
      ),
    ).toBe(true);
  });

  it('createdFrom นอก allowlist ถูกปฏิเสธ', async () => {
    const errors = await errorsOf(CreateBrowserPrintRequestDto, {
      ...validBody,
      createdFrom: 'SOMEWHERE_ELSE',
    });
    expect(errors.some((e) => e.property === 'createdFrom')).toBe(true);
  });

  it('mode ที่ไม่รู้จักถูกปฏิเสธ (directive §4: ต้องปฏิเสธ mode ที่ไม่รู้จัก)', async () => {
    const errors = await errorsOf(CreateBrowserPrintRequestDto, {
      ...validBody,
      mode: 'PRINT_GATEWAY',
    });
    expect(errors.some((e) => e.property === 'mode')).toBe(true);
  });

  it('reprintReason ยาวเกิน 200 ถูกปฏิเสธ', async () => {
    const errors = await errorsOf(CreateBrowserPrintRequestDto, {
      ...validBody,
      reprintReason: 'ก'.repeat(201),
    });
    expect(errors.some((e) => e.property === 'reprintReason')).toBe(true);
  });

  it('field แปลกปลอม (เช่น isReprint จาก client) ถูกปฏิเสธโดย whitelist', async () => {
    const errors = await errorsOf(CreateBrowserPrintRequestDto, { ...validBody, isReprint: true });
    expect(errors.length).toBeGreaterThan(0);
  });
});

describe('ListBrowserPrintRequestsQuery', () => {
  it('query ว่างผ่าน (ใช้ default ฝั่ง service)', async () => {
    expect(await errorsOf(ListBrowserPrintRequestsQuery, {})).toHaveLength(0);
  });

  it('page/pageSize เป็นสตริงตัวเลข → transform เป็น number แล้วผ่าน', async () => {
    const q = plainToInstance(ListBrowserPrintRequestsQuery, { page: '2', pageSize: '50' });
    expect(await validate(q)).toHaveLength(0);
    expect(q.page).toBe(2);
    expect(q.pageSize).toBe(50);
  });

  it('pageSize เกิน 100 ถูกปฏิเสธ', async () => {
    const errors = await errorsOf(ListBrowserPrintRequestsQuery, { pageSize: '200' });
    expect(errors.some((e) => e.property === 'pageSize')).toBe(true);
  });

  it('status นอก enum ถูกปฏิเสธ (PRINTED ไม่ใช่สถานะ browser print)', async () => {
    const errors = await errorsOf(ListBrowserPrintRequestsQuery, { status: 'PRINTED' });
    expect(errors.some((e) => e.property === 'status')).toBe(true);
  });

  it('from/to ต้องเป็น ISO8601', async () => {
    const errors = await errorsOf(ListBrowserPrintRequestsQuery, { from: 'yesterday' });
    expect(errors.some((e) => e.property === 'from')).toBe(true);
    expect(
      await errorsOf(ListBrowserPrintRequestsQuery, {
        from: '2026-07-01T00:00:00Z',
        to: '2026-07-24T00:00:00Z',
      }),
    ).toHaveLength(0);
  });
});
