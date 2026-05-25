create table if not exists public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by_user_id uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.family_members (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid references public.users(id) on delete set null,
  nickname text not null,
  role text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint family_members_role_check check (role in ('owner', 'co_owner', 'member')),
  constraint family_members_family_user_unique unique (family_id, user_id)
);

create table if not exists public.family_invitations (
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

create index if not exists families_created_by_user_id_idx
  on public.families (created_by_user_id);

create index if not exists family_members_family_id_idx
  on public.family_members (family_id);

create index if not exists family_members_user_id_idx
  on public.family_members (user_id);

create index if not exists family_invitations_family_id_idx
  on public.family_invitations (family_id);

create index if not exists family_invitations_family_member_id_idx
  on public.family_invitations (family_member_id);

create index if not exists family_invitations_invite_token_idx
  on public.family_invitations (invite_token);

alter table public.families enable row level security;
alter table public.family_members enable row level security;
alter table public.family_invitations enable row level security;

drop trigger if exists families_set_updated_at on public.families;
create trigger families_set_updated_at
before update on public.families
for each row execute function public.set_updated_at();

drop trigger if exists family_members_set_updated_at on public.family_members;
create trigger family_members_set_updated_at
before update on public.family_members
for each row execute function public.set_updated_at();

drop trigger if exists family_invitations_set_updated_at on public.family_invitations;
create trigger family_invitations_set_updated_at
before update on public.family_invitations
for each row execute function public.set_updated_at();
