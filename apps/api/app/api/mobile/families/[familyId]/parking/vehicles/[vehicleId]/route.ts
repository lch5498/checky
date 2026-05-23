import {
  deleteVehicle,
  updateVehicle,
} from '../../../../../../../../src/parking';
import { jsonFromError } from '../../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../../src/mobile-auth';
import {
  readJsonObject,
  requiredString,
} from '../../../../../../../../src/validation';

export const runtime = 'nodejs';

type RouteContext = {
  params: Promise<{
    familyId: string;
    vehicleId: string;
  }>;
};

export async function PATCH(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, vehicleId } = await context.params;
    const payload = await readJsonObject(request);
    const nickname = requiredString(payload, 'nickname', { maxLength: 30 });
    const plateNumber = requiredString(payload, 'plateNumber', { maxLength: 30 });
    const vehicle = await updateVehicle(userId, familyId, vehicleId, {
      nickname,
      plateNumber,
    });

    return Response.json({ vehicle });
  } catch (error) {
    return jsonFromError(error, 'vehicle_update_failed');
  }
}

export async function DELETE(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, vehicleId } = await context.params;

    await deleteVehicle(userId, familyId, vehicleId);

    return Response.json({ ok: true });
  } catch (error) {
    return jsonFromError(error, 'vehicle_delete_failed');
  }
}
