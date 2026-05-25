import { randomBytes } from 'node:crypto';

import { HttpError } from './http';
import { getSupabaseAdmin } from './supabase';
import { getUserById } from './users';

export type FamilyRole = 'owner' | 'co_owner' | 'member';

export type Family = {
  id: string;
  name: string;
  created_by_user_id: string | null;
  created_at: string;
  updated_at: string;
};

export type FamilyMember = {
  id: string;
  family_id: string;
  user_id: string | null;
  nickname: string;
  role: FamilyRole;
  created_at: string;
  updated_at: string;
  user?: {
    id: string;
    nickname: string;
  };
};

export type FamilyInvitation = {
  id: string;
  family_id: string;
  family_member_id: string;
  invited_by_user_id: string | null;
  role?: FamilyRole;
  member_nickname?: string;
  invite_token: string;
  expires_at: string;
  accepted_by_user_id: string | null;
  accepted_at: string | null;
  revoked_at: string | null;
  created_at: string;
  updated_at: string;
};

const WRITER_ROLES: FamilyRole[] = ['owner', 'co_owner'];
const INVITATION_TTL_DAYS = 7;

export async function listFamilies(userId: string) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('family_members')
    .select(
      `
        id,
        role,
        created_at,
        family:families (
          id,
          name,
          created_by_user_id,
          created_at,
          updated_at
        )
      `,
    )
    .eq('user_id', userId)
    .order('created_at', { ascending: true });

  if (error) {
    throw error;
  }

  return (data ?? []).map((membership) => ({
    membershipId: membership.id as string,
    role: membership.role as FamilyRole,
    joinedAt: membership.created_at as string,
    family: membership.family as unknown as Family,
  }));
}

export async function createFamily(userId: string, name: string) {
  const supabase = getSupabaseAdmin();
  const familyName = normalizeName(name);
  const user = await getUserById(userId);

  const { data: family, error: createFamilyError } = await supabase
    .from('families')
    .insert({
      name: familyName,
      created_by_user_id: userId,
    })
    .select('*')
    .single();

  if (createFamilyError) {
    throw createFamilyError;
  }

  const { error: createMemberError } = await supabase
    .from('family_members')
    .insert({
      family_id: family.id,
      user_id: userId,
      nickname: user?.nickname ?? '대표',
      role: 'owner',
    });

  if (createMemberError) {
    await supabase.from('families').delete().eq('id', family.id);
    throw createMemberError;
  }

  return family as Family;
}

export async function getFamilyDetail(userId: string, familyId: string) {
  const membership = await requireMembership(userId, familyId);
  const family = await getFamilyOrThrow(familyId);
  const members = await listFamilyMembers(userId, familyId);

  return {
    family,
    myRole: membership.role,
    canManage: canManage(membership.role),
    members,
  };
}

export async function updateFamily(userId: string, familyId: string, name: string) {
  await requireFamilyManager(userId, familyId);

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('families')
    .update({ name: normalizeName(name) })
    .eq('id', familyId)
    .select('*')
    .single();

  if (error) {
    throw error;
  }

  return data as Family;
}

export async function deleteFamily(userId: string, familyId: string) {
  await requireFamilyManager(userId, familyId);

  const supabase = getSupabaseAdmin();
  const { error } = await supabase.from('families').delete().eq('id', familyId);

  if (error) {
    throw error;
  }
}

export async function listFamilyMembers(userId: string, familyId: string) {
  await requireMembership(userId, familyId);

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('family_members')
    .select(
      `
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
      `,
    )
    .eq('family_id', familyId)
    .order('created_at', { ascending: true });

  if (error) {
    throw error;
  }

  return (data ?? []) as unknown as FamilyMember[];
}

export async function createFamilyMember(
  userId: string,
  familyId: string,
  input: { nickname: string; role: FamilyRole },
) {
  await requireFamilyManager(userId, familyId);
  assertFamilyRole(input.role);

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('family_members')
    .insert({
      family_id: familyId,
      nickname: normalizeNickname(input.nickname),
      role: input.role,
    })
    .select(
      `
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
      `,
    )
    .single();

  if (error) {
    throw error;
  }

  return data as unknown as FamilyMember;
}

export async function removeFamilyMember(
  userId: string,
  familyId: string,
  memberId: string,
) {
  await requireFamilyManager(userId, familyId);

  const supabase = getSupabaseAdmin();
  const { data: member, error: memberError } = await supabase
    .from('family_members')
    .select('*')
    .eq('id', memberId)
    .eq('family_id', familyId)
    .maybeSingle();

  if (memberError) {
    throw memberError;
  }

  if (!member) {
    throw new HttpError(404, { error: 'member_not_found' });
  }

  if (member.user_id === userId) {
    throw new HttpError(409, { error: 'cannot_remove_self' });
  }

  if (member.role === 'owner') {
    const { count, error: countError } = await supabase
      .from('family_members')
      .select('id', { count: 'exact', head: true })
      .eq('family_id', familyId)
      .eq('role', 'owner');

    if (countError) {
      throw countError;
    }

    if ((count ?? 0) <= 1) {
      throw new HttpError(409, { error: 'cannot_remove_last_owner' });
    }
  }

  const { error } = await supabase
    .from('family_members')
    .delete()
    .eq('id', memberId)
    .eq('family_id', familyId);

  if (error) {
    throw error;
  }
}

export async function createFamilyInvitation(
  userId: string,
  familyId: string,
  memberId: string,
) {
  await requireFamilyManager(userId, familyId);

  const supabase = getSupabaseAdmin();
  const member = await getFamilyMemberOrThrow(familyId, memberId);

  if (member.user_id) {
    throw new HttpError(409, { error: 'family_member_already_linked' });
  }

  const token = randomBytes(24).toString('base64url');
  const expiresAt = new Date(
    Date.now() + INVITATION_TTL_DAYS * 24 * 60 * 60 * 1000,
  ).toISOString();

  const { data, error } = await supabase
    .from('family_invitations')
    .insert({
      family_id: familyId,
      family_member_id: member.id,
      invited_by_user_id: userId,
      invite_token: token,
      expires_at: expiresAt,
    })
    .select('*')
    .single();

  if (error) {
    throw error;
  }

  return {
    ...(data as FamilyInvitation),
    role: member.role,
    member_nickname: member.nickname,
  };
}

export async function getInvitationPreview(inviteToken: string) {
  const invitation = await getValidInvitation(inviteToken);
  const family = await getFamilyOrThrow(invitation.family_id);
  const member = await getFamilyMemberOrThrow(
    invitation.family_id,
    invitation.family_member_id,
  );

  return {
    family,
    memberId: member.id,
    memberNickname: member.nickname,
    role: member.role,
    expiresAt: invitation.expires_at,
  };
}

export async function acceptFamilyInvitation(userId: string, inviteToken: string) {
  const invitation = await getValidInvitation(inviteToken);
  const supabase = getSupabaseAdmin();
  const member = await getFamilyMemberOrThrow(
    invitation.family_id,
    invitation.family_member_id,
  );

  if (member.user_id && member.user_id !== userId) {
    throw new HttpError(409, { error: 'family_member_already_linked' });
  }

  const { data: existingMember, error: existingMemberError } = await supabase
    .from('family_members')
    .select('id')
    .eq('family_id', invitation.family_id)
    .eq('user_id', userId)
    .neq('id', member.id)
    .maybeSingle();

  if (existingMemberError) {
    throw existingMemberError;
  }

  if (existingMember) {
    throw new HttpError(409, { error: 'family_user_already_linked' });
  }

  const user = await getUserById(userId);
  const { error: updateMemberError } = await supabase
    .from('family_members')
    .update({
      user_id: userId,
      nickname: member.nickname || user?.nickname || '구성원',
    })
    .eq('id', member.id)
    .eq('family_id', invitation.family_id);

  if (updateMemberError) {
    throw updateMemberError;
  }

  const { error: acceptError } = await supabase
    .from('family_invitations')
    .update({
      accepted_by_user_id: userId,
      accepted_at: new Date().toISOString(),
    })
    .eq('id', invitation.id);

  if (acceptError) {
    throw acceptError;
  }

  return getFamilyDetail(userId, invitation.family_id);
}

export function getInviteUrl(inviteToken: string) {
  const baseUrl = process.env.MOBILE_INVITE_BASE_URL ?? 'housekeeping://family-invite';

  return `${baseUrl.replace(/\/$/, '')}/${inviteToken}`;
}

function normalizeName(name: string) {
  const normalized = name.trim();

  if (!normalized) {
    throw new HttpError(400, { error: 'name_required' });
  }

  if (normalized.length > 50) {
    throw new HttpError(400, { error: 'name_too_long' });
  }

  return normalized;
}

function normalizeNickname(nickname: string) {
  const normalized = nickname.trim();

  if (!normalized) {
    throw new HttpError(400, { error: 'nickname_required' });
  }

  if (normalized.length > 40) {
    throw new HttpError(400, { error: 'nickname_too_long' });
  }

  return normalized;
}

async function getFamilyOrThrow(familyId: string) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('families')
    .select('*')
    .eq('id', familyId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'family_not_found' });
  }

  return data as Family;
}

async function getFamilyMemberOrThrow(familyId: string, memberId: string) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('family_members')
    .select('*')
    .eq('id', memberId)
    .eq('family_id', familyId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'member_not_found' });
  }

  return data as FamilyMember;
}

export async function requireMembership(userId: string, familyId: string) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('family_members')
    .select('*')
    .eq('family_id', familyId)
    .eq('user_id', userId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(403, { error: 'family_access_denied' });
  }

  return data as FamilyMember;
}

export async function requireFamilyManager(userId: string, familyId: string) {
  const membership = await requireMembership(userId, familyId);

  if (!canManage(membership.role)) {
    throw new HttpError(403, { error: 'family_write_forbidden' });
  }

  return membership;
}

async function getValidInvitation(inviteToken: string) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('family_invitations')
    .select('*')
    .eq('invite_token', inviteToken.trim())
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'invitation_not_found' });
  }

  const invitation = data as FamilyInvitation;

  if (invitation.revoked_at || invitation.accepted_at) {
    throw new HttpError(409, { error: 'invitation_already_used' });
  }

  if (new Date(invitation.expires_at).getTime() < Date.now()) {
    throw new HttpError(410, { error: 'invitation_expired' });
  }

  return invitation;
}

function canManage(role: FamilyRole) {
  return WRITER_ROLES.includes(role);
}

function assertFamilyRole(role: string): asserts role is FamilyRole {
  if (!['owner', 'co_owner', 'member'].includes(role)) {
    throw new HttpError(400, { error: 'invalid_family_role' });
  }
}
