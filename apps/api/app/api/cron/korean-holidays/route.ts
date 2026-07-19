import { timingSafeEqual } from 'node:crypto';

import { HttpError, jsonFromError } from '../../../../src/http';
import { syncKoreanHolidays } from '../../../../src/korean-holidays';
import { getBearerToken } from '../../../../src/session';

export const runtime = 'nodejs';

export async function GET(request: Request) {
  try {
    assertCronAuthorized(request);
    const { searchParams } = new URL(request.url);
    const result = await syncKoreanHolidays({
      startYear: optionalYear(searchParams.get('startYear')),
      endYear: optionalYear(searchParams.get('endYear')),
    });

    return Response.json(result);
  } catch (error) {
    return jsonFromError(error, 'korean_holidays_sync_failed');
  }
}

function optionalYear(value: string | null) {
  if (value === null) {
    return undefined;
  }

  if (!/^\d{4}$/.test(value)) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'year' });
  }

  return Number(value);
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
