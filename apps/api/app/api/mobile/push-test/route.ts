import { sendFcmNotification } from '../../../../src/fcm';
import { HttpError, jsonFromError } from '../../../../src/http';
import { authenticateMobileRequest } from '../../../../src/mobile-auth';
import { listPushTokensForUser } from '../../../../src/push-tokens';
import { optionalString, readJsonObject } from '../../../../src/validation';

export const runtime = 'nodejs';

export async function POST(request: Request) {
  try {
    const userId = authenticateMobileRequest(request);
    const payload = await readJsonObject(request);
    const title =
      optionalString(payload, 'title', { maxLength: 80 }) ?? '체키 테스트 알림';
    const body =
      optionalString(payload, 'body', { maxLength: 200 }) ??
      '푸시 알림 연결이 정상입니다.';
    const validateOnly = payload.validateOnly === true;

    const tokens = await listPushTokensForUser(userId);

    if (tokens.length === 0) {
      throw new HttpError(404, { error: 'no_push_tokens' });
    }

    const results = await Promise.all(
      tokens.map(async (pushToken) => {
        const result = await sendFcmNotification({
          token: pushToken.token,
          title,
          body,
          validateOnly,
          data: {
            type: 'push_test',
          },
        });

        return {
          id: pushToken.id,
          platform: pushToken.platform,
          ...result,
        };
      }),
    );

    const successCount = results.filter((result) => result.ok).length;
    const failureCount = results.length - successCount;

    return Response.json(
      {
        ok: successCount > 0,
        validateOnly,
        tokenCount: tokens.length,
        successCount,
        failureCount,
        results,
      },
      { status: successCount > 0 ? 200 : 502 },
    );
  } catch (error) {
    return jsonFromError(error, 'push_test_failed');
  }
}
