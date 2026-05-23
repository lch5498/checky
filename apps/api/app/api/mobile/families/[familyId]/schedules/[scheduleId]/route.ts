import {
  deleteSchedule,
  updateSchedule,
} from '../../../../../../../src/schedules';
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
    scheduleId: string;
  }>;
};

export async function PATCH(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, scheduleId } = await context.params;
    const payload = await readJsonObject(request);
    const schedule = await updateSchedule(userId, familyId, scheduleId, {
      familyMemberId: requiredString(payload, 'familyMemberId'),
      title: requiredString(payload, 'title', { maxLength: 80 }),
      content: optionalText(payload, 'content'),
      startsAt: requiredString(payload, 'startsAt'),
      endsAt: requiredString(payload, 'endsAt'),
      vehicleBoardingAt: optionalText(payload, 'vehicleBoardingAt'),
      vehicleDropoffAt: optionalText(payload, 'vehicleDropoffAt'),
    });

    return Response.json({ schedule });
  } catch (error) {
    return jsonFromError(error, 'schedule_update_failed');
  }
}

export async function DELETE(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, scheduleId } = await context.params;

    await deleteSchedule(userId, familyId, scheduleId);

    return Response.json({ ok: true });
  } catch (error) {
    return jsonFromError(error, 'schedule_delete_failed');
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
