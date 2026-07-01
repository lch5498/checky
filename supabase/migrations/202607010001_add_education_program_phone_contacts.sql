alter table public.education_programs
  add column if not exists phone_contacts jsonb not null default '[]'::jsonb;

update public.education_programs
set phone_contacts = '[]'::jsonb
where phone_contacts is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'education_programs_phone_contacts_array_check'
      and conrelid = 'public.education_programs'::regclass
  ) then
    alter table public.education_programs
      add constraint education_programs_phone_contacts_array_check
      check (jsonb_typeof(phone_contacts) = 'array');
  end if;
end $$;
