import { HttpError } from './http';
import { getSupabaseAdmin } from './supabase';

export type PushPlatform = 'ios' | 'android';

export type PushTokenRecord = {
  id: string;
  token: string;
  platform: PushPlatform;
};

export function normalizePushPlatform(platform: string): PushPlatform {
  if (platform === 'ios' || platform === 'android') return platform;
  throw new HttpError(400, { error: 'unsupported_push_platform' });
}

export async function upsertPushToken(
  userId: string,
  input: { token: string; platform: PushPlatform },
) {
  const supabase = getSupabaseAdmin();
  const now = new Date().toISOString();
  const { error } = await supabase.from('push_tokens').upsert(
    {
      user_id: userId,
      platform: input.platform,
      token: input.token,
      enabled: true,
      last_seen_at: now,
      updated_at: now,
    },
    { onConflict: 'token' },
  );

  if (error) {
    throw new HttpError(500, { error: 'push_token_save_failed' });
  }
}

export async function deletePushToken(userId: string, token: string) {
  const supabase = getSupabaseAdmin();
  const { error } = await supabase
    .from('push_tokens')
    .delete()
    .eq('user_id', userId)
    .eq('token', token);

  if (error) {
    throw new HttpError(500, { error: 'push_token_delete_failed' });
  }
}

export async function listPushTokensForUser(userId: string) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('push_tokens')
    .select('id, token, platform')
    .eq('user_id', userId)
    .eq('enabled', true)
    .order('last_seen_at', { ascending: false });

  if (error) {
    throw new HttpError(500, { error: 'push_token_list_failed' });
  }

  return (data ?? []) as PushTokenRecord[];
}
