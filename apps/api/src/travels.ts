import { requireMembership } from './families';
import { HttpError } from './http';
import { getSupabaseAdmin } from './supabase';

export type TravelTrip = {
  id: string;
  family_id: string;
  title: string;
  starts_on: string;
  ends_on: string;
  created_by_user_id: string | null;
  created_at: string;
  updated_at: string;
};

export type TravelItinerary = {
  id: string;
  family_id: string;
  trip_id: string;
  itinerary_date: string;
  title: string;
  content: string | null;
  map_url: string | null;
  starts_at: string | null;
  sort_order: number;
  created_by_user_id: string | null;
  created_at: string;
  updated_at: string;
};

export async function getTravelDashboard(userId: string, familyId: string) {
  await requireMembership(userId, familyId);

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('travel_trips')
    .select('*')
    .eq('family_id', familyId)
    .order('starts_on', { ascending: false })
    .order('created_at', { ascending: false });

  if (error) {
    throw error;
  }

  return { trips: (data ?? []) as TravelTrip[] };
}

export async function createTravelTrip(
  userId: string,
  familyId: string,
  input: { title: string; startsOn: string; endsOn: string },
) {
  await requireMembership(userId, familyId);

  const startsOn = normalizeDate(input.startsOn, 'startsOn');
  const endsOn = normalizeDate(input.endsOn, 'endsOn');

  if (endsOn < startsOn) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'endsOn' });
  }

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('travel_trips')
    .insert({
      family_id: familyId,
      title: normalizeText(input.title, 80, 'title'),
      starts_on: startsOn,
      ends_on: endsOn,
      created_by_user_id: userId,
    })
    .select('*')
    .single();

  if (error) {
    throw error;
  }

  return data as TravelTrip;
}

export async function getTravelTripDetail(
  userId: string,
  familyId: string,
  tripId: string,
) {
  await requireMembership(userId, familyId);
  const [trip, itineraries] = await Promise.all([
    getTripOrThrow(familyId, tripId),
    listItineraries(familyId, tripId),
  ]);

  return { trip, itineraries };
}

export async function createTravelItinerary(
  userId: string,
  familyId: string,
  tripId: string,
  input: {
    itineraryDate: string;
    title: string;
    content?: string;
    mapUrl?: string;
    startsAt?: string;
  },
) {
  await requireMembership(userId, familyId);
  const trip = await getTripOrThrow(familyId, tripId);
  const itineraryDate = normalizeDate(input.itineraryDate, 'itineraryDate');

  if (itineraryDate < trip.starts_on || itineraryDate > trip.ends_on) {
    throw new HttpError(400, {
      error: 'invalid_payload',
      field: 'itineraryDate',
    });
  }

  const supabase = getSupabaseAdmin();
  const sortOrder = await nextItinerarySortOrder(familyId, tripId, itineraryDate);
  const { data, error } = await supabase
    .from('travel_itineraries')
    .insert({
      family_id: familyId,
      trip_id: tripId,
      itinerary_date: itineraryDate,
      title: normalizeText(input.title, 80, 'title'),
      content: normalizeOptionalText(input.content, 2000, 'content'),
      map_url: normalizeOptionalText(input.mapUrl, 1000, 'mapUrl'),
      starts_at: normalizeOptionalTime(input.startsAt, 'startsAt'),
      sort_order: sortOrder,
      created_by_user_id: userId,
    })
    .select('*')
    .single();

  if (error) {
    throw error;
  }

  return data as TravelItinerary;
}

async function getTripOrThrow(familyId: string, tripId: string) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('travel_trips')
    .select('*')
    .eq('family_id', familyId)
    .eq('id', tripId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'travel_trip_not_found' });
  }

  return data as TravelTrip;
}

async function listItineraries(familyId: string, tripId: string) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('travel_itineraries')
    .select('*')
    .eq('family_id', familyId)
    .eq('trip_id', tripId)
    .order('itinerary_date', { ascending: true })
    .order('sort_order', { ascending: true })
    .order('created_at', { ascending: true });

  if (error) {
    throw error;
  }

  return (data ?? []) as TravelItinerary[];
}

async function nextItinerarySortOrder(
  familyId: string,
  tripId: string,
  itineraryDate: string,
) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('travel_itineraries')
    .select('sort_order')
    .eq('family_id', familyId)
    .eq('trip_id', tripId)
    .eq('itinerary_date', itineraryDate)
    .order('sort_order', { ascending: false })
    .limit(1);

  if (error) {
    throw error;
  }

  const lastSortOrder = (data?.[0]?.sort_order as number | undefined) ?? 0;
  return lastSortOrder + 1;
}

function normalizeText(value: string, maxLength: number, field: string) {
  const normalized = value.trim();

  if (!normalized || normalized.length > maxLength) {
    throw new HttpError(400, { error: 'invalid_payload', field });
  }

  return normalized;
}

function normalizeOptionalText(
  value: string | undefined,
  maxLength: number,
  field: string,
) {
  if (value === undefined || value === null) {
    return null;
  }

  const normalized = value.trim();
  if (!normalized) {
    return null;
  }

  if (normalized.length > maxLength) {
    throw new HttpError(400, { error: 'invalid_payload', field });
  }

  return normalized;
}

function normalizeDate(value: string, field: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new HttpError(400, { error: 'invalid_payload', field });
  }

  const date = new Date(`${value}T00:00:00.000Z`);
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
    throw new HttpError(400, { error: 'invalid_payload', field });
  }

  return value;
}

function normalizeOptionalTime(value: string | undefined, field: string) {
  if (value === undefined || value === null || !value.trim()) {
    return null;
  }

  const normalized = value.trim();
  const match = normalized.match(/^([01]\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?$/);
  if (!match) {
    throw new HttpError(400, { error: 'invalid_payload', field });
  }

  return `${match[1]}:${match[2]}:${match[3] ?? '00'}`;
}
