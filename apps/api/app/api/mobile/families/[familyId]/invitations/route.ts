import {
  createFamilyInvitation,
  getInviteUrl,
} from '../../../../../../src/families';
import { jsonFromError } from '../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../src/mobile-auth';
import {
  readJsonObject,
  requiredString,
} from '../../../../../../src/validation';

export const runtime = 'nodejs';

type RouteContext = {
  params: Promise<{
    familyId: string;
  }>;
};

export async function POST(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId } = await context.params;
    const payload = await readJsonObject(request);
    const memberId = requiredString(payload, 'memberId');
    const invitation = await createFamilyInvitation(userId, familyId, memberId);

    return Response.json(
      {
        invitation: {
          ...invitation,
          invite_url: getInviteUrl(invitation.invite_token),
        },
      },
      { status: 201 },
    );
  } catch (error) {
    return jsonFromError(error, 'family_invitation_create_failed');
  }
}
