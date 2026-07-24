import { createHash } from 'crypto';
import { processOneJob } from '../poll-loop';
import { PrintJob, PrintJobPayload } from '../types';
import { TransportSendError } from '../transports/transport';

function hashPayload(payload: PrintJobPayload): string {
  const orderedKeys = Object.keys(payload).sort();
  return createHash('sha256').update(JSON.stringify(payload, orderedKeys)).digest('hex');
}

function makeJob(overrides: Partial<PrintJob> = {}): PrintJob {
  const payload: PrintJobPayload = {
    packageId: 'clx4qr7z10000abcd12345678',
    setName: 'ชุดทำแผล',
    wrapType: 'SEAL',
    sterilizeDate: '2026-06-30T00:00:00.000Z',
    expiryDate: '2026-12-27T00:00:00.000Z',
    ...(overrides.payload ?? {}),
  };
  return {
    id: 'job-1',
    packageId: 'clx4qr7z10000abcd12345678',
    requestedPrinterId: null,
    printerId: 'printer-1',
    status: 'CLAIMED',
    attemptCount: 1,
    isReprint: false,
    reprintReason: null,
    payload,
    payloadHash: hashPayload(payload),
    ...overrides,
  };
}

function makeApi(job: PrintJob | null, overrides: Record<string, jest.Mock> = {}) {
  return {
    claim: jest.fn().mockResolvedValue(job),
    markPrinting: jest.fn().mockResolvedValue(job),
    markSent: jest.fn().mockResolvedValue(job),
    ack: jest.fn().mockResolvedValue(job),
    fail: jest.fn().mockResolvedValue(job),
    reportMaybeSent: jest.fn().mockResolvedValue(job),
    ...overrides,
  };
}

describe('processOneJob', () => {
  it('returns false and does nothing when there is no job to claim', async () => {
    const api = makeApi(null);
    const transport = { isSimulated: false, send: jest.fn() };
    expect(await processOneJob(api as any, transport)).toBe(false);
    expect(transport.send).not.toHaveBeenCalled();
  });

  it('claims → printing → sends → sent → ack (backend decides PRINTED/SIMULATED, no flag sent)', async () => {
    const api = makeApi(makeJob());
    const transport = { isSimulated: false, send: jest.fn().mockResolvedValue(undefined) };
    expect(await processOneJob(api as any, transport)).toBe(true);
    expect(api.markPrinting).toHaveBeenCalledWith('job-1');
    expect(transport.send).toHaveBeenCalledTimes(1);
    expect(api.markSent).toHaveBeenCalledWith('job-1');
    expect(api.ack).toHaveBeenCalledWith('job-1'); // FIX-05: no simulated arg
    expect(api.fail).not.toHaveBeenCalled();
    expect(api.reportMaybeSent).not.toHaveBeenCalled();
  });

  it('rejects a payloadHash mismatch — never calls transport.send()', async () => {
    const api = makeApi(makeJob({ payloadHash: 'tampered' }));
    const transport = { isSimulated: false, send: jest.fn() };
    await processOneJob(api as any, transport);
    expect(transport.send).not.toHaveBeenCalled();
    expect(api.fail).toHaveBeenCalledWith('job-1', 'PAYLOAD_HASH_MISMATCH', expect.any(String));
  });

  it('NOT_SENT transport error → fail() (retry safe), never markSent/ack', async () => {
    const api = makeApi(makeJob());
    const transport = {
      isSimulated: false,
      send: jest.fn().mockRejectedValue(new TransportSendError('NOT_SENT', 'port closed')),
    };
    await processOneJob(api as any, transport);
    expect(api.fail).toHaveBeenCalledWith('job-1', 'TRANSPORT_NOT_SENT', 'port closed');
    expect(api.reportMaybeSent).not.toHaveBeenCalled();
    expect(api.markSent).not.toHaveBeenCalled();
    expect(api.ack).not.toHaveBeenCalled();
  });

  it('MAYBE_SENT transport error → reportMaybeSent() (ACK_UNKNOWN, no retry), never fail()', async () => {
    const api = makeApi(makeJob());
    const transport = {
      isSimulated: false,
      send: jest.fn().mockRejectedValue(new TransportSendError('MAYBE_SENT', 'drain error')),
    };
    await processOneJob(api as any, transport);
    expect(api.reportMaybeSent).toHaveBeenCalledWith('job-1', 'TRANSPORT_MAYBE_SENT', 'drain error');
    expect(api.fail).not.toHaveBeenCalled();
    expect(api.ack).not.toHaveBeenCalled();
  });

  it('UNKNOWN (untyped) transport error → treated as MAYBE_SENT, never fail()/retry', async () => {
    const api = makeApi(makeJob());
    const transport = {
      isSimulated: false,
      send: jest.fn().mockRejectedValue(new Error('mystery write failure')),
    };
    await processOneJob(api as any, transport);
    expect(api.reportMaybeSent).toHaveBeenCalledWith('job-1', 'TRANSPORT_MAYBE_SENT', 'mystery write failure');
    expect(api.fail).not.toHaveBeenCalled();
  });

  it('render/validation error before send → fail() (NOT_SENT), never send', async () => {
    const api = makeApi(makeJob({ payload: { packageId: '../evil\r\n', setName: 'x', wrapType: 'SEAL', sterilizeDate: null, expiryDate: null } as any }));
    // recompute the hash so it passes verification and reaches buildTsplLabel (which rejects the bad id)
    const job = makeJob();
    job.payload = { packageId: '../evil\r\n', setName: 'x', wrapType: 'SEAL', sterilizeDate: null, expiryDate: null };
    job.payloadHash = hashPayload(job.payload);
    api.claim = jest.fn().mockResolvedValue(job);
    const transport = { isSimulated: false, send: jest.fn() };
    await processOneJob(api as any, transport);
    expect(transport.send).not.toHaveBeenCalled();
    expect(api.fail).toHaveBeenCalledWith('job-1', 'INVALID_PAYLOAD', expect.any(String));
  });

  it('once send() succeeded, never fail()/retry even if markSent()/ack() then fail (duplicate-print ambiguity)', async () => {
    const api = makeApi(makeJob(), { markSent: jest.fn().mockRejectedValue(new Error('network dropped')) });
    const transport = { isSimulated: false, send: jest.fn().mockResolvedValue(undefined) };
    expect(await processOneJob(api as any, transport)).toBe(true);
    expect(transport.send).toHaveBeenCalledTimes(1);
    expect(api.fail).not.toHaveBeenCalled();
    expect(api.reportMaybeSent).not.toHaveBeenCalled();
    expect(api.ack).not.toHaveBeenCalled();
  });
});
