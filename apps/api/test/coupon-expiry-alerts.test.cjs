const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');

function service() {
  const state = { coupons: [], claims: [], sends: [], history: [] };
  const db = { from(table) {
    const filters = [];
    let operation = 'select';
    let changes;
    const query = {
      select: () => query,
      is: (key, value) => { filters.push([key, value]); return query; },
      in: (key, value) => { filters.push([key, value]); return query; },
      order: () => query,
      range: () => Promise.resolve({ data: state.coupons.filter(row =>
        filters.every(([key, value]) => Array.isArray(value)
          ? value.includes(row[key]) : row[key] === value)), error: null }),
      insert: value => { operation = 'insert'; changes = value; return query; },
      update: value => { operation = 'update'; changes = value; return query; },
      eq: () => query,
      maybeSingle: async () => {
        if (state.claims.some(row => row.coupon_id === changes.coupon_id &&
          row.expires_on === changes.expires_on && row.days_before === changes.days_before)) {
          return { data: null, error: { code: '23505' } };
        }
        const row = { ...changes, id: `claim-${state.claims.length}` };
        state.claims.push(row);
        return { data: row, error: null };
      },
      then: (resolve, reject) => Promise.resolve(
        operation === 'update' ? { error: null, changes } : { data: [], error: null },
      ).then(resolve, reject),
    };
    assert.ok(['coupons', 'coupon_expiry_deliveries'].includes(table));
    return query;
  } };
  const mocks = {
    './fcm': { sendFcmNotification: async input => {
      state.sends.push(input); return { ok: true, messageId: 'sent' };
    } },
    './notifications': { recordPushNotificationHistory: async input => state.history.push(input) },
    './schedule-alerts': { listPushTokensByFamilyId: async ids =>
      new Map(ids.map(id => [id, [{ token: 'token', user_id: 'user' }]])) },
    './supabase': { getSupabaseAdmin: () => db },
  };
  const source = fs.readFileSync(path.join(__dirname, '../src/coupon-expiry-alerts.ts'), 'utf8');
  const output = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022,
  } }).outputText;
  const exports = {};
  new Function('require', 'exports', output)(name => mocks[name], exports);
  return { api: exports, state };
}

test('coupon reminders use Seoul date and only run during the 9am hour', () => {
  const { api } = service();
  assert.equal(api.couponAlertDates(new Date('2026-10-16T23:59:00Z')), null);
  assert.deepEqual(api.couponAlertDates(new Date('2026-10-17T00:00:00Z')), [
    { daysBefore: 1, expiresOn: '2026-10-18' },
    { daysBefore: 7, expiresOn: '2026-10-24' },
  ]);
  assert.equal(api.couponAlertDates(new Date('2026-10-17T01:00:00Z')), null);
});

test('unused coupons get 7/1 day pushes once; used and deleted coupons do not', async () => {
  const { api, state } = service();
  state.coupons.push(
    { id: 'seven', family_id: 'family', title: '커피', expires_on: '2026-10-24', used_at: null, deleted_at: null },
    { id: 'one', family_id: 'family', title: '빵', expires_on: '2026-10-18', used_at: null, deleted_at: null },
    { id: 'used', family_id: 'family', title: '사용함', expires_on: '2026-10-24', used_at: 'now', deleted_at: null },
    { id: 'deleted', family_id: 'family', title: '삭제함', expires_on: '2026-10-24', used_at: null, deleted_at: 'now' },
  );
  const now = new Date('2026-10-17T00:03:00Z');
  const first = await api.dispatchDueCouponExpiryAlerts(now);
  assert.equal(first.sentCouponCount, 2);
  assert.deepEqual(state.sends.map(item => item.data.couponId), ['seven', 'one']);
  assert.deepEqual(state.history.map(item => item.type), ['coupon_expiry', 'coupon_expiry']);
  await api.dispatchDueCouponExpiryAlerts(now);
  assert.equal(state.sends.length, 2);
});
