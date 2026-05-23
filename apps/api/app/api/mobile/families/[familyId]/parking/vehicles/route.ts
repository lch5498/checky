import {
  createVehicle,
  listVehicles,
} from '../../../../../../../src/parking';
import { jsonFromError } from '../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../src/mobile-auth';
import {
  readJsonObject,
  requiredString,
} from '../../../../../../../src/validation';

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
    const vehicles = await listVehicles(userId, familyId);

    return Response.json({ vehicles });
  } catch (error) {
    return jsonFromError(error, 'vehicles_fetch_failed');
  }
}

export async function POST(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId } = await context.params;
    const payload = await readJsonObject(request);
    const nickname = requiredString(payload, 'nickname', { maxLength: 30 });
    const plateNumber = requiredString(payload, 'plateNumber', { maxLength: 30 });
    const vehicle = await createVehicle(userId, familyId, {
      nickname,
      plateNumber,
    });

    return Response.json({ vehicle }, { status: 201 });
  } catch (error) {
    return jsonFromError(error, 'vehicle_create_failed');
  }
}
