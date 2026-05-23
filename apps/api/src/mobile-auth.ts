import { HttpError } from './http';
import { getBearerToken, verifySessionToken } from './session';

export function authenticateMobileRequest(request: Request) {
  const token = getBearerToken(request);

  if (!token) {
    throw new HttpError(401, { error: 'missing_token' });
  }

  const session = verifySessionToken(token);

  if (!session) {
    throw new HttpError(401, { error: 'invalid_token' });
  }

  return session.sub;
}
