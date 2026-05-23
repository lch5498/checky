import {
  acceptFamilyInvitation,
  getInvitationPreview,
} from '../../../../../src/families';
import { jsonFromError } from '../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../src/mobile-auth';

export const runtime = 'nodejs';

type RouteContext = {
  params: Promise<{
    inviteToken: string;
  }>;
};

export async function GET(request: Request, context: RouteContext) {
  try {
    authenticateMobileRequest(request);
    const { inviteToken } = await context.params;
    const invitation = await getInvitationPreview(inviteToken);

    return Response.json({ invitation });
  } catch (error) {
    return jsonFromError(error, 'family_invitation_fetch_failed');
  }
}

export async function POST(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { inviteToken } = await context.params;
    const detail = await acceptFamilyInvitation(userId, inviteToken);

    return Response.json(detail);
  } catch (error) {
    return jsonFromError(error, 'family_invitation_accept_failed');
  }
}
