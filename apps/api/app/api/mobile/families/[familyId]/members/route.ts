import {
  createFamilyMember,
  listFamilyMembers,
} from '../../../../../../src/families';
import { jsonFromError } from '../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../src/mobile-auth';
import {
  readJsonObject,
  requiredFamilyRole,
  requiredString,
} from '../../../../../../src/validation';

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

export async function POST(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId } = await context.params;
    const payload = await readJsonObject(request);
    const nickname = requiredString(payload, 'nickname', { maxLength: 40 });
    const role = requiredFamilyRole(payload, 'role');
    const member = await createFamilyMember(userId, familyId, {
      nickname,
      role,
    });

    return Response.json({ member }, { status: 201 });
  } catch (error) {
    return jsonFromError(error, 'family_member_create_failed');
  }
}
