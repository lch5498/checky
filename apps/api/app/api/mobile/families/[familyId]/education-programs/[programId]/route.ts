import {
  deleteEducationProgram,
  updateEducationProgram,
} from '../../../../../../../src/education-programs';
import { HttpError, jsonFromError } from '../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../src/mobile-auth';
import {
  readJsonObject,
  requiredString,
} from '../../../../../../../src/validation';

export const runtime = 'nodejs';

type RouteContext = {
  params: Promise<{
    familyId: string;
    programId: string;
  }>;
};

export async function PATCH(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, programId } = await context.params;
    const payload = await readJsonObject(request);
    const result = await updateEducationProgram(
      userId,
      familyId,
      programId,
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

    return Response.json(result);
  } catch (error) {
    return jsonFromError(error, 'education_program_update_failed');
  }
}

export async function DELETE(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, programId } = await context.params;
    const payload = await readJsonObject(request);
    await deleteEducationProgram(userId, familyId, programId, {
      calendarApplyScope: optionalCalendarApplyScope(payload),
      timeZoneOffsetMinutes: optionalNumber(payload, 'timeZoneOffsetMinutes'),
    });

    return new Response(null, { status: 204 });
  } catch (error) {
    return jsonFromError(error, 'education_program_delete_failed');
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
