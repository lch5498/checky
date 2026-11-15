const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');

class HttpError extends Error {
  constructor(status, body) {
    super(body.error);
    this.status = status;
    this.body = body;
  }
}

// Minimal chainable stand-in for the supabase-js query builder, enough for briefings.ts.
function fakeDb(state) {
  const tableRows = (table) => ({
    briefing_settings: state.settings,
    briefing_deliveries: state.deliveries,
  })[table] ?? state[table] ?? [];
  function builder(table) {
    const filters = [];
    let operation = 'select';
    let changes;
    let orFilter;
    const apply = (rows) =>
      rows.filter((row) =>
        filters.every(([op, key, value]) => {
          switch (op) {
            case 'eq': return row[key] === value;
            case 'is': return row[key] === value;
            case 'gte': return row[key] >= value;
            case 'lte': return row[key] <= value;
            case 'gt': return row[key] > value;
            case 'lt': return row[key] < value;
            case 'in': return value.includes(row[key]);
            default: return true;
          }
        }) && (!orFilter || orFilter.some(([key, value]) => String(row[key]) === value)),
      );
    const result = () => {
      if (operation === 'insert') {
        if (table === 'briefing_deliveries') {
          const duplicate = state.deliveries.some(
            (row) => row.user_id === changes.user_id && row.briefing_kind === changes.briefing_kind
              && row.briefing_date === changes.briefing_date,
          );
          if (duplicate) return { data: null, error: { code: '23505' } };
          const row = { ...changes, id: `delivery-${state.deliveries.length}` };
          state.deliveries.push(row);
          return { data: row, error: null };
        }
        return { data: changes, error: null };
      }
      if (operation === 'update') {
        const id = filters.find(([op, key]) => op === 'eq' && key === 'id')?.[2];
        const row = state.deliveries.find((item) => item.id === id);
        if (row) Object.assign(row, changes);
        return { data: null, error: null };
      }
      if (operation === 'upsert') {
        const existing = state.settings.find((row) => row.user_id === changes.user_id);
        if (existing) Object.assign(existing, changes); else state.settings.push({ ...changes });
        return { data: state.settings.find((row) => row.user_id === changes.user_id), error: null };
      }
      const rows = apply(tableRows(table));
      return { data: rows, error: null };
    };
    const query = {
      select: () => query,
      insert: (value) => { operation = 'insert'; changes = value; return query; },
      update: (value) => { operation = 'update'; changes = value; return query; },
      upsert: (value) => { operation = 'upsert'; changes = value; return query; },
      order: () => query,
      limit: () => query,
      or: (expression) => {
        orFilter = expression.split(',').map((part) => {
          const [key, , value] = part.split('.');
          return [key, value];
        });
        return query;
      },
      maybeSingle: async () => {
        const { data, error } = result();
        return { data: Array.isArray(data) ? data[0] ?? null : data, error };
      },
      single: async () => {
        const { data, error } = result();
        return { data: Array.isArray(data) ? data[0] : data, error };
      },
      then: (resolve, reject) => Promise.resolve(result()).then(resolve, reject),
    };
    for (const op of ['eq', 'is', 'gte', 'lte', 'gt', 'lt', 'in']) {
      query[op] = (key, value) => { filters.push([op, key, value]); return query; };
    }
    return query;
  }
  return {
    from: (table) => builder(table),
    rpc: async (name, args) => {
      assert.equal(name, 'list_current_parking_records');
      return { data: state.parking.filter((row) => row.family_id === args.target_family_id), error: null };
    },
  };
}

function service() {
  const state = {
    settings: [], deliveries: [], schedules: [], coupons: [], travel_trips: [], vehicles: [], parking: [],
    families: {}, tokens: {}, sends: [], history: [],
  };
  const mocks = {
    './families': { listFamilies: async (userId) => (state.families[userId] ?? []).map((family) => ({ family })) },
    './fcm': { sendFcmNotification: async (input) => { state.sends.push(input); return { ok: true, messageId: 'sent' }; } },
    './http': { HttpError },
    './notifications': { recordPushNotificationHistory: async (input) => state.history.push(input) },
    './push-tokens': { listPushTokensForUser: async (userId) => state.tokens[userId] ?? [] },
    './supabase': { getSupabaseAdmin: () => fakeDb(state) },
    './validation': {
      optionalBoolean: (payload, key) => {
        const value = payload[key];
        if (value === undefined || value === null) return undefined;
        if (typeof value !== 'boolean') throw new HttpError(400, { error: 'invalid_payload', field: key });
        return value;
      },
    },
  };
  const source = fs.readFileSync(path.join(__dirname, '../src/briefings.ts'), 'utf8');
  const output = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022,
  } }).outputText;
  const exports = {};
  new Function('require', 'exports', output)((name) => mocks[name], exports);
  return { api: exports, state };
}

const seoul = (text) => new Date(`${text}+09:00`);

const family = (overrides = {}) => ({
  familyId: 'family', familyName: '우리집', schedules: [], parking: [], coupons: [], trips: [], ...overrides,
});
const schedule = (title, startsAt, overrides = {}) => ({
  title, startsAt: seoul(startsAt).toISOString(), endsAt: seoul(startsAt).toISOString(),
  isAllDay: false, memberNickname: null, ...overrides,
});

test('send time accepts HH:MM (with optional seconds) and rejects anything else', () => {
  const { api } = service();
  assert.equal(api.normalizeSendTime('08:00'), '08:00');
  assert.equal(api.normalizeSendTime('23:59:00'), '23:59');
  for (const bad of ['8:00', '24:00', '08:60', 'morning', 800, null]) {
    assert.throws(() => api.normalizeSendTime(bad), (error) => error.status === 400);
  }
});

test('daily briefings are due once their Seoul send time enters the lookback window', () => {
  const { api } = service();
  const due = (sendTime, start, end) => api.dueBriefingDates('daily', sendTime, seoul(start), seoul(end));
  assert.deepEqual(due('08:00', '2026-11-15T07:55:00', '2026-11-15T08:00:00'), ['2026-11-15']);
  assert.deepEqual(due('08:00', '2026-11-15T07:58:00', '2026-11-15T08:03:00'), ['2026-11-15']);
  assert.deepEqual(due('08:00', '2026-11-15T07:50:00', '2026-11-15T07:55:00'), []);
  assert.deepEqual(due('08:00', '2026-11-15T08:00:00', '2026-11-15T08:05:00'), []);
  // A window that crosses midnight still fires yesterday's 23:58 briefing.
  assert.deepEqual(due('23:58', '2026-11-15T23:57:00', '2026-11-16T00:02:00'), ['2026-11-15']);
});

test('weekly previews are due only on Sunday 20:00 Seoul', () => {
  const { api } = service();
  const due = (start, end) => api.dueBriefingDates('weekly', '08:00', seoul(start), seoul(end));
  assert.deepEqual(due('2026-11-15T19:58:00', '2026-11-15T20:03:00'), ['2026-11-15']); // Sunday
  assert.deepEqual(due('2026-11-16T19:58:00', '2026-11-16T20:03:00'), []); // Monday
  assert.deepEqual(due('2026-11-15T07:58:00', '2026-11-15T08:03:00'), []); // user's time is ignored
});

test('daily template lists today, parking, coupons and the nearest trip in order', () => {
  const { api } = service();
  const message = api.composeDailyBriefing('2026-11-15', [
    family({
      schedules: [
        schedule('학원', '2026-11-15T15:00:00', { memberNickname: '민준' }),
        schedule('치과', '2026-11-15T09:00:00', { memberNickname: '민준' }),
        schedule('가족 외식', '2026-11-15T00:00:00', { isAllDay: true }),
        schedule('저녁 약속', '2026-11-15T19:00:00'),
      ],
      parking: [
        { vehicleNickname: '아빠차', locationText: 'A동 B2 기둥 12' },
        { vehicleNickname: '엄마차', locationText: 'B동 B1' },
      ],
      coupons: [
        { title: '빵집', expiresOn: '2026-11-21' },
        { title: '스타벅스', expiresOn: '2026-11-20' },
      ],
      trips: [
        { title: '부산 여행', startsOn: '2026-12-24', endsOn: '2026-12-26' },
        { title: '제주 여행', startsOn: '2026-11-20', endsOn: '2026-11-23' },
      ],
    }),
  ]);
  assert.equal(message.title, '아침 브리핑 · 11/15 (일)');
  assert.equal(message.body, [
    '오늘 일정 4건',
    '· 종일 가족 외식',
    '· 09:00 치과 (민준)',
    '· 15:00 학원 (민준)',
    '· 외 1건',
    '주차 아빠차 A동 B2 기둥 12 · 엄마차 B동 B1',
    '쿠폰 2장 7일 내 만료 (스타벅스 11/20)',
    '제주 여행 D-5',
  ].join('\n'));
});

test('daily template handles empty days, single coupons, D-Day and ongoing trips', () => {
  const { api } = service();
  assert.equal(
    api.composeDailyBriefing('2026-11-15', [family()]).body,
    '오늘은 등록된 일정이 없어요.',
  );
  assert.equal(
    api.composeDailyBriefing('2026-11-15', [family({
      coupons: [{ title: '스타벅스', expiresOn: '2026-11-20' }],
      trips: [{ title: '제주 여행', startsOn: '2026-11-15', endsOn: '2026-11-17' }],
    })]).body,
    ['오늘 일정 없음', '쿠폰 스타벅스 11/20 만료', '제주 여행 D-Day'].join('\n'),
  );
  assert.equal(
    api.composeDailyBriefing('2026-11-16', [family({
      trips: [
        { title: '끝난 여행', startsOn: '2026-11-01', endsOn: '2026-11-02' },
        { title: '제주 여행', startsOn: '2026-11-15', endsOn: '2026-11-17' },
      ],
    })]).body,
    ['오늘 일정 없음', '제주 여행 2일차'].join('\n'),
  );
});

test('multiple groups are prefixed with their names', () => {
  const { api } = service();
  const message = api.composeDailyBriefing('2026-11-15', [
    family({ familyName: '우리집', schedules: [schedule('치과', '2026-11-15T09:00:00')] }),
    family({ familyName: '친가', parking: [{ vehicleNickname: '할아버지차', locationText: '마당' }] }),
  ]);
  assert.equal(message.body, [
    '[우리집]', '오늘 일정 1건', '· 09:00 치과',
    '[친가]', '오늘 일정 없음', '주차 할아버지차 마당',
  ].join('\n'));
});

test('weekly template summarizes the coming week', () => {
  const { api } = service();
  const message = api.composeWeeklyBriefing('2026-11-16', [
    family({
      schedules: [
        schedule('치과', '2026-11-17T09:00:00', { memberNickname: '민준' }),
        schedule('학원', '2026-11-17T15:00:00'),
        schedule('모임', '2026-11-20T19:00:00'),
        schedule('장보기', '2026-11-21T10:00:00'),
      ],
      coupons: [{ title: '빵집', expiresOn: '2026-11-21' }, { title: '카페', expiresOn: '2026-11-22' }],
      trips: [
        { title: '제주 여행', startsOn: '2026-11-20', endsOn: '2026-11-23' },
        { title: '먼 여행', startsOn: '2026-12-20', endsOn: '2026-12-23' },
      ],
    }),
  ]);
  assert.equal(message.title, '주간 미리보기 · 11/16 (월) ~ 11/22 (일)');
  assert.equal(message.body, [
    '이번 주 일정 4건 (화 2 · 금 1 · 토 1)',
    '· 11/17 (화) 09:00 치과 (민준)',
    '· 11/17 (화) 15:00 학원',
    '· 11/20 (금) 19:00 모임',
    '· 외 1건',
    '제주 여행 11/20 ~ 11/23',
    '쿠폰 2장 이번 주 만료 (빵집 11/21)',
  ].join('\n'));
  assert.equal(api.composeWeeklyBriefing('2026-11-16', [family()]).body, '이번 주 일정 없음');
});

test('settings default off and partial updates keep the other fields', async () => {
  const { api, state } = service();
  assert.deepEqual(await api.getBriefingSettings('user'), {
    enabled: false, sendTime: '08:00', weeklyPreviewEnabled: false,
  });
  assert.deepEqual(await api.updateBriefingSettings('user', { enabled: true }), {
    enabled: true, sendTime: '08:00', weeklyPreviewEnabled: false,
  });
  assert.deepEqual(await api.updateBriefingSettings('user', { sendTime: '07:30' }), {
    enabled: true, sendTime: '07:30', weeklyPreviewEnabled: false,
  });
  assert.equal(state.settings.length, 1);
  await assert.rejects(api.updateBriefingSettings('user', { sendTime: 'soon' }), (error) => error.status === 400);
});

test('due briefings are sent once per day, recorded, and skipped without tokens', async () => {
  const { api, state } = service();
  state.settings.push(
    { user_id: 'alice', enabled: true, send_time: '08:00:00', weekly_preview_enabled: false },
    { user_id: 'bob', enabled: true, send_time: '08:00:00', weekly_preview_enabled: false },
    { user_id: 'carol', enabled: true, send_time: '09:00:00', weekly_preview_enabled: false },
  );
  state.families.alice = [{ id: 'family', name: '우리집' }];
  state.families.bob = [{ id: 'family', name: '우리집' }];
  state.tokens.alice = [{ id: 't1', token: 'alice-token', platform: 'ios' }];
  state.schedules.push({
    family_id: 'family', title: '치과', is_all_day: false,
    starts_at: seoul('2026-11-15T09:00:00').toISOString(), ends_at: seoul('2026-11-15T10:00:00').toISOString(),
    family_member: { nickname: '민준' },
  }, {
    family_id: 'family', title: '내일 일정', is_all_day: false,
    starts_at: seoul('2026-11-16T09:00:00').toISOString(), ends_at: seoul('2026-11-16T10:00:00').toISOString(),
    family_member: null,
  });
  state.coupons.push({ family_id: 'family', title: '스타벅스', expires_on: '2026-11-20', used_at: null, deleted_at: null });
  state.vehicles.push({ id: 'v1', nickname: '아빠차' });
  state.parking.push({ family_id: 'family', vehicle_id: 'v1', location_text: 'A동 B2', parked_at: '2026-11-14T00:00:00Z' });

  const now = seoul('2026-11-15T08:02:00');
  const first = await api.dispatchDueBriefings(now);
  assert.equal(first.dueCount, 2);
  assert.equal(first.sentCount, 1);
  assert.deepEqual(first.briefings.map((item) => [item.userId, item.status]), [
    ['alice', 'sent'], ['bob', 'no_targets'],
  ]);
  assert.equal(state.sends.length, 1);
  assert.equal(state.sends[0].title, '아침 브리핑 · 11/15 (일)');
  assert.equal(state.sends[0].body, [
    '오늘 일정 1건', '· 09:00 치과 (민준)', '주차 아빠차 A동 B2', '쿠폰 스타벅스 11/20 만료',
  ].join('\n'));
  assert.deepEqual(state.sends[0].data, {
    type: 'briefing_daily', kind: 'daily', date: '2026-11-15', familyId: 'family',
  });
  assert.equal(state.history.length, 1);
  assert.equal(state.history[0].type, 'briefing_daily');
  assert.equal(state.deliveries.find((row) => row.user_id === 'alice').status, 'sent');
  assert.equal(state.deliveries.find((row) => row.user_id === 'bob').status, 'no_targets');

  const second = await api.dispatchDueBriefings(seoul('2026-11-15T08:04:00'));
  assert.deepEqual(second.briefings.map((item) => item.status), ['already_claimed', 'already_claimed']);
  assert.equal(state.sends.length, 1);
});
