import { createParkingRecord } from '../../../../../../../src/parking';
import { jsonFromError } from '../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../src/mobile-auth';
import {
  optionalString,
  readJsonObject,
  requiredString,
} from '../../../../../../../src/validation';

export const runtime = 'nodejs';

type RouteContext = {
  params: Promise<{
    familyId: string;
  }>;
};

export async function POST(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId } = await context.params;
    const payload = await readJsonObject(request);
    const vehicleId = requiredString(payload, 'vehicleId');
    const presetId = optionalString(payload, 'presetId');
    const locationText = requiredString(payload, 'locationText', {
      maxLength: 80,
    });
    const record = await createParkingRecord(userId, familyId, {
      vehicleId,
      presetId,
      locationText,
    });

    return Response.json({ record }, { status: 201 });
  } catch (error) {
    return jsonFromError(error, 'parking_record_create_failed');
  }
}
