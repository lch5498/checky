alter table public.travel_trips
  add column if not exists checklist_seeded_at timestamptz;

create table if not exists public.travel_trip_checklist_items (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  trip_id uuid not null references public.travel_trips(id) on delete cascade,
  name text not null,
  is_checked boolean not null default false,
  sort_order integer not null default 1,
  created_by_user_id uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint travel_trip_checklist_items_name_check check (char_length(btrim(name)) between 1 and 40),
  constraint travel_trip_checklist_items_trip_name_unique unique (trip_id, name)
);

create index if not exists travel_trip_checklist_items_family_trip_idx
  on public.travel_trip_checklist_items (family_id, trip_id, sort_order, created_at);

alter table public.travel_trip_checklist_items enable row level security;

drop trigger if exists travel_trip_checklist_items_set_updated_at on public.travel_trip_checklist_items;
create trigger travel_trip_checklist_items_set_updated_at
  before update on public.travel_trip_checklist_items
  for each row
  execute function public.set_updated_at();
