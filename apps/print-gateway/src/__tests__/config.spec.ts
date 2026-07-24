/**
 * config.ts ทำ validation ที่ module load time (throw ทันทีถ้าตั้งค่าอันตราย)
 * ต้อง reset module registry + ตั้ง env ใหม่ทุกเทสเพื่อให้ import ใหม่จริง
 * (FIX-06: กฎ HTTPS เข้มขึ้น — Private IP ไม่ใช่ข้อยกเว้นใน production)
 */
describe('print-gateway config guards', () => {
  const ORIGINAL_ENV = process.env;

  beforeEach(() => {
    jest.resetModules();
    process.env = { ...ORIGINAL_ENV, GATEWAY_API_KEY: 'k' };
  });
  afterAll(() => {
    process.env = ORIGINAL_ENV;
  });

  const load = () => require('../config');

  // ── development/test: http เฉพาะ localhost/127.0.0.1 ──
  it('development + http localhost → start ได้', () => {
    process.env.NODE_ENV = 'development';
    process.env.API_BASE_URL = 'http://localhost:3000/api/v1';
    expect(load).not.toThrow();
  });

  it('development + http 127.0.0.1 → start ได้', () => {
    process.env.NODE_ENV = 'development';
    process.env.API_BASE_URL = 'http://127.0.0.1:3000/api/v1';
    expect(load).not.toThrow();
  });

  it('development + http private LAN IP → start ไม่ได้ (FIX-06: เฉพาะ localhost)', () => {
    process.env.NODE_ENV = 'development';
    process.env.API_BASE_URL = 'http://192.168.1.50:3000/api/v1';
    expect(load).toThrow(/localhost/);
  });

  it('development + http public host → start ไม่ได้', () => {
    process.env.NODE_ENV = 'development';
    process.env.API_BASE_URL = 'http://api.example.com/api/v1';
    expect(load).toThrow();
  });

  // ── production: https เท่านั้น (แม้ localhost/private IP ก็ไม่ยอม http) ──
  it('production + http localhost → start ไม่ได้', () => {
    process.env.NODE_ENV = 'production';
    process.env.PRINTER_TRANSPORT = 'serial';
    process.env.PRINTER_SERIAL_PATH = '/dev/ttyUSB0';
    process.env.API_BASE_URL = 'http://localhost:3000/api/v1';
    expect(load).toThrow(/https/);
  });

  it('production + http private IP → start ไม่ได้', () => {
    process.env.NODE_ENV = 'production';
    process.env.PRINTER_TRANSPORT = 'serial';
    process.env.API_BASE_URL = 'http://10.0.0.5:3000/api/v1';
    expect(load).toThrow(/https/);
  });

  it('production + http public IP → start ไม่ได้', () => {
    process.env.NODE_ENV = 'production';
    process.env.PRINTER_TRANSPORT = 'serial';
    process.env.API_BASE_URL = 'http://203.0.113.9/api/v1';
    expect(load).toThrow(/https/);
  });

  it('production + https → start ได้', () => {
    process.env.NODE_ENV = 'production';
    process.env.PRINTER_TRANSPORT = 'serial';
    process.env.API_BASE_URL = 'https://api.example.com/api/v1';
    expect(load).not.toThrow();
  });

  // ── console transport guard (FIX-05 / audit 1.2) ──
  it('production + PRINTER_TRANSPORT=console → start ไม่ได้', () => {
    process.env.NODE_ENV = 'production';
    process.env.PRINTER_TRANSPORT = 'console';
    process.env.API_BASE_URL = 'https://api.example.com/api/v1';
    expect(load).toThrow(/console/);
  });

  it('production + PRINTER_TRANSPORT=serial → start ได้', () => {
    process.env.NODE_ENV = 'production';
    process.env.PRINTER_TRANSPORT = 'serial';
    process.env.API_BASE_URL = 'https://api.example.com/api/v1';
    expect(load).not.toThrow();
  });
});
