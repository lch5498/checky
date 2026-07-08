import { getTravelTripDetail } from '../../../../../../../src/travels';
import { jsonFromError } from '../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../src/mobile-auth';

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
    const detail = await getTravelTripDetail(userId, familyId, tripId);

    return Response.json(detail);
  } catch (error) {
    return jsonFromError(error, 'travel_trip_fetch_failed');
  }
}
