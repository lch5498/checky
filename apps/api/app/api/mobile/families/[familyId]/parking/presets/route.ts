import {
  createParkingLocationPreset,
  listParkingLocationPresets,
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
    const presets = await listParkingLocationPresets(userId, familyId);

    return Response.json({ presets });
  } catch (error) {
    return jsonFromError(error, 'parking_presets_fetch_failed');
  }
}

export async function POST(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId } = await context.params;
    const payload = await readJsonObject(request);
    const name = requiredString(payload, 'name', { maxLength: 40 });
    const preset = await createParkingLocationPreset(userId, familyId, { name });

    return Response.json({ preset }, { status: 201 });
  } catch (error) {
    return jsonFromError(error, 'parking_preset_create_failed');
  }
}
