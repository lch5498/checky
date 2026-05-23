export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly body: Record<string, unknown>,
  ) {
    super(String(body.error ?? 'http_error'));
  }
}

export function jsonFromError(error: unknown, fallbackError: string) {
  if (error instanceof HttpError) {
    return Response.json(error.body, { status: error.status });
  }

  console.error(error);
  return Response.json({ error: fallbackError }, { status: 500 });
}
