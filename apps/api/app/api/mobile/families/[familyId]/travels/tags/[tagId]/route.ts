import {
  deleteTravelTag,
  updateTravelTag,
} from '../../../../../../../../src/travels';
import { jsonFromError } from '../../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../../src/mobile-auth';
import { readJsonObject, requiredString } from '../../../../../../../../src/validation';

export const runtime = 'nodejs';

type RouteContext = {
  params: Promise<{
    familyId: string;
    tagId: string;
  }>;
};

export async function PATCH(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, tagId } = await context.params;
    const payload = await readJsonObject(request);
    const tag = await updateTravelTag(userId, familyId, tagId, {
      name: requiredString(payload, 'name', { maxLength: 24 }),
    });

    return Response.json(tag);
  } catch (error) {
    return jsonFromError(error, 'travel_tag_update_failed');
  }
}

export async function DELETE(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, tagId } = await context.params;
    await deleteTravelTag(userId, familyId, tagId);

    return Response.json({ ok: true });
  } catch (error) {
    return jsonFromError(error, 'travel_tag_delete_failed');
  }
}
