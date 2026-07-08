import {
  createTravelTrip,
  getTravelDashboard,
} from '../../../../../../src/travels';
import { jsonFromError } from '../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../src/mobile-auth';
import { readJsonObject, requiredString } from '../../../../../../src/validation';

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
    const dashboard = await getTravelDashboard(userId, familyId);

    return Response.json(dashboard);
  } catch (error) {
    return jsonFromError(error, 'travels_fetch_failed');
  }
}

export async function POST(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId } = await context.params;
    const payload = await readJsonObject(request);
    const trip = await createTravelTrip(userId, familyId, {
      title: requiredString(payload, 'title', { maxLength: 80 }),
      startsOn: requiredString(payload, 'startsOn'),
      endsOn: requiredString(payload, 'endsOn'),
    });

    return Response.json(trip, { status: 201 });
  } catch (error) {
    return jsonFromError(error, 'travel_trip_create_failed');
  }
}
