import {
  deleteScrapPost,
  updateScrapPost,
} from '../../../../../../../../../src/scraps';
import { jsonFromError } from '../../../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../../../src/mobile-auth';
import { readJsonObject, requiredString } from '../../../../../../../../../src/validation';

export const runtime = 'nodejs';

type RouteContext = {
  params: Promise<{
    familyId: string;
    channelId: string;
    postId: string;
  }>;
};

export async function DELETE(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, channelId, postId } = await context.params;
    await deleteScrapPost(userId, familyId, channelId, postId);

    return Response.json({ ok: true });
  } catch (error) {
    return jsonFromError(error, 'scrap_post_delete_failed');
  }
}

export async function PATCH(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, channelId, postId } = await context.params;
    const payload = await readJsonObject(request);
    const post = await updateScrapPost(userId, familyId, channelId, postId, {
      content: requiredString(payload, 'content', { maxLength: 2000 }),
    });

    return Response.json(post);
  } catch (error) {
    return jsonFromError(error, 'scrap_post_update_failed');
  }
}
