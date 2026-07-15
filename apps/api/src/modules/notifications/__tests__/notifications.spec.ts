import { FcmService } from '../fcm.service';
import { ExpiryReminderScheduler } from '../expiry-reminder.scheduler';
import { DailySummaryReminderScheduler } from '../daily-summary-reminder.scheduler';

describe('FcmService — no-op mode (no Firebase creds in env)', () => {
  const originalEnv = process.env;

  beforeEach(() => {
    process.env = { ...originalEnv };
    delete process.env.FIREBASE_PROJECT_ID;
    delete process.env.FIREBASE_CLIENT_EMAIL;
    delete process.env.FIREBASE_PRIVATE_KEY;
  });

  afterAll(() => {
    process.env = originalEnv;
  });

  it('stays disabled and logs instead of throwing when creds are missing', async () => {
    const svc = new FcmService();
    svc.onModuleInit();

    expect(svc.isEnabled).toBe(false);

    const result = await svc.sendToTokens(['token-1', 'token-2'], { title: 't', body: 'b' });
    expect(result.invalidTokens).toEqual([]);
  });

  it('returns immediately for an empty token list', async () => {
    const svc = new FcmService();
    svc.onModuleInit();
    const result = await svc.sendToTokens([], { title: 't', body: 'b' });
    expect(result.invalidTokens).toEqual([]);
  });
});

describe('ExpiryReminderScheduler', () => {
  it('notifies active users when packages are near expiry', async () => {
    const findMany = jest.fn().mockResolvedValue([{ id: 'P1', expiryDate: new Date() }]);
    const sendToActiveUsers = jest.fn().mockResolvedValue(undefined);

    const scheduler = new ExpiryReminderScheduler(
      { package: { findMany } } as any,
      { sendToActiveUsers } as any,
    );

    await scheduler.handleCron();

    expect(findMany).toHaveBeenCalledTimes(1);
    expect(sendToActiveUsers).toHaveBeenCalledTimes(1);
    expect(sendToActiveUsers.mock.calls[0][0].body).toContain('1 ห่อ');
  });

  it('does nothing when no package is near expiry', async () => {
    const findMany = jest.fn().mockResolvedValue([]);
    const sendToActiveUsers = jest.fn();

    const scheduler = new ExpiryReminderScheduler(
      { package: { findMany } } as any,
      { sendToActiveUsers } as any,
    );

    await scheduler.handleCron();

    expect(sendToActiveUsers).not.toHaveBeenCalled();
  });
});

describe('DailySummaryReminderScheduler', () => {
  it('sends a reminder when movements happened today', async () => {
    const count = jest.fn().mockResolvedValue(5);
    const sendToActiveUsers = jest.fn().mockResolvedValue(undefined);

    const scheduler = new DailySummaryReminderScheduler(
      { movement: { count } } as any,
      { sendToActiveUsers } as any,
    );

    await scheduler.handleCron();

    expect(sendToActiveUsers).toHaveBeenCalledTimes(1);
    expect(sendToActiveUsers.mock.calls[0][0].body).toContain('5 รายการ');
  });

  it('stays silent on a day with zero movements', async () => {
    const count = jest.fn().mockResolvedValue(0);
    const sendToActiveUsers = jest.fn();

    const scheduler = new DailySummaryReminderScheduler(
      { movement: { count } } as any,
      { sendToActiveUsers } as any,
    );

    await scheduler.handleCron();

    expect(sendToActiveUsers).not.toHaveBeenCalled();
  });
});
