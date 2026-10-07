const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');

// Isolate the service from Supabase while exercising its actual permission and version logic.
function service() {
  const state = { role: 'member', rows: [], members: [], calls: 0, storage: [], insertError: false };
  const cache = {};
  function load(name) {
    if (cache[name]) return cache[name];
    if (name === './families') return { requireMembership: async (_user, family) => {
      if (family !== 'allowed') throw new (load('./http').HttpError)(403, { error: 'family_access_denied' });
      return { role: state.role };
    }};
    if (name === './supabase') return { getSupabaseAdmin: () => {
      state.calls++;
      return {
        from: (table) => {
          const filters = [];
          let operation = 'select', change, countOnly = false, many = table === 'family_members';
          const execute = () => {
            if (operation === 'insert') {
              if (state.insertError) return { error: state.insertError === true ? new Error('insert failed') : state.insertError, data: null };
              const row = { ...change, version: 1, deleted_at: null };
              state.rows.push(row);
              return { data: row, error: null };
            }
            const rows = (table === 'family_members' ? state.members : state.rows)
              .filter(r => filters.every(([k, v]) => Array.isArray(v) ? v.includes(r[k]) : r[k] === v));
            if (countOnly) return { data: null, count: rows.length, error: null };
            if (operation === 'update') rows.forEach(r => Object.assign(r, change));
            if (operation === 'delete') state.rows = state.rows.filter(r => !rows.includes(r));
            return { data: many ? rows.map(r => ({ ...r })) : rows[0] ? { ...rows[0] } : null, error: null };
          };
          const query = {
            eq: (k, v) => { filters.push([k, v]); return query; },
            is: (k, v) => { filters.push([k, v]); return query; },
            in: (k, v) => { filters.push([k, v]); return query; },
            order: () => query,
            range: () => { many = true; return query; },
            select: (_columns, options) => { countOnly = options?.head === true; return query; },
            update: value => { operation = 'update'; change = value; return query; },
            insert: value => { operation = 'insert'; change = value; return query; },
            delete: () => { operation = 'delete'; return query; },
            maybeSingle: async () => execute(), single: async () => execute(),
            then: (resolve, reject) => Promise.resolve(execute()).then(resolve, reject),
          };
          return query;
        },
        storage: { from: () => ({
          upload: async (key, bytes, options) => { state.storage.push(['upload', key, options.contentType]); return { error: null }; },
          remove: async keys => { state.storage.push(['remove', ...keys]); return { error: null }; },
          download: async key => { state.storage.push(['download', key]); return { data: new Blob(['image'], { type: 'image/png' }), error: null }; },
        }) },
      };
    }};
    if (name.startsWith('node:')) return require(name);
    const source = fs.readFileSync(path.join(__dirname, '../src', `${name.slice(2)}.ts`), 'utf8');
    const output = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
    const exports = {};
    cache[name] = exports;
    new Function('require', 'exports', output)(load, exports);
    return exports;
  }
  return { api: load('./coupons'), state };
}
const request = body => new Request('https://test', { method: 'POST', body: JSON.stringify(body) });
const row = () => ({ id: 'coupon', family_id: 'allowed', title: '커피', memo: '', expires_on: null,
  image_path: 'allowed/coupon.png', created_by_user_id: 'creator', used_at: null, version: 1, deleted_at: null });

test('all coupon operations reject another group before DB/storage access', async () => {
  const { api, state } = service();
  const actions = [() => api.listCoupons('user', 'other'), () => api.getCoupon('user', 'other', 'coupon'),
    () => api.createCoupon('user', 'other', request({})), () => api.updateCoupon('user', 'other', 'coupon', request({})),
    () => api.deleteCoupon('user', 'other', 'coupon', request({})), () => api.couponImageResponse('user', 'other', 'coupon')];
  for (const action of actions) await assert.rejects(action(), { status: 403 });
  assert.equal(state.calls, 0);
});
test('members can mark used; stale updates cannot overwrite the winner', async () => {
  const { api, state } = service(); state.rows.push(row());
  state.members.push({ family_id: 'allowed', user_id: 'user', nickname: '민수' },
    { family_id: 'other', user_id: 'user', nickname: '다른 그룹 이름' });
  const result = await api.updateCoupon('user', 'allowed', 'coupon', request({ version: 1, used: true }));
  assert.equal(result.version, 2); assert.equal(result.used_by_user_id, 'user');
  assert.equal(result.used_by_name, '민수');
  assert.equal(result.can_manage, false); assert.equal(result.image_path, undefined);
  await assert.rejects(api.updateCoupon('creator', 'allowed', 'coupon', request({ version: 1, used: false })), { status: 409 });
  assert.equal(state.rows[0].used_by_user_id, 'user');
});

test('list/detail resolve existing completion names only in the coupon group; undo clears attribution', async () => {
  const { api, state } = service();
  state.rows.push({ ...row(), used_at: '2026-10-08', used_by_user_id: 'user' });
  state.members.push({ family_id: 'allowed', user_id: 'user', nickname: '엄마' },
    { family_id: 'other', user_id: 'user', nickname: '다른 그룹' });
  assert.equal((await api.listCoupons('viewer', 'allowed')).coupons[0].used_by_name, '엄마');
  assert.equal((await api.getCoupon('viewer', 'allowed', 'coupon')).used_by_name, '엄마');
  state.members = state.members.filter(m => m.family_id === 'other');
  assert.equal((await api.getCoupon('viewer', 'allowed', 'coupon')).used_by_name, null);
  const canceled = await api.updateCoupon('viewer', 'allowed', 'coupon', request({ version: 1, used: false }));
  assert.equal(canceled.used_by_name, null);
  assert.equal(canceled.used_by_user_id, null);
  assert.equal(canceled.used_at, null);
});
test('metadata and deletion require creator or group owner', async () => {
  const { api, state } = service(); state.rows.push(row());
  await assert.rejects(api.updateCoupon('user', 'allowed', 'coupon', request({ version: 1, title: 'new' })), { status: 403 });
  await assert.rejects(api.deleteCoupon('user', 'allowed', 'coupon', request({ version: 1 })), { status: 403 });
  state.role = 'owner';
  const result = await api.updateCoupon('owner', 'allowed', 'coupon', request({ version: 1, title: 'new' }));
  assert.equal(result.title, 'new');
  await api.deleteCoupon('owner', 'allowed', 'coupon', request({ version: 2 }));
  assert.equal(state.rows.length, 0); assert.deepEqual(state.storage, [['remove', 'allowed/coupon.png']]);
});
test('image response checks the coupon family and hides deleted coupons', async () => {
  const { api, state } = service(); state.rows.push({ ...row(), family_id: 'other' });
  await assert.rejects(api.couponImageResponse('user', 'allowed', 'coupon'), { status: 404 });
  state.rows[0].family_id = 'allowed'; state.rows[0].deleted_at = 'today';
  await assert.rejects(api.couponImageResponse('user', 'allowed', 'coupon'), { status: 404 });
  assert.equal(state.storage.length, 0);
  state.rows[0].deleted_at = null;
  const response = await api.couponImageResponse('user', 'allowed', 'coupon');
  assert.equal(response.headers.get('cache-control'), 'private, no-store');
});
test('failed metadata insert removes the uploaded image', async () => {
  const { api, state } = service(); state.insertError = true;
  const image = Buffer.from([137,80,78,71,13,10,26,10,0,0,0,0]).toString('base64');
  await assert.rejects(api.createCoupon('user', 'allowed', request({ title: '커피', imageBase64: image })), /insert failed/);
  assert.equal(state.storage[0][0], 'upload'); assert.equal(state.storage[0][2], 'image/png');
  assert.deepEqual(state.storage[1], ['remove', state.storage[0][1]]);
});

test('100 stored images blocks uploads, including used, expired and cleanup-pending coupons', async () => {
  const { api, state } = service();
  state.rows = Array.from({ length: 100 }, (_, i) => ({ ...row(), id: String(i),
    used_at: i % 2 ? '2026-01-01' : null, expires_on: '2020-01-01', deleted_at: i === 99 ? 'today' : null }));
  const image = Buffer.from([137,80,78,71,13,10,26,10,0,0,0,0]).toString('base64');
  await assert.rejects(api.createCoupon('user', 'allowed', request({ title: '커피', imageBase64: image })),
    e => e.status === 409 && e.body.error === 'coupon_limit_reached');
  assert.equal(state.storage.length, 0);
  state.rows.pop();
  await api.createCoupon('user', 'allowed', request({ title: '커피', imageBase64: image }));
  assert.equal(state.rows.length, 100);
});

test('concurrent DB quota rejection cleans up the uploaded file and returns a friendly conflict', async () => {
  const { api, state } = service();
  const image = Buffer.from([137,80,78,71,13,10,26,10,0,0,0,0]).toString('base64');
  for (const error of [{ code: 'P0001', message: 'coupon_limit_reached' },
    { code: '23505', message: 'duplicate key violates unique constraint "coupons_family_image_slot_key"' }]) {
    state.insertError = error;
    await assert.rejects(api.createCoupon('user', 'allowed', request({ title: '커피', imageBase64: image })),
      e => e.status === 409 && e.body.error === 'coupon_limit_reached');
    assert.equal(state.storage.at(-1)[0], 'remove');
  }
});
