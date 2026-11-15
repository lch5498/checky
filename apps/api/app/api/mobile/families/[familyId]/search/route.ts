import { jsonFromError } from '../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../src/mobile-auth';
import { searchFamilyContent } from '../../../../../../src/search';

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
    const results = await searchFamilyContent(userId, familyId, {
      query: searchParams.get('q') ?? '',
      types: searchParams.get('types'),
      anchor: searchParams.get('anchor'),
    });

    return Response.json(results);
  } catch (error) {
    return jsonFromError(error, 'family_search_failed');
  }
}
