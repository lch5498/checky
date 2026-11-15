-- Morning briefing push: per-user opt-in settings and one delivery record per briefing day.
create table if not exists public.briefing_settings (
  user_id uuid primary key references public.users(id) on delete cascade,
  enabled boolean not null default false,
  -- Asia/Seoul wall-clock time of the daily briefing.
  send_time time not null default '08:00',
  weekly_preview_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.briefing_settings enable row level security;

drop trigger if exists briefing_settings_set_updated_at on public.briefing_settings;
create trigger briefing_settings_set_updated_at
before update on public.briefing_settings
for each row execute function public.set_updated_at();

create table if not exists public.briefing_deliveries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  briefing_kind text not null check (briefing_kind in ('daily', 'weekly')),
  -- Asia/Seoul date the briefing is for.
  briefing_date date not null,
  status text not null default 'processing'
    check (status in ('processing', 'sent', 'failed', 'no_targets', 'empty')),
  token_count integer not null default 0,
  success_count integer not null default 0,
  failure_count integer not null default 0,
  error_summary jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, briefing_kind, briefing_date)
);

create index if not exists briefing_deliveries_user_id_idx
  on public.briefing_deliveries (user_id, briefing_date desc);

alter table public.briefing_deliveries enable row level security;

drop trigger if exists briefing_deliveries_set_updated_at on public.briefing_deliveries;
create trigger briefing_deliveries_set_updated_at
before update on public.briefing_deliveries
for each row execute function public.set_updated_at();
