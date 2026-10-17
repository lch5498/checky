const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');

function service() {
  const state = {
    vehicle: { id: 'vehicle', family_id: 'family', parking_photo_record_id: null },
    currentId: 'record', storage: [],
  };
  const db = {
    from(table) {
      let operation = 'select';
      let patch;
      const query = {
        select: () => query, eq: () => query, order: () => query,
        limit: () => query,
        update: value => { operation = 'update'; patch = value; return query; },
        maybeSingle: async () => ({ data: table === 'vehicles' ? state.vehicle :
          { id: state.currentId }, error: null }),
        then: (resolve, reject) => {
          if (operation === 'update' && table === 'vehicles')
            Object.assign(state.vehicle, patch);
          return Promise.resolve({ error: null }).then(resolve, reject);
        },
      };
      return query;
    },
    storage: { from: bucket => {
      assert.equal(bucket, 'parking-photos');
      return {
        upload: async (key, bytes, options) => {
          state.storage.push(['upload', key, options.upsert, options.contentType]);
          return { error: null };
        },
        download: async key => {
          state.storage.push(['download', key]);
          return { data: new Blob(['photo'], { type: 'image/jpeg' }), error: null };
        },
        remove: async keys => {
          state.storage.push(['remove', ...keys]);
          return { error: null };
        },
      };
    } },
  };
  const mocks = {
    './families': {
      requireFamilyManager: async (user, family) => {
        if (user !== 'owner' || family !== 'family') throw { status: 403 };
      },
      requireMembership: async (user, family) => {
        if (!['owner', 'viewer'].includes(user) || family !== 'family')
          throw { status: 403 };
      },
    },
    './group-activity-logs': { recordGroupActivity: async () => {} },
    './group-refresh': { scheduleGroupRefresh: () => {} },
    './http': { HttpError: class HttpError extends Error {
      constructor(status, body) { super(body.error); this.status = status; }
    } },
    './supabase': { getSupabaseAdmin: () => db },
  };
  const source = fs.readFileSync(path.join(__dirname, '../src/parking.ts'), 'utf8');
  const output = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022,
  } }).outputText;
  const exports = {};
  new Function('require', 'exports', output)(name => mocks[name], exports);
  return { api: exports, state };
}

test('only current parking photo is served and replacement uses one vehicle path', async () => {
  const { api, state } = service();
  const bytes = Buffer.from('photo');
  await assert.rejects(api.saveCurrentParkingPhoto('viewer', 'family', 'vehicle',
    'record', bytes, 'image/jpeg'), { status: 403 });
  await assert.rejects(api.saveCurrentParkingPhoto('owner', 'family', 'vehicle',
    'old-record', bytes, 'image/jpeg'), { status: 409 });
  await api.saveCurrentParkingPhoto('owner', 'family', 'vehicle',
    'record', bytes, 'image/jpeg');
  await api.saveCurrentParkingPhoto('owner', 'family', 'vehicle',
    'record', bytes, 'image/jpeg');
  assert.deepEqual(state.storage.slice(0, 2), [
    ['upload', 'family/vehicle.photo', true, 'image/jpeg'],
    ['upload', 'family/vehicle.photo', true, 'image/jpeg'],
  ]);
  assert.equal(state.vehicle.parking_photo_record_id, 'record');
  const response = await api.currentParkingPhotoResponse('viewer', 'family', 'vehicle');
  assert.equal(response.status, 200);
  await assert.rejects(api.currentParkingPhotoResponse('outsider', 'family', 'vehicle'),
    { status: 403 });
  state.currentId = 'new-record';
  await assert.rejects(api.currentParkingPhotoResponse('viewer', 'family', 'vehicle'),
    { status: 404 });
});
