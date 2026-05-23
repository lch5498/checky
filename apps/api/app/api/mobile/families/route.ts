import { createFamily, listFamilies } from '../../../../src/families';
import { jsonFromError } from '../../../../src/http';
import { authenticateMobileRequest } from '../../../../src/mobile-auth';
import {
  readJsonObject,
  requiredString,
} from '../../../../src/validation';

export const runtime = 'nodejs';

export async function GET(request: Request) {
  try {
    const userId = authenticateMobileRequest(request);
    const families = await listFamilies(userId);

    return Response.json({ families });
  } catch (error) {
    return jsonFromError(error, 'families_fetch_failed');
  }
}

export async function POST(request: Request) {
  try {
    const userId = authenticateMobileRequest(request);
    const payload = await readJsonObject(request);
    const name = requiredString(payload, 'name', { maxLength: 50 });
    const family = await createFamily(userId, name);

    return Response.json({ family }, { status: 201 });
  } catch (error) {
    return jsonFromError(error, 'family_create_failed');
  }
}
