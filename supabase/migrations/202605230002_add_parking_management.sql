create table if not exists public.vehicles (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  nickname text not null,
  plate_number text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.parking_location_presets (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  name text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.parking_records (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  preset_id uuid references public.parking_location_presets(id) on delete set null,
  location_text text not null,
  created_by_user_id uuid references public.users(id) on delete set null,
  parked_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists vehicles_family_id_idx
  on public.vehicles (family_id);

create index if not exists parking_location_presets_family_id_idx
  on public.parking_location_presets (family_id);

create index if not exists parking_records_family_vehicle_parked_at_idx
  on public.parking_records (family_id, vehicle_id, parked_at desc);

alter table public.vehicles enable row level security;
alter table public.parking_location_presets enable row level security;
alter table public.parking_records enable row level security;

drop trigger if exists vehicles_set_updated_at on public.vehicles;
create trigger vehicles_set_updated_at
before update on public.vehicles
for each row execute function public.set_updated_at();

drop trigger if exists parking_location_presets_set_updated_at on public.parking_location_presets;
create trigger parking_location_presets_set_updated_at
before update on public.parking_location_presets
for each row execute function public.set_updated_at();

drop trigger if exists parking_records_set_updated_at on public.parking_records;
create trigger parking_records_set_updated_at
before update on public.parking_records
for each row execute function public.set_updated_at();
