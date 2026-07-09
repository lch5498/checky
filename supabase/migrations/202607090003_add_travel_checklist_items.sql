create table if not exists public.travel_checklist_items (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  name text not null,
  created_by_user_id uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint travel_checklist_items_name_check check (char_length(btrim(name)) between 1 and 40),
  constraint travel_checklist_items_family_name_unique unique (family_id, name)
);

create index if not exists travel_checklist_items_family_name_idx
  on public.travel_checklist_items (family_id, name);

alter table public.travel_checklist_items enable row level security;

drop trigger if exists travel_checklist_items_set_updated_at on public.travel_checklist_items;
create trigger travel_checklist_items_set_updated_at
  before update on public.travel_checklist_items
  for each row
  execute function public.set_updated_at();
