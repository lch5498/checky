import {
  deleteScrapComment,
  updateScrapComment,
} from '../../../../../../../../../../../src/scraps';
import { jsonFromError } from '../../../../../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../../../../../src/mobile-auth';
import {
  readJsonObject,
  requiredString,
} from '../../../../../../../../../../../src/validation';

export const runtime = 'nodejs';

type RouteContext = {
  params: Promise<{
    familyId: string;
    channelId: string;
    postId: string;
    commentId: string;
  }>;
};

export async function DELETE(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, channelId, postId, commentId } = await context.params;
    await deleteScrapComment(userId, familyId, channelId, postId, commentId);

    return Response.json({ ok: true });
  } catch (error) {
    return jsonFromError(error, 'scrap_comment_delete_failed');
  }
}

export async function PATCH(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, channelId, postId, commentId } = await context.params;
    const payload = await readJsonObject(request);
    const comment = await updateScrapComment(
      userId,
      familyId,
      channelId,
      postId,
      commentId,
      {
        content: requiredString(payload, 'content', { maxLength: 1000 }),
      },
    );

    return Response.json(comment);
  } catch (error) {
    return jsonFromError(error, 'scrap_comment_update_failed');
  }
}
