import { HttpError } from './http';
import { requiredString } from './validation';

export const COUPON_IMAGE_MAX_BYTES = 2 * 1024 * 1024;
const MAX_BODY_BYTES = 3 * 1024 * 1024;

// Bound the stream, not just Content-Length (which clients can omit).
export async function readCouponPayload(request: Request) {
  const reader = request.body?.getReader();
  if (!reader) throw new HttpError(400, { error: 'invalid_payload' });
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.length;
      if (length > MAX_BODY_BYTES) {
        await reader.cancel();
        throw new HttpError(413, { error: 'coupon_image_too_large' });
      }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  let payload: unknown;
  try { payload = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw new HttpError(400, { error: 'invalid_json' }); }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    throw new HttpError(400, { error: 'invalid_payload' });
  }
  return payload as Record<string, unknown>;
}

export function couponFields(payload: Record<string, unknown>) {
  const title = requiredString(payload, 'title', { maxLength: 100 });
  const memo = payload.memo ?? '';
  if (typeof memo !== 'string' || memo.length > 1000) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'memo' });
  }
  let couponNumber: string | undefined;
  if ('couponNumber' in payload) {
    const value = payload.couponNumber ?? '';
    if (typeof value !== 'string' || value.trim().length > 128 ||
      /[\u0000-\u001f\u007f]/.test(value)) {
      throw new HttpError(400, { error: 'invalid_payload', field: 'couponNumber' });
    }
    couponNumber = value.trim();
  }
  const expires = payload.expiresOn ?? null;
  if (expires !== null && (typeof expires !== 'string' ||
    !/^\d{4}-\d{2}-\d{2}$/.test(expires) ||
    expires.startsWith('0000-') ||
    !Number.isFinite(Date.parse(expires)) ||
    new Date(expires).toISOString().slice(0, 10) !== expires)) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'expiresOn' });
  }
  return { title, memo: memo.trim(), expires_on: expires as string | null,
    ...(couponNumber === undefined ? {} : { coupon_number: couponNumber }) };
}

export function couponImage(value: unknown) {
  if (typeof value !== 'string' || !value.length || value.length % 4 !== 0 ||
    !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) {
    throw new HttpError(400, { error: 'coupon_image_invalid' });
  }
  const bytes = Buffer.from(value, 'base64');
  if (bytes.length > COUPON_IMAGE_MAX_BYTES) {
    throw new HttpError(413, { error: 'coupon_image_too_large' });
  }
  // Never trust a client filename or MIME type; SVG/HTML are not accepted.
  if (bytes.length >= 12) {
    if (bytes.subarray(0, 3).equals(Buffer.from([0xff, 0xd8, 0xff])))
      return { bytes, contentType: 'image/jpeg', extension: 'jpg' };
    if (bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10])))
      return { bytes, contentType: 'image/png', extension: 'png' };
    if (bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP')
      return { bytes, contentType: 'image/webp', extension: 'webp' };
  }
  throw new HttpError(400, { error: 'coupon_image_invalid' });
}

export function couponVersion(payload: Record<string, unknown>) {
  if (!Number.isSafeInteger(payload.version) || (payload.version as number) < 1 ||
    (payload.version as number) >= 2147483647) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'version' });
  }
  return payload.version as number;
}
