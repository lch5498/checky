import { listFamilyMembers } from '../../../../../../src/families';
import { jsonFromError } from '../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../src/mobile-auth';

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
    const members = await listFamilyMembers(userId, familyId);

    return Response.json({ members });
  } catch (error) {
    return jsonFromError(error, 'family_members_fetch_failed');
  }
}
