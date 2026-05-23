create table if not exists public.schedules (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  family_member_id uuid references public.family_members(id) on delete set null,
  title text not null,
  content text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  vehicle_boarding_at timestamptz,
  vehicle_dropoff_at timestamptz,
  created_by_user_id uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint schedules_time_order_check check (ends_at >= starts_at)
);

create index if not exists schedules_family_starts_at_idx
  on public.schedules (family_id, starts_at);

create index if not exists schedules_family_ends_at_idx
  on public.schedules (family_id, ends_at);

create index if not exists schedules_family_member_id_idx
  on public.schedules (family_member_id);

alter table public.schedules enable row level security;

drop trigger if exists schedules_set_updated_at on public.schedules;
create trigger schedules_set_updated_at
before update on public.schedules
for each row execute function public.set_updated_at();
