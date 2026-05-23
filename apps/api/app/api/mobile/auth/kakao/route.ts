import { getKakaoUser } from '../../../../../src/kakao';
import { jsonFromError } from '../../../../../src/http';
import {
  createSessionToken,
  getSessionTtlSeconds,
} from '../../../../../src/session';
import { findOrCreateUserFromKakao } from '../../../../../src/users';
import {
  optionalString,
  readJsonObject,
  requiredString,
} from '../../../../../src/validation';

export const runtime = 'nodejs';

export async function POST(request: Request) {
  try {
    const payload = await readJsonObject(request);
    const accessToken = requiredString(payload, 'accessToken');
    const nickname = optionalString(payload, 'nickname', { maxLength: 30 });
    const kakaoUser = await getKakaoUser(accessToken);
    const loginResult = await findOrCreateUserFromKakao(kakaoUser, {
      nickname,
    });

    if (loginResult.requiresProfile) {
      return Response.json(
        {
          error: 'profile_required',
          provider: loginResult.provider,
          providerId: loginResult.providerId,
        },
        { status: 409 },
      );
    }

    const user = loginResult.user;
    const sessionToken = createSessionToken(user.id);

    return Response.json({
      tokenType: 'Bearer',
      accessToken: sessionToken,
      expiresIn: getSessionTtlSeconds(),
      isNewUser: loginResult.isNewUser,
      user,
    });
  } catch (error) {
    return jsonFromError(error, 'login_failed');
  }
}
