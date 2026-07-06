import {
  createAnniversary,
  getAnniversaryDashboard,
} from '../../../../../../src/anniversaries';
import { HttpError, jsonFromError } from '../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../src/mobile-auth';
import {
  optionalString,
  readJsonObject,
  requiredString,
} from '../../../../../../src/validation';

export const runtime = 'nodejs';

type RouteContext = {
  params: Promise<{
    familyId: string;
  }>;
};

export async function GET(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId } = await context.params;
    const dashboard = await getAnniversaryDashboard(userId, familyId);

    return Response.json(dashboard);
  } catch (error) {
    return jsonFromError(error, 'anniversaries_fetch_failed');
  }
}

export async function POST(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId } = await context.params;
    const payload = await readJsonObject(request);
    const result = await createAnniversary(userId, familyId, {
      category: requiredCategory(payload),
      customCategoryLabel: optionalString(payload, 'customCategoryLabel', {
        maxLength: 40,
      }),
      title: requiredString(payload, 'title', { maxLength: 80 }),
      calendarType: requiredCalendarType(payload),
      month: requiredNumber(payload, 'month'),
      day: requiredNumber(payload, 'day'),
      isLunarLeap: optionalBoolean(payload, 'isLunarLeap'),
      year: optionalNumberOrNull(payload, 'year'),
      alertOffsetMinutes: optionalNumberOrNull(payload, 'alertOffsetMinutes'),
      timeZoneOffsetMinutes: optionalNumber(payload, 'timeZoneOffsetMinutes'),
    });

    return Response.json(result, { status: 201 });
  } catch (error) {
    return jsonFromError(error, 'anniversary_create_failed');
  }
}

function requiredCategory(payload: Record<string, unknown>) {
  const value = requiredString(payload, 'category');

  if (value !== 'birthday' && value !== 'wedding' && value !== 'custom') {
    throw new HttpError(400, { error: 'invalid_payload', field: 'category' });
  }

  return value;
}

function requiredCalendarType(payload: Record<string, unknown>) {
  const value = requiredString(payload, 'calendarType');

  if (value !== 'solar' && value !== 'lunar') {
    throw new HttpError(400, {
      error: 'invalid_payload',
      field: 'calendarType',
    });
  }

  return value;
}

function requiredNumber(payload: Record<string, unknown>, key: string) {
  const value = payload[key];

  if (typeof value !== 'number') {
    throw new HttpError(400, { error: 'invalid_payload', field: key });
  }

  return value;
}

function optionalNumber(payload: Record<string, unknown>, key: string) {
  const value = payload[key];

  if (value === undefined || value === null) {
    return undefined;
  }

  if (typeof value !== 'number') {
    throw new HttpError(400, { error: 'invalid_payload', field: key });
  }

  return value;
}

function optionalNumberOrNull(payload: Record<string, unknown>, key: string) {
  const value = payload[key];

  if (value === undefined || value === null) {
    return null;
  }

  if (typeof value !== 'number') {
    throw new HttpError(400, { error: 'invalid_payload', field: key });
  }

  return value;
}

function optionalBoolean(payload: Record<string, unknown>, key: string) {
  const value = payload[key];

  if (value === undefined || value === null) {
    return undefined;
  }

  if (typeof value !== 'boolean') {
    throw new HttpError(400, { error: 'invalid_payload', field: key });
  }

  return value;
}
