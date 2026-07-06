import { jsonFromError } from '../../../../../src/http';
import { getBearerToken, verifySessionToken } from '../../../../../src/session';
import {
  deleteUserAccount,
  getUserById,
  updateUserNickname,
} from '../../../../../src/users';
import {
  readJsonObject,
  requiredString,
} from '../../../../../src/validation';

export const runtime = 'nodejs';

export async function GET(request: Request) {
  try {
    const session = authenticateRequest(request);
    const user = await getUserById(session.sub);

    if (!user) {
      return Response.json({ error: 'user_not_found' }, { status: 401 });
    }

    return Response.json({ user });
  } catch (error) {
    if (error instanceof Response) {
      return error;
    }

    console.error(error);
    return Response.json({ error: 'session_check_failed' }, { status: 500 });
  }
}

export async function PATCH(request: Request) {
  try {
    const session = authenticateRequest(request);
    const payload = await readJsonObject(request);
    const nickname = requiredString(payload, 'nickname', { maxLength: 30 });
    const user = await updateUserNickname(session.sub, nickname, {
      updateFamilyMemberNicknames:
        payload.updateFamilyMemberNicknames === true,
    });

    return Response.json({ user });
  } catch (error) {
    if (error instanceof Response) {
      return error;
    }

    return jsonFromError(error, 'profile_update_failed');
  }
}

export async function DELETE(request: Request) {
  try {
    const session = authenticateRequest(request);
    await deleteUserAccount(session.sub);

    return new Response(null, { status: 204 });
  } catch (error) {
    if (error instanceof Response) {
      return error;
    }

    return jsonFromError(error, 'account_delete_failed');
  }
}

function authenticateRequest(request: Request) {
  const token = getBearerToken(request);

  if (!token) {
    throw Response.json({ error: 'missing_token' }, { status: 401 });
  }

  const session = verifySessionToken(token);

  if (!session) {
    throw Response.json({ error: 'invalid_token' }, { status: 401 });
  }

  return session;
}
