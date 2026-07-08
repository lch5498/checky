import {
  createTravelItinerary,
  reorderTravelItineraries,
} from '../../../../../../../../src/travels';
import { HttpError, jsonFromError } from '../../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../../src/mobile-auth';
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

export async function PATCH(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, tripId } = await context.params;
    const payload = await readJsonObject(request);
    const detail = await reorderTravelItineraries(userId, familyId, tripId, {
      items: requiredReorderItems(payload, 'items'),
    });

    return Response.json(detail);
  } catch (error) {
    return jsonFromError(error, 'travel_itineraries_reorder_failed');
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

function requiredReorderItems(payload: Record<string, unknown>, key: string) {
  const value = payload[key];

  if (!Array.isArray(value)) {
    throw new HttpError(400, { error: 'invalid_payload', field: key });
  }

  return value.map((item, index) => {
    if (!item || typeof item !== 'object' || Array.isArray(item)) {
      throw new HttpError(400, {
        error: 'invalid_payload',
        field: `${key}.${index}`,
      });
    }

    const record = item as Record<string, unknown>;
    const id = record.id;
    const itineraryDate = record.itineraryDate;

    if (typeof id !== 'string' || typeof itineraryDate !== 'string') {
      throw new HttpError(400, {
        error: 'invalid_payload',
        field: `${key}.${index}`,
      });
    }

    return { id, itineraryDate };
  });
}
