create table if not exists public.travel_trips (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  title text not null,
  starts_on date not null,
  ends_on date not null,
  created_by_user_id uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint travel_trips_title_check check (char_length(btrim(title)) between 1 and 80),
  constraint travel_trips_date_range_check check (ends_on >= starts_on)
);

create table if not exists public.travel_itineraries (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  trip_id uuid not null references public.travel_trips(id) on delete cascade,
  itinerary_date date not null,
  title text not null,
  content text,
  map_url text,
  starts_at time,
  sort_order integer not null default 1,
  created_by_user_id uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint travel_itineraries_title_check check (char_length(btrim(title)) between 1 and 80),
  constraint travel_itineraries_content_check check (content is null or char_length(content) <= 2000),
  constraint travel_itineraries_map_url_check check (map_url is null or char_length(map_url) <= 1000)
);

create index if not exists travel_trips_family_starts_on_idx
  on public.travel_trips (family_id, starts_on desc);

create index if not exists travel_itineraries_trip_date_sort_idx
  on public.travel_itineraries (trip_id, itinerary_date asc, sort_order asc, created_at asc);

alter table public.travel_trips enable row level security;
alter table public.travel_itineraries enable row level security;

drop trigger if exists travel_trips_set_updated_at on public.travel_trips;
create trigger travel_trips_set_updated_at
  before update on public.travel_trips
  for each row
  execute function public.set_updated_at();

drop trigger if exists travel_itineraries_set_updated_at on public.travel_itineraries;
create trigger travel_itineraries_set_updated_at
  before update on public.travel_itineraries
  for each row
  execute function public.set_updated_at();
