create extension if not exists "pgcrypto";

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.users (
  id uuid primary key default gen_random_uuid(),
  nickname text not null,
  last_login_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.authentications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  oauth_provider text not null,
  oauth_provider_id text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint authentications_provider_user_unique unique (
    oauth_provider,
    oauth_provider_id
  )
);

create table public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by_user_id uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.family_members (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid references public.users(id) on delete set null,
  nickname text not null,
  role text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint family_members_role_check check (
    role in ('owner', 'co_owner', 'member')
  ),
  constraint family_members_family_user_unique unique (family_id, user_id)
);

create table public.family_invitations (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  family_member_id uuid not null references public.family_members(id) on delete cascade,
  invited_by_user_id uuid references public.users(id) on delete set null,
  invite_token text not null unique,
  expires_at timestamptz not null,
  accepted_by_user_id uuid references public.users(id) on delete set null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  nickname text not null,
  plate_number text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.parking_location_presets (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  parent_preset_id uuid references public.parking_location_presets(id) on delete cascade,
  preset_type text not null,
  name text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint parking_location_presets_type_check check (
    preset_type in ('building', 'floor', 'detail')
  )
);

create table public.parking_records (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  building_preset_id uuid references public.parking_location_presets(id) on delete set null,
  floor_preset_id uuid references public.parking_location_presets(id) on delete set null,
  detail_preset_id uuid references public.parking_location_presets(id) on delete set null,
  building_text text not null,
  floor_text text not null,
  detail_text text not null,
  location_text text not null,
  created_by_user_id uuid references public.users(id) on delete set null,
  parked_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.education_programs (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  family_member_id uuid references public.family_members(id) on delete set null,
  name text not null,
  starts_on date not null,
  ends_on date not null,
  recurrence_type text not null default 'weekly',
  weekly_schedules jsonb not null default '[]'::jsonb,
  monthly_schedules jsonb not null default '[]'::jsonb,
  created_by_user_id uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint education_programs_date_order_check check (ends_on >= starts_on),
  constraint education_programs_recurrence_type_check check (
    recurrence_type in ('weekly', 'monthly')
  ),
  constraint education_programs_weekly_schedules_array_check check (
    jsonb_typeof(weekly_schedules) = 'array'
  ),
  constraint education_programs_monthly_schedules_array_check check (
    jsonb_typeof(monthly_schedules) = 'array'
  )
);

create table public.schedules (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  family_member_id uuid references public.family_members(id) on delete set null,
  education_program_id uuid references public.education_programs(id) on delete cascade,
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

create index authentications_user_id_idx
  on public.authentications (user_id);

create index families_created_by_user_id_idx
  on public.families (created_by_user_id);

create index family_members_family_id_idx
  on public.family_members (family_id);

create index family_members_user_id_idx
  on public.family_members (user_id);

create index family_invitations_family_id_idx
  on public.family_invitations (family_id);

create index family_invitations_family_member_id_idx
  on public.family_invitations (family_member_id);

create index family_invitations_invite_token_idx
  on public.family_invitations (invite_token);

create index vehicles_family_id_idx
  on public.vehicles (family_id);

create index parking_location_presets_family_id_idx
  on public.parking_location_presets (family_id);

create index parking_location_presets_parent_id_idx
  on public.parking_location_presets (parent_preset_id);

create index parking_location_presets_family_type_sort_idx
  on public.parking_location_presets (
    family_id,
    preset_type,
    sort_order,
    created_at
  );

create index parking_records_family_vehicle_parked_at_idx
  on public.parking_records (family_id, vehicle_id, parked_at desc);

create index education_programs_family_id_idx
  on public.education_programs (family_id);

create index education_programs_family_member_id_idx
  on public.education_programs (family_member_id);

create index schedules_family_starts_at_idx
  on public.schedules (family_id, starts_at);

create index schedules_family_ends_at_idx
  on public.schedules (family_id, ends_at);

create index schedules_family_member_id_idx
  on public.schedules (family_member_id);

create index schedules_education_program_id_idx
  on public.schedules (education_program_id);

alter table public.users enable row level security;
alter table public.authentications enable row level security;
alter table public.families enable row level security;
alter table public.family_members enable row level security;
alter table public.family_invitations enable row level security;
alter table public.vehicles enable row level security;
alter table public.parking_location_presets enable row level security;
alter table public.parking_records enable row level security;
alter table public.education_programs enable row level security;
alter table public.schedules enable row level security;

create trigger users_set_updated_at
before update on public.users
for each row execute function public.set_updated_at();

create trigger authentications_set_updated_at
before update on public.authentications
for each row execute function public.set_updated_at();

create trigger families_set_updated_at
before update on public.families
for each row execute function public.set_updated_at();

create trigger family_members_set_updated_at
before update on public.family_members
for each row execute function public.set_updated_at();

create trigger family_invitations_set_updated_at
before update on public.family_invitations
for each row execute function public.set_updated_at();

create trigger vehicles_set_updated_at
before update on public.vehicles
for each row execute function public.set_updated_at();

create trigger parking_location_presets_set_updated_at
before update on public.parking_location_presets
for each row execute function public.set_updated_at();

create trigger parking_records_set_updated_at
before update on public.parking_records
for each row execute function public.set_updated_at();

create trigger education_programs_set_updated_at
before update on public.education_programs
for each row execute function public.set_updated_at();

create trigger schedules_set_updated_at
before update on public.schedules
for each row execute function public.set_updated_at();

create or replace function public.list_current_parking_records(
  target_family_id uuid
)
returns table (
  id uuid,
  family_id uuid,
  vehicle_id uuid,
  building_preset_id uuid,
  floor_preset_id uuid,
  detail_preset_id uuid,
  building_text text,
  floor_text text,
  detail_text text,
  location_text text,
  created_by_user_id uuid,
  parked_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  created_by_user jsonb
)
language sql
stable
security invoker
set search_path = public
as $$
  select distinct on (record.vehicle_id)
    record.id,
    record.family_id,
    record.vehicle_id,
    record.building_preset_id,
    record.floor_preset_id,
    record.detail_preset_id,
    record.building_text,
    record.floor_text,
    record.detail_text,
    record.location_text,
    record.created_by_user_id,
    record.parked_at,
    record.created_at,
    record.updated_at,
    case
      when creator.id is null then null
      else jsonb_build_object(
        'id', creator.id,
        'nickname', creator.nickname
      )
    end as created_by_user
  from public.parking_records as record
  left join public.users as creator
    on creator.id = record.created_by_user_id
  where record.family_id = target_family_id
  order by record.vehicle_id, record.parked_at desc, record.created_at desc;
$$;
