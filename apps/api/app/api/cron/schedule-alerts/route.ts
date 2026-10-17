import { timingSafeEqual } from 'node:crypto';

import { HttpError, jsonFromError } from '../../../../src/http';
import { dispatchDueCouponExpiryAlerts } from '../../../../src/coupon-expiry-alerts';
import { dispatchDueScheduleAlerts } from '../../../../src/schedule-alerts';
import { getBearerToken } from '../../../../src/session';

export const runtime = 'nodejs';

export async function GET(request: Request) {
  try {
    assertCronAuthorized(request);
    const result = await dispatchDueScheduleAlerts();
    const coupons = await dispatchDueCouponExpiryAlerts();

    return Response.json({ ...result, coupons }, {
      status: result.failureCount + coupons.failureCount === 0 ? 200 : 207,
    });
  } catch (error) {
    return jsonFromError(error, 'schedule_alerts_dispatch_failed');
  }
}

function assertCronAuthorized(request: Request) {
  const cronSecret = process.env.CRON_SECRET?.trim();

  if (!cronSecret) {
    return;
  }

  const bearerToken = getBearerToken(request);

  if (!bearerToken) {
    throw new HttpError(401, { error: 'unauthorized' });
  }

  const bearerTokenBuffer = Buffer.from(bearerToken);
  const cronSecretBuffer = Buffer.from(cronSecret);

  if (
    bearerTokenBuffer.length !== cronSecretBuffer.length ||
    !timingSafeEqual(bearerTokenBuffer, cronSecretBuffer)
  ) {
    throw new HttpError(401, { error: 'unauthorized' });
  }
}
