import { after } from 'next/server';

import { sendFcmRefresh } from './fcm';
import { getSupabaseAdmin } from './supabase';

/** Call only after a successful group mutation. Push failure must not fail the save. */
export function scheduleGroupRefresh(familyId: string) {
  after(async () => {
    try {
      const supabase = getSupabaseAdmin();
      const { data: members, error } = await supabase
        .from('family_members').select('user_id').eq('family_id', familyId);
      if (error) throw error;
      const userIds = [...new Set((members ?? []).flatMap(
        (member) => member.user_id ? [member.user_id as string] : [],
      ))];
      if (userIds.length === 0) return;
      const { data: tokens, error: tokenError } = await supabase
        .from('push_tokens').select('id, token')
        .in('user_id', userIds).eq('enabled', true);
      if (tokenError) throw tokenError;
      // Include the actor's other devices too. Bound fan-out per request.
      for (let offset = 0; offset < (tokens?.length ?? 0); offset += 10) {
        await Promise.all((tokens ?? []).slice(offset, offset + 10).map(async (token) => {
          try {
            const result = await sendFcmRefresh(token.token, familyId);
            if (!result.ok) {
              console.error('Group refresh push rejected', { status: result.status, error: result.error });
            }
          } catch {
            console.error('Group refresh push delivery failed');
          }
        }));
      }
    } catch {
      console.error('Group refresh push preparation failed');
    }
  });
}
