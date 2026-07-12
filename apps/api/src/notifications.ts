import { HttpError } from './http';
import { getSupabaseAdmin } from './supabase';

type NotificationHistoryRow = {
  id: string;
  notification_type: string;
  title: string;
  body: string;
  sent_at: string;
  family: { name: string } | { name: string }[] | null;
};

type RecordPushNotificationInput = {
  userIds: string[];
  familyId: string;
  scheduleId: string;
  type: string;
  title: string;
  body: string;
  data: Record<string, string>;
};

export type PushNotificationHistoryItem = {
  id: string;
  type: string;
  title: string;
  body: string;
  familyName: string | null;
  sentAt: string;
};

export async function recordPushNotificationHistory(
  input: RecordPushNotificationInput,
) {
  const userIds = [...new Set(input.userIds)];

  if (userIds.length === 0) {
    return;
  }

  const supabase = getSupabaseAdmin();
  const { error } = await supabase.from('push_notification_history').insert(
    userIds.map((userId) => ({
      user_id: userId,
      family_id: input.familyId,
      schedule_id: input.scheduleId,
      notification_type: input.type,
      title: input.title,
      body: input.body,
      data: input.data,
    })),
  );

  if (error) {
    throw new HttpError(500, { error: 'push_notification_history_save_failed' });
  }
}

export async function listPushNotificationHistory(userId: string) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('push_notification_history')
    .select(
      `
        id,
        notification_type,
        title,
        body,
        sent_at,
        family:families (
          name
        )
      `,
    )
    .eq('user_id', userId)
    .order('sent_at', { ascending: false })
    .limit(100);

  if (error) {
    throw new HttpError(500, { error: 'push_notification_history_fetch_failed' });
  }

  return (data ?? []).map((row) => toPushNotificationHistoryItem(row));
}

function toPushNotificationHistoryItem(row: unknown): PushNotificationHistoryItem {
  const notification = row as NotificationHistoryRow;
  const family = Array.isArray(notification.family)
    ? notification.family[0]
    : notification.family;

  return {
    id: notification.id,
    type: notification.notification_type,
    title: notification.title,
    body: notification.body,
    familyName: family?.name ?? null,
    sentAt: notification.sent_at,
  };
}
