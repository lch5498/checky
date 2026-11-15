import { listFamilies } from './families';
import { sendFcmNotification, type FcmSendResult } from './fcm';
import { HttpError } from './http';
import { recordPushNotificationHistory } from './notifications';
import { listPushTokensForUser } from './push-tokens';
import { getSupabaseAdmin } from './supabase';
import { optionalBoolean } from './validation';

// Briefings are deterministic templates: same input, same text. No generative AI.
// All wall-clock reasoning uses Asia/Seoul, like the coupon expiry alerts.

const SEOUL_OFFSET_MS = 9 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const DEFAULT_LOOKBACK_MINUTES = 5;
const MAX_SCHEDULE_LINES = 3;
const COUPON_WINDOW_DAYS = 7;
const WEEKDAY_LABELS = ['일', '월', '화', '수', '목', '금', '토'];

/// Sunday evening, Asia/Seoul. Fixed; only the toggle is user-facing.
export const BRIEFING_WEEKLY_TIME = '20:00';

export type BriefingKind = 'daily' | 'weekly';

export type BriefingSettings = {
  enabled: boolean;
  /** `HH:MM`, Asia/Seoul. */
  sendTime: string;
  weeklyPreviewEnabled: boolean;
};

export const DEFAULT_BRIEFING_SETTINGS: BriefingSettings = {
  enabled: false,
  sendTime: '08:00',
  weeklyPreviewEnabled: false,
};

type SettingsRow = {
  user_id: string;
  enabled: boolean;
  send_time: string;
  weekly_preview_enabled: boolean;
};

export type BriefingSchedule = {
  title: string;
  startsAt: string;
  endsAt: string;
  isAllDay: boolean;
  memberNickname: string | null;
};

export type BriefingFamilyData = {
  familyId: string;
  familyName: string;
  schedules: BriefingSchedule[];
  parking: Array<{ vehicleNickname: string; locationText: string }>;
  coupons: Array<{ title: string; expiresOn: string }>;
  trips: Array<{ title: string; startsOn: string; endsOn: string }>;
};

export type BriefingMessage = { title: string; body: string };

// ---------------------------------------------------------------------------
// Settings

export function normalizeSendTime(value: unknown) {
  if (typeof value !== 'string') {
    throw new HttpError(400, { error: 'invalid_payload', field: 'sendTime' });
  }

  const match = /^([01]\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?$/.exec(value.trim());

  if (!match) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'sendTime' });
  }

  return `${match[1]}:${match[2]}`;
}

function presentSettings(row: SettingsRow | null): BriefingSettings {
  if (!row) {
    return { ...DEFAULT_BRIEFING_SETTINGS };
  }

  return {
    enabled: row.enabled,
    sendTime: normalizeSendTime(row.send_time),
    weeklyPreviewEnabled: row.weekly_preview_enabled,
  };
}

export async function getBriefingSettings(userId: string) {
  const { data, error } = await getSupabaseAdmin()
    .from('briefing_settings')
    .select('user_id, enabled, send_time, weekly_preview_enabled')
    .eq('user_id', userId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  return presentSettings((data as SettingsRow | null) ?? null);
}

export async function updateBriefingSettings(
  userId: string,
  payload: Record<string, unknown>,
) {
  const current = await getBriefingSettings(userId);
  const next: BriefingSettings = {
    enabled: optionalBoolean(payload, 'enabled') ?? current.enabled,
    sendTime:
      payload.sendTime === undefined || payload.sendTime === null
        ? current.sendTime
        : normalizeSendTime(payload.sendTime),
    weeklyPreviewEnabled:
      optionalBoolean(payload, 'weeklyPreviewEnabled') ?? current.weeklyPreviewEnabled,
  };

  const { data, error } = await getSupabaseAdmin()
    .from('briefing_settings')
    .upsert(
      {
        user_id: userId,
        enabled: next.enabled,
        send_time: next.sendTime,
        weekly_preview_enabled: next.weeklyPreviewEnabled,
      },
      { onConflict: 'user_id' },
    )
    .select('user_id, enabled, send_time, weekly_preview_enabled')
    .single();

  if (error) {
    throw error;
  }

  return presentSettings(data as SettingsRow);
}

// ---------------------------------------------------------------------------
// Seoul calendar helpers (exported for tests)

/** `YYYY-MM-DD` of the instant in Asia/Seoul. */
export function seoulDateKey(instant: Date) {
  return new Date(instant.getTime() + SEOUL_OFFSET_MS).toISOString().slice(0, 10);
}

/** The instant at `HH:MM` Asia/Seoul on the given `YYYY-MM-DD`. */
export function seoulInstant(dateKey: string, time: string) {
  const [year, month, day] = dateKey.split('-').map(Number);
  const [hour, minute] = time.split(':').map(Number);
  return new Date(Date.UTC(year, month - 1, day, hour, minute) - SEOUL_OFFSET_MS);
}

export function addDays(dateKey: string, days: number) {
  const [year, month, day] = dateKey.split('-').map(Number);
  return new Date(Date.UTC(year, month - 1, day) + days * DAY_MS).toISOString().slice(0, 10);
}

function weekdayOf(dateKey: string) {
  const [year, month, day] = dateKey.split('-').map(Number);
  return new Date(Date.UTC(year, month - 1, day)).getUTCDay();
}

function daysBetween(fromKey: string, toKey: string) {
  const [fy, fm, fd] = fromKey.split('-').map(Number);
  const [ty, tm, td] = toKey.split('-').map(Number);
  return Math.round((Date.UTC(ty, tm - 1, td) - Date.UTC(fy, fm - 1, fd)) / DAY_MS);
}

/** `11/15 (토)` */
export function formatDateLabel(dateKey: string) {
  const [, month, day] = dateKey.split('-').map(Number);
  return `${month}/${day} (${WEEKDAY_LABELS[weekdayOf(dateKey)]})`;
}

/** `11/15` */
function formatShortDate(dateKey: string) {
  const [, month, day] = dateKey.split('-').map(Number);
  return `${month}/${day}`;
}

function formatSeoulTime(instant: string) {
  const seoul = new Date(new Date(instant).getTime() + SEOUL_OFFSET_MS);
  const hours = String(seoul.getUTCHours()).padStart(2, '0');
  const minutes = String(seoul.getUTCMinutes()).padStart(2, '0');
  return `${hours}:${minutes}`;
}

/**
 * Seoul dates whose briefing of `kind` falls in (windowStart, windowEnd].
 * The day before is checked too so a window that crosses midnight still fires.
 */
export function dueBriefingDates(
  kind: BriefingKind,
  sendTime: string,
  windowStart: Date,
  windowEnd: Date,
) {
  const today = seoulDateKey(windowEnd);
  const time = kind === 'weekly' ? BRIEFING_WEEKLY_TIME : sendTime;

  return [addDays(today, -1), today].filter((dateKey) => {
    if (kind === 'weekly' && weekdayOf(dateKey) !== 0) {
      return false;
    }

    const dueAt = seoulInstant(dateKey, time).getTime();
    return dueAt > windowStart.getTime() && dueAt <= windowEnd.getTime();
  });
}

// ---------------------------------------------------------------------------
// Templates (pure)

function scheduleLine(schedule: BriefingSchedule, withDate: boolean) {
  const when = schedule.isAllDay ? '종일' : formatSeoulTime(schedule.startsAt);
  const date = withDate ? `${formatDateLabel(seoulDateKey(new Date(schedule.startsAt)))} ` : '';
  const member = schedule.memberNickname?.trim();
  return `· ${date}${when} ${schedule.title}${member ? ` (${member})` : ''}`;
}

function scheduleLines(schedules: BriefingSchedule[], withDate: boolean) {
  const sorted = [...schedules].sort((a, b) => a.startsAt.localeCompare(b.startsAt));
  const lines = sorted.slice(0, MAX_SCHEDULE_LINES).map((schedule) => scheduleLine(schedule, withDate));

  if (sorted.length > MAX_SCHEDULE_LINES) {
    lines.push(`· 외 ${sorted.length - MAX_SCHEDULE_LINES}건`);
  }

  return lines;
}

function couponLine(coupons: BriefingFamilyData['coupons'], horizon: string) {
  if (coupons.length === 0) {
    return null;
  }

  const sorted = [...coupons].sort((a, b) => a.expiresOn.localeCompare(b.expiresOn));
  const first = sorted[0];

  if (sorted.length === 1) {
    return `쿠폰 ${first.title} ${formatShortDate(first.expiresOn)} 만료`;
  }

  return `쿠폰 ${sorted.length}장 ${horizon} 만료 (${first.title} ${formatShortDate(first.expiresOn)})`;
}

function tripLine(trips: BriefingFamilyData['trips'], todayKey: string) {
  const upcoming = [...trips]
    .filter((trip) => trip.endsOn >= todayKey)
    .sort((a, b) => a.startsOn.localeCompare(b.startsOn));
  const trip = upcoming[0];

  if (!trip) {
    return null;
  }

  const daysUntil = daysBetween(todayKey, trip.startsOn);

  if (daysUntil > 0) {
    return `${trip.title} D-${daysUntil}`;
  }

  if (daysUntil === 0) {
    return `${trip.title} D-Day`;
  }

  return `${trip.title} ${-daysUntil + 1}일차`;
}

function dailyFamilyLines(family: BriefingFamilyData, todayKey: string) {
  const lines: string[] = [];

  if (family.schedules.length === 0) {
    lines.push('오늘 일정 없음');
  } else {
    lines.push(`오늘 일정 ${family.schedules.length}건`, ...scheduleLines(family.schedules, false));
  }

  if (family.parking.length > 0) {
    lines.push(
      `주차 ${family.parking
        .map((record) => `${record.vehicleNickname} ${record.locationText}`.trim())
        .join(' · ')}`,
    );
  }

  const coupon = couponLine(family.coupons, `${COUPON_WINDOW_DAYS}일 내`);
  if (coupon) {
    lines.push(coupon);
  }

  const trip = tripLine(family.trips, todayKey);
  if (trip) {
    lines.push(trip);
  }

  return lines;
}

export function composeDailyBriefing(
  todayKey: string,
  families: BriefingFamilyData[],
): BriefingMessage {
  const title = `아침 브리핑 · ${formatDateLabel(todayKey)}`;
  const hasContent = families.some(
    (family) =>
      family.schedules.length > 0 ||
      family.parking.length > 0 ||
      family.coupons.length > 0 ||
      tripLine(family.trips, todayKey) !== null,
  );

  if (!hasContent) {
    return { title, body: '오늘은 등록된 일정이 없어요.' };
  }

  const body = families
    .flatMap((family) => [
      ...(families.length > 1 ? [`[${family.familyName}]`] : []),
      ...dailyFamilyLines(family, todayKey),
    ])
    .join('\n');

  return { title, body };
}

function weeklyFamilyLines(family: BriefingFamilyData, weekStart: string, weekEnd: string) {
  const lines: string[] = [];

  if (family.schedules.length === 0) {
    lines.push('이번 주 일정 없음');
  } else {
    const countByDay = new Map<string, number>();
    for (const schedule of family.schedules) {
      const key = seoulDateKey(new Date(schedule.startsAt));
      countByDay.set(key, (countByDay.get(key) ?? 0) + 1);
    }
    const perDay = [...countByDay.entries()]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([dateKey, count]) => `${WEEKDAY_LABELS[weekdayOf(dateKey)]} ${count}`)
      .join(' · ');
    lines.push(`이번 주 일정 ${family.schedules.length}건 (${perDay})`, ...scheduleLines(family.schedules, true));
  }

  const trips = [...family.trips]
    .filter((trip) => trip.startsOn <= weekEnd && trip.endsOn >= weekStart)
    .sort((a, b) => a.startsOn.localeCompare(b.startsOn));
  for (const trip of trips) {
    lines.push(`${trip.title} ${formatShortDate(trip.startsOn)} ~ ${formatShortDate(trip.endsOn)}`);
  }

  const coupon = couponLine(family.coupons, '이번 주');
  if (coupon) {
    lines.push(coupon);
  }

  return lines;
}

export function composeWeeklyBriefing(
  weekStart: string,
  families: BriefingFamilyData[],
): BriefingMessage {
  const weekEnd = addDays(weekStart, 6);
  const title = `주간 미리보기 · ${formatDateLabel(weekStart)} ~ ${formatDateLabel(weekEnd)}`;
  const body = families
    .flatMap((family) => [
      ...(families.length > 1 ? [`[${family.familyName}]`] : []),
      ...weeklyFamilyLines(family, weekStart, weekEnd),
    ])
    .join('\n');

  return { title, body };
}

// ---------------------------------------------------------------------------
// Data loading

type ScheduleRow = {
  title: string;
  starts_at: string;
  ends_at: string;
  is_all_day: boolean;
  family_member: { nickname: string } | { nickname: string }[] | null;
};

async function loadFamilyData(
  family: { id: string; name: string },
  options: {
    rangeStartKey: string;
    rangeEndKeyInclusive: string;
    todayKey: string;
    includeParking: boolean;
  },
): Promise<BriefingFamilyData> {
  const db = getSupabaseAdmin();
  const rangeStart = seoulInstant(options.rangeStartKey, '00:00').toISOString();
  const rangeEnd = seoulInstant(addDays(options.rangeEndKeyInclusive, 1), '00:00').toISOString();

  const [schedules, coupons, trips, parking] = await Promise.all([
    db
      .from('schedules')
      .select('title, starts_at, ends_at, is_all_day, family_member:family_members (nickname)')
      .eq('family_id', family.id)
      .lt('starts_at', rangeEnd)
      .gt('ends_at', rangeStart)
      .order('starts_at', { ascending: true })
      .limit(200),
    db
      .from('coupons')
      .select('title, expires_on')
      .eq('family_id', family.id)
      .is('used_at', null)
      .is('deleted_at', null)
      .gte('expires_on', options.rangeStartKey)
      .lte('expires_on', options.rangeEndKeyInclusive)
      .order('expires_on', { ascending: true })
      .limit(50),
    db
      .from('travel_trips')
      .select('title, starts_on, ends_on')
      .eq('family_id', family.id)
      .gte('ends_on', options.todayKey)
      .order('starts_on', { ascending: true })
      .limit(10),
    options.includeParking ? loadCurrentParking(family.id) : Promise.resolve([]),
  ]);

  if (schedules.error) throw schedules.error;
  if (coupons.error) throw coupons.error;
  if (trips.error) throw trips.error;

  return {
    familyId: family.id,
    familyName: family.name,
    schedules: ((schedules.data ?? []) as unknown as ScheduleRow[]).map((row) => {
      const member = Array.isArray(row.family_member) ? row.family_member[0] : row.family_member;
      return {
        title: row.title,
        startsAt: row.starts_at,
        endsAt: row.ends_at,
        isAllDay: row.is_all_day,
        memberNickname: member?.nickname ?? null,
      };
    }),
    coupons: ((coupons.data ?? []) as Array<{ title: string; expires_on: string }>).map((row) => ({
      title: row.title,
      expiresOn: row.expires_on,
    })),
    trips: ((trips.data ?? []) as Array<{ title: string; starts_on: string; ends_on: string }>).map(
      (row) => ({ title: row.title, startsOn: row.starts_on, endsOn: row.ends_on }),
    ),
    parking,
  };
}

async function loadCurrentParking(familyId: string) {
  const db = getSupabaseAdmin();
  const { data: records, error } = await db.rpc('list_current_parking_records', {
    target_family_id: familyId,
  });

  if (error) throw error;

  const rows = (records ?? []) as Array<{ vehicle_id: string; location_text: string; parked_at: string }>;

  if (rows.length === 0) {
    return [];
  }

  const { data: vehicles, error: vehiclesError } = await db
    .from('vehicles')
    .select('id, nickname')
    .in('id', rows.map((row) => row.vehicle_id));

  if (vehiclesError) throw vehiclesError;

  const nicknameById = new Map(
    ((vehicles ?? []) as Array<{ id: string; nickname: string }>).map((vehicle) => [vehicle.id, vehicle.nickname]),
  );

  return [...rows]
    .sort((a, b) => b.parked_at.localeCompare(a.parked_at))
    .map((row) => ({
      vehicleNickname: nicknameById.get(row.vehicle_id) ?? '차량',
      locationText: row.location_text,
    }));
}

// ---------------------------------------------------------------------------
// Dispatch

export type BriefingDispatchResult = {
  ok: boolean;
  dueCount: number;
  sentCount: number;
  skippedCount: number;
  failureCount: number;
  briefings: Array<{
    userId: string;
    kind: BriefingKind;
    date: string;
    status: 'sent' | 'failed' | 'no_targets' | 'empty' | 'already_claimed';
    tokenCount: number;
    successCount: number;
    failureCount: number;
  }>;
};

export async function dispatchDueBriefings(now = new Date()): Promise<BriefingDispatchResult> {
  const lookbackMinutes = getLookbackMinutes();
  const windowStart = new Date(now.getTime() - lookbackMinutes * 60 * 1000);
  const settings = await listActiveBriefingSettings();
  const due: Array<{ userId: string; kind: BriefingKind; date: string }> = [];

  for (const row of settings) {
    if (row.enabled) {
      for (const date of dueBriefingDates('daily', normalizeSendTime(row.send_time), windowStart, now)) {
        due.push({ userId: row.user_id, kind: 'daily', date });
      }
    }

    if (row.weekly_preview_enabled) {
      for (const date of dueBriefingDates('weekly', BRIEFING_WEEKLY_TIME, windowStart, now)) {
        due.push({ userId: row.user_id, kind: 'weekly', date });
      }
    }
  }

  const briefings: BriefingDispatchResult['briefings'] = [];
  for (const item of due) {
    briefings.push(await deliverBriefing(item));
  }

  const sent = briefings.filter((item) => item.status === 'sent');

  return {
    ok: briefings.every((item) => item.failureCount === 0),
    dueCount: due.length,
    sentCount: sent.length,
    skippedCount: briefings.length - sent.length,
    failureCount: briefings.reduce((sum, item) => sum + item.failureCount, 0),
    briefings,
  };
}

async function listActiveBriefingSettings() {
  const { data, error } = await getSupabaseAdmin()
    .from('briefing_settings')
    .select('user_id, enabled, send_time, weekly_preview_enabled')
    .or('enabled.eq.true,weekly_preview_enabled.eq.true')
    .limit(5000);

  if (error) throw error;

  return (data ?? []) as SettingsRow[];
}

async function deliverBriefing(item: {
  userId: string;
  kind: BriefingKind;
  date: string;
}): Promise<BriefingDispatchResult['briefings'][number]> {
  const base = { userId: item.userId, kind: item.kind, date: item.date, tokenCount: 0, successCount: 0, failureCount: 0 };
  const db = getSupabaseAdmin();
  const { data: delivery, error: claimError } = await db
    .from('briefing_deliveries')
    .insert({ user_id: item.userId, briefing_kind: item.kind, briefing_date: item.date, status: 'processing' })
    .select('id')
    .maybeSingle();

  if (claimError?.code === '23505') {
    return { ...base, status: 'already_claimed' };
  }
  if (claimError) throw claimError;
  if (!delivery) return { ...base, status: 'already_claimed' };

  const deliveryId = (delivery as { id: string }).id;
  const tokens = await listPushTokensForUser(item.userId);

  if (tokens.length === 0) {
    await finishDelivery(deliveryId, { status: 'no_targets', tokenCount: 0, successCount: 0, failureCount: 0, errors: [] });
    return { ...base, status: 'no_targets' };
  }

  const families = (await listFamilies(item.userId)).map(({ family }) => ({ id: family.id, name: family.name }));

  if (families.length === 0) {
    await finishDelivery(deliveryId, { status: 'empty', tokenCount: tokens.length, successCount: 0, failureCount: 0, errors: [] });
    return { ...base, status: 'empty', tokenCount: tokens.length };
  }

  const message = await composeBriefingFor(item.kind, item.date, families);
  const data = { type: `briefing_${item.kind}`, kind: item.kind, date: item.date, familyId: families[0].id };
  const results = await Promise.all(
    tokens.map((token) => sendFcmNotification({ token: token.token, title: message.title, body: message.body, data })),
  );
  const successCount = results.filter((result) => result.ok).length;
  const failureCount = results.length - successCount;

  await finishDelivery(deliveryId, {
    status: successCount > 0 ? 'sent' : 'failed',
    tokenCount: tokens.length,
    successCount,
    failureCount,
    errors: results.filter((result) => !result.ok),
  });

  if (successCount > 0) {
    await recordPushNotificationHistory({
      userIds: [item.userId],
      familyId: families[0].id,
      type: `briefing_${item.kind}`,
      title: message.title,
      body: message.body,
      data,
    });
  }

  return { ...base, status: successCount > 0 ? 'sent' : 'failed', tokenCount: tokens.length, successCount, failureCount };
}

async function composeBriefingFor(
  kind: BriefingKind,
  date: string,
  families: Array<{ id: string; name: string }>,
) {
  if (kind === 'weekly') {
    // The preview goes out on Sunday evening for the week starting Monday.
    const weekStart = addDays(date, 1);
    const weekEnd = addDays(weekStart, 6);
    const data = await Promise.all(
      families.map((family) =>
        loadFamilyData(family, {
          rangeStartKey: weekStart,
          rangeEndKeyInclusive: weekEnd,
          todayKey: date,
          includeParking: false,
        }),
      ),
    );
    return composeWeeklyBriefing(weekStart, data);
  }

  const data = await Promise.all(
    families.map((family) =>
      loadFamilyData(family, {
        rangeStartKey: date,
        rangeEndKeyInclusive: addDays(date, COUPON_WINDOW_DAYS),
        todayKey: date,
        includeParking: true,
      }),
    ),
  );
  // Only today's schedules belong in the morning briefing; coupons use the 7-day window.
  const today = data.map((family) => ({
    ...family,
    schedules: family.schedules.filter((schedule) => {
      const dayStart = seoulInstant(date, '00:00').getTime();
      const dayEnd = dayStart + DAY_MS;
      const starts = new Date(schedule.startsAt).getTime();
      const ends = new Date(schedule.endsAt).getTime();
      return starts < dayEnd && ends > dayStart;
    }),
  }));
  return composeDailyBriefing(date, today);
}

async function finishDelivery(
  deliveryId: string,
  input: {
    status: 'sent' | 'failed' | 'no_targets' | 'empty';
    tokenCount: number;
    successCount: number;
    failureCount: number;
    errors: FcmSendResult[];
  },
) {
  const { error } = await getSupabaseAdmin()
    .from('briefing_deliveries')
    .update({
      status: input.status,
      token_count: input.tokenCount,
      success_count: input.successCount,
      failure_count: input.failureCount,
      error_summary: input.errors,
    })
    .eq('id', deliveryId);

  if (error) throw error;
}

function getLookbackMinutes() {
  const value = Number(process.env.SCHEDULE_ALERT_LOOKBACK_MINUTES);

  if (!Number.isInteger(value) || value < 1 || value > 60) {
    return DEFAULT_LOOKBACK_MINUTES;
  }

  return value;
}
