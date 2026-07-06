import {
  assertFamilyMemberColor,
  removeFamilyMember,
  updateFamilyMember,
} from '../../../../../../../src/families';
import { jsonFromError } from '../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../src/mobile-auth';
import {
  readJsonObject,
  optionalString,
} from '../../../../../../../src/validation';

export const runtime = 'nodejs';

type RouteContext = {
  params: Promise<{
    familyId: string;
    memberId: string;
  }>;
};

export async function PATCH(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, memberId } = await context.params;
    const payload = await readJsonObject(request);
    const nickname = optionalString(payload, 'nickname', { maxLength: 40 });
    const color = optionalString(payload, 'color', { maxLength: 20 });

    if (color !== undefined) {
      assertFamilyMemberColor(color);
    }

    const member = await updateFamilyMember(userId, familyId, memberId, {
      nickname,
      color,
    });

    return Response.json({ member });
  } catch (error) {
    return jsonFromError(error, 'family_member_update_failed');
  }
}

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
