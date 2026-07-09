import {
  createTravelTripChecklistItem,
  getTravelTripChecklistItems,
} from '../../../../../../../../src/travels';
import { jsonFromError } from '../../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../../src/mobile-auth';
import { readJsonObject, requiredString } from '../../../../../../../../src/validation';

export const runtime = 'nodejs';

type RouteContext = {
  params: Promise<{
    familyId: string;
    tripId: string;
  }>;
};

export async function GET(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, tripId } = await context.params;
    const items = await getTravelTripChecklistItems(userId, familyId, tripId);

    return Response.json({ items });
  } catch (error) {
    return jsonFromError(error, 'travel_trip_checklist_items_fetch_failed');
  }
}

export async function POST(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, tripId } = await context.params;
    const payload = await readJsonObject(request);
    const item = await createTravelTripChecklistItem(userId, familyId, tripId, {
      name: requiredString(payload, 'name', { maxLength: 40 }),
    });

    return Response.json(item, { status: 201 });
  } catch (error) {
    return jsonFromError(error, 'travel_trip_checklist_item_create_failed');
  }
}
