import {
  createTravelTag,
  getTravelTags,
} from '../../../../../../../src/travels';
import { jsonFromError } from '../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../src/mobile-auth';
import { readJsonObject, requiredString } from '../../../../../../../src/validation';

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
    const tags = await getTravelTags(userId, familyId);

    return Response.json({ tags });
  } catch (error) {
    return jsonFromError(error, 'travel_tags_fetch_failed');
  }
}

export async function POST(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId } = await context.params;
    const payload = await readJsonObject(request);
    const tag = await createTravelTag(userId, familyId, {
      name: requiredString(payload, 'name', { maxLength: 24 }),
    });

    return Response.json(tag, { status: 201 });
  } catch (error) {
    return jsonFromError(error, 'travel_tag_create_failed');
  }
}
