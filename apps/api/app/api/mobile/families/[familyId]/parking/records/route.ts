import { createParkingRecord } from '../../../../../../../src/parking';
import { HttpError, jsonFromError } from '../../../../../../../src/http';
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
    const buildingPresetId = optionalString(payload, 'buildingPresetId');
    const floorPresetId = optionalString(payload, 'floorPresetId');
    const detailPresetId = optionalString(payload, 'detailPresetId');
    const buildingText = requiredString(payload, 'buildingText', {
      maxLength: 40,
    });
    const floorText = requiredString(payload, 'floorText', { maxLength: 40 });
    const detailText = optionalText(payload, 'detailText', { maxLength: 40 });
    const record = await createParkingRecord(userId, familyId, {
      vehicleId,
      buildingPresetId,
      floorPresetId,
      detailPresetId,
      buildingText,
      floorText,
      detailText,
    });

    return Response.json({ record }, { status: 201 });
  } catch (error) {
    return jsonFromError(error, 'parking_record_create_failed');
  }
}

function optionalText(
  payload: Record<string, unknown>,
  key: string,
  options: { maxLength?: number } = {},
) {
  const value = payload[key];

  if (value === undefined || value === null) {
    return '';
  }

  if (typeof value !== 'string') {
    throw new HttpError(400, { error: 'invalid_payload', field: key });
  }

  const normalized = value.trim();

  if (options.maxLength && normalized.length > options.maxLength) {
    throw new HttpError(400, { error: 'invalid_payload', field: key });
  }

  return normalized;
}
