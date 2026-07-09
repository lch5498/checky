import {
  deleteTravelChecklistItem,
  updateTravelChecklistItem,
} from '../../../../../../../../src/travels';
import { jsonFromError } from '../../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../../src/mobile-auth';
import { readJsonObject, requiredString } from '../../../../../../../../src/validation';

export const runtime = 'nodejs';

type RouteContext = {
  params: Promise<{
    familyId: string;
    itemId: string;
  }>;
};

export async function PATCH(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, itemId } = await context.params;
    const payload = await readJsonObject(request);
    const item = await updateTravelChecklistItem(userId, familyId, itemId, {
      name: requiredString(payload, 'name', { maxLength: 40 }),
    });

    return Response.json(item);
  } catch (error) {
    return jsonFromError(error, 'travel_checklist_item_update_failed');
  }
}

export async function DELETE(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, itemId } = await context.params;
    await deleteTravelChecklistItem(userId, familyId, itemId);

    return Response.json({ ok: true });
  } catch (error) {
    return jsonFromError(error, 'travel_checklist_item_delete_failed');
  }
}
