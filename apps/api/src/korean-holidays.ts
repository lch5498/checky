import { HttpError } from './http';
import { getSupabaseAdmin } from './supabase';

const KASI_REST_DAY_URL =
  'https://apis.data.go.kr/B090041/openapi/service/SpcdeInfoService/getRestDeInfo';
const KOREA_TIME_ZONE = 'Asia/Seoul';

type KoreanHolidayRow = {
  holiday_date: string;
  name: string;
  source: 'kasi' | 'manual';
};

type KasisRestDay = {
  dateName?: unknown;
  isHoliday?: unknown;
  locdate?: unknown;
};

export type KoreanHoliday = {
  date: string;
  name: string;
};

export async function listKoreanHolidays(
  rangeStart: string,
  rangeEnd: string,
) {
  const startDate = koreanDateFromIso(rangeStart);
  const endDate = koreanDateFromIso(rangeEnd);

  if (endDate <= startDate) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'range' });
  }

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('korean_holidays')
    .select('holiday_date, name, source')
    .gte('holiday_date', startDate)
    .lt('holiday_date', endDate)
    .order('holiday_date', { ascending: true });

  if (error) {
    throw error;
  }

  return (data ?? []).map((row) => {
    const holiday = row as KoreanHolidayRow;
    return {
      date: holiday.holiday_date,
      name: normalizeHolidayName(holiday.name),
    };
  });
}

export async function syncKoreanHolidays(input: {
  startYear?: number;
  endYear?: number;
} = {}) {
  const serviceKey = process.env.KASI_SERVICE_KEY?.trim();
  if (!serviceKey) {
    throw new HttpError(500, { error: 'kasi_service_key_missing' });
  }

  const currentYear = Number(
    new Intl.DateTimeFormat('en-US', {
      timeZone: KOREA_TIME_ZONE,
      year: 'numeric',
    }).format(new Date()),
  );
  const startYear = input.startYear ?? currentYear;
  const endYear = input.endYear ?? currentYear + 1;

  if (
    !Number.isInteger(startYear) ||
    !Number.isInteger(endYear) ||
    startYear < 1900 ||
    endYear > 2100 ||
    endYear < startYear ||
    endYear - startYear > 50
  ) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'year' });
  }

  const results = [];
  for (let year = startYear; year <= endYear; year += 1) {
    const holidays = await fetchKasiHolidays(year, serviceKey);
    const result = await upsertKoreanHolidays(year, holidays);
    results.push({ year, ...result });
  }

  return {
    startYear,
    endYear,
    years: results,
    holidayCount: results.reduce((sum, result) => sum + result.holidayCount, 0),
  };
}

async function fetchKasiHolidays(year: number, serviceKey: string) {
  const url = new URL(KASI_REST_DAY_URL);
  url.searchParams.set('ServiceKey', serviceKey);
  url.searchParams.set('solYear', String(year));
  url.searchParams.set('numOfRows', '100');
  url.searchParams.set('_type', 'json');

  const response = await fetch(url, {
    headers: { Accept: 'application/json' },
    signal: AbortSignal.timeout(10_000),
  });

  if (!response.ok) {
    throw new HttpError(502, {
      error: 'kasi_holiday_fetch_failed',
      status: response.status,
    });
  }

  const payload = (await response.json()) as {
    response?: {
      header?: { resultCode?: string; resultMsg?: string };
      body?: { items?: { item?: KasisRestDay | KasisRestDay[] } };
    };
  };
  const header = payload.response?.header;
  if (header?.resultCode && header.resultCode !== '00') {
    throw new HttpError(502, {
      error: 'kasi_holiday_fetch_failed',
      detail: header.resultMsg ?? header.resultCode,
    });
  }

  const item = payload.response?.body?.items?.item;
  const items = Array.isArray(item) ? item : item ? [item] : [];
  const holidays = new Map<string, string>();

  for (const entry of items) {
    if (entry.isHoliday !== 'Y') {
      continue;
    }

    const date = toDateOnly(entry.locdate);
    const name =
        typeof entry.dateName === 'string'
            ? normalizeHolidayName(entry.dateName)
            : '';
    if (!date || !name) {
      continue;
    }

    const previous = holidays.get(date);
    holidays.set(date, previous ? `${previous} · ${name}` : name);
  }

  return [...holidays].map(([date, name]) => ({ date, name }));
}

async function upsertKoreanHolidays(
  year: number,
  holidays: Array<{ date: string; name: string }>,
) {
  const supabase = getSupabaseAdmin();
  const startDate = `${year}-01-01`;
  const endDate = `${year + 1}-01-01`;
  const { data: manualRows, error: manualError } = await supabase
    .from('korean_holidays')
    .select('holiday_date')
    .eq('source', 'manual')
    .gte('holiday_date', startDate)
    .lt('holiday_date', endDate);

  if (manualError) {
    throw manualError;
  }

  const manualDates = new Set(
    (manualRows ?? []).map((row) => (row as { holiday_date: string }).holiday_date),
  );
  const rows = holidays
    .filter((holiday) => !manualDates.has(holiday.date))
    .map((holiday) => ({
      holiday_date: holiday.date,
      name: holiday.name,
      source: 'kasi' as const,
      source_updated_at: new Date().toISOString(),
    }));

  if (rows.length > 0) {
    const { error } = await supabase
      .from('korean_holidays')
      .upsert(rows, { onConflict: 'holiday_date' });

    if (error) {
      throw error;
    }
  }

  return { holidayCount: rows.length };
}

function koreanDateFromIso(value: string) {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw new HttpError(400, { error: 'invalid_payload', field: 'range' });
  }

  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: KOREA_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(parsed);
  const partValue = (type: string) =>
    parts.find((part) => part.type === type)?.value;

  return `${partValue('year')}-${partValue('month')}-${partValue('day')}`;
}

function toDateOnly(value: unknown) {
  const date = String(value ?? '');
  if (!/^\d{8}$/.test(date)) {
    return null;
  }

  return `${date.substring(0, 4)}-${date.substring(4, 6)}-${date.substring(6, 8)}`;
}

function normalizeHolidayName(value: string) {
  return value.trim().replaceAll('기독탄신일', '크리스마스');
}
