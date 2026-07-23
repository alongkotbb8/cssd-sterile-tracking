import { PrintJob } from './types';

/**
 * เรียก backend ด้วย `X-Gateway-Key` เท่านั้น (ไม่ใช่ JWT ผู้ใช้) — endpoint
 * ทั้งหมดที่ไฟล์นี้เรียกอยู่ใต้ GatewayAuthGuard ฝั่ง API
 * (apps/api/src/modules/print-jobs/print-gateway.controller.ts)
 */
export class ApiClient {
  constructor(
    private baseUrl: string,
    private apiKey: string,
  ) {}

  private async request<T>(path: string, init?: RequestInit): Promise<T> {
    const res = await fetch(`${this.baseUrl}${path}`, {
      ...init,
      headers: {
        'Content-Type': 'application/json',
        'X-Gateway-Key': this.apiKey,
        ...(init?.headers ?? {}),
      },
    });
    if (!res.ok) {
      const body = await res.text().catch(() => '');
      throw new Error(`${init?.method ?? 'GET'} ${path} → ${res.status}: ${body}`);
    }
    if (res.status === 204) return undefined as T;
    return res.json() as Promise<T>;
  }

  heartbeat(): Promise<void> {
    return this.request('/print-gateway/heartbeat', { method: 'POST' });
  }

  /** null = ไม่มีงานรอพิมพ์ */
  claim(): Promise<PrintJob | null> {
    return this.request('/print-gateway/claim', { method: 'POST' });
  }

  markPrinting(jobId: string): Promise<PrintJob> {
    return this.request(`/print-gateway/jobs/${jobId}/printing`, { method: 'POST' });
  }

  /** เรียกทันทีหลัง transport.send() คืนผลสำเร็จ — ก่อน ack เสมอ (PRINTING → SENT) */
  markSent(jobId: string): Promise<PrintJob> {
    return this.request(`/print-gateway/jobs/${jobId}/sent`, { method: 'POST' });
  }

  /** ยืนยันพิมพ์ — backend ตัดสิน PRINTED vs SIMULATED เองจาก capability ของ gateway (FIX-05) */
  ack(jobId: string): Promise<PrintJob> {
    return this.request(`/print-gateway/jobs/${jobId}/ack`, { method: 'POST' });
  }

  fail(jobId: string, errorCode: string, message?: string): Promise<PrintJob> {
    return this.request(`/print-gateway/jobs/${jobId}/fail`, {
      method: 'POST',
      body: JSON.stringify({ errorCode, message }),
    });
  }

  /** MAYBE_SENT (FIX-04): อาจส่งถึงเครื่องพิมพ์แล้วบางส่วน → ACK_UNKNOWN ห้าม retry */
  reportMaybeSent(jobId: string, errorCode: string, message?: string): Promise<PrintJob> {
    return this.request(`/print-gateway/jobs/${jobId}/maybe-sent`, {
      method: 'POST',
      body: JSON.stringify({ errorCode, message }),
    });
  }
}
