import {
  listFamilyMembers,
  requireFamilyManager,
  requireMembership,
} from './families';
import { normalizeAlertOffsetMinutes } from './alert-offset';
import { recordGroupActivity } from './group-activity-logs';
import { listKoreanHolidays } from './korean-holidays';
import { listEducationPrograms } from './education-programs';
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
  is_all_day: boolean;
  vehicle_boarding_at: string | null;
  vehicle_dropoff_at: string | null;
  education_program_id: string | null;
  anniversary_id: string | null;
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
  education_program?: {
    id: string;
    name: string;
    phone_contacts: Array<{ label: string; phoneNumber: string }>;
  } | null;
  anniversary?: {
    id: string;
    category: string;
    title: string;
  } | null;
};

export type ScheduleInput = {
  familyMemberId: string;
  title: string;
  content?: string;
  startsAt: string;
  endsAt: string;
  isAllDay?: boolean;
  vehicleBoardingAt?: string;
  vehicleDropoffAt?: string;
  educationProgramId?: string;
  alertOffsetMinutes?: number | null;
};

type MembershipCheckOptions = {
  skipMembershipCheck?: boolean;
};

export async function getScheduleDashboard(
  userId: string,
  familyId: string,
  rangeStart: string,
  rangeEnd: string,
) {
  const membership = await requireMembership(userId, familyId);
  const [members, schedules, educationPrograms, holidays] = await Promise.all([
    listFamilyMembers(userId, familyId, { skipMembershipCheck: true }),
    listSchedules(userId, familyId, rangeStart, rangeEnd, {
      skipMembershipCheck: true,
    }),
    listEducationPrograms(userId, familyId, { skipMembershipCheck: true }),
    listKoreanHolidays(rangeStart, rangeEnd),
  ]);

  return {
    canManage: membership.role === 'owner',
    members,
    schedules,
    educationPrograms,
    holidays,
  };
}

export async function listSchedules(
  userId: string,
  familyId: string,
  rangeStart: string,
  rangeEnd: string,
  options: MembershipCheckOptions = {},
) {
  if (!options.skipMembershipCheck) {
    await requireMembership(userId, familyId);
  }

  const startsAt = normalizeDateTime(rangeStart, 'rangeStart');
  const endsAt = normalizeDateTime(rangeEnd, 'rangeEnd');

  if (new Date(endsAt).getTime() < new Date(startsAt).getTime()) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'rangeEnd' });
  }

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('schedules')
    .select(scheduleSelect)
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
      is_all_day: normalized.isAllDay,
      vehicle_boarding_at: normalized.vehicleBoardingAt,
      vehicle_dropoff_at: normalized.vehicleDropoffAt,
      education_program_id: normalized.educationProgramId,
      alert_offset_minutes: normalized.alertOffsetMinutes,
      created_by_user_id: userId,
    })
    .select(scheduleSelect)
    .single();

  if (error) {
    throw error;
  }

  const schedule = data as unknown as Schedule;
  await recordGroupActivity({
    familyId,
    actorUserId: userId,
    type: 'schedule',
    title: schedule.title,
    detail: '일정을 등록했어요.',
    target: {
      type: 'schedule',
      id: schedule.id,
      startsAt: schedule.starts_at,
    },
  });
  return schedule;
}

export async function updateSchedule(
  userId: string,
  familyId: string,
  scheduleId: string,
  input: ScheduleInput,
) {
  await requireFamilyManager(userId, familyId);
  await requireEditableSchedule(familyId, scheduleId);
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
      is_all_day: normalized.isAllDay,
      vehicle_boarding_at: normalized.vehicleBoardingAt,
      vehicle_dropoff_at: normalized.vehicleDropoffAt,
      education_program_id: normalized.educationProgramId,
      alert_offset_minutes: normalized.alertOffsetMinutes,
    })
    .eq('id', scheduleId)
    .eq('family_id', familyId)
    .select(scheduleSelect)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'schedule_not_found' });
  }

  const schedule = data as unknown as Schedule;
  await recordGroupActivity({
    familyId,
    actorUserId: userId,
    type: 'schedule',
    title: schedule.title,
    detail: '일정을 수정했어요.',
    target: {
      type: 'schedule',
      id: schedule.id,
      startsAt: schedule.starts_at,
    },
  });
  return schedule;
}

export async function deleteSchedule(
  userId: string,
  familyId: string,
  scheduleId: string,
) {
  await requireFamilyManager(userId, familyId);
  const schedule = await requireEditableSchedule(familyId, scheduleId);

  const supabase = getSupabaseAdmin();
  const { error } = await supabase
    .from('schedules')
    .delete()
    .eq('id', scheduleId)
    .eq('family_id', familyId);

  if (error) {
    throw error;
  }

  await recordGroupActivity({
    familyId,
    actorUserId: userId,
    type: 'schedule',
    title: schedule.title,
    detail: '일정을 삭제했어요.',
  });
}

async function requireEditableSchedule(familyId: string, scheduleId: string) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('schedules')
    .select('id, anniversary_id, title')
    .eq('id', scheduleId)
    .eq('family_id', familyId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'schedule_not_found' });
  }

  if (data.anniversary_id) {
    throw new HttpError(400, { error: 'anniversary_schedule_readonly' });
  }

  return data as { id: string; anniversary_id: string | null; title: string };
}

async function normalizeScheduleInput(familyId: string, input: ScheduleInput) {
  const startsAt = normalizeDateTime(input.startsAt, 'startsAt');
  const endsAt = normalizeDateTime(input.endsAt, 'endsAt');

  if (new Date(endsAt).getTime() < new Date(startsAt).getTime()) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'endsAt' });
  }

  const familyMemberId = await getFamilyMemberOrThrow(
    familyId,
    input.familyMemberId,
  );
  const educationProgramId = await normalizeEducationProgramId(
    familyId,
    familyMemberId,
    input.educationProgramId,
  );

  return {
    familyMemberId,
    title: normalizeText(input.title, 'title', 80),
    content: normalizeOptionalText(input.content, 'content', 1000),
    startsAt,
    endsAt,
    isAllDay: input.isAllDay === true,
    vehicleBoardingAt: normalizeOptionalDateTime(
      input.vehicleBoardingAt,
      'vehicleBoardingAt',
    ),
    vehicleDropoffAt: normalizeOptionalDateTime(
      input.vehicleDropoffAt,
      'vehicleDropoffAt',
    ),
    educationProgramId,
    alertOffsetMinutes: normalizeAlertOffsetMinutes(input.alertOffsetMinutes),
  };
}

async function normalizeEducationProgramId(
  familyId: string,
  familyMemberId: string,
  educationProgramId: string | undefined,
) {
  if (educationProgramId === undefined || !educationProgramId.trim()) {
    return null;
  }

  const normalized = educationProgramId.trim();
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('education_programs')
    .select('id, family_member_id')
    .eq('id', normalized)
    .eq('family_id', familyId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'education_program_not_found' });
  }

  if (data.family_member_id !== familyMemberId) {
    throw new HttpError(400, {
      error: 'education_program_member_mismatch',
      field: 'educationProgramId',
    });
  }

  return normalized;
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

  return normalized;
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

const scheduleSelect = `
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
  ),
  education_program:education_programs (
    id,
    name,
    phone_contacts
  ),
  anniversary:anniversaries (
    id,
    category,
    title
  )
`;
