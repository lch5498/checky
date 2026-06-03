import {
  createEducationProgram,
  getEducationProgramDashboard,
} from '../../../../../../src/education-programs';
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
    const dashboard = await getEducationProgramDashboard(userId, familyId);

    return Response.json(dashboard);
  } catch (error) {
    return jsonFromError(error, 'education_programs_fetch_failed');
  }
}

export async function POST(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId } = await context.params;
    const payload = await readJsonObject(request);
    const result = await createEducationProgram(
      userId,
      familyId,
      {
        familyMemberId: requiredString(payload, 'familyMemberId'),
        name: requiredString(payload, 'name', { maxLength: 80 }),
        startsOn: requiredString(payload, 'startsOn'),
        endsOn: requiredString(payload, 'endsOn'),
        weeklySchedules: requiredWeeklySchedules(payload),
        timeZoneOffsetMinutes: optionalNumber(payload, 'timeZoneOffsetMinutes'),
      },
      {
        calendarApplyScope: optionalCalendarApplyScope(payload),
      },
    );

    return Response.json(result, { status: 201 });
  } catch (error) {
    return jsonFromError(error, 'education_program_create_failed');
  }
}

function requiredWeeklySchedules(payload: Record<string, unknown>) {
  const value = payload.weeklySchedules;

  if (!Array.isArray(value)) {
    throw new HttpError(400, {
      error: 'invalid_payload',
      field: 'weeklySchedules',
    });
  }

  return value as never;
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

function optionalCalendarApplyScope(payload: Record<string, unknown>) {
  const value = payload.calendarApplyScope;

  if (value === undefined || value === null) {
    return undefined;
  }

  if (value !== 'all' && value !== 'future') {
    throw new HttpError(400, {
      error: 'invalid_payload',
      field: 'calendarApplyScope',
    });
  }

  return value;
}
