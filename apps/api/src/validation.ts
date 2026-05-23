import { HttpError } from './http';

export async function readJsonObject(request: Request) {
  let payload: unknown;

  try {
    payload = await request.json();
  } catch {
    throw new HttpError(400, { error: 'invalid_json' });
  }

  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    throw new HttpError(400, { error: 'invalid_payload' });
  }

  return payload as Record<string, unknown>;
}

export function requiredString(
  payload: Record<string, unknown>,
  key: string,
  options: { maxLength?: number } = {},
) {
  const value = payload[key];

  if (typeof value !== 'string') {
    throw new HttpError(400, { error: 'invalid_payload', field: key });
  }

  const normalized = value.trim();

  if (!normalized) {
    throw new HttpError(400, { error: 'invalid_payload', field: key });
  }

  if (options.maxLength && normalized.length > options.maxLength) {
    throw new HttpError(400, { error: 'invalid_payload', field: key });
  }

  return normalized;
}

export function optionalString(
  payload: Record<string, unknown>,
  key: string,
  options: { maxLength?: number } = {},
) {
  const value = payload[key];

  if (value === undefined || value === null) {
    return undefined;
  }

  return requiredString(payload, key, options);
}

export function requiredFamilyRole(payload: Record<string, unknown>, key: string) {
  const role = requiredString(payload, key);

  if (!['owner', 'co_owner', 'member'].includes(role)) {
    throw new HttpError(400, { error: 'invalid_payload', field: key });
  }

  return role as 'owner' | 'co_owner' | 'member';
}
