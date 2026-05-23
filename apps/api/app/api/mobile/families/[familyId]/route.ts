import {
  deleteFamily,
  getFamilyDetail,
  updateFamily,
} from '../../../../../src/families';
import { jsonFromError } from '../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../src/mobile-auth';
import {
  readJsonObject,
  requiredString,
} from '../../../../../src/validation';

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
    const detail = await getFamilyDetail(userId, familyId);

    return Response.json(detail);
  } catch (error) {
    return jsonFromError(error, 'family_fetch_failed');
  }
}

export async function PATCH(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId } = await context.params;
    const payload = await readJsonObject(request);
    const name = requiredString(payload, 'name', { maxLength: 50 });
    const family = await updateFamily(userId, familyId, name);

    return Response.json({ family });
  } catch (error) {
    return jsonFromError(error, 'family_update_failed');
  }
}

export async function DELETE(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId } = await context.params;

    await deleteFamily(userId, familyId);

    return Response.json({ ok: true });
  } catch (error) {
    return jsonFromError(error, 'family_delete_failed');
  }
}
