alter table public.vehicles
  add column parking_photo_record_id uuid references public.parking_records(id) on delete set null;

create or replace function public.clear_current_parking_photo_on_new_record()
returns trigger language plpgsql set search_path = public as $$
begin
  update public.vehicles set parking_photo_record_id = null
  where id = new.vehicle_id and family_id = new.family_id;
  return new;
end;
$$;

create trigger parking_records_clear_current_photo
after insert on public.parking_records
for each row execute function public.clear_current_parking_photo_on_new_record();

-- One private object per vehicle. Its path is stable and its bytes are replaced
-- when the current parking location photo changes. History rows never own photos.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('parking-photos', 'parking-photos', false, 524288,
  array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
