import {
  deleteParkingLocationPreset,
  updateParkingLocationPreset,
} from '../../../../../../../../src/parking';
import { jsonFromError } from '../../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../../src/mobile-auth';
import {
  optionalString,
  readJsonObject,
  requiredString,
} from '../../../../../../../../src/validation';

export const runtime = 'nodejs';

type RouteContext = {
  params: Promise<{
    familyId: string;
    presetId: string;
  }>;
};

export async function PATCH(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, presetId } = await context.params;
    const payload = await readJsonObject(request);
    const name = requiredString(payload, 'name', { maxLength: 40 });
    const presetType = requiredString(payload, 'presetType');
    const parentPresetId = optionalString(payload, 'parentPresetId');
    const preset = await updateParkingLocationPreset(userId, familyId, presetId, {
      presetType,
      name,
      parentPresetId,
    });

    return Response.json({ preset });
  } catch (error) {
    return jsonFromError(error, 'parking_preset_update_failed');
  }
}

export async function DELETE(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, presetId } = await context.params;

    await deleteParkingLocationPreset(userId, familyId, presetId);

    return Response.json({ ok: true });
  } catch (error) {
    return jsonFromError(error, 'parking_preset_delete_failed');
  }
}
