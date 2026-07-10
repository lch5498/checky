import {
  createTravelChecklistItem,
  getTravelChecklistItems,
} from '../../../../../../../src/travels';
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

export async function GET(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId } = await context.params;
    const items = await getTravelChecklistItems(userId, familyId);

    return Response.json({ items });
  } catch (error) {
    return jsonFromError(error, 'travel_checklist_items_fetch_failed');
  }
}

export async function POST(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId } = await context.params;
    const payload = await readJsonObject(request);
    const item = await createTravelChecklistItem(userId, familyId, {
      name: requiredString(payload, 'name', { maxLength: 40 }),
      parentId: optionalString(payload, 'parentId'),
    });

    return Response.json(item, { status: 201 });
  } catch (error) {
    return jsonFromError(error, 'travel_checklist_item_create_failed');
  }
}
