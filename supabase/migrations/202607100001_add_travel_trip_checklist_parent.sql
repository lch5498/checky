alter table public.travel_trip_checklist_items
  add column if not exists parent_id uuid references public.travel_trip_checklist_items(id) on delete cascade;

alter table public.travel_checklist_items
  add column if not exists parent_id uuid references public.travel_checklist_items(id) on delete cascade;

alter table public.travel_trip_checklist_items
  drop constraint if exists travel_trip_checklist_items_trip_name_unique;

alter table public.travel_checklist_items
  drop constraint if exists travel_checklist_items_family_name_unique;

drop index if exists public.travel_trip_checklist_items_trip_parent_name_unique;
drop index if exists public.travel_trip_checklist_items_trip_root_name_unique;
drop index if exists public.travel_trip_checklist_items_trip_child_name_unique;
drop index if exists public.travel_checklist_items_family_parent_name_unique;
drop index if exists public.travel_checklist_items_family_root_name_unique;
drop index if exists public.travel_checklist_items_family_child_name_unique;

create unique index travel_trip_checklist_items_trip_root_name_unique
  on public.travel_trip_checklist_items (trip_id, name)
  where parent_id is null;

create unique index travel_trip_checklist_items_trip_child_name_unique
  on public.travel_trip_checklist_items (trip_id, parent_id, name)
  where parent_id is not null;

create unique index travel_checklist_items_family_root_name_unique
  on public.travel_checklist_items (family_id, name)
  where parent_id is null;

create unique index travel_checklist_items_family_child_name_unique
  on public.travel_checklist_items (family_id, parent_id, name)
  where parent_id is not null;

create index if not exists travel_trip_checklist_items_parent_idx
  on public.travel_trip_checklist_items (family_id, trip_id, parent_id, sort_order, created_at);

create index if not exists travel_checklist_items_parent_idx
  on public.travel_checklist_items (family_id, parent_id, name, created_at);
