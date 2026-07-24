import { config } from './config';
import { ApiClient } from './api-client';
import { processOneJob } from './poll-loop';
import { ConsoleTransport } from './transports/console-transport';
import { SerialTransport } from './transports/serial-transport';
import { UsbSpoolTransport } from './transports/usb-spool-transport';
import { PrinterTransport } from './transports/transport';

function makeTransport(name: string): PrinterTransport {
  switch (name) {
    case 'console':
      return new ConsoleTransport();
    case 'serial': {
      if (!config.serialPath) {
        throw new Error('PRINTER_TRANSPORT=serial ต้องตั้งค่า PRINTER_SERIAL_PATH ด้วย (เช่น /dev/tty.usbserial-xxxx)');
      }
      return new SerialTransport(config.serialPath, config.serialBaudRate);
    }
    case 'usb_spool':
      // Xprinter XP-420B USB (printer-class) → ส่ง raw TSPL เข้า OS printer queue
      // Pilot: Raspberry Pi/Linux + CUPS (lp -o raw); Windows lpr = unsupported (opt-in)
      return new UsbSpoolTransport(
        config.printerQueueName,
        config.spoolTimeoutMs,
        config.allowUnverifiedWindowsSpool,
      );
    default:
      throw new Error(
        `Unknown PRINTER_TRANSPORT "${name}" — รองรับ "console" (mock), "serial", "usb_spool" เท่านั้น`,
      );
  }
}

async function main() {
  console.log('=== CSSD Print Gateway ===');
  console.log(`API: ${config.apiBaseUrl}`);
  console.log(`Transport: ${config.printerTransport}`);

  const api = new ApiClient(config.apiBaseUrl, config.gatewayApiKey);
  const transport = makeTransport(config.printerTransport);

  // Heartbeat แยก interval จาก poll loop — ให้ backend รู้ว่า gateway ยังออนไลน์
  // อยู่แม้ตอนนั้นไม่มีงานพิมพ์ (ใช้ตรวจสุขภาพ ไม่ใช่ตัวตัดสินความอยู่รอดของ job)
  setInterval(() => {
    api.heartbeat().catch((e) => console.error('[gateway] heartbeat failed:', e));
  }, config.heartbeatIntervalMs);
  await api.heartbeat().catch((e) => console.error('[gateway] initial heartbeat failed:', e));

  console.log('Polling for print jobs...');
  // eslint-disable-next-line no-constant-condition
  while (true) {
    try {
      const handled = await processOneJob(api, transport);
      if (!handled) {
        await sleep(config.pollIntervalMs);
      }
      // มีงาน → poll ต่อทันที (ไม่ sleep) เผื่อมีคิวค้างอีก
    } catch (e) {
      console.error('[gateway] poll loop error:', e);
      await sleep(config.pollIntervalMs);
    }
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

main().catch((e) => {
  console.error('[gateway] fatal error, exiting:', e);
  process.exit(1);
});
