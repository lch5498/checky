import {
  createScrapChannel,
  getScrapDashboard,
  reorderScrapChannels,
} from '../../../../../../src/scraps';
import { HttpError, jsonFromError } from '../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../src/mobile-auth';
import { readJsonObject, requiredString } from '../../../../../../src/validation';

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
    const dashboard = await getScrapDashboard(userId, familyId);

    return Response.json(dashboard);
  } catch (error) {
    return jsonFromError(error, 'scraps_fetch_failed');
  }
}

export async function POST(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId } = await context.params;
    const payload = await readJsonObject(request);
    const channel = await createScrapChannel(userId, familyId, {
      name: requiredString(payload, 'name', { maxLength: 60 }),
    });

    return Response.json(channel, { status: 201 });
  } catch (error) {
    return jsonFromError(error, 'scrap_channel_create_failed');
  }
}

export async function PATCH(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId } = await context.params;
    const payload = await readJsonObject(request);
    const dashboard = await reorderScrapChannels(userId, familyId, {
      channelIds: requiredStringArray(payload, 'channelIds'),
    });

    return Response.json(dashboard);
  } catch (error) {
    return jsonFromError(error, 'scrap_channels_reorder_failed');
  }
}

function requiredStringArray(
  payload: Record<string, unknown>,
  key: string,
) {
  const value = payload[key];

  if (
    !Array.isArray(value) ||
    value.length === 0 ||
    value.some((item) => typeof item !== 'string')
  ) {
    throw new HttpError(400, { error: 'invalid_payload', field: key });
  }

  return value as string[];
}
