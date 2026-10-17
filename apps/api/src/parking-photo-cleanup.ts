import { getSupabaseAdmin } from './supabase';

// Family deletion cascades vehicles in Postgres, but Storage objects require
// explicit removal before those vehicle IDs disappear.
export async function removeParkingPhotosForFamilies(familyIds: string[]) {
  const db = getSupabaseAdmin();
  for (const familyId of familyIds) {
    for (let offset = 0; ; offset += 500) {
      const { data, error } = await db.from('vehicles').select('id')
        .eq('family_id', familyId).order('id').range(offset, offset + 499);
      if (error) throw error;
      const paths = (data ?? []).map((vehicle) => `${familyId}/${vehicle.id}.photo`);
      if (paths.length > 0) {
        const { error: removeError } = await db.storage.from('parking-photos')
          .remove(paths);
        if (removeError) throw removeError;
      }
      if ((data ?? []).length < 500) break;
    }
  }
}
