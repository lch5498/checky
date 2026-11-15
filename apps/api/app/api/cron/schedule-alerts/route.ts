import { timingSafeEqual } from 'node:crypto';

import { dispatchDueBriefings } from '../../../../src/briefings';
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
    const briefings = await dispatchBriefingsSafely();

    return Response.json({ ...result, coupons, briefings }, {
      status:
        result.failureCount + coupons.failureCount + briefings.failureCount === 0
          ? 200
          : 207,
    });
  } catch (error) {
    return jsonFromError(error, 'schedule_alerts_dispatch_failed');
  }
}

// A briefing problem (for example the migration not yet applied) must not block
// schedule and coupon alerts, which run in the same cron tick.
async function dispatchBriefingsSafely() {
  try {
    return await dispatchDueBriefings();
  } catch (error) {
    console.error('briefing dispatch failed', error);
    return {
      ok: false,
      failureCount: 1,
      error: error instanceof Error ? error.message : 'briefing_dispatch_failed',
    };
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
