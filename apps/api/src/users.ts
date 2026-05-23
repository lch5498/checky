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

type KakaoLoginResult =
  | {
      requiresProfile: true;
      provider: typeof KAKAO_PROVIDER;
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
): Promise<KakaoLoginResult> {
  const supabase = getSupabaseAdmin();
  const providerId = String(kakaoUser.id);
  const nickname = normalizeNickname(options.nickname);
  const now = new Date().toISOString();

  const { data: authentication, error: authenticationError } = await supabase
    .from('authentications')
    .select('user_id')
    .eq('oauth_provider', KAKAO_PROVIDER)
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
      provider: KAKAO_PROVIDER,
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
      oauth_provider: KAKAO_PROVIDER,
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

function normalizeNickname(nickname: string | undefined) {
  const normalized = nickname?.trim();

  return normalized && normalized.length > 0 ? normalized : null;
}
