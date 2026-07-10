import { saveTravelTripChecklistItemsToFavorites } from '../../../../../../../../../src/travels';
import { jsonFromError } from '../../../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../../../src/mobile-auth';

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
    const items = await saveTravelTripChecklistItemsToFavorites(
      userId,
      familyId,
      tripId,
    );

    return Response.json({ items });
  } catch (error) {
    return jsonFromError(error, 'travel_trip_checklist_favorites_save_failed');
  }
}
