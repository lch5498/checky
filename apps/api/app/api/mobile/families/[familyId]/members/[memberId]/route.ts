import { removeFamilyMember } from '../../../../../../../src/families';
import { jsonFromError } from '../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../src/mobile-auth';

export const runtime = 'nodejs';

type RouteContext = {
  params: Promise<{
    familyId: string;
    memberId: string;
  }>;
};

export async function DELETE(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, memberId } = await context.params;

    await removeFamilyMember(userId, familyId, memberId);

    return Response.json({ ok: true });
  } catch (error) {
    return jsonFromError(error, 'family_member_delete_failed');
  }
}
