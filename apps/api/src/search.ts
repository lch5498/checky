import { presentWithCompletionNames } from './coupons';
import { requireMembership } from './families';
import { HttpError } from './http';
import { getSupabaseAdmin } from './supabase';

export const SEARCH_RESULT_TYPES = [
  'schedule',
  'coupon',
  'scrap_post',
  'scrap_comment',
  'travel_trip',
  'travel_itinerary',
  'parking',
] as const;

export type SearchResultType = (typeof SEARCH_RESULT_TYPES)[number];

export const SEARCH_MIN_QUERY_LENGTH = 2;
export const SEARCH_MAX_QUERY_LENGTH = 100;
export const SEARCH_MAX_TERMS = 8;
export const SEARCH_PER_TYPE_LIMIT = 20;

type SearchRow = {
  result_type: SearchResultType;
  id: string;
  display_order: number;
  occurred_at: string;
  payload: Record<string, unknown>;
};

export type SearchSection = {
  items: Array<Record<string, unknown>>;
  has_more: boolean;
};

export type SearchResponse = {
  query: string;
  results: Record<SearchResultType, SearchSection>;
};

/// Splits a query into distinct non-empty words. Returns [] when it is too short to search.
export function parseSearchTerms(rawQuery: string) {
  const query = rawQuery.trim();

  if (query.length < SEARCH_MIN_QUERY_LENGTH) {
    return [];
  }

  const terms = [...new Set(query.split(/\s+/).filter((term) => term.length > 0))];
  return terms.slice(0, SEARCH_MAX_TERMS);
}

function parseResultTypes(raw: string | null): SearchResultType[] | null {
  if (!raw || raw.trim() === '') {
    return null;
  }

  const types = [...new Set(raw.split(',').map((value) => value.trim()).filter(Boolean))];
  const invalid = types.filter(
    (type) => !SEARCH_RESULT_TYPES.includes(type as SearchResultType),
  );

  if (types.length === 0 || invalid.length > 0) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'types' });
  }

  return types as SearchResultType[];
}

/// Schedules are anchored to the caller's end of today. Missing means "server now".
function parseAnchor(raw: string | null): string | null {
  if (!raw || raw.trim() === '') {
    return null;
  }

  const parsed = new Date(raw);

  if (Number.isNaN(parsed.getTime())) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'anchor' });
  }

  return parsed.toISOString();
}

function emptyResults(): Record<SearchResultType, SearchSection> {
  const results = {} as Record<SearchResultType, SearchSection>;

  for (const type of SEARCH_RESULT_TYPES) {
    results[type] = { items: [], has_more: false };
  }

  return results;
}

export async function searchFamilyContent(
  userId: string,
  familyId: string,
  options: { query: string; types?: string | null; anchor?: string | null },
): Promise<SearchResponse> {
  const member = await requireMembership(userId, familyId);
  const query = options.query.trim();

  if (query.length < SEARCH_MIN_QUERY_LENGTH || query.length > SEARCH_MAX_QUERY_LENGTH) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'q' });
  }

  const terms = parseSearchTerms(query);
  const types = parseResultTypes(options.types ?? null);
  const anchor = parseAnchor(options.anchor ?? null);
  const { data, error } = await getSupabaseAdmin().rpc('search_family_content', {
    target_family_id: familyId,
    search_terms: terms,
    // One extra row per type tells the client that more results exist.
    per_type_limit: SEARCH_PER_TYPE_LIMIT + 1,
    result_types: types,
    ...(anchor ? { schedule_anchor: anchor } : {}),
  });

  if (error) {
    throw error;
  }

  const results = emptyResults();
  const rowsByType = new Map<SearchResultType, SearchRow[]>();

  for (const row of (data ?? []) as SearchRow[]) {
    const rows = rowsByType.get(row.result_type) ?? [];
    rows.push(row);
    rowsByType.set(row.result_type, rows);
  }

  for (const [type, rows] of rowsByType) {
    // The function already orders each type for display; display_order makes that explicit.
    const sorted = [...rows].sort((a, b) => a.display_order - b.display_order);
    const visible = sorted.slice(0, SEARCH_PER_TYPE_LIMIT);
    let items = visible.map((row) => row.payload);

    if (type === 'coupon') {
      items = await presentWithCompletionNames(
        items as Parameters<typeof presentWithCompletionNames>[0],
        familyId,
        userId,
        member.role,
      );
    }

    results[type] = { items, has_more: sorted.length > SEARCH_PER_TYPE_LIMIT };
  }

  return { query, results };
}
