import { randomUUID } from 'node:crypto';
import { requireMembership } from './families';
import { HttpError } from './http';
import { getSupabaseAdmin } from './supabase';
import { couponFields, couponImage, couponVersion, readCouponPayload } from './coupon-validation';

export const COUPON_GROUP_LIMIT = 100;

function couponLimitError() {
  return new HttpError(409, { error: 'coupon_limit_reached', limit: COUPON_GROUP_LIMIT });
}

type Coupon = {
  id: string; family_id: string; title: string; memo: string; expires_on: string | null;
  image_path: string; created_by_user_id: string | null; used_at: string | null;
  used_by_user_id: string | null; version: number; deleted_at: string | null;
  created_at: string; updated_at: string;
  image_slot?: number;
};

function present(coupon: Coupon, userId: string, role: string, usedByName: string | null = null) {
  const { image_path: _path, deleted_at: _deleted, image_slot: _slot, ...data } = coupon;
  return { ...data, used_by_name: coupon.used_at ? usedByName : null,
    can_manage: role === 'owner' || coupon.created_by_user_id === userId };
}

async function presentWithCompletionNames(coupons: Coupon[], familyId: string, userId: string, role: string) {
  const ids = [...new Set(coupons.filter(c => c.used_at && c.used_by_user_id).map(c => c.used_by_user_id!))];
  const names = new Map<string, string>();
  if (ids.length > 0) {
    // A person's name can differ between groups. Never resolve via another group.
    const { data, error } = await getSupabaseAdmin().from('family_members')
      .select('user_id,nickname').eq('family_id', familyId).in('user_id', ids);
    if (error) throw error;
    for (const member of data ?? []) names.set(member.user_id, member.nickname);
  }
  return coupons.map(c => present(c, userId, role, names.get(c.used_by_user_id ?? '') ?? null));
}

async function findCoupon(familyId: string, id: string) {
  const { data, error } = await getSupabaseAdmin().from('coupons').select('*')
    .eq('family_id', familyId).eq('id', id).maybeSingle();
  if (error) throw error;
  if (!data) throw new HttpError(404, { error: 'coupon_not_found' });
  return data as Coupon;
}

export async function listCoupons(userId: string, familyId: string) {
  const member = await requireMembership(userId, familyId);
  // Page explicitly: do not silently truncate at Supabase's default 1000 rows.
  const result: Coupon[] = [];
  for (let offset = 0; ; offset += 500) {
    const { data, error } = await getSupabaseAdmin().from('coupons').select('*')
      .eq('family_id', familyId).is('deleted_at', null)
      .order('expires_on', { ascending: true, nullsFirst: false })
      .order('created_at', { ascending: false }).order('id').range(offset, offset + 499);
    if (error) throw error;
    result.push(...data as Coupon[]);
    if (data.length < 500) break;
  }
  return { coupons: await presentWithCompletionNames(result, familyId, userId, member.role) };
}

export async function createCoupon(userId: string, familyId: string, request: Request) {
  const member = await requireMembership(userId, familyId);
  const payload = await readCouponPayload(request);
  const fields = couponFields(payload);
  const image = couponImage(payload.imageBase64);
  const id = randomUUID();
  const imagePath = `${familyId}/${id}.${image.extension}`;
  const db = getSupabaseAdmin();
  // Fast rejection before uploading. The DB slot constraint handles races.
  const { count, error: countError } = await db.from('coupons')
    .select('id', { count: 'exact', head: true }).eq('family_id', familyId);
  if (countError) throw countError;
  if (count === null) throw new Error('coupon_count_unavailable');
  if (count >= COUPON_GROUP_LIMIT) throw couponLimitError();
  const { error: uploadError } = await db.storage.from('coupons').upload(imagePath, image.bytes,
    { contentType: image.contentType, upsert: false });
  if (uploadError) throw uploadError;
  const { data, error } = await db.from('coupons').insert({ id, family_id: familyId,
    ...fields, image_path: imagePath, created_by_user_id: userId }).select('*').single();
  if (error) {
    const cleanup = await db.storage.from('coupons').remove([imagePath]);
    if (cleanup.error) console.error('coupon_upload_cleanup_failed', id);
    if (error.message === 'coupon_limit_reached' ||
      (error.code === '23505' && error.message.includes('coupons_family_image_slot_key'))) {
      throw couponLimitError();
    }
    throw error;
  }
  return present(data as Coupon, userId, member.role);
}

export async function getCoupon(userId: string, familyId: string, id: string) {
  const member = await requireMembership(userId, familyId);
  const coupon = await findCoupon(familyId, id);
  if (coupon.deleted_at) throw new HttpError(404, { error: 'coupon_not_found' });
  return (await presentWithCompletionNames([coupon], familyId, userId, member.role))[0];
}

export async function updateCoupon(userId: string, familyId: string, id: string, request: Request) {
  const member = await requireMembership(userId, familyId);
  const payload = await readCouponPayload(request);
  const version = couponVersion(payload);
  const coupon = await findCoupon(familyId, id);
  if (coupon.deleted_at) throw new HttpError(404, { error: 'coupon_not_found' });
  const changes: Record<string, unknown> = { version: version + 1, updated_at: new Date().toISOString() };
  if ('used' in payload) {
    if (typeof payload.used !== 'boolean' || 'title' in payload || 'memo' in payload || 'expiresOn' in payload)
      throw new HttpError(400, { error: 'invalid_payload' });
    changes.used_at = payload.used ? new Date().toISOString() : null;
    changes.used_by_user_id = payload.used ? userId : null;
  } else {
    if (member.role !== 'owner' && coupon.created_by_user_id !== userId)
      throw new HttpError(403, { error: 'coupon_manage_denied' });
    Object.assign(changes, couponFields(payload));
  }
  const { data, error } = await getSupabaseAdmin().from('coupons').update(changes)
    .eq('family_id', familyId).eq('id', id).eq('version', version).is('deleted_at', null)
    .select('*').maybeSingle();
  if (error) throw error;
  if (!data) throw new HttpError(409, { error: 'coupon_changed' });
  return (await presentWithCompletionNames([data as Coupon], familyId, userId, member.role))[0];
}

export async function deleteCoupon(userId: string, familyId: string, id: string, request: Request) {
  const member = await requireMembership(userId, familyId);
  const version = couponVersion(await readCouponPayload(request));
  const coupon = await findCoupon(familyId, id);
  if (member.role !== 'owner' && coupon.created_by_user_id !== userId)
    throw new HttpError(403, { error: 'coupon_manage_denied' });
  const db = getSupabaseAdmin();
  // Hide first; retain the tombstone so failed Storage cleanup can be retried.
  if (!coupon.deleted_at) {
    const { data, error } = await db.from('coupons').update({ deleted_at: new Date().toISOString() })
      .eq('family_id', familyId).eq('id', id).eq('version', version).is('deleted_at', null).select('id').maybeSingle();
    if (error) throw error;
    if (!data) throw new HttpError(409, { error: 'coupon_changed' });
  }
  const { error: storageError } = await db.storage.from('coupons').remove([coupon.image_path]);
  if (storageError) throw storageError;
  const { error } = await db.from('coupons').delete().eq('family_id', familyId).eq('id', id);
  if (error) throw error;
  return { ok: true };
}

export async function couponImageResponse(userId: string, familyId: string, id: string) {
  await requireMembership(userId, familyId);
  const coupon = await findCoupon(familyId, id);
  if (coupon.deleted_at) throw new HttpError(404, { error: 'coupon_not_found' });
  const { data, error } = await getSupabaseAdmin().storage.from('coupons').download(coupon.image_path);
  if (error) throw error;
  return new Response(data, { headers: { 'Content-Type': data.type,
    'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff' } });
}
