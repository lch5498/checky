import {
  deleteTravelItinerary,
  updateTravelItinerary,
} from '../../../../../../../../../src/travels';
import { HttpError, jsonFromError } from '../../../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../../../src/mobile-auth';
import { readJsonObject, requiredString } from '../../../../../../../../../src/validation';

export const runtime = 'nodejs';

type RouteContext = {
  params: Promise<{
    familyId: string;
    tripId: string;
    itineraryId: string;
  }>;
};

export async function PATCH(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, tripId, itineraryId } = await context.params;
    const payload = await readJsonObject(request);
    const itinerary = await updateTravelItinerary(
      userId,
      familyId,
      tripId,
      itineraryId,
      {
        itineraryDate: requiredString(payload, 'itineraryDate'),
        title: requiredString(payload, 'title', { maxLength: 80 }),
        content: optionalBlankString(payload, 'content'),
        mapUrl: optionalBlankString(payload, 'mapUrl'),
        startsAt: optionalBlankString(payload, 'startsAt'),
      },
    );

    return Response.json(itinerary);
  } catch (error) {
    return jsonFromError(error, 'travel_itinerary_update_failed');
  }
}

export async function DELETE(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, tripId, itineraryId } = await context.params;
    await deleteTravelItinerary(userId, familyId, tripId, itineraryId);

    return Response.json({ ok: true });
  } catch (error) {
    return jsonFromError(error, 'travel_itinerary_delete_failed');
  }
}

function optionalBlankString(payload: Record<string, unknown>, key: string) {
  const value = payload[key];

  if (value === undefined || value === null) {
    return undefined;
  }

  if (typeof value !== 'string') {
    throw new HttpError(400, { error: 'invalid_payload', field: key });
  }

  return value;
}
