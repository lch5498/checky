import { importPKCS8, SignJWT } from 'jose';

import { HttpError } from './http';

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';

let cachedAccessToken:
  | {
      token: string;
      expiresAtMs: number;
    }
  | null = null;

type FirebaseServiceAccount = {
  projectId: string;
  clientEmail: string;
  privateKey: string;
};

type FcmSendInput = {
  token: string;
  title: string;
  body: string;
  data?: Record<string, string>;
  validateOnly?: boolean;
};

export type FcmSendResult =
  | { ok: true; messageId: string }
  | { ok: false; status: number; error: string };

export async function sendFcmNotification(input: FcmSendInput) {
  const serviceAccount = getFirebaseServiceAccount();
  const accessToken = await getFirebaseAccessToken(serviceAccount);
  const response = await fetch(
    'https://fcm.googleapis.com/v1/projects/' +
      serviceAccount.projectId +
      '/messages:send',
    {
      method: 'POST',
      headers: {
        authorization: 'Bearer ' + accessToken,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        validate_only: input.validateOnly ?? false,
        message: {
          token: input.token,
          notification: {
            title: input.title,
            body: input.body,
          },
          data: input.data ?? {},
        },
      }),
    },
  );

  const payload = await readResponseJson(response);

  if (!response.ok) {
    return {
      ok: false,
      status: response.status,
      error: getFirebaseError(payload),
    } satisfies FcmSendResult;
  }

  return {
    ok: true,
    messageId: typeof payload.name === 'string' ? payload.name : '',
  } satisfies FcmSendResult;
}

async function getFirebaseAccessToken(serviceAccount: FirebaseServiceAccount) {
  if (cachedAccessToken && cachedAccessToken.expiresAtMs > Date.now() + 60_000) {
    return cachedAccessToken.token;
  }

  const now = Math.floor(Date.now() / 1000);
  const privateKey = await importPKCS8(serviceAccount.privateKey, 'RS256');
  const assertion = await new SignJWT({ scope: FCM_SCOPE })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(serviceAccount.clientEmail)
    .setSubject(serviceAccount.clientEmail)
    .setAudience(GOOGLE_TOKEN_URL)
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(privateKey);

  const response = await fetch(GOOGLE_TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  const payload = await readResponseJson(response);

  if (!response.ok || typeof payload.access_token !== 'string') {
    throw new HttpError(502, {
      error: 'firebase_access_token_failed',
      detail: getFirebaseError(payload),
    });
  }

  const expiresInSeconds =
    typeof payload.expires_in === 'number' ? payload.expires_in : 3600;
  cachedAccessToken = {
    token: payload.access_token,
    expiresAtMs: Date.now() + expiresInSeconds * 1000,
  };

  return cachedAccessToken.token;
}

function getFirebaseServiceAccount(): FirebaseServiceAccount {
  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;

  if (serviceAccountJson) {
    try {
      const parsed = JSON.parse(serviceAccountJson) as Record<string, unknown>;
      return normalizeServiceAccount({
        projectId: parsed.project_id,
        clientEmail: parsed.client_email,
        privateKey: parsed.private_key,
      });
    } catch {
      throw new HttpError(500, { error: 'invalid_firebase_service_account' });
    }
  }

  return normalizeServiceAccount({
    projectId: process.env.FIREBASE_PROJECT_ID,
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
    privateKey: process.env.FIREBASE_PRIVATE_KEY,
  });
}

function normalizeServiceAccount(input: Record<string, unknown>) {
  const projectId = typeof input.projectId === 'string' ? input.projectId.trim() : '';
  const clientEmail =
    typeof input.clientEmail === 'string' ? input.clientEmail.trim() : '';
  const privateKey =
    typeof input.privateKey === 'string'
      ? input.privateKey.replace(/\\n/g, '\n').trim()
      : '';

  if (!projectId || !clientEmail || !privateKey) {
    throw new HttpError(500, { error: 'missing_firebase_credentials' });
  }

  return { projectId, clientEmail, privateKey } satisfies FirebaseServiceAccount;
}

async function readResponseJson(response: Response) {
  try {
    return (await response.json()) as Record<string, unknown>;
  } catch {
    return {};
  }
}

function getFirebaseError(payload: Record<string, unknown>) {
  const error = payload.error;

  if (error && typeof error === 'object' && !Array.isArray(error)) {
    const firebaseError = error as Record<string, unknown>;
    if (typeof firebaseError.status === 'string') return firebaseError.status;
    if (typeof firebaseError.message === 'string') return firebaseError.message;
  }

  if (typeof payload.error_description === 'string') {
    return payload.error_description;
  }

  if (typeof payload.error === 'string') {
    return payload.error;
  }

  return 'fcm_send_failed';
}
