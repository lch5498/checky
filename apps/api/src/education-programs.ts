import {
  listFamilyMembers,
  requireFamilyManager,
  requireMembership,
} from './families';
import { normalizeAlertOffsetMinutes } from './alert-offset';
import { HttpError } from './http';
import { getSupabaseAdmin } from './supabase';

const MAX_GENERATED_SCHEDULES = 370;
const EDUCATION_PROGRAM_DATE_WINDOW_YEARS = 1;
const MAX_PHONE_CONTACTS = 10;

export type EducationWeeklySchedule = {
  weekday: number;
  isAllDay?: boolean;
  startsAt: string;
  endsAt: string;
  vehicleBoardingTime: string | null;
  vehicleDropoffTime: string | null;
};

export type EducationRecurrenceType = 'weekly' | 'monthly';

export type EducationMonthlySchedule = {
  weekOfMonth: number;
  weekday: number;
  dayOfMonth?: number | null;
  isAllDay?: boolean;
  startsAt: string;
  endsAt: string;
  vehicleBoardingTime: string | null;
  vehicleDropoffTime: string | null;
};

export type EducationProgramPhoneContact = {
  label: string;
  phoneNumber: string;
};

export type EducationProgram = {
  id: string;
  family_id: string;
  family_member_id: string | null;
  name: string;
  starts_on: string;
  ends_on: string;
  recurrence_type: EducationRecurrenceType;
  weekly_schedules: EducationWeeklySchedule[];
  monthly_schedules: EducationMonthlySchedule[];
  phone_contacts: EducationProgramPhoneContact[];
  alert_offset_minutes: number | null;
  created_by_user_id: string | null;
  created_at: string;
  updated_at: string;
  family_member?: {
    id: string;
    family_id: string;
    user_id: string;
    role: string;
    user?: {
      id: string;
      nickname: string;
    };
  } | null;
};

export type EducationProgramInput = {
  familyMemberId: string;
  name: string;
  startsOn: string;
  endsOn: string;
  recurrenceType?: EducationRecurrenceType;
  weeklySchedules?: EducationWeeklySchedule[];
  monthlySchedules?: EducationMonthlySchedule[];
  phoneContacts?: EducationProgramPhoneContact[];
  alertOffsetMinutes?: number | null;
  timeZoneOffsetMinutes?: number;
};

export type CalendarApplyScope = 'all' | 'future';

type MembershipCheckOptions = {
  skipMembershipCheck?: boolean;
};

type NormalizedEducationProgramInput = {
  familyMemberId: string;
  name: string;
  startsOn: string;
  endsOn: string;
  recurrenceType: EducationRecurrenceType;
  weeklySchedules: EducationWeeklySchedule[];
  monthlySchedules: EducationMonthlySchedule[];
  phoneContacts: EducationProgramPhoneContact[];
  alertOffsetMinutes: number | null;
  timeZoneOffsetMinutes: number;
};

export async function getEducationProgramDashboard(
  userId: string,
  familyId: string,
) {
  const membership = await requireMembership(userId, familyId);
  const [members, programs] = await Promise.all([
    listFamilyMembers(userId, familyId, { skipMembershipCheck: true }),
    listEducationPrograms(userId, familyId, { skipMembershipCheck: true }),
  ]);

  return {
    canManage: membership.role === 'owner',
    members,
    programs,
  };
}

export async function listEducationPrograms(
  userId: string,
  familyId: string,
  options: MembershipCheckOptions = {},
) {
  if (!options.skipMembershipCheck) {
    await requireMembership(userId, familyId);
  }

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('education_programs')
    .select(programSelect)
    .eq('family_id', familyId)
    .order('created_at', { ascending: true });

  if (error) {
    throw error;
  }

  return (data ?? []) as unknown as EducationProgram[];
}

export async function createEducationProgram(
  userId: string,
  familyId: string,
  input: EducationProgramInput,
  options: { calendarApplyScope?: CalendarApplyScope } = {},
) {
  await requireFamilyManager(userId, familyId);
  const normalized = await normalizeEducationProgramInput(familyId, input);
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('education_programs')
    .insert({
      family_id: familyId,
      family_member_id: normalized.familyMemberId,
      name: normalized.name,
      starts_on: normalized.startsOn,
      ends_on: normalized.endsOn,
      recurrence_type: normalized.recurrenceType,
      weekly_schedules: normalized.weeklySchedules,
      monthly_schedules: normalized.monthlySchedules,
      phone_contacts: normalized.phoneContacts,
      alert_offset_minutes: normalized.alertOffsetMinutes,
      created_by_user_id: userId,
    })
    .select(programSelect)
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
      { futureOnly: options.calendarApplyScope === 'future' },
    );

    return {
      program: data as unknown as EducationProgram,
      generatedScheduleCount,
    };
  } catch (error) {
    await supabase.from('education_programs').delete().eq('id', data.id);
    throw error;
  }
}

export async function updateEducationProgram(
  userId: string,
  familyId: string,
  programId: string,
  input: EducationProgramInput,
  options: { calendarApplyScope?: CalendarApplyScope } = {},
) {
  await requireFamilyManager(userId, familyId);
  const normalized = await normalizeEducationProgramInput(familyId, input);
  const supabase = getSupabaseAdmin();
  const { data: existingData, error: existingError } = await supabase
    .from('education_programs')
    .select(programSelect)
    .eq('id', programId)
    .eq('family_id', familyId)
    .maybeSingle();

  if (existingError) {
    throw existingError;
  }

  if (!existingData) {
    throw new HttpError(404, { error: 'education_program_not_found' });
  }

  const existingProgram = existingData as unknown as EducationProgram;
  const hasCalendarChanges = hasScheduleImpactingChanges(
    existingProgram,
    normalized,
  );

  const { data, error } = await supabase
    .from('education_programs')
    .update({
      family_member_id: normalized.familyMemberId,
      name: normalized.name,
      starts_on: normalized.startsOn,
      ends_on: normalized.endsOn,
      recurrence_type: normalized.recurrenceType,
      weekly_schedules: normalized.weeklySchedules,
      monthly_schedules: normalized.monthlySchedules,
      phone_contacts: normalized.phoneContacts,
      alert_offset_minutes: normalized.alertOffsetMinutes,
    })
    .eq('id', programId)
    .eq('family_id', familyId)
    .select(programSelect)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'education_program_not_found' });
  }

  const generatedScheduleCount = hasCalendarChanges
    ? await replaceGeneratedSchedules(
        userId,
        familyId,
        programId,
        normalized,
        { futureOnly: options.calendarApplyScope !== 'all' },
      )
    : 0;

  return {
    program: data as unknown as EducationProgram,
    generatedScheduleCount,
  };
}

export async function deleteEducationProgram(
  userId: string,
  familyId: string,
  programId: string,
  options: {
    calendarApplyScope?: CalendarApplyScope;
    timeZoneOffsetMinutes?: number;
  } = {},
) {
  await requireFamilyManager(userId, familyId);

  const supabase = getSupabaseAdmin();

  if (options.calendarApplyScope === 'future') {
    const timeZoneOffsetMinutes = normalizeTimeZoneOffset(
      options.timeZoneOffsetMinutes,
    );
    const today = dateOnlyInTimeZone(new Date(), timeZoneOffsetMinutes);
    const { error: detachError } = await supabase
      .from('schedules')
      .update({ education_program_id: null })
      .eq('education_program_id', programId)
      .eq('family_id', familyId)
      .lt('starts_at', zonedDateTimeIso(today, '00:00', timeZoneOffsetMinutes));

    if (detachError) {
      throw detachError;
    }
  }

  const { error } = await supabase
    .from('education_programs')
    .delete()
    .eq('id', programId)
    .eq('family_id', familyId);

  if (error) {
    throw error;
  }
}

async function replaceGeneratedSchedules(
  userId: string,
  familyId: string,
  programId: string,
  input: NormalizedEducationProgramInput,
  options: { futureOnly: boolean },
) {
  const today = dateOnlyInTimeZone(new Date(), input.timeZoneOffsetMinutes);
  const startsOnOrToday = maxDateOnly(input.startsOn, formatDateOnly(today));
  const generationInput = options.futureOnly
    ? { ...input, startsOn: startsOnOrToday }
    : input;
  const generatedSchedules = generateSchedules(
    familyId,
    programId,
    userId,
    generationInput,
  );
  const supabase = getSupabaseAdmin();
  let deleteQuery = supabase
    .from('schedules')
    .delete()
    .eq('education_program_id', programId)
    .eq('family_id', familyId);

  if (options.futureOnly) {
    deleteQuery = deleteQuery.gte(
      'starts_at',
      zonedDateTimeIso(today, '00:00', input.timeZoneOffsetMinutes),
    );
  }

  const { error: deleteError } = await deleteQuery;

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

function generateSchedules(
  familyId: string,
  programId: string,
  userId: string,
  input: NormalizedEducationProgramInput,
) {
  const schedules = [];
  const start = parseDateOnly(input.startsOn, 'startsOn');
  const end = parseDateOnly(input.endsOn, 'endsOn');
  const weeklySchedulesByWeekday = new Map(
    input.weeklySchedules.map((schedule) => [schedule.weekday, schedule]),
  );
  for (let cursor = new Date(start); cursor.getTime() <= end.getTime(); cursor = addDays(cursor, 1)) {
    const rule =
      input.recurrenceType === 'monthly'
        ? input.monthlySchedules.find((schedule) =>
            schedule.dayOfMonth != null
              ? cursor.getUTCDate() === schedule.dayOfMonth
              : monthlyScheduleDateKey(weekOfMonth(cursor), cursor.getUTCDay()) ===
                  monthlyScheduleDateKey(schedule.weekOfMonth, schedule.weekday),
          )
        : weeklySchedulesByWeekday.get(cursor.getUTCDay());

    if (!rule) {
      continue;
    }

    schedules.push({
      family_id: familyId,
      family_member_id: input.familyMemberId,
      education_program_id: programId,
      title: input.name,
      content: null,
      starts_at: zonedDateTimeIso(cursor, rule.startsAt, input.timeZoneOffsetMinutes),
      ends_at: zonedDateTimeIso(
        rule.isAllDay ? addDays(cursor, 1) : cursor,
        rule.isAllDay ? '00:00' : rule.endsAt,
        input.timeZoneOffsetMinutes,
      ),
      is_all_day: rule.isAllDay === true,
      vehicle_boarding_at: rule.vehicleBoardingTime
        ? zonedDateTimeIso(cursor, rule.vehicleBoardingTime, input.timeZoneOffsetMinutes)
        : null,
      vehicle_dropoff_at: rule.vehicleDropoffTime
        ? zonedDateTimeIso(cursor, rule.vehicleDropoffTime, input.timeZoneOffsetMinutes)
        : null,
      alert_offset_minutes: input.alertOffsetMinutes,
      created_by_user_id: userId,
    });
  }

  if (schedules.length > MAX_GENERATED_SCHEDULES) {
    throw new HttpError(400, {
      error: 'too_many_generated_schedules',
      max: MAX_GENERATED_SCHEDULES,
    });
  }

  return schedules;
}

async function normalizeEducationProgramInput(
  familyId: string,
  input: EducationProgramInput,
): Promise<NormalizedEducationProgramInput> {
  const familyMemberId = normalizeText(input.familyMemberId, 'familyMemberId', 80);
  await getFamilyMemberOrThrow(familyId, familyMemberId);

  const startsOn = normalizeDateOnly(input.startsOn, 'startsOn');
  const endsOn = normalizeDateOnly(input.endsOn, 'endsOn');
  const timeZoneOffsetMinutes = normalizeTimeZoneOffset(
    input.timeZoneOffsetMinutes,
  );
  assertDateInAllowedWindow(startsOn, 'startsOn', timeZoneOffsetMinutes);
  assertDateInAllowedWindow(endsOn, 'endsOn', timeZoneOffsetMinutes);

  if (parseDateOnly(endsOn, 'endsOn').getTime() < parseDateOnly(startsOn, 'startsOn').getTime()) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'endsOn' });
  }

  const recurrenceType = normalizeRecurrenceType(input.recurrenceType);
  const weeklySchedules =
    recurrenceType === 'weekly'
      ? normalizeWeeklySchedules(input.weeklySchedules)
      : [];
  const monthlySchedules =
    recurrenceType === 'monthly'
      ? normalizeMonthlySchedules(input.monthlySchedules)
      : [];

  return {
    familyMemberId,
    name: normalizeText(input.name, 'name', 80),
    startsOn,
    endsOn,
    recurrenceType,
    weeklySchedules,
    monthlySchedules,
    phoneContacts: normalizePhoneContacts(input.phoneContacts),
    alertOffsetMinutes: normalizeAlertOffsetMinutes(input.alertOffsetMinutes),
    timeZoneOffsetMinutes,
  };
}

function normalizeRecurrenceType(value: EducationRecurrenceType | undefined) {
  if (value === undefined || value === null) {
    return 'weekly';
  }

  if (value !== 'weekly' && value !== 'monthly') {
    throw new HttpError(400, { error: 'invalid_payload', field: 'recurrenceType' });
  }

  return value;
}

function normalizeWeeklySchedules(value: EducationWeeklySchedule[] | undefined) {
  if (!Array.isArray(value) || value.length === 0) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'weeklySchedules' });
  }

  if (value.length > 7) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'weeklySchedules' });
  }

  const seen = new Set<number>();

  return value
    .map((schedule) => {
      const weekday = Number(schedule.weekday);
      const startsAt = normalizeTime(schedule.startsAt, 'startsAt');
      const endsAt = normalizeTime(schedule.endsAt, 'endsAt');
      const isAllDay = schedule.isAllDay === true;
      const vehicleBoardingTime = normalizeOptionalTime(
        schedule.vehicleBoardingTime,
        'vehicleBoardingTime',
      );
      const vehicleDropoffTime = normalizeOptionalTime(
        schedule.vehicleDropoffTime,
        'vehicleDropoffTime',
      );

      if (!Number.isInteger(weekday) || weekday < 0 || weekday > 6 || seen.has(weekday)) {
        throw new HttpError(400, { error: 'invalid_payload', field: 'weekday' });
      }

      if (!isAllDay && timeToMinutes(endsAt) < timeToMinutes(startsAt)) {
        throw new HttpError(400, { error: 'invalid_payload', field: 'endsAt' });
      }

      seen.add(weekday);

      return {
        weekday,
        startsAt: isAllDay ? '00:00' : startsAt,
        endsAt: isAllDay ? '00:00' : endsAt,
        isAllDay,
        vehicleBoardingTime,
        vehicleDropoffTime,
      };
    })
    .sort((left, right) => left.weekday - right.weekday);
}

function normalizeMonthlySchedules(value: EducationMonthlySchedule[] | undefined) {
  if (!Array.isArray(value) || value.length === 0) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'monthlySchedules' });
  }

  if (value.length > 4) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'monthlySchedules' });
  }

  const seen = new Set<string>();

  return value
    .map((schedule) => {
      const dayOfMonth =
        schedule.dayOfMonth === undefined || schedule.dayOfMonth === null
          ? null
          : Number(schedule.dayOfMonth);
      const weekOfMonth = Number(schedule.weekOfMonth);
      const weekday = Number(schedule.weekday);
      const startsAt = normalizeTime(schedule.startsAt, 'startsAt');
      const endsAt = normalizeTime(schedule.endsAt, 'endsAt');
      const isAllDay = schedule.isAllDay === true;
      const vehicleBoardingTime = normalizeOptionalTime(
        schedule.vehicleBoardingTime,
        'vehicleBoardingTime',
      );
      const vehicleDropoffTime = normalizeOptionalTime(
        schedule.vehicleDropoffTime,
        'vehicleDropoffTime',
      );

      if (dayOfMonth !== null) {
        if (!Number.isInteger(dayOfMonth) || dayOfMonth < 1 || dayOfMonth > 31) {
          throw new HttpError(400, { error: 'invalid_payload', field: 'dayOfMonth' });
        }
      } else {
        if (
          !Number.isInteger(weekOfMonth) ||
          weekOfMonth < 1 ||
          weekOfMonth > 4
        ) {
          throw new HttpError(400, { error: 'invalid_payload', field: 'weekOfMonth' });
        }

        if (!Number.isInteger(weekday) || weekday < 0 || weekday > 6) {
          throw new HttpError(400, { error: 'invalid_payload', field: 'weekday' });
        }
      }

      if (!isAllDay && timeToMinutes(endsAt) < timeToMinutes(startsAt)) {
        throw new HttpError(400, { error: 'invalid_payload', field: 'endsAt' });
      }

      const duplicateKey = dayOfMonth === null
        ? monthlyScheduleDateKey(weekOfMonth, weekday)
        : `day:${dayOfMonth}`;

      if (seen.has(duplicateKey)) {
        throw new HttpError(400, { error: 'invalid_payload', field: 'monthlySchedules' });
      }

      seen.add(duplicateKey);

      return {
        weekOfMonth,
        weekday,
        dayOfMonth,
        startsAt: isAllDay ? '00:00' : startsAt,
        endsAt: isAllDay ? '00:00' : endsAt,
        isAllDay,
        vehicleBoardingTime,
        vehicleDropoffTime,
      };
    })
    .sort((left, right) => left.weekOfMonth - right.weekOfMonth);
}

function normalizePhoneContacts(value: EducationProgramPhoneContact[] | undefined) {
  if (value === undefined || value === null) {
    return [];
  }

  if (!Array.isArray(value) || value.length > MAX_PHONE_CONTACTS) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'phoneContacts' });
  }

  return value.map((contact) => {
    if (typeof contact !== 'object' || contact === null) {
      throw new HttpError(400, { error: 'invalid_payload', field: 'phoneContacts' });
    }

    return {
      label: normalizeText(contact.label, 'phoneContacts.label', 30),
      phoneNumber: normalizeText(contact.phoneNumber, 'phoneContacts.phoneNumber', 40),
    };
  });
}

function hasScheduleImpactingChanges(
  existing: EducationProgram,
  input: NormalizedEducationProgramInput,
) {
  return (
    existing.family_member_id !== input.familyMemberId ||
    existing.name !== input.name ||
    existing.starts_on !== input.startsOn ||
    existing.ends_on !== input.endsOn ||
    existing.recurrence_type !== input.recurrenceType ||
    stableJson(existing.weekly_schedules ?? []) !== stableJson(input.weeklySchedules) ||
    stableJson(existing.monthly_schedules ?? []) !== stableJson(input.monthlySchedules) ||
    existing.alert_offset_minutes !== input.alertOffsetMinutes
  );
}

function stableJson(value: unknown) {
  return JSON.stringify(value);
}

async function getFamilyMemberOrThrow(familyId: string, familyMemberId: string) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('family_members')
    .select('id')
    .eq('id', familyMemberId)
    .eq('family_id', familyId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'family_member_not_found' });
  }
}

function normalizeText(value: string, field: string, maxLength: number) {
  const normalized = value.trim();

  if (!normalized || normalized.length > maxLength) {
    throw new HttpError(400, { error: 'invalid_payload', field });
  }

  return normalized;
}

function normalizeDateOnly(value: string, field: string) {
  const normalized = value.trim();

  if (!/^\d{4}-\d{2}-\d{2}$/.test(normalized)) {
    throw new HttpError(400, { error: 'invalid_payload', field });
  }

  parseDateOnly(normalized, field);

  return normalized;
}

function parseDateOnly(value: string, field: string) {
  const date = new Date(`${value}T00:00:00.000Z`);

  if (Number.isNaN(date.getTime())) {
    throw new HttpError(400, { error: 'invalid_payload', field });
  }

  return date;
}

function assertDateInAllowedWindow(
  value: string,
  field: string,
  offsetMinutes: number,
) {
  const date = parseDateOnly(value, field);
  const today = dateOnlyInTimeZone(new Date(), offsetMinutes);
  const minDate = addYears(today, -EDUCATION_PROGRAM_DATE_WINDOW_YEARS);
  const maxDate = addYears(today, EDUCATION_PROGRAM_DATE_WINDOW_YEARS);

  if (date.getTime() < minDate.getTime() || date.getTime() > maxDate.getTime()) {
    throw new HttpError(400, {
      error: 'education_program_date_out_of_range',
      field,
      min: formatDateOnly(minDate),
      max: formatDateOnly(maxDate),
    });
  }
}

function normalizeTime(value: string, field: string) {
  const normalized = value.trim();

  if (!/^\d{2}:\d{2}$/.test(normalized)) {
    throw new HttpError(400, { error: 'invalid_payload', field });
  }

  const [hours, minutes] = normalized.split(':').map(Number);

  if (hours > 23 || minutes > 59) {
    throw new HttpError(400, { error: 'invalid_payload', field });
  }

  return normalized;
}

function normalizeOptionalTime(value: unknown, field: string) {
  if (value === undefined || value === null) {
    return null;
  }

  if (typeof value !== 'string') {
    throw new HttpError(400, { error: 'invalid_payload', field });
  }

  if (!value.trim()) {
    return null;
  }

  return normalizeTime(value, field);
}

function normalizeTimeZoneOffset(value: number | undefined) {
  if (value === undefined) {
    return 540;
  }

  if (!Number.isInteger(value) || value < -720 || value > 840) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'timeZoneOffsetMinutes' });
  }

  return value;
}

function timeToMinutes(value: string) {
  const [hours, minutes] = value.split(':').map(Number);

  return hours * 60 + minutes;
}

function addDays(value: Date, days: number) {
  const next = new Date(value);
  next.setUTCDate(next.getUTCDate() + days);

  return next;
}

function addYears(value: Date, years: number) {
  const next = new Date(value);
  next.setUTCFullYear(next.getUTCFullYear() + years);

  return next;
}

function weekOfMonth(value: Date) {
  return Math.floor((value.getUTCDate() - 1) / 7) + 1;
}

function monthlyScheduleDateKey(weekOfMonthValue: number, weekday: number) {
  return `${weekOfMonthValue}:${weekday}`;
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

function formatDateOnly(value: Date) {
  return value.toISOString().slice(0, 10);
}

function maxDateOnly(left: string, right: string) {
  return parseDateOnly(left, 'startsOn').getTime() >=
    parseDateOnly(right, 'startsOn').getTime()
    ? left
    : right;
}

function zonedDateTimeIso(date: Date, time: string, offsetMinutes: number) {
  const [hours, minutes] = time.split(':').map(Number);
  const utcTime = Date.UTC(
    date.getUTCFullYear(),
    date.getUTCMonth(),
    date.getUTCDate(),
    hours,
    minutes,
  ) - offsetMinutes * 60 * 1000;

  return new Date(utcTime).toISOString();
}

const programSelect = `
  *,
  family_member:family_members (
    id,
    family_id,
    user_id,
    nickname,
    role,
    created_at,
    updated_at,
    user:users (
      id,
      nickname
    )
  )
`;
