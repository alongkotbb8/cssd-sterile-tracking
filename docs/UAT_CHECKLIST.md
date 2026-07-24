# UAT Checklist — CSSD Sterile Tracking (Gate 7)

> อ้างอิง: [CSSD_MASTER_EXECUTION_DIRECTIVE.md](../CSSD_MASTER_EXECUTION_DIRECTIVE.md) §GATE 7
> + [MACOS_BROWSER_PRINT_DIRECTIVE.md](../MACOS_BROWSER_PRINT_DIRECTIVE.md) (browser print)
> ผู้ตรวจ: ตาม §7A (CSSD staff, Supervisor, Admin/IT, Print Gateway owner, Patient Safety approver)
> ทุกข้อต้องมีหลักฐาน (ภาพหน้าจอ/ภาพถ่าย/บันทึก) และผลผูกกับ build/commit ที่ระบุ

## A. Authentication / RBAC

| # | Scenario | ผล | หลักฐาน |
|---|---|---|---|
| A1 | Login สำเร็จทุก role (CSSD / SUPERVISOR / ADMIN) | ☐ | |
| A2 | รหัสผิดถูกปฏิเสธ + lockout เมื่อผิดซ้ำ | ☐ | |
| A3 | Logout / logout ทุกอุปกรณ์ → token เก่าใช้ไม่ได้ | ☐ | |
| A4 | CSSD ห้ามบันทึกผล CI/BI, ห้าม resolve งานพิมพ์ | ☐ | |

## B. วงจรห่อ (Package lifecycle)

| # | Scenario | ผล | หลักฐาน |
|---|---|---|---|
| B1 | สร้างห่อ + เลขรันจาก backend + พิมพ์ label | ☐ | |
| B2 | สแกนเข้ารอบนึ่ง → บันทึกผลผ่าน → STERILE + วันหมดอายุถูกต้อง | ☐ | |
| B3 | บันทึกผลไม่ผ่าน → recall ห่อของรอบ + แสดงตำแหน่งปัจจุบัน | ☐ | |
| B4 | เบิกออก (ต้องเลือกแผนก) / ส่งคืน (บันทึกแผนกคืน) / reprocess | ☐ | |
| B5 | ห่อหมดอายุถูกบล็อกการเบิกแบบ fail-closed | ☐ | |
| B6 | PACKED_OUT ไปสถานที่ external เท่านั้น + รับคืน | ☐ | |
| B7 | Tag ติด/ถอด/กรอง | ☐ | |
| B8 | Dashboard + รายงานรายสัปดาห์ (PDF/Excel) ตรงข้อมูลจริง | ☐ | |

## C. การพิมพ์ — โหมด PRINT_GATEWAY (เส้นทางหลัก)

| # | Scenario | ผล | หลักฐาน |
|---|---|---|---|
| C1 | สร้าง print job → Gateway claim → พิมพ์จริง → PRINTED + printedAt | ☐ | |
| C2 | พิมพ์ซ้ำต้องกรอกเหตุผล + reprintCount เพิ่ม | ☐ | |
| C3 | จำลองพิมพ์ล้มเหลว → FAILED/RETRYING → DEAD_LETTER ตาม flow | ☐ | |
| C4 | ACK_UNKNOWN → Supervisor resolve (ผู้ใช้ทั่วไปทำไม่ได้) | ☐ | |
| C5 | Gateway offline → งานคงค้างใน queue ไม่หาย | ☐ | |

## D. การพิมพ์ — โหมด BROWSER_DIALOG (Mac + XP-420B)

> รายละเอียดเต็ม + hardware acceptance 16 ข้อ: [MAC_XP420B_BROWSER_PRINT.md](MAC_XP420B_BROWSER_PRINT.md) §5

| # | Scenario | ผล | หลักฐาน |
|---|---|---|---|
| D1 | ปุ่ม "พิมพ์ผ่านเครื่องนี้" แสดงเฉพาะเมื่อเปิด flag | ☐ | |
| D2 | Preview แสดงข้อมูลจาก backend; ห่อไม่ sterile ไม่มีวันที่ + มีแถบเตือน | ☐ | |
| D3 | กดพิมพ์ → history เป็น DIALOG_OPENED ก่อนหน้าต่างพิมพ์เปิด | ☐ | |
| D4 | ยืนยัน "กระดาษออกถูกต้อง" → USER_CONFIRMED (สื่อว่าผู้ใช้ยืนยันเอง) | ☐ | |
| D5 | "ไม่ได้พิมพ์/ยกเลิก" → CANCELLED; refresh ไม่เปิด dialog ซ้ำ | ☐ | |
| D6 | พิมพ์ซ้ำ: มี warning + บังคับเหตุผล + history แยกรายการ | ☐ | |
| D7 | ตลอด flow: Package.printedAt/สถานะ Gateway job ไม่เปลี่ยน | ☐ | |
| D8 | ผ่าน Manual Hardware Acceptance ครบ 16 ข้อ (10 ใบ + 50 ใบ) | ☐ | |

## E. Pilot constraints (§7C) + Stop conditions (§7D)

| # | เงื่อนไข | ผล |
|---|---|---|
| E1 | จุดพิมพ์ 1 จุด, XP-420B 1 เครื่อง, gateway 1 ตัว, ผู้ใช้จำกัด | ☐ |
| E2 | กำหนดระยะเวลา pilot + rollback plan + แผนทำงานต่อแบบ manual | ☐ |
| E3 | มี on-call owner ตลอด pilot | ☐ |
| E4 | Stop conditions ตกลงและสื่อสารแล้ว (ข้อมูลผิด/label ผิด/ระบบล่ม) | ☐ |

## บันทึกผล

- Build/commit ที่ทดสอบ: ______________
- วันที่ / ผู้ทดสอบ / role: ______________
- ปัญหาที่พบ + ความรุนแรง (P0–P3): ______________
- ผลรวม: ☐ ผ่าน ☐ ไม่ผ่าน (เหตุผล: ______________)
