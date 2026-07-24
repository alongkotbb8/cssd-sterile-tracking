export type PrintJobStatus =
  | 'QUEUED'
  | 'CLAIMED'
  | 'PRINTING'
  | 'SENT'
  | 'PRINTED'
  | 'SIMULATED'
  | 'FAILED'
  | 'RETRYING'
  | 'DEAD_LETTER'
  | 'ACK_UNKNOWN'
  | 'CANCELLED';

/** ต้องตรงกับ PrintJobPayload ฝั่ง backend (apps/api/src/modules/print-jobs/print-jobs.service.ts) */
export interface PrintJobPayload {
  packageId: string;
  setName: string;
  wrapType: string; // 'SEAL' | 'CLOTH'
  sterilizeDate: string | null;
  expiryDate: string | null;
}

export interface PrintJob {
  id: string;
  packageId: string;
  requestedPrinterId: string | null;
  printerId: string | null;
  status: PrintJobStatus;
  attemptCount: number;
  isReprint: boolean;
  reprintReason: string | null;
  payload: PrintJobPayload;
  payloadHash: string;
}
