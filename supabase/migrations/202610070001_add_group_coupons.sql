create table public.coupons (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 100),
  memo text not null default '' check (char_length(memo) <= 1000),
  expires_on date,
  image_path text not null unique,
  created_by_user_id uuid references public.users(id) on delete set null,
  used_at timestamptz,
  used_by_user_id uuid references public.users(id) on delete set null,
  version integer not null default 1,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.coupons enable row level security;
create index coupons_family_expiry_idx on public.coupons (family_id, expires_on, created_at desc)
  where deleted_at is null;

-- Own API session authentication only: no public/client read or write policies.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('coupons', 'coupons', false, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false,
  file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
