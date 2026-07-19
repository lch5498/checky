import { requireMembership } from '../../../../../../src/families';
import { HttpError, jsonFromError } from '../../../../../../src/http';
import { listKoreanHolidays } from '../../../../../../src/korean-holidays';
import { authenticateMobileRequest } from '../../../../../../src/mobile-auth';

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
    const { searchParams } = new URL(request.url);
    const rangeStart = searchParams.get('rangeStart');
    const rangeEnd = searchParams.get('rangeEnd');

    if (!rangeStart || !rangeEnd) {
      throw new HttpError(400, { error: 'invalid_payload', field: 'range' });
    }

    await requireMembership(userId, familyId);
    const holidays = await listKoreanHolidays(rangeStart, rangeEnd);

    return Response.json({ holidays });
  } catch (error) {
    return jsonFromError(error, 'holidays_fetch_failed');
  }
}
