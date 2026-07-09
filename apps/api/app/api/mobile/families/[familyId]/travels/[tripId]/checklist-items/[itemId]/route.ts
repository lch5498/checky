import {
  deleteTravelTripChecklistItem,
  updateTravelTripChecklistItem,
} from '../../../../../../../../../src/travels';
import { HttpError, jsonFromError } from '../../../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../../../src/mobile-auth';
import { readJsonObject } from '../../../../../../../../../src/validation';

export const runtime = 'nodejs';

type RouteContext = {
  params: Promise<{
    familyId: string;
    tripId: string;
    itemId: string;
  }>;
};

export async function PATCH(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, tripId, itemId } = await context.params;
    const payload = await readJsonObject(request);
    const item = await updateTravelTripChecklistItem(
      userId,
      familyId,
      tripId,
      itemId,
      {
        name: optionalString(payload, 'name'),
        isChecked: optionalBoolean(payload, 'isChecked'),
      },
    );

    return Response.json(item);
  } catch (error) {
    return jsonFromError(error, 'travel_trip_checklist_item_update_failed');
  }
}

export async function DELETE(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, tripId, itemId } = await context.params;
    await deleteTravelTripChecklistItem(userId, familyId, tripId, itemId);

    return Response.json({ ok: true });
  } catch (error) {
    return jsonFromError(error, 'travel_trip_checklist_item_delete_failed');
  }
}

function optionalString(payload: Record<string, unknown>, key: string) {
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
