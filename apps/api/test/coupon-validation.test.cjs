// Compile only the pure validation module to a temporary CJS directory; no DB or secrets needed.
// Run: node --test apps/api/test/coupon-validation.test.cjs
const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const ts = require('typescript');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'checky-coupon-test-'));
for (const name of ['http', 'validation', 'coupon-validation']) {
  const source = fs.readFileSync(path.join(__dirname, '../src', `${name}.ts`), 'utf8');
  fs.writeFileSync(path.join(temp, `${name}.js`), ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText);
}
after(() => fs.rmSync(temp, { recursive: true, force: true }));
const { couponFields, couponImage, couponVersion, readCouponPayload } = require(path.join(temp, 'coupon-validation.js'));

test('coupon fields validate real dates and optional expiry', () => {
  assert.equal(couponFields({ title: ' 커피 ' }).title, '커피');
  assert.equal(couponFields({ title: '커피' }).expires_on, null);
  assert.equal(couponFields({ title: '커피', expiresOn: '2028-02-29' }).expires_on, '2028-02-29');
  for (const date of ['0000-01-01', '2026-02-29', '2026-02-30', '2026-13-01', '2026-1-1', 'today', 123]) {
    assert.throws(() => couponFields({ title: '커피', expiresOn: date }), { status: 400 });
  }
  assert.throws(() => couponFields({ title: ' ' }), { status: 400 });
  assert.throws(() => couponFields({ title: 'x', memo: 'a'.repeat(1001) }), { status: 400 });
});
test('coupon number preserves leading zeros and can be omitted or cleared', () => {
  assert.equal(couponFields({ title: '커피' }).coupon_number, undefined);
  assert.equal(couponFields({ title: '커피', couponNumber: ' 0012-AB ' }).coupon_number, '0012-AB');
  assert.equal(couponFields({ title: '커피', couponNumber: '' }).coupon_number, '');
  for (const couponNumber of [123, 'x'.repeat(129), 'AB\nCD']) {
    assert.throws(() => couponFields({ title: '커피', couponNumber }),
      error => error.status === 400 && error.body.field === 'couponNumber');
  }
});
test('images reject active content, invalid encoding and oversized data', () => {
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j5e0AAAAASUVORK5CYII=', 'base64');
  assert.equal(couponImage(png.toString('base64')).contentType, 'image/png');
  assert.throws(() => couponImage(Buffer.from('<svg onload="alert(1)"></svg>').toString('base64')), { status: 400 });
  assert.throws(() => couponImage('not!base64'), { status: 400 });
  assert.throws(() => couponImage(Buffer.alloc(2097153).toString('base64')), { status: 413 });
});
test('version is mandatory and bounded to safe positive integers', () => {
  assert.equal(couponVersion({ version: 2 }), 2);
  for (const version of [undefined, '2', 0, -1, 1.5, 2147483647, Number.MAX_SAFE_INTEGER + 1])
    assert.throws(() => couponVersion({ version }), { status: 400 });
});
test('body reader limits actual bytes even without Content-Length', async () => {
  assert.deepEqual(await readCouponPayload(new Request('https://test', { method: 'POST', body: '{"title":"커피"}' })), { title: '커피' });
  await assert.rejects(readCouponPayload(new Request('https://test', { method: 'POST', body: '[]' })), { status: 400 });
  await assert.rejects(readCouponPayload(new Request('https://test', { method: 'POST', body: 'a'.repeat(3 * 1024 * 1024 + 1) })), { status: 413 });
});
