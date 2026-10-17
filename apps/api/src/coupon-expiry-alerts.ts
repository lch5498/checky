import { sendFcmNotification } from './fcm';
import { recordPushNotificationHistory } from './notifications';
import { listPushTokensByFamilyId } from './schedule-alerts';
import { getSupabaseAdmin } from './supabase';

type DueCoupon = {
  id: string;
  family_id: string;
  title: string;
  expires_on: string;
  daysBefore: 1 | 7;
};

const SEOUL_OFFSET_MS = 9 * 60 * 60 * 1000;

export function couponAlertDates(now: Date) {
  const seoulTime = new Date(now.getTime() + SEOUL_OFFSET_MS);
  if (seoulTime.getUTCHours() !== 9) return null;
  const dayStart = Date.UTC(
    seoulTime.getUTCFullYear(),
    seoulTime.getUTCMonth(),
    seoulTime.getUTCDate(),
  );
  return [1, 7].map((daysBefore) => ({
    daysBefore: daysBefore as 1 | 7,
    expiresOn: new Date(dayStart + daysBefore * 86400000)
      .toISOString().slice(0, 10),
  }));
}

export async function dispatchDueCouponExpiryAlerts(now = new Date()) {
  const dates = couponAlertDates(now);
  if (!dates) return { dueCouponCount: 0, sentCouponCount: 0, failureCount: 0 };

  const db = getSupabaseAdmin();
  const coupons: DueCoupon[] = [];
  for (let offset = 0; ; offset += 500) {
    const { data, error } = await db.from('coupons')
      .select('id,family_id,title,expires_on')
      .is('used_at', null).is('deleted_at', null)
      .in('expires_on', dates.map((date) => date.expiresOn))
      .order('id').range(offset, offset + 499);
    if (error) throw error;
    for (const row of data ?? []) {
      const date = dates.find((item) => item.expiresOn === row.expires_on);
      if (date) coupons.push({ ...row, daysBefore: date.daysBefore });
    }
    if ((data ?? []).length < 500) break;
  }

  const tokensByFamily = await listPushTokensByFamilyId(
    [...new Set(coupons.map((coupon) => coupon.family_id))],
  );
  let sentCouponCount = 0;
  let failureCount = 0;
  for (const coupon of coupons) {
    const tokens = tokensByFamily.get(coupon.family_id) ?? [];
    if (tokens.length === 0) continue;
    const { data: delivery, error: claimError } = await db
      .from('coupon_expiry_deliveries')
      .insert({ coupon_id: coupon.id, expires_on: coupon.expires_on,
        days_before: coupon.daysBefore })
      .select('id').maybeSingle();
    if (claimError?.code === '23505') continue;
    if (claimError) throw claimError;
    if (!delivery) continue;

    const title = `${coupon.title} 만료 ${coupon.daysBefore}일 전`;
    const body = `${coupon.expires_on}까지 사용할 수 있어요.`;
    const data = { type: 'coupon_expiry', couponId: coupon.id,
      familyId: coupon.family_id };
    const results = await Promise.all(tokens.map(async (token) => ({
      userId: token.user_id,
      result: await sendFcmNotification({ token: token.token, title, body, data }),
    })));
    const successes = results.filter((entry) => entry.result.ok);
    const failures = results.filter((entry) => !entry.result.ok);
    const { error: updateError } = await db.from('coupon_expiry_deliveries')
      .update({ status: successes.length > 0 ? 'sent' : 'failed',
        token_count: tokens.length, success_count: successes.length,
        failure_count: failures.length,
        error_summary: failures.map((entry) => entry.result) })
      .eq('id', delivery.id);
    if (updateError) throw updateError;
    if (successes.length > 0) {
      await recordPushNotificationHistory({
        userIds: successes.map((entry) => entry.userId),
        familyId: coupon.family_id, type: 'coupon_expiry', title, body, data,
      });
      sentCouponCount++;
    }
    failureCount += failures.length;
  }
  return { dueCouponCount: coupons.length, sentCouponCount, failureCount };
}
