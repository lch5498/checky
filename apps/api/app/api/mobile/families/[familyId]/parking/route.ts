import { getParkingDashboard } from '../../../../../../src/parking';
import { jsonFromError } from '../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../src/mobile-auth';

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
    const dashboard = await getParkingDashboard(userId, familyId);

    return Response.json(dashboard);
  } catch (error) {
    return jsonFromError(error, 'parking_fetch_failed');
  }
}
