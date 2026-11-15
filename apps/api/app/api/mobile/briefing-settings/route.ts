import { getBriefingSettings, updateBriefingSettings } from '../../../../src/briefings';
import { jsonFromError } from '../../../../src/http';
import { authenticateMobileRequest } from '../../../../src/mobile-auth';
import { readJsonObject } from '../../../../src/validation';

export const runtime = 'nodejs';

export async function GET(request: Request) {
  try {
    const userId = authenticateMobileRequest(request);
    const settings = await getBriefingSettings(userId);

    return Response.json({ settings });
  } catch (error) {
    return jsonFromError(error, 'briefing_settings_fetch_failed');
  }
}

export async function PUT(request: Request) {
  try {
    const userId = authenticateMobileRequest(request);
    const payload = await readJsonObject(request);
    const settings = await updateBriefingSettings(userId, payload);

    return Response.json({ settings });
  } catch (error) {
    return jsonFromError(error, 'briefing_settings_update_failed');
  }
}
