create table public.korean_holidays (
  holiday_date date primary key,
  name text not null,
  source text not null check (source in ('kasi', 'manual')),
  source_updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index korean_holidays_date_idx
  on public.korean_holidays (holiday_date);

alter table public.korean_holidays enable row level security;
