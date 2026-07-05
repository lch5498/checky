import type { KakaoUser } from './kakao';
import { getSupabaseAdmin } from './supabase';

export type AppUser = {
  id: string;
  nickname: string;
  last_login_at: string | null;
  created_at: string;
  updated_at: string;
};

const KAKAO_PROVIDER = 'kakao';
const APPLE_PROVIDER = 'apple';

type OAuthProvider = typeof KAKAO_PROVIDER | typeof APPLE_PROVIDER;

type OAuthLoginResult =
  | {
      requiresProfile: true;
      provider: OAuthProvider;
      providerId: string;
    }
  | {
      requiresProfile: false;
      isNewUser: boolean;
      user: AppUser;
    };

export async function findOrCreateUserFromKakao(
  kakaoUser: KakaoUser,
  options: { nickname?: string } = {},
): Promise<OAuthLoginResult> {
  const providerId = String(kakaoUser.id);
  return findOrCreateUserFromProvider(KAKAO_PROVIDER, providerId, options);
}

export async function findOrCreateUserFromApple(
  appleUser: { sub: string },
  options: { nickname?: string } = {},
): Promise<OAuthLoginResult> {
  return findOrCreateUserFromProvider(APPLE_PROVIDER, appleUser.sub, {
    ...options,
    defaultNickname: '체키 사용자',
  });
}

async function findOrCreateUserFromProvider(
  provider: OAuthProvider,
  providerId: string,
  options: { nickname?: string; defaultNickname?: string } = {},
): Promise<OAuthLoginResult> {
  const supabase = getSupabaseAdmin();
  const nickname =
    normalizeNickname(options.nickname) ??
    normalizeNickname(options.defaultNickname);
  const now = new Date().toISOString();

  const { data: authentication, error: authenticationError } = await supabase
    .from('authentications')
    .select('user_id')
    .eq('oauth_provider', provider)
    .eq('oauth_provider_id', providerId)
    .maybeSingle();

  if (authenticationError) {
    throw authenticationError;
  }

  if (authentication?.user_id) {
    const { data: user, error: userError } = await supabase
      .from('users')
      .update({
        last_login_at: now,
      })
      .eq('id', authentication.user_id)
      .select('*')
      .single();

    if (userError) {
      throw userError;
    }

    return {
      requiresProfile: false,
      isNewUser: false,
      user: user as AppUser,
    };
  }

  if (!nickname) {
    return {
      requiresProfile: true,
      provider,
      providerId,
    };
  }

  const { data: user, error: createUserError } = await supabase
    .from('users')
    .insert({
      nickname,
      last_login_at: now,
    })
    .select('*')
    .single();

  if (createUserError) {
    throw createUserError;
  }

  const { error: createAuthenticationError } = await supabase
    .from('authentications')
    .insert({
      user_id: user.id,
      oauth_provider: provider,
      oauth_provider_id: providerId,
    });

  if (createAuthenticationError) {
    throw createAuthenticationError;
  }

  return {
    requiresProfile: false,
    isNewUser: true,
    user: user as AppUser,
  };
}

export async function getUserById(userId: string) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('users')
    .select('*')
    .eq('id', userId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  return data as AppUser | null;
}

export async function updateUserNickname(userId: string, nickname: string) {
  const supabase = getSupabaseAdmin();
  const normalizedNickname = normalizeNickname(nickname);

  if (!normalizedNickname) {
    throw new Error('nickname_required');
  }

  const { data, error } = await supabase
    .from('users')
    .update({ nickname: normalizedNickname })
    .eq('id', userId)
    .select('*')
    .single();

  if (error) {
    throw error;
  }

  return data as AppUser;
}

export async function deleteUserAccount(userId: string) {
  const supabase = getSupabaseAdmin();

  const { data: memberships, error: membershipsError } = await supabase
    .from('family_members')
    .select('family_id, role')
    .eq('user_id', userId);

  if (membershipsError) {
    throw membershipsError;
  }

  const ownerFamilyIds = [
    ...new Set(
      (memberships ?? [])
        .filter((membership) => membership.role === 'owner')
        .map((membership) => membership.family_id as string),
    ),
  ];

  if (ownerFamilyIds.length > 0) {
    const { error: familiesDeleteError } = await supabase
      .from('families')
      .delete()
      .in('id', ownerFamilyIds);

    if (familiesDeleteError) {
      throw familiesDeleteError;
    }
  }

  const { error: membershipsDeleteError } = await supabase
    .from('family_members')
    .delete()
    .eq('user_id', userId);

  if (membershipsDeleteError) {
    throw membershipsDeleteError;
  }

  const { error: userDeleteError } = await supabase
    .from('users')
    .delete()
    .eq('id', userId);

  if (userDeleteError) {
    throw userDeleteError;
  }
}

function normalizeNickname(nickname: string | undefined) {
  const normalized = nickname?.trim();

  return normalized && normalized.length > 0 ? normalized : null;
}
