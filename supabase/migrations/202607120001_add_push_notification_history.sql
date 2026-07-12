create table public.push_notification_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  family_id uuid references public.families(id) on delete set null,
  schedule_id uuid references public.schedules(id) on delete set null,
  notification_type text not null,
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  sent_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index push_notification_history_user_sent_at_idx
  on public.push_notification_history (user_id, sent_at desc);

alter table public.push_notification_history enable row level security;
