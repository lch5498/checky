import { requireMembership } from './families';
import { HttpError } from './http';
import { getSupabaseAdmin } from './supabase';

export type TravelTrip = {
  id: string;
  family_id: string;
  title: string;
  starts_on: string;
  ends_on: string;
  checklist_seeded_at: string | null;
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
  tags?: TravelTag[];
};

export type TravelTag = {
  id: string;
  family_id: string;
  name: string;
  created_by_user_id: string | null;
  created_at: string;
  updated_at: string;
};

export type TravelChecklistItem = {
  id: string;
  family_id: string;
  parent_id: string | null;
  name: string;
  created_by_user_id: string | null;
  created_at: string;
  updated_at: string;
};

export type TravelTripChecklistItem = {
  id: string;
  family_id: string;
  trip_id: string;
  parent_id: string | null;
  name: string;
  is_checked: boolean;
  sort_order: number;
  created_by_user_id: string | null;
  created_at: string;
  updated_at: string;
};

const DEFAULT_TRAVEL_TAGS = ['식당', '카페', '교통', '호텔', '관광', '숙소'];
const DEFAULT_TRAVEL_CHECKLIST_ITEMS = [
  '여권',
  '충전기',
  '보조배터리',
  '상비약',
  '세면도구',
];

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

export async function getTravelTags(userId: string, familyId: string) {
  await requireMembership(userId, familyId);

  return listTravelTags(userId, familyId);
}

export async function createTravelTag(
  userId: string,
  familyId: string,
  input: { name: string },
) {
  await requireMembership(userId, familyId);

  const [tag] = await ensureTravelTags(userId, familyId, [input.name]);
  if (!tag) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'name' });
  }

  return tag;
}

export async function updateTravelTag(
  userId: string,
  familyId: string,
  tagId: string,
  input: { name: string },
) {
  await requireMembership(userId, familyId);

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('travel_tags')
    .update({ name: normalizeText(input.name, 24, 'name') })
    .eq('family_id', familyId)
    .eq('id', tagId)
    .select('*')
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'travel_tag_not_found' });
  }

  return data as TravelTag;
}

export async function deleteTravelTag(
  userId: string,
  familyId: string,
  tagId: string,
) {
  await requireMembership(userId, familyId);

  const supabase = getSupabaseAdmin();
  const { error } = await supabase
    .from('travel_tags')
    .delete()
    .eq('family_id', familyId)
    .eq('id', tagId);

  if (error) {
    throw error;
  }
}

export async function getTravelChecklistItems(
  userId: string,
  familyId: string,
) {
  await requireMembership(userId, familyId);

  return listTravelChecklistItems(userId, familyId);
}

export async function createTravelChecklistItem(
  userId: string,
  familyId: string,
  input: { name: string; parentId?: string },
) {
  await requireMembership(userId, familyId);

  const name = normalizeText(input.name, 40, 'name');
  const parent = input.parentId
    ? await getTravelChecklistParentOrThrow(familyId, input.parentId)
    : null;

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('travel_checklist_items')
    .insert({
      family_id: familyId,
      parent_id: parent?.id ?? null,
      name,
      created_by_user_id: userId,
    })
    .select('*')
    .single();

  if (error) {
    throw error;
  }

  return data as TravelChecklistItem;
}

export async function updateTravelChecklistItem(
  userId: string,
  familyId: string,
  itemId: string,
  input: { name: string },
) {
  await requireMembership(userId, familyId);

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('travel_checklist_items')
    .update({ name: normalizeText(input.name, 40, 'name') })
    .eq('family_id', familyId)
    .eq('id', itemId)
    .select('*')
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'travel_checklist_item_not_found' });
  }

  return data as TravelChecklistItem;
}

export async function deleteTravelChecklistItem(
  userId: string,
  familyId: string,
  itemId: string,
) {
  await requireMembership(userId, familyId);

  const supabase = getSupabaseAdmin();
  const { error } = await supabase
    .from('travel_checklist_items')
    .delete()
    .eq('family_id', familyId)
    .eq('id', itemId);

  if (error) {
    throw error;
  }
}

export async function saveTravelTripChecklistItemsToFavorites(
  userId: string,
  familyId: string,
  tripId: string,
) {
  await requireMembership(userId, familyId);
  const trip = await getTripOrThrow(familyId, tripId);
  const tripItems = await listTravelTripChecklistItems(userId, familyId, trip);
  const supabase = getSupabaseAdmin();
  const { error: deleteError } = await supabase
    .from('travel_checklist_items')
    .delete()
    .eq('family_id', familyId);

  if (deleteError) {
    throw deleteError;
  }

  await ensureTravelChecklistTreeFromTripItems(userId, familyId, tripItems);

  return listTravelChecklistItems(userId, familyId);
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

export async function updateTravelTrip(
  userId: string,
  familyId: string,
  tripId: string,
  input: { title: string; startsOn: string; endsOn: string },
) {
  await requireMembership(userId, familyId);
  await getTripOrThrow(familyId, tripId);

  const startsOn = normalizeDate(input.startsOn, 'startsOn');
  const endsOn = normalizeDate(input.endsOn, 'endsOn');

  if (endsOn < startsOn) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'endsOn' });
  }

  const itineraries = await listItineraries(familyId, tripId);
  const outOfRangeItinerary = itineraries.find(
    (itinerary) =>
      itinerary.itinerary_date < startsOn || itinerary.itinerary_date > endsOn,
  );

  if (outOfRangeItinerary) {
    throw new HttpError(400, {
      error: 'travel_trip_date_range_has_itineraries',
      field: 'startsOn',
    });
  }

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('travel_trips')
    .update({
      title: normalizeText(input.title, 80, 'title'),
      starts_on: startsOn,
      ends_on: endsOn,
    })
    .eq('family_id', familyId)
    .eq('id', tripId)
    .select('*')
    .single();

  if (error) {
    throw error;
  }

  return data as TravelTrip;
}

export async function deleteTravelTrip(
  userId: string,
  familyId: string,
  tripId: string,
) {
  await requireMembership(userId, familyId);
  await getTripOrThrow(familyId, tripId);

  const supabase = getSupabaseAdmin();
  const { error } = await supabase
    .from('travel_trips')
    .delete()
    .eq('family_id', familyId)
    .eq('id', tripId);

  if (error) {
    throw error;
  }
}

export async function getTravelTripDetail(
  userId: string,
  familyId: string,
  tripId: string,
) {
  await requireMembership(userId, familyId);
  const trip = await getTripOrThrow(familyId, tripId);
  const [itineraries, tags, checklistItems] = await Promise.all([
    listItineraries(familyId, tripId),
    listTravelTags(userId, familyId),
    listTravelTripChecklistItems(userId, familyId, trip),
  ]);

  return { trip, itineraries, tags, checklistItems };
}

export async function getTravelTripChecklistItems(
  userId: string,
  familyId: string,
  tripId: string,
) {
  await requireMembership(userId, familyId);
  const trip = await getTripOrThrow(familyId, tripId);

  return listTravelTripChecklistItems(userId, familyId, trip);
}

export async function createTravelTripChecklistItem(
  userId: string,
  familyId: string,
  tripId: string,
  input: { name: string; parentId?: string },
) {
  await requireMembership(userId, familyId);
  const trip = await getTripOrThrow(familyId, tripId);
  await ensureTravelTripChecklistSeeded(userId, familyId, trip);

  const name = normalizeText(input.name, 40, 'name');
  const parent = input.parentId
    ? await getTravelTripChecklistParentOrThrow(familyId, tripId, input.parentId)
    : null;

  const supabase = getSupabaseAdmin();
  const sortOrder = await nextTravelTripChecklistSortOrder(
    familyId,
    tripId,
    parent?.id ?? null,
  );
  const { data, error } = await supabase
    .from('travel_trip_checklist_items')
    .insert({
      family_id: familyId,
      trip_id: tripId,
      parent_id: parent?.id ?? null,
      name,
      sort_order: sortOrder,
      created_by_user_id: userId,
    })
    .select('*')
    .single();

  if (error) {
    throw error;
  }

  return data as TravelTripChecklistItem;
}

export async function updateTravelTripChecklistItem(
  userId: string,
  familyId: string,
  tripId: string,
  itemId: string,
  input: { name?: string; isChecked?: boolean },
) {
  await requireMembership(userId, familyId);
  await getTripOrThrow(familyId, tripId);

  const update: { name?: string; is_checked?: boolean } = {};
  if (input.name !== undefined) {
    update.name = normalizeText(input.name, 40, 'name');
  }
  if (input.isChecked !== undefined) {
    update.is_checked = input.isChecked;
  }

  if (Object.keys(update).length === 0) {
    throw new HttpError(400, { error: 'invalid_payload' });
  }

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('travel_trip_checklist_items')
    .update(update)
    .eq('family_id', familyId)
    .eq('trip_id', tripId)
    .eq('id', itemId)
    .select('*')
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'travel_trip_checklist_item_not_found' });
  }

  return data as TravelTripChecklistItem;
}

export async function deleteTravelTripChecklistItem(
  userId: string,
  familyId: string,
  tripId: string,
  itemId: string,
) {
  await requireMembership(userId, familyId);
  await getTripOrThrow(familyId, tripId);

  const supabase = getSupabaseAdmin();
  const { error } = await supabase
    .from('travel_trip_checklist_items')
    .delete()
    .eq('family_id', familyId)
    .eq('trip_id', tripId)
    .eq('id', itemId);

  if (error) {
    throw error;
  }
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
    tagNames?: string[];
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

  await setItineraryTags(
    userId,
    familyId,
    (data as TravelItinerary).id,
    input.tagNames ?? [],
  );

  const [itinerary] = await attachItineraryTags(familyId, [
    data as TravelItinerary,
  ]);

  return itinerary;
}

export async function updateTravelItinerary(
  userId: string,
  familyId: string,
  tripId: string,
  itineraryId: string,
  input: {
    itineraryDate: string;
    title: string;
    content?: string;
    mapUrl?: string;
    startsAt?: string;
    tagNames?: string[];
  },
) {
  await requireMembership(userId, familyId);
  const trip = await getTripOrThrow(familyId, tripId);
  await getItineraryOrThrow(familyId, tripId, itineraryId);
  const itineraryDate = normalizeDate(input.itineraryDate, 'itineraryDate');

  if (itineraryDate < trip.starts_on || itineraryDate > trip.ends_on) {
    throw new HttpError(400, {
      error: 'invalid_payload',
      field: 'itineraryDate',
    });
  }

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('travel_itineraries')
    .update({
      itinerary_date: itineraryDate,
      title: normalizeText(input.title, 80, 'title'),
      content: normalizeOptionalText(input.content, 2000, 'content'),
      map_url: normalizeOptionalText(input.mapUrl, 1000, 'mapUrl'),
      starts_at: normalizeOptionalTime(input.startsAt, 'startsAt'),
    })
    .eq('family_id', familyId)
    .eq('trip_id', tripId)
    .eq('id', itineraryId)
    .select('*')
    .single();

  if (error) {
    throw error;
  }

  await setItineraryTags(userId, familyId, itineraryId, input.tagNames ?? []);
  await compactItinerarySortOrders(familyId, tripId);

  const [itinerary] = await attachItineraryTags(familyId, [
    data as TravelItinerary,
  ]);

  return itinerary;
}

export async function deleteTravelItinerary(
  userId: string,
  familyId: string,
  tripId: string,
  itineraryId: string,
) {
  await requireMembership(userId, familyId);
  await getItineraryOrThrow(familyId, tripId, itineraryId);

  const supabase = getSupabaseAdmin();
  const { error } = await supabase
    .from('travel_itineraries')
    .delete()
    .eq('family_id', familyId)
    .eq('trip_id', tripId)
    .eq('id', itineraryId);

  if (error) {
    throw error;
  }

  await compactItinerarySortOrders(familyId, tripId);
}

export async function reorderTravelItineraries(
  userId: string,
  familyId: string,
  tripId: string,
  input: { items: { id: string; itineraryDate: string }[] },
) {
  await requireMembership(userId, familyId);
  const trip = await getTripOrThrow(familyId, tripId);
  const existing = await listItineraries(familyId, tripId);

  if (existing.length !== input.items.length) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'items' });
  }

  const existingIds = new Set(existing.map((item) => item.id));
  const inputIds = new Set(input.items.map((item) => item.id));

  if (
    inputIds.size !== input.items.length ||
    existing.length !== inputIds.size ||
    [...inputIds].some((id) => !existingIds.has(id))
  ) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'items' });
  }

  const sortOrderByDate = new Map<string, number>();
  const updates = input.items.map((item) => {
    const itineraryDate = normalizeDate(item.itineraryDate, 'itineraryDate');

    if (itineraryDate < trip.starts_on || itineraryDate > trip.ends_on) {
      throw new HttpError(400, {
        error: 'invalid_payload',
        field: 'itineraryDate',
      });
    }

    const sortOrder = (sortOrderByDate.get(itineraryDate) ?? 0) + 1;
    sortOrderByDate.set(itineraryDate, sortOrder);

    return {
      id: item.id,
      itineraryDate,
      sortOrder,
    };
  });

  const supabase = getSupabaseAdmin();
  const results = await Promise.all(
    updates.map((item) =>
      supabase
        .from('travel_itineraries')
        .update({
          itinerary_date: item.itineraryDate,
          sort_order: item.sortOrder,
        })
        .eq('family_id', familyId)
        .eq('trip_id', tripId)
        .eq('id', item.id),
    ),
  );

  const updateError = results.find((result) => result.error)?.error;
  if (updateError) {
    throw updateError;
  }

  return getTravelTripDetail(userId, familyId, tripId);
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

async function getItineraryOrThrow(
  familyId: string,
  tripId: string,
  itineraryId: string,
) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('travel_itineraries')
    .select('*')
    .eq('family_id', familyId)
    .eq('trip_id', tripId)
    .eq('id', itineraryId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'travel_itinerary_not_found' });
  }

  return data as TravelItinerary;
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

  return attachItineraryTags(familyId, (data ?? []) as TravelItinerary[]);
}

async function listTravelTags(userId: string, familyId: string) {
  await ensureTravelTags(userId, familyId, DEFAULT_TRAVEL_TAGS);

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('travel_tags')
    .select('*')
    .eq('family_id', familyId)
    .order('name', { ascending: true });

  if (error) {
    throw error;
  }

  return (data ?? []) as TravelTag[];
}

async function listTravelChecklistItems(userId: string, familyId: string) {
  await ensureTravelChecklistItems(
    userId,
    familyId,
    DEFAULT_TRAVEL_CHECKLIST_ITEMS,
  );

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('travel_checklist_items')
    .select('*')
    .eq('family_id', familyId)
    .order('parent_id', { ascending: true, nullsFirst: true })
    .order('name', { ascending: true })
    .order('created_at', { ascending: true });

  if (error) {
    throw error;
  }

  return (data ?? []) as TravelChecklistItem[];
}

async function listTravelTripChecklistItems(
  userId: string,
  familyId: string,
  trip: TravelTrip,
) {
  await ensureTravelTripChecklistSeeded(userId, familyId, trip);

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('travel_trip_checklist_items')
    .select('*')
    .eq('family_id', familyId)
    .eq('trip_id', trip.id)
    .order('parent_id', { ascending: true, nullsFirst: true })
    .order('sort_order', { ascending: true })
    .order('created_at', { ascending: true });

  if (error) {
    throw error;
  }

  return (data ?? []) as TravelTripChecklistItem[];
}

async function attachItineraryTags(
  familyId: string,
  itineraries: TravelItinerary[],
) {
  if (itineraries.length === 0) {
    return itineraries;
  }

  const itineraryIds = itineraries.map((itinerary) => itinerary.id);
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('travel_itinerary_tags')
    .select('itinerary_id, tag:travel_tags (*)')
    .eq('family_id', familyId)
    .in('itinerary_id', itineraryIds);

  if (error) {
    throw error;
  }

  const tagsByItineraryId = new Map<string, TravelTag[]>();

  for (const row of data ?? []) {
    const itineraryId = row.itinerary_id as string;
    const tag = row.tag as unknown as TravelTag | null;

    if (!tag) {
      continue;
    }

    const tags = tagsByItineraryId.get(itineraryId) ?? [];
    tags.push(tag);
    tagsByItineraryId.set(itineraryId, tags);
  }

  return itineraries.map((itinerary) => ({
    ...itinerary,
    tags: (tagsByItineraryId.get(itinerary.id) ?? []).sort((a, b) =>
      a.name.localeCompare(b.name),
    ),
  }));
}

async function setItineraryTags(
  userId: string,
  familyId: string,
  itineraryId: string,
  tagNames: string[],
) {
  const supabase = getSupabaseAdmin();
  const tags = await ensureTravelTags(userId, familyId, tagNames);

  const { error: deleteError } = await supabase
    .from('travel_itinerary_tags')
    .delete()
    .eq('family_id', familyId)
    .eq('itinerary_id', itineraryId);

  if (deleteError) {
    throw deleteError;
  }

  if (tags.length === 0) {
    return;
  }

  const { error } = await supabase.from('travel_itinerary_tags').insert(
    tags.map((tag) => ({
      family_id: familyId,
      itinerary_id: itineraryId,
      tag_id: tag.id,
    })),
  );

  if (error) {
    throw error;
  }
}

async function ensureTravelTags(
  userId: string,
  familyId: string,
  tagNames: string[],
) {
  const names = normalizeTagNames(tagNames);
  if (names.length === 0) {
    return [] as TravelTag[];
  }

  const supabase = getSupabaseAdmin();
  const { error: upsertError } = await supabase.from('travel_tags').upsert(
    names.map((name) => ({
      family_id: familyId,
      name,
      created_by_user_id: userId,
    })),
    { onConflict: 'family_id,name', ignoreDuplicates: true },
  );

  if (upsertError) {
    throw upsertError;
  }

  const { data, error } = await supabase
    .from('travel_tags')
    .select('*')
    .eq('family_id', familyId)
    .in('name', names);

  if (error) {
    throw error;
  }

  return (data ?? []) as TravelTag[];
}

async function ensureTravelChecklistItems(
  userId: string,
  familyId: string,
  itemNames: string[],
) {
  const names = normalizeChecklistItemNames(itemNames);
  if (names.length === 0) {
    return [] as TravelChecklistItem[];
  }

  const supabase = getSupabaseAdmin();
  const { data: existing, error: existingError } = await supabase
    .from('travel_checklist_items')
    .select('name')
    .eq('family_id', familyId)
    .is('parent_id', null)
    .in('name', names);

  if (existingError) {
    throw existingError;
  }

  const existingNames = new Set((existing ?? []).map((item) => item.name as string));
  const missingNames = names.filter((name) => !existingNames.has(name));

  if (missingNames.length > 0) {
    const { error: insertError } = await supabase
      .from('travel_checklist_items')
      .insert(missingNames.map((name) => ({
        family_id: familyId,
        parent_id: null,
        name,
        created_by_user_id: userId,
      })));

    if (insertError) {
      throw insertError;
    }
  }

  const { data, error } = await supabase
    .from('travel_checklist_items')
    .select('*')
    .eq('family_id', familyId)
    .is('parent_id', null)
    .in('name', names);

  if (error) {
    throw error;
  }

  return (data ?? []) as TravelChecklistItem[];
}

async function ensureTravelChecklistTreeFromTripItems(
  userId: string,
  familyId: string,
  tripItems: TravelTripChecklistItem[],
) {
  const rootTripItems = tripItems.filter((item) => !item.parent_id);
  if (rootTripItems.length === 0) {
    return;
  }

  const supabase = getSupabaseAdmin();
  const rootNames = normalizeChecklistItemNames(rootTripItems.map((item) => item.name));
  await ensureTravelChecklistItems(userId, familyId, rootNames);

  const { data: roots, error: rootFetchError } = await supabase
    .from('travel_checklist_items')
    .select('*')
    .eq('family_id', familyId)
    .is('parent_id', null)
    .in('name', rootNames);

  if (rootFetchError) {
    throw rootFetchError;
  }

  const rootByName = new Map(
    ((roots ?? []) as TravelChecklistItem[]).map((item) => [item.name, item]),
  );

  for (const rootTripItem of rootTripItems) {
    const favoriteRoot = rootByName.get(rootTripItem.name);
    if (!favoriteRoot) {
      continue;
    }

    const childNames = normalizeChecklistItemNames(
      tripItems
        .filter((item) => item.parent_id === rootTripItem.id)
        .map((item) => item.name),
    );

    if (childNames.length === 0) {
      continue;
    }

    const { data: existingChildren, error: existingChildError } = await supabase
      .from('travel_checklist_items')
      .select('name')
      .eq('family_id', familyId)
      .eq('parent_id', favoriteRoot.id)
      .in('name', childNames);

    if (existingChildError) {
      throw existingChildError;
    }

    const existingChildNames = new Set(
      (existingChildren ?? []).map((item) => item.name as string),
    );
    const missingChildNames = childNames.filter(
      (name) => !existingChildNames.has(name),
    );

    if (missingChildNames.length === 0) {
      continue;
    }

    const { error: insertChildError } = await supabase
      .from('travel_checklist_items')
      .insert(missingChildNames.map((name) => ({
        family_id: familyId,
        parent_id: favoriteRoot.id,
        name,
        created_by_user_id: userId,
      })));

    if (insertChildError) {
      throw insertChildError;
    }
  }
}

async function ensureTravelTripChecklistSeeded(
  userId: string,
  familyId: string,
  trip: TravelTrip,
) {
  if (trip.checklist_seeded_at) {
    return;
  }

  const checklistItems = await listTravelChecklistItems(userId, familyId);
  const supabase = getSupabaseAdmin();

  if (checklistItems.length > 0) {
    const rootItems = checklistItems.filter((item) => !item.parent_id);
    const { data: insertedRoots, error: insertError } =
      rootItems.length === 0
        ? { data: [] as TravelTripChecklistItem[], error: null }
        : await supabase
            .from('travel_trip_checklist_items')
            .insert(
              rootItems.map((item, index) => ({
                family_id: familyId,
                trip_id: trip.id,
                parent_id: null,
                name: item.name,
                sort_order: index + 1,
                created_by_user_id: userId,
              })),
            )
            .select('*');

    if (insertError) {
      throw insertError;
    }

    const tripRootByName = new Map(
      ((insertedRoots ?? []) as TravelTripChecklistItem[]).map((item) => [
        item.name,
        item,
      ]),
    );

    const childrenToInsert = checklistItems
      .filter((item) => item.parent_id)
      .flatMap((item) => {
        const favoriteParent = rootItems.find((root) => root.id === item.parent_id);
        const tripParent = favoriteParent
          ? tripRootByName.get(favoriteParent.name)
          : undefined;

        if (!tripParent) {
          return [];
        }

        const siblings = checklistItems.filter(
          (candidate) => candidate.parent_id === item.parent_id,
        );
        return [
          {
            family_id: familyId,
            trip_id: trip.id,
            parent_id: tripParent.id,
            name: item.name,
            sort_order:
              siblings.findIndex((candidate) => candidate.id === item.id) + 1,
            created_by_user_id: userId,
          },
        ];
      });

    if (childrenToInsert.length > 0) {
      const { error: insertChildrenError } = await supabase
        .from('travel_trip_checklist_items')
        .insert(childrenToInsert);

      if (insertChildrenError) {
        throw insertChildrenError;
      }
    }
  }

  const { error } = await supabase
    .from('travel_trips')
    .update({ checklist_seeded_at: new Date().toISOString() })
    .eq('family_id', familyId)
    .eq('id', trip.id);

  if (error) {
    throw error;
  }

  trip.checklist_seeded_at = new Date().toISOString();
}

async function nextTravelTripChecklistSortOrder(
  familyId: string,
  tripId: string,
  parentId: string | null = null,
) {
  const supabase = getSupabaseAdmin();
  let query = supabase
    .from('travel_trip_checklist_items')
    .select('sort_order')
    .eq('family_id', familyId)
    .eq('trip_id', tripId)
    .order('sort_order', { ascending: false })
    .limit(1);

  query =
    parentId === null ? query.is('parent_id', null) : query.eq('parent_id', parentId);

  const { data, error } = await query;

  if (error) {
    throw error;
  }

  const lastSortOrder = (data?.[0]?.sort_order as number | undefined) ?? 0;
  return lastSortOrder + 1;
}

async function getTravelTripChecklistParentOrThrow(
  familyId: string,
  tripId: string,
  parentId: string,
) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('travel_trip_checklist_items')
    .select('*')
    .eq('family_id', familyId)
    .eq('trip_id', tripId)
    .eq('id', parentId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, {
      error: 'travel_trip_checklist_parent_not_found',
    });
  }

  const parent = data as TravelTripChecklistItem;
  if (parent.parent_id) {
    throw new HttpError(400, {
      error: 'invalid_payload',
      field: 'parentId',
    });
  }

  return parent;
}

async function getTravelChecklistParentOrThrow(
  familyId: string,
  parentId: string,
) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('travel_checklist_items')
    .select('*')
    .eq('family_id', familyId)
    .eq('id', parentId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'travel_checklist_parent_not_found' });
  }

  const parent = data as TravelChecklistItem;
  if (parent.parent_id) {
    throw new HttpError(400, {
      error: 'invalid_payload',
      field: 'parentId',
    });
  }

  return parent;
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

async function compactItinerarySortOrders(familyId: string, tripId: string) {
  const itineraries = await listItineraries(familyId, tripId);
  const sortOrderByDate = new Map<string, number>();

  const supabase = getSupabaseAdmin();
  const results = await Promise.all(
    itineraries.map((itinerary) => {
      const sortOrder =
        (sortOrderByDate.get(itinerary.itinerary_date) ?? 0) + 1;
      sortOrderByDate.set(itinerary.itinerary_date, sortOrder);

      if (itinerary.sort_order === sortOrder) {
        return Promise.resolve({ error: null });
      }

      return supabase
        .from('travel_itineraries')
        .update({ sort_order: sortOrder })
        .eq('family_id', familyId)
        .eq('trip_id', tripId)
        .eq('id', itinerary.id);
    }),
  );

  const updateError = results.find((result) => result.error)?.error;
  if (updateError) {
    throw updateError;
  }
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

function normalizeTagNames(values: string[]) {
  const names = values
    .map((value) => normalizeOptionalText(value, 24, 'tagNames'))
    .filter((value): value is string => Boolean(value));

  return [...new Set(names)];
}

function normalizeChecklistItemNames(values: string[]) {
  const names = values
    .map((value) => normalizeOptionalText(value, 40, 'name'))
    .filter((value): value is string => Boolean(value));

  return [...new Set(names)];
}
