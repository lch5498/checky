import { currentParkingPhotoResponse, saveCurrentParkingPhoto } from '../../../../../../../../../src/parking';
import { HttpError, jsonFromError } from '../../../../../../../../../src/http';
import { authenticateMobileRequest } from '../../../../../../../../../src/mobile-auth';

export const runtime = 'nodejs';

type RouteContext = { params: Promise<{ familyId: string; vehicleId: string }> };
const MAX_IMAGE_BYTES = 512 * 1024;
const MAX_BODY_BYTES = 720 * 1024;

export async function GET(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, vehicleId } = await context.params;
    return await currentParkingPhotoResponse(userId, familyId, vehicleId);
  } catch (error) {
    return jsonFromError(error, 'parking_photo_fetch_failed');
  }
}

export async function PUT(request: Request, context: RouteContext) {
  try {
    const userId = authenticateMobileRequest(request);
    const { familyId, vehicleId } = await context.params;
    const payload = await readPhotoPayload(request);
    await saveCurrentParkingPhoto(userId, familyId, vehicleId,
      payload.recordId, payload.bytes, payload.contentType);
    return Response.json({ ok: true });
  } catch (error) {
    return jsonFromError(error, 'parking_photo_upload_failed');
  }
}

async function readPhotoPayload(request: Request) {
  const reader = request.body?.getReader();
  if (!reader) throw new HttpError(400, { error: 'invalid_payload' });
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > MAX_BODY_BYTES) {
        await reader.cancel();
        throw new HttpError(413, { error: 'parking_photo_too_large' });
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
  const { recordId, imageBase64 } = payload as Record<string, unknown>;
  if (typeof recordId !== 'string' || !/^[0-9a-f-]{36}$/i.test(recordId) ||
      typeof imageBase64 !== 'string' || imageBase64.length % 4 !== 0 ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(imageBase64)) {
    throw new HttpError(400, { error: 'parking_photo_invalid' });
  }
  const bytes = Buffer.from(imageBase64, 'base64');
  if (bytes.length > MAX_IMAGE_BYTES) {
    throw new HttpError(413, { error: 'parking_photo_too_large' });
  }
  const jpeg = bytes.length >= 4 && bytes[0] === 0xff && bytes[1] === 0xd8 &&
    bytes[bytes.length - 2] === 0xff && bytes[bytes.length - 1] === 0xd9;
  const png = bytes.length >= 8 && bytes.subarray(0, 8)
    .equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  const webp = bytes.length >= 12 && bytes.toString('ascii', 0, 4) === 'RIFF' &&
    bytes.toString('ascii', 8, 12) === 'WEBP';
  if (!jpeg && !png && !webp) {
    throw new HttpError(400, { error: 'parking_photo_invalid' });
  }
  return { recordId, bytes, contentType: jpeg ? 'image/jpeg' :
    png ? 'image/png' : 'image/webp' };
}
