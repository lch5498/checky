import {
  createSchedule,
  getScheduleDashboard,
} from '../../../../../../src/schedules';
import { HttpError, jsonFromError } from '../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../src/mobile-auth';
import {
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
    const { searchParams } = new URL(request.url);
    const rangeStart = searchParams.get('rangeStart');
    const rangeEnd = searchParams.get('rangeEnd');

    if (!rangeStart || !rangeEnd) {
      throw new HttpError(400, { error: 'invalid_payload', field: 'range' });
    }

    const dashboard = await getScheduleDashboard(
      userId,
      familyId,
      rangeStart,
      rangeEnd,
    );

    return Response.json(dashboard);
  } catch (error) {
    return jsonFromError(error, 'schedules_fetch_failed');
  }
}

export async function POST(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId } = await context.params;
    const payload = await readJsonObject(request);
    const schedule = await createSchedule(userId, familyId, {
      familyMemberId: requiredString(payload, 'familyMemberId'),
      title: requiredString(payload, 'title', { maxLength: 80 }),
      content: optionalText(payload, 'content'),
      startsAt: requiredString(payload, 'startsAt'),
      endsAt: requiredString(payload, 'endsAt'),
      isAllDay: optionalBoolean(payload, 'isAllDay'),
      vehicleBoardingAt: optionalText(payload, 'vehicleBoardingAt'),
      vehicleDropoffAt: optionalText(payload, 'vehicleDropoffAt'),
      educationProgramId:
        optionalText(payload, 'educationTemplateId') ??
        optionalText(payload, 'educationProgramId'),
      alertOffsetMinutes: optionalNumberOrNull(payload, 'alertOffsetMinutes'),
    });

    return Response.json({ schedule }, { status: 201 });
  } catch (error) {
    return jsonFromError(error, 'schedule_create_failed');
  }
}

function optionalText(payload: Record<string, unknown>, key: string) {
  const value = payload[key];

  if (value === undefined || value === null) {
    return undefined;
  }

  if (typeof value !== 'string') {
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
