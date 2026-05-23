import {
  listFamilyMembers,
  requireFamilyManager,
  requireMembership,
} from './families';
import { HttpError } from './http';
import { getSupabaseAdmin } from './supabase';

export type Schedule = {
  id: string;
  family_id: string;
  family_member_id: string | null;
  title: string;
  content: string | null;
  starts_at: string;
  ends_at: string;
  vehicle_boarding_at: string | null;
  vehicle_dropoff_at: string | null;
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

export type ScheduleInput = {
  familyMemberId: string;
  title: string;
  content?: string;
  startsAt: string;
  endsAt: string;
  vehicleBoardingAt?: string;
  vehicleDropoffAt?: string;
};

export async function getScheduleDashboard(
  userId: string,
  familyId: string,
  rangeStart: string,
  rangeEnd: string,
) {
  const membership = await requireMembership(userId, familyId);
  const [members, schedules] = await Promise.all([
    listFamilyMembers(userId, familyId),
    listSchedules(userId, familyId, rangeStart, rangeEnd),
  ]);

  return {
    canManage: membership.role === 'owner' || membership.role === 'co_owner',
    members,
    schedules,
  };
}

export async function listSchedules(
  userId: string,
  familyId: string,
  rangeStart: string,
  rangeEnd: string,
) {
  await requireMembership(userId, familyId);
  const startsAt = normalizeDateTime(rangeStart, 'rangeStart');
  const endsAt = normalizeDateTime(rangeEnd, 'rangeEnd');

  if (new Date(endsAt).getTime() < new Date(startsAt).getTime()) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'rangeEnd' });
  }

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('schedules')
    .select(
      `
        *,
        family_member:family_members (
          id,
          family_id,
          user_id,
          role,
          created_at,
          updated_at,
          user:users (
            id,
            nickname
          )
        )
      `,
    )
    .eq('family_id', familyId)
    .lt('starts_at', endsAt)
    .gt('ends_at', startsAt)
    .order('starts_at', { ascending: true });

  if (error) {
    throw error;
  }

  return (data ?? []) as unknown as Schedule[];
}

export async function createSchedule(
  userId: string,
  familyId: string,
  input: ScheduleInput,
) {
  await requireFamilyManager(userId, familyId);
  const normalized = await normalizeScheduleInput(familyId, input);

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('schedules')
    .insert({
      family_id: familyId,
      family_member_id: normalized.familyMemberId,
      title: normalized.title,
      content: normalized.content,
      starts_at: normalized.startsAt,
      ends_at: normalized.endsAt,
      vehicle_boarding_at: normalized.vehicleBoardingAt,
      vehicle_dropoff_at: normalized.vehicleDropoffAt,
      created_by_user_id: userId,
    })
    .select(
      `
        *,
        family_member:family_members (
          id,
          family_id,
          user_id,
          role,
          created_at,
          updated_at,
          user:users (
            id,
            nickname
          )
        )
      `,
    )
    .single();

  if (error) {
    throw error;
  }

  return data as unknown as Schedule;
}

export async function updateSchedule(
  userId: string,
  familyId: string,
  scheduleId: string,
  input: ScheduleInput,
) {
  await requireFamilyManager(userId, familyId);
  const normalized = await normalizeScheduleInput(familyId, input);

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('schedules')
    .update({
      family_member_id: normalized.familyMemberId,
      title: normalized.title,
      content: normalized.content,
      starts_at: normalized.startsAt,
      ends_at: normalized.endsAt,
      vehicle_boarding_at: normalized.vehicleBoardingAt,
      vehicle_dropoff_at: normalized.vehicleDropoffAt,
    })
    .eq('id', scheduleId)
    .eq('family_id', familyId)
    .select(
      `
        *,
        family_member:family_members (
          id,
          family_id,
          user_id,
          role,
          created_at,
          updated_at,
          user:users (
            id,
            nickname
          )
        )
      `,
    )
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'schedule_not_found' });
  }

  return data as unknown as Schedule;
}

export async function deleteSchedule(
  userId: string,
  familyId: string,
  scheduleId: string,
) {
  await requireFamilyManager(userId, familyId);

  const supabase = getSupabaseAdmin();
  const { error } = await supabase
    .from('schedules')
    .delete()
    .eq('id', scheduleId)
    .eq('family_id', familyId);

  if (error) {
    throw error;
  }
}

async function normalizeScheduleInput(familyId: string, input: ScheduleInput) {
  const startsAt = normalizeDateTime(input.startsAt, 'startsAt');
  const endsAt = normalizeDateTime(input.endsAt, 'endsAt');

  if (new Date(endsAt).getTime() < new Date(startsAt).getTime()) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'endsAt' });
  }

  await getFamilyMemberOrThrow(familyId, input.familyMemberId);

  return {
    familyMemberId: input.familyMemberId.trim(),
    title: normalizeText(input.title, 'title', 80),
    content: normalizeOptionalText(input.content, 'content', 1000),
    startsAt,
    endsAt,
    vehicleBoardingAt: normalizeOptionalDateTime(
      input.vehicleBoardingAt,
      'vehicleBoardingAt',
    ),
    vehicleDropoffAt: normalizeOptionalDateTime(
      input.vehicleDropoffAt,
      'vehicleDropoffAt',
    ),
  };
}

async function getFamilyMemberOrThrow(familyId: string, familyMemberId: string) {
  const normalized = familyMemberId.trim();

  if (!normalized) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'familyMemberId' });
  }

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('family_members')
    .select('id')
    .eq('id', normalized)
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

  if (!normalized) {
    throw new HttpError(400, { error: 'invalid_payload', field });
  }

  if (normalized.length > maxLength) {
    throw new HttpError(400, { error: 'invalid_payload', field });
  }

  return normalized;
}

function normalizeOptionalText(
  value: string | undefined,
  field: string,
  maxLength: number,
) {
  if (value === undefined) {
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

function normalizeDateTime(value: string, field: string) {
  const normalized = value.trim();
  const time = new Date(normalized).getTime();

  if (!normalized || Number.isNaN(time)) {
    throw new HttpError(400, { error: 'invalid_payload', field });
  }

  return new Date(time).toISOString();
}

function normalizeOptionalDateTime(value: string | undefined, field: string) {
  if (value === undefined || !value.trim()) {
    return null;
  }

  return normalizeDateTime(value, field);
}
