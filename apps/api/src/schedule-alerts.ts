import { sendFcmNotification, type FcmSendResult } from './fcm';
import { getSupabaseAdmin } from './supabase';

const DEFAULT_LOOKBACK_MINUTES = 5;

type FamilyRelation = {
  id: string;
  name: string;
};

type FamilyMemberRelation = {
  id: string;
  nickname: string;
};

type DueScheduleRow = {
  id: string;
  family_id: string;
  title: string;
  starts_at: string;
  anniversary_id: string | null;
  alert_offset_minutes: number;
  alert_due_at: string;
  family: FamilyRelation | FamilyRelation[] | null;
  family_member: FamilyMemberRelation | FamilyMemberRelation[] | null;
};

type PushTokenRow = {
  id: string;
  token: string;
  platform: 'ios' | 'android';
  user_id: string;
};

type DeliveryRow = {
  id: string;
};

export type ScheduleAlertDispatchResult = {
  ok: boolean;
  windowStart: string;
  windowEnd: string;
  dueScheduleCount: number;
  claimedScheduleCount: number;
  sentScheduleCount: number;
  tokenCount: number;
  successCount: number;
  failureCount: number;
  schedules: Array<{
    scheduleId: string;
    familyId: string;
    title: string;
    notificationTitle: string;
    notificationBody: string;
    tokenCount: number;
    successCount: number;
    failureCount: number;
    skipped?: boolean;
    skipReason?: string;
  }>;
};

export function formatScheduleAlertOffset(minutes: number) {
  if (minutes === 0) {
    return '정시';
  }

  if (minutes % (60 * 24) === 0) {
    return `${minutes / (60 * 24)}일전`;
  }

  if (minutes % 60 === 0) {
    return `${minutes / 60}시간전`;
  }

  return `${minutes}분전`;
}

export async function dispatchDueScheduleAlerts(now = new Date()) {
  const lookbackMinutes = getLookbackMinutes();
  const windowStart = new Date(now.getTime() - lookbackMinutes * 60 * 1000);
  const windowEnd = now;
  const dueSchedules = await listDueSchedules(windowStart, windowEnd);
  const tokensByFamilyId = await listPushTokensByFamilyId(
    Array.from(new Set(dueSchedules.map((schedule) => schedule.family_id))),
  );

  const scheduleResults = await Promise.all(
    dueSchedules.map(async (schedule) => {
      const delivery = await claimScheduleAlert(schedule);

      if (!delivery) {
        return {
          scheduleId: schedule.id,
          familyId: schedule.family_id,
          title: schedule.title,
          notificationTitle: notificationTitle(schedule),
          notificationBody: notificationBody(schedule),
          tokenCount: 0,
          successCount: 0,
          failureCount: 0,
          skipped: true,
          skipReason: 'already_claimed',
        };
      }

      const tokens = tokensByFamilyId.get(schedule.family_id) ?? [];
      const title = notificationTitle(schedule);
      const body = notificationBody(schedule);

      if (tokens.length === 0) {
        await updateDelivery(delivery.id, {
          status: 'no_targets',
          tokenCount: 0,
          successCount: 0,
          failureCount: 0,
          errorSummary: [],
        });

        return {
          scheduleId: schedule.id,
          familyId: schedule.family_id,
          title: schedule.title,
          notificationTitle: title,
          notificationBody: body,
          tokenCount: 0,
          successCount: 0,
          failureCount: 0,
          skipped: true,
          skipReason: 'no_targets',
        };
      }

      const sendResults = await Promise.all(
        tokens.map(async (pushToken) => {
          const result = await sendFcmNotification({
            token: pushToken.token,
            title,
            body,
            data: {
              type: 'schedule_alert',
              scheduleId: schedule.id,
              familyId: schedule.family_id,
              startsAt: schedule.starts_at,
            },
          });

          return { pushToken, result };
        }),
      );

      const successCount = sendResults.filter(({ result }) => result.ok).length;
      const failureCount = sendResults.length - successCount;
      const errorSummary = summarizeErrors(sendResults.map(({ result }) => result));

      await updateDelivery(delivery.id, {
        status: successCount > 0 ? 'sent' : 'failed',
        tokenCount: tokens.length,
        successCount,
        failureCount,
        errorSummary,
      });

      return {
        scheduleId: schedule.id,
        familyId: schedule.family_id,
        title: schedule.title,
        notificationTitle: title,
        notificationBody: body,
        tokenCount: tokens.length,
        successCount,
        failureCount,
      };
    }),
  );

  const claimedSchedules = scheduleResults.filter(
    (result) => result.skipReason !== 'already_claimed',
  );
  const sentSchedules = claimedSchedules.filter((result) => result.tokenCount > 0);
  const tokenCount = sentSchedules.reduce(
    (sum, result) => sum + result.tokenCount,
    0,
  );
  const successCount = sentSchedules.reduce(
    (sum, result) => sum + result.successCount,
    0,
  );
  const failureCount = sentSchedules.reduce(
    (sum, result) => sum + result.failureCount,
    0,
  );

  return {
    ok: failureCount === 0,
    windowStart: windowStart.toISOString(),
    windowEnd: windowEnd.toISOString(),
    dueScheduleCount: dueSchedules.length,
    claimedScheduleCount: claimedSchedules.length,
    sentScheduleCount: sentSchedules.length,
    tokenCount,
    successCount,
    failureCount,
    schedules: scheduleResults,
  } satisfies ScheduleAlertDispatchResult;
}

async function listDueSchedules(windowStart: Date, windowEnd: Date) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('schedules')
    .select(
      `
        id,
        family_id,
        title,
        starts_at,
        anniversary_id,
        alert_offset_minutes,
        alert_due_at,
        family:families (
          id,
          name
        ),
        family_member:family_members (
          id,
          nickname
        )
      `,
    )
    .not('alert_due_at', 'is', null)
    .gte('alert_due_at', windowStart.toISOString())
    .lte('alert_due_at', windowEnd.toISOString())
    .order('alert_due_at', { ascending: true })
    .limit(200);

  if (error) {
    throw error;
  }

  return (data ?? []) as unknown as DueScheduleRow[];
}

async function listPushTokensByFamilyId(familyIds: string[]) {
  const tokensByFamilyId = new Map<string, PushTokenRow[]>();

  if (familyIds.length === 0) {
    return tokensByFamilyId;
  }

  const supabase = getSupabaseAdmin();
  const { data: members, error: membersError } = await supabase
    .from('family_members')
    .select('family_id, user_id')
    .in('family_id', familyIds)
    .not('user_id', 'is', null);

  if (membersError) {
    throw membersError;
  }

  const userIdsByFamilyId = new Map<string, Set<string>>();
  for (const member of (members ?? []) as Array<{
    family_id: string;
    user_id: string | null;
  }>) {
    if (!member.user_id) {
      continue;
    }

    const userIds = userIdsByFamilyId.get(member.family_id) ?? new Set<string>();
    userIds.add(member.user_id);
    userIdsByFamilyId.set(member.family_id, userIds);
  }

  const userIds = Array.from(
    new Set(
      Array.from(userIdsByFamilyId.values()).flatMap((familyUserIds) =>
        Array.from(familyUserIds),
      ),
    ),
  );

  if (userIds.length === 0) {
    return tokensByFamilyId;
  }

  const { data: pushTokens, error: pushTokensError } = await supabase
    .from('push_tokens')
    .select('id, user_id, token, platform')
    .in('user_id', userIds)
    .eq('enabled', true);

  if (pushTokensError) {
    throw pushTokensError;
  }

  const tokensByUserId = new Map<string, PushTokenRow[]>();
  for (const pushToken of (pushTokens ?? []) as PushTokenRow[]) {
    const tokens = tokensByUserId.get(pushToken.user_id) ?? [];
    tokens.push(pushToken);
    tokensByUserId.set(pushToken.user_id, tokens);
  }

  for (const familyId of familyIds) {
    const familyUserIds = userIdsByFamilyId.get(familyId) ?? new Set<string>();
    const familyTokens = Array.from(familyUserIds).flatMap(
      (userId) => tokensByUserId.get(userId) ?? [],
    );
    tokensByFamilyId.set(familyId, familyTokens);
  }

  return tokensByFamilyId;
}

async function claimScheduleAlert(schedule: DueScheduleRow) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('schedule_alert_deliveries')
    .insert({
      schedule_id: schedule.id,
      alert_due_at: schedule.alert_due_at,
      status: 'processing',
    })
    .select('id')
    .maybeSingle();

  if (error) {
    if (error.code === '23505') {
      return null;
    }

    throw error;
  }

  return data as DeliveryRow | null;
}

async function updateDelivery(
  deliveryId: string,
  input: {
    status: 'sent' | 'failed' | 'no_targets';
    tokenCount: number;
    successCount: number;
    failureCount: number;
    errorSummary: Array<Record<string, unknown>>;
  },
) {
  const supabase = getSupabaseAdmin();
  const { error } = await supabase
    .from('schedule_alert_deliveries')
    .update({
      status: input.status,
      token_count: input.tokenCount,
      success_count: input.successCount,
      failure_count: input.failureCount,
      error_summary: input.errorSummary,
    })
    .eq('id', deliveryId);

  if (error) {
    throw error;
  }
}

function notificationTitle(schedule: DueScheduleRow) {
  const member = Array.isArray(schedule.family_member)
    ? schedule.family_member[0]
    : schedule.family_member;
  const memberName = member?.nickname?.trim();

  return memberName ? `${schedule.title} (${memberName})` : schedule.title;
}

function notificationBody(schedule: DueScheduleRow) {
  if (schedule.anniversary_id) {
    return formatAnniversaryAlertOffset(schedule.alert_offset_minutes);
  }

  return formatScheduleAlertOffset(schedule.alert_offset_minutes);
}

function formatAnniversaryAlertOffset(minutes: number) {
  if (minutes >= 0) {
    if (minutes === 0) {
      return '정시';
    }

    const daysBefore = Math.ceil(minutes / (60 * 24));

    return `${daysBefore}일전`;
  }

  return formatScheduleAlertOffset(minutes);
}

function summarizeErrors(results: FcmSendResult[]) {
  const counts = new Map<string, number>();

  for (const result of results) {
    if (result.ok) {
      continue;
    }

    const key = `${result.status}:${result.error}`;
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }

  return Array.from(counts.entries()).map(([key, count]) => {
    const [status, ...errorParts] = key.split(':');
    return {
      status: Number(status),
      error: errorParts.join(':'),
      count,
    };
  });
}

function getLookbackMinutes() {
  const value = Number(process.env.SCHEDULE_ALERT_LOOKBACK_MINUTES);

  if (!Number.isInteger(value) || value < 1 || value > 60) {
    return DEFAULT_LOOKBACK_MINUTES;
  }

  return value;
}
