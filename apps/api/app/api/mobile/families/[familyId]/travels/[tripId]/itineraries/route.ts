import { createTravelItinerary } from '../../../../../../../../src/travels';
import { jsonFromError } from '../../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../../src/mobile-auth';
import { HttpError } from '../../../../../../../../src/http';
import { readJsonObject, requiredString } from '../../../../../../../../src/validation';

export const runtime = 'nodejs';

type RouteContext = {
  params: Promise<{
    familyId: string;
    tripId: string;
  }>;
};

export async function POST(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, tripId } = await context.params;
    const payload = await readJsonObject(request);
    const itinerary = await createTravelItinerary(userId, familyId, tripId, {
      itineraryDate: requiredString(payload, 'itineraryDate'),
      title: requiredString(payload, 'title', { maxLength: 80 }),
      content: optionalBlankString(payload, 'content'),
      mapUrl: optionalBlankString(payload, 'mapUrl'),
      startsAt: optionalBlankString(payload, 'startsAt'),
    });

    return Response.json(itinerary, { status: 201 });
  } catch (error) {
    return jsonFromError(error, 'travel_itinerary_create_failed');
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
