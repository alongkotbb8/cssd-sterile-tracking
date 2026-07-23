import * as fs from 'fs';
import * as path from 'path';

/**
 * Master directive A2.2 — guard: every stable error `code:` thrown anywhere in
 * the backend source must be declared in the cross-language registry
 * (packages/shared/error-codes.json). This prevents the backend from adding a
 * new code that the Flutter client (and the mobile mapping test) never learns
 * about. The mobile side (apps/mobile/test/error_code_mapping_test.dart) asserts
 * the reverse: every registry "client" code has a th+en mapping.
 */
const registry = JSON.parse(
  fs.readFileSync(
    path.join(__dirname, '../../../../packages/shared/error-codes.json'),
    'utf8',
  ),
) as { client: string[]; internal: string[] };

const KNOWN = new Set([...registry.client, ...registry.internal]);

function walk(dir: string): string[] {
  const out: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === 'node_modules') continue;
      out.push(...walk(full));
    } else if (entry.name.endsWith('.ts') && !entry.name.endsWith('.spec.ts')) {
      out.push(full);
    }
  }
  return out;
}

describe('backend error-code registry (directive A2.2)', () => {
  const srcRoot = path.join(__dirname, '..');
  // จับทั้ง `code: 'XXX'` (HttpException) และ `errorCode: 'XXX'` (scan per-item result)
  const codeLiteral = /\b(?:code|errorCode):\s*['"]([A-Z][A-Z0-9_]+)['"]/g;

  const found = new Map<string, string[]>(); // code -> files
  beforeAll(() => {
    for (const file of walk(srcRoot)) {
      const text = fs.readFileSync(file, 'utf8');
      for (const m of text.matchAll(codeLiteral)) {
        const code = m[1];
        found.set(code, [...(found.get(code) ?? []), path.relative(srcRoot, file)]);
      }
    }
  });

  it('พบ code ที่ throw จริงอย่างน้อยหนึ่งตัว (sanity)', () => {
    expect(found.size).toBeGreaterThan(10);
  });

  it('ทุก code ที่ throw ถูกประกาศใน error-codes.json (client หรือ internal)', () => {
    const undeclared: string[] = [];
    for (const [code, files] of found) {
      if (!KNOWN.has(code)) undeclared.push(`${code} (${files.join(', ')})`);
    }
    expect(undeclared).toEqual([]);
  });

  it('ทุก client code ในทะเบียนถูก throw จากที่ใดที่หนึ่งจริง (กันทะเบียนค้าง)', () => {
    // internal บางตัว (เช่น session/gateway) throw ในโค้ด — client ทุกตัวควรมีที่ throw
    const orphan = registry.client.filter((c) => !found.has(c));
    expect(orphan).toEqual([]);
  });

  it('client และ internal ไม่ทับซ้อนกัน', () => {
    const overlap = registry.client.filter((c) => registry.internal.includes(c));
    expect(overlap).toEqual([]);
  });
});
