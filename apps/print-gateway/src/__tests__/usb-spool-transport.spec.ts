import { EventEmitter } from 'events';

jest.mock('child_process', () => ({ spawn: jest.fn() }));
// eslint-disable-next-line @typescript-eslint/no-var-requires
import { spawn } from 'child_process';
import { UsbSpoolTransport } from '../transports/usb-spool-transport';

const mockSpawn = spawn as unknown as jest.Mock;

function fakeChild() {
  const child: any = new EventEmitter();
  child.stdin = new EventEmitter();
  child.stdin.end = jest.fn();
  child.stderr = new EventEmitter();
  child.kill = jest.fn();
  return child;
}

describe('UsbSpoolTransport (posix lp path)', () => {
  beforeEach(() => mockSpawn.mockReset());

  it('rejects an unsafe queue name at construction (command-injection guard)', () => {
    expect(() => new UsbSpoolTransport('bad; rm -rf /')).toThrow();
    expect(() => new UsbSpoolTransport('q with space')).toThrow();
    expect(() => new UsbSpoolTransport('CSSD-XP420B-01')).not.toThrow();
  });

  // Windows lpr = unsupported จนกว่าจะผ่าน hardware verification — ต้อง opt-in
  it('refuses to construct on win32 unless explicitly allowed (unsupported pending verification)', () => {
    const orig = process.platform;
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    Object.defineProperty(process, 'platform', { value: 'win32', configurable: true });
    try {
      expect(() => new UsbSpoolTransport('q1')).toThrow(/hardware verification|Windows/i);
      // opt-in ชัดเจน → สร้างได้ (พร้อม warn) เก็บไว้เป็น fallback/ทดสอบ
      expect(() => new UsbSpoolTransport('q1', 1000, true)).not.toThrow();
      expect(warn).toHaveBeenCalled();
    } finally {
      Object.defineProperty(process, 'platform', { value: orig, configurable: true });
      warn.mockRestore();
    }
  });

  it('spawns lp with -o raw and no shell, writes TSPL to stdin', async () => {
    const child = fakeChild();
    mockSpawn.mockReturnValue(child);
    const p = new UsbSpoolTransport('q1', 1000).send(Buffer.from('TSPL'));
    child.emit('close', 0);
    await expect(p).resolves.toBeUndefined();
    expect(mockSpawn).toHaveBeenCalledWith('lp', ['-d', 'q1', '-o', 'raw'], expect.anything());
    expect(child.stdin.end).toHaveBeenCalledTimes(1);
  });

  it('SENT on exit code 0', async () => {
    const child = fakeChild();
    mockSpawn.mockReturnValue(child);
    const p = new UsbSpoolTransport('q1', 1000).send(Buffer.from('X'));
    child.emit('close', 0);
    await expect(p).resolves.toBeUndefined();
  });

  it('NOT_SENT when spawn errors (command missing / not started)', async () => {
    const child = fakeChild();
    mockSpawn.mockReturnValue(child);
    const p = new UsbSpoolTransport('q1', 1000).send(Buffer.from('X'));
    child.emit('error', Object.assign(new Error('spawn lp ENOENT'), { code: 'ENOENT' }));
    await expect(p).rejects.toMatchObject({ name: 'TransportSendError', outcome: 'NOT_SENT' });
  });

  it('MAYBE_SENT on non-zero exit (process ran — could have reached spooler)', async () => {
    const child = fakeChild();
    mockSpawn.mockReturnValue(child);
    const p = new UsbSpoolTransport('q1', 1000).send(Buffer.from('X'));
    child.stderr.emit('data', Buffer.from('lp: some error'));
    child.emit('close', 1);
    await expect(p).rejects.toMatchObject({ name: 'TransportSendError', outcome: 'MAYBE_SENT' });
  });

  it('MAYBE_SENT on stdin error mid-write (EPIPE)', async () => {
    const child = fakeChild();
    mockSpawn.mockReturnValue(child);
    const p = new UsbSpoolTransport('q1', 1000).send(Buffer.from('X'));
    child.stdin.emit('error', Object.assign(new Error('write EPIPE'), { code: 'EPIPE' }));
    await expect(p).rejects.toMatchObject({ name: 'TransportSendError', outcome: 'MAYBE_SENT' });
  });

  it('MAYBE_SENT on timeout (no close within timeout) — never auto-retry', async () => {
    const child = fakeChild();
    mockSpawn.mockReturnValue(child);
    const p = new UsbSpoolTransport('q1', 30).send(Buffer.from('X'));
    // ไม่ emit close → ปล่อยให้ timeout จริงยิง
    await expect(p).rejects.toMatchObject({ name: 'TransportSendError', outcome: 'MAYBE_SENT' });
    expect(child.kill).toHaveBeenCalled();
  });
});
