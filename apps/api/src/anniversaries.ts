import { Lunar } from 'lunar-javascript';

import { normalizeAlertOffsetMinutes } from './alert-offset';
import { requireFamilyManager, requireMembership } from './families';
import { HttpError } from './http';
import { getSupabaseAdmin } from './supabase';

const ANNIVERSARY_GENERATION_YEARS = 70;

export type AnniversaryCategory = 'birthday' | 'wedding' | 'custom';
export type AnniversaryCalendarType = 'solar' | 'lunar';

export type Anniversary = {
  id: string;
  family_id: string;
  category: AnniversaryCategory;
  title: string;
  calendar_type: AnniversaryCalendarType;
  month: number;
  day: number;
  is_lunar_leap: boolean;
  year: number | null;
  alert_offset_minutes: number | null;
  created_by_user_id: string | null;
  created_at: string;
  updated_at: string;
};

type AnniversarySchedule = {
  id: string;
  anniversary_id: string;
  title: string;
  starts_at: string;
  ends_at: string;
};

export type AnniversaryInput = {
  category: AnniversaryCategory;
  title: string;
  calendarType: AnniversaryCalendarType;
  month: number;
  day: number;
  isLunarLeap?: boolean;
  year?: number | null;
  alertOffsetMinutes?: number | null;
  timeZoneOffsetMinutes?: number;
};

type NormalizedAnniversaryInput = {
  category: AnniversaryCategory;
  title: string;
  calendarType: AnniversaryCalendarType;
  month: number;
  day: number;
  isLunarLeap: boolean;
  year: number | null;
  alertOffsetMinutes: number | null;
  timeZoneOffsetMinutes: number;
};

export async function getAnniversaryDashboard(userId: string, familyId: string) {
  const membership = await requireMembership(userId, familyId);
  const anniversaries = await listAnniversaries(userId, familyId, {
    skipMembershipCheck: true,
  });
  const recentSchedulesByAnniversaryId = await listRecentAnniversarySchedules(
    familyId,
    anniversaries.map((anniversary) => anniversary.id),
  );

  return {
    canManage: membership.role === 'owner',
    anniversaries: anniversaries.map((anniversary) => {
      const nextOccurrence = nextOccurrenceForAnniversary(anniversary);

      return {
        ...anniversary,
        nextOccurrenceDate: nextOccurrence?.date ?? null,
        nextOccurrenceOrdinal: nextOccurrence?.ordinal ?? null,
        elapsedDays: elapsedDaysForAnniversary(anniversary),
        recentSchedules:
          recentSchedulesByAnniversaryId.get(anniversary.id) ?? [],
      };
    }),
  };
}

export async function listAnniversaries(
  userId: string,
  familyId: string,
  options: { skipMembershipCheck?: boolean } = {},
) {
  if (!options.skipMembershipCheck) {
    await requireMembership(userId, familyId);
  }

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('anniversaries')
    .select('*')
    .eq('family_id', familyId)
    .order('created_at', { ascending: true });

  if (error) {
    throw error;
  }

  return (data ?? []) as unknown as Anniversary[];
}

export async function createAnniversary(
  userId: string,
  familyId: string,
  input: AnniversaryInput,
) {
  await requireFamilyManager(userId, familyId);
  const normalized = normalizeAnniversaryInput(input);
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('anniversaries')
    .insert({
      family_id: familyId,
      category: normalized.category,
      title: normalized.title,
      calendar_type: normalized.calendarType,
      month: normalized.month,
      day: normalized.day,
      is_lunar_leap: normalized.isLunarLeap,
      year: normalized.year,
      alert_offset_minutes: normalized.alertOffsetMinutes,
      created_by_user_id: userId,
    })
    .select('*')
    .single();

  if (error) {
    throw error;
  }

  try {
    const generatedScheduleCount = await replaceGeneratedSchedules(
      userId,
      familyId,
      data.id as string,
      normalized,
    );

    return {
      anniversary: {
        ...(data as unknown as Anniversary),
        ...nextOccurrencePayload(data as unknown as Anniversary),
        recentSchedules: await getRecentAnniversarySchedules(
          familyId,
          data.id as string,
        ),
      },
      generatedScheduleCount,
    };
  } catch (error) {
    await supabase.from('anniversaries').delete().eq('id', data.id);
    throw error;
  }
}

export async function updateAnniversary(
  userId: string,
  familyId: string,
  anniversaryId: string,
  input: AnniversaryInput,
) {
  await requireFamilyManager(userId, familyId);
  const normalized = normalizeAnniversaryInput(input);
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('anniversaries')
    .update({
      category: normalized.category,
      title: normalized.title,
      calendar_type: normalized.calendarType,
      month: normalized.month,
      day: normalized.day,
      is_lunar_leap: normalized.isLunarLeap,
      year: normalized.year,
      alert_offset_minutes: normalized.alertOffsetMinutes,
    })
    .eq('id', anniversaryId)
    .eq('family_id', familyId)
    .select('*')
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'anniversary_not_found' });
  }

  const generatedScheduleCount = await replaceGeneratedSchedules(
    userId,
    familyId,
    anniversaryId,
    normalized,
  );

  return {
    anniversary: {
      ...(data as unknown as Anniversary),
      ...nextOccurrencePayload(data as unknown as Anniversary),
      recentSchedules: await getRecentAnniversarySchedules(
        familyId,
        anniversaryId,
      ),
    },
    generatedScheduleCount,
  };
}

export async function deleteAnniversary(
  userId: string,
  familyId: string,
  anniversaryId: string,
) {
  await requireFamilyManager(userId, familyId);
  const supabase = getSupabaseAdmin();
  const { error: schedulesError } = await supabase
    .from('schedules')
    .delete()
    .eq('anniversary_id', anniversaryId)
    .eq('family_id', familyId);

  if (schedulesError) {
    throw schedulesError;
  }

  const { error } = await supabase
    .from('anniversaries')
    .delete()
    .eq('id', anniversaryId)
    .eq('family_id', familyId);

  if (error) {
    throw error;
  }
}

async function replaceGeneratedSchedules(
  userId: string,
  familyId: string,
  anniversaryId: string,
  input: NormalizedAnniversaryInput,
) {
  const generatedSchedules = generateSchedules(
    userId,
    familyId,
    anniversaryId,
    input,
  );
  const supabase = getSupabaseAdmin();
  const { error: deleteError } = await supabase
    .from('schedules')
    .delete()
    .eq('anniversary_id', anniversaryId)
    .eq('family_id', familyId);

  if (deleteError) {
    throw deleteError;
  }

  if (generatedSchedules.length === 0) {
    return 0;
  }

  const { error: insertError } = await supabase
    .from('schedules')
    .insert(generatedSchedules);

  if (insertError) {
    throw insertError;
  }

  return generatedSchedules.length;
}

async function getRecentAnniversarySchedules(
  familyId: string,
  anniversaryId: string,
) {
  const schedulesByAnniversaryId = await listRecentAnniversarySchedules(
    familyId,
    [anniversaryId],
  );

  return schedulesByAnniversaryId.get(anniversaryId) ?? [];
}

async function listRecentAnniversarySchedules(
  familyId: string,
  anniversaryIds: string[],
) {
  const schedulesByAnniversaryId = new Map<string, AnniversarySchedule[]>();

  if (anniversaryIds.length === 0) {
    return schedulesByAnniversaryId;
  }

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('schedules')
    .select('id, anniversary_id, title, starts_at, ends_at')
    .eq('family_id', familyId)
    .in('anniversary_id', anniversaryIds)
    .gte('starts_at', new Date().toISOString())
    .order('starts_at', { ascending: true });

  if (error) {
    throw error;
  }

  for (const schedule of (data ?? []) as unknown as AnniversarySchedule[]) {
    const schedules = schedulesByAnniversaryId.get(schedule.anniversary_id);

    if (!schedules) {
      schedulesByAnniversaryId.set(schedule.anniversary_id, [schedule]);
      continue;
    }

    if (schedules.length < 5) {
      schedules.push(schedule);
    }
  }

  return schedulesByAnniversaryId;
}

function generateSchedules(
  userId: string,
  familyId: string,
  anniversaryId: string,
  input: NormalizedAnniversaryInput,
) {
  const today = dateOnlyInTimeZone(new Date(), input.timeZoneOffsetMinutes);
  const endYear = today.getUTCFullYear() + ANNIVERSARY_GENERATION_YEARS;
  const schedules = [];

  for (
    let year = today.getUTCFullYear();
    year <= endYear && schedules.length < ANNIVERSARY_GENERATION_YEARS;
    year++
  ) {
    const occurrence = occurrenceDateForYear(input, year);

    if (!occurrence || occurrence.getTime() < today.getTime()) {
      continue;
    }

    schedules.push({
      family_id: familyId,
      family_member_id: null,
      anniversary_id: anniversaryId,
      title: input.title,
      content: categoryLabel(input.category),
      starts_at: zonedDateTimeIso(occurrence, '00:00', input.timeZoneOffsetMinutes),
      ends_at: zonedDateTimeIso(
        addDays(occurrence, 1),
        '00:00',
        input.timeZoneOffsetMinutes,
      ),
      vehicle_boarding_at: null,
      vehicle_dropoff_at: null,
      alert_offset_minutes: input.alertOffsetMinutes,
      created_by_user_id: userId,
    });
  }

  return schedules;
}

function occurrenceDateForYear(input: NormalizedAnniversaryInput, year: number) {
  if (input.calendarType === 'solar') {
    return solarDate(year, input.month, input.day);
  }

  try {
    const lunarMonth = input.isLunarLeap ? -input.month : input.month;
    const lunar = Lunar.fromYmd(year, lunarMonth, input.day);
    const solar = lunar.getSolar();

    return solarDate(solar.getYear(), solar.getMonth(), solar.getDay());
  } catch {
    return null;
  }
}

function nextOccurrenceForAnniversary(anniversary: Anniversary) {
  const today = dateOnlyInTimeZone(new Date(), 540);
  const input: NormalizedAnniversaryInput = {
    category: anniversary.category,
    title: anniversary.title,
    calendarType: anniversary.calendar_type,
    month: anniversary.month,
    day: anniversary.day,
    isLunarLeap: anniversary.is_lunar_leap,
    year: anniversary.year,
    alertOffsetMinutes: anniversary.alert_offset_minutes,
    timeZoneOffsetMinutes: 540,
  };

  for (
    let year = today.getUTCFullYear();
    year <= today.getUTCFullYear() + ANNIVERSARY_GENERATION_YEARS;
    year++
  ) {
    const occurrence = occurrenceDateForYear(input, year);

    if (occurrence && occurrence.getTime() >= today.getTime()) {
      return {
        date: formatDateOnly(occurrence),
        ordinal: anniversary.year
          ? anniversaryOrdinal(anniversary.year, year)
          : null,
      };
    }
  }

  return null;
}

function nextOccurrencePayload(anniversary: Anniversary) {
  const nextOccurrence = nextOccurrenceForAnniversary(anniversary);

  return {
    nextOccurrenceDate: nextOccurrence?.date ?? null,
    nextOccurrenceOrdinal: nextOccurrence?.ordinal ?? null,
    elapsedDays: elapsedDaysForAnniversary(anniversary),
  };
}

function elapsedDaysForAnniversary(anniversary: Anniversary) {
  if (!anniversary.year) {
    return null;
  }

  const today = dateOnlyInTimeZone(new Date(), 540);
  const startedAt = occurrenceDateForYear(
    {
      category: anniversary.category,
      title: anniversary.title,
      calendarType: anniversary.calendar_type,
      month: anniversary.month,
      day: anniversary.day,
      isLunarLeap: anniversary.is_lunar_leap,
      year: anniversary.year,
      alertOffsetMinutes: anniversary.alert_offset_minutes,
      timeZoneOffsetMinutes: 540,
    },
    anniversary.year,
  );

  if (!startedAt || startedAt.getTime() > today.getTime()) {
    return null;
  }

  return Math.floor((today.getTime() - startedAt.getTime()) / 86400000);
}

function normalizeAnniversaryInput(
  input: AnniversaryInput,
): NormalizedAnniversaryInput {
  const category = normalizeCategory(input.category);
  const calendarType = normalizeCalendarType(input.calendarType);
  const month = normalizeInteger(input.month, 'month', 1, 12);
  const day = normalizeInteger(input.day, 'day', 1, 31);
  const isLunarLeap = Boolean(input.isLunarLeap);
  const year = normalizeOptionalYear(input.year);
  const normalized: NormalizedAnniversaryInput = {
    category,
    title: normalizeText(input.title, 'title', 80),
    calendarType,
    month,
    day,
    isLunarLeap: calendarType === 'lunar' ? isLunarLeap : false,
    year,
    alertOffsetMinutes: normalizeAlertOffsetMinutes(input.alertOffsetMinutes),
    timeZoneOffsetMinutes: normalizeTimeZoneOffset(input.timeZoneOffsetMinutes),
  };

  if (!hasOccurrenceInGenerationRange(normalized)) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'day' });
  }

  return normalized;
}

function hasOccurrenceInGenerationRange(input: NormalizedAnniversaryInput) {
  const today = dateOnlyInTimeZone(new Date(), input.timeZoneOffsetMinutes);
  const endYear = today.getUTCFullYear() + ANNIVERSARY_GENERATION_YEARS;

  for (let year = today.getUTCFullYear(); year <= endYear; year++) {
    if (occurrenceDateForYear(input, year)) {
      return true;
    }
  }

  return false;
}

function normalizeCategory(value: unknown): AnniversaryCategory {
  if (value === 'birthday' || value === 'wedding' || value === 'custom') {
    return value;
  }

  throw new HttpError(400, { error: 'invalid_payload', field: 'category' });
}

function normalizeCalendarType(value: unknown): AnniversaryCalendarType {
  if (value === 'solar' || value === 'lunar') {
    return value;
  }

  throw new HttpError(400, { error: 'invalid_payload', field: 'calendarType' });
}

function normalizeInteger(
  value: unknown,
  field: string,
  minimum: number,
  maximum: number,
) {
  const numberValue = Number(value);

  if (
    !Number.isInteger(numberValue) ||
    numberValue < minimum ||
    numberValue > maximum
  ) {
    throw new HttpError(400, { error: 'invalid_payload', field });
  }

  return numberValue;
}

function normalizeOptionalYear(value: number | null | undefined) {
  if (value === undefined || value === null) {
    return null;
  }

  const currentYear = new Date().getUTCFullYear();

  return normalizeInteger(value, 'year', 1900, currentYear);
}

function anniversaryOrdinal(year: number, occurrenceYear: number) {
  const ordinal = occurrenceYear - year;

  return ordinal > 0 ? ordinal : null;
}

function normalizeText(value: string, field: string, maxLength: number) {
  const normalized = value.trim();

  if (!normalized || normalized.length > maxLength) {
    throw new HttpError(400, { error: 'invalid_payload', field });
  }

  return normalized;
}

function normalizeTimeZoneOffset(value: number | undefined) {
  if (value === undefined) {
    return 540;
  }

  if (!Number.isInteger(value) || value < -720 || value > 840) {
    throw new HttpError(400, {
      error: 'invalid_payload',
      field: 'timeZoneOffsetMinutes',
    });
  }

  return value;
}

function categoryLabel(category: AnniversaryCategory) {
  return {
    birthday: '생일',
    wedding: '결혼기념일',
    custom: '기념일',
  }[category];
}

function solarDate(year: number, month: number, day: number) {
  const date = new Date(Date.UTC(year, month - 1, day));

  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1) {
    return null;
  }

  return date;
}

function dateOnlyInTimeZone(value: Date, offsetMinutes: number) {
  const shifted = new Date(value.getTime() + offsetMinutes * 60 * 1000);

  return new Date(
    Date.UTC(
      shifted.getUTCFullYear(),
      shifted.getUTCMonth(),
      shifted.getUTCDate(),
    ),
  );
}

function addDays(value: Date, days: number) {
  const next = new Date(value);
  next.setUTCDate(next.getUTCDate() + days);

  return next;
}

function formatDateOnly(value: Date) {
  return value.toISOString().slice(0, 10);
}

function zonedDateTimeIso(date: Date, time: string, offsetMinutes: number) {
  const [hours, minutes] = time.split(':').map(Number);
  const utcTime =
    Date.UTC(
      date.getUTCFullYear(),
      date.getUTCMonth(),
      date.getUTCDate(),
      hours,
      minutes,
    ) -
    offsetMinutes * 60 * 1000;

  return new Date(utcTime).toISOString();
}
