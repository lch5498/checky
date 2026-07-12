import { jsonFromError } from '../../../../src/http';
import { authenticateMobileRequest } from '../../../../src/mobile-auth';
import { listPushNotificationHistory } from '../../../../src/notifications';

export const runtime = 'nodejs';

export async function GET(request: Request) {
  try {
    const userId = authenticateMobileRequest(request);
    const notifications = await listPushNotificationHistory(userId);

    return Response.json({ notifications });
  } catch (error) {
    return jsonFromError(error, 'push_notification_history_fetch_failed');
  }
}
