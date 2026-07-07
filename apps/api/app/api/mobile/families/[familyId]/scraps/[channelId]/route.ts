import {
  createScrapPost,
  deleteScrapChannel,
  getScrapChannel,
  updateScrapChannel,
} from '../../../../../../../src/scraps';
import { jsonFromError } from '../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../src/mobile-auth';
import { readJsonObject, requiredString } from '../../../../../../../src/validation';

export const runtime = 'nodejs';

type RouteContext = {
  params: Promise<{
    familyId: string;
    channelId: string;
  }>;
};

export async function GET(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, channelId } = await context.params;
    const channel = await getScrapChannel(userId, familyId, channelId);

    return Response.json(channel);
  } catch (error) {
    return jsonFromError(error, 'scrap_channel_fetch_failed');
  }
}

export async function POST(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, channelId } = await context.params;
    const payload = await readJsonObject(request);
    const post = await createScrapPost(userId, familyId, channelId, {
      content: requiredString(payload, 'content', { maxLength: 2000 }),
    });

    return Response.json(post, { status: 201 });
  } catch (error) {
    return jsonFromError(error, 'scrap_post_create_failed');
  }
}

export async function PATCH(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, channelId } = await context.params;
    const payload = await readJsonObject(request);
    const channel = await updateScrapChannel(userId, familyId, channelId, {
      name: requiredString(payload, 'name', { maxLength: 60 }),
    });

    return Response.json(channel);
  } catch (error) {
    return jsonFromError(error, 'scrap_channel_update_failed');
  }
}

export async function DELETE(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, channelId } = await context.params;
    await deleteScrapChannel(userId, familyId, channelId);

    return Response.json({ ok: true });
  } catch (error) {
    return jsonFromError(error, 'scrap_channel_delete_failed');
  }
}
