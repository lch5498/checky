-- Each stored image occupies one of 100 slots, including used/expired coupons
-- and deletion tombstones whose Storage cleanup has not finished.
begin;
lock table public.coupons in access exclusive mode;

do $$
begin
  if exists (select 1 from public.coupons group by family_id having count(*) > 100) then
    raise exception 'coupon_limit_migration: remove excess coupons before applying (max 100 per group)';
  end if;
end $$;

alter table public.coupons add column image_slot smallint;
with numbered as (
  select id, row_number() over (partition by family_id order by created_at, id) as slot
  from public.coupons
)
update public.coupons c set image_slot = numbered.slot from numbered where c.id = numbered.id;
alter table public.coupons
  alter column image_slot set not null,
  add constraint coupons_image_slot_range check (image_slot between 1 and 100),
  add constraint coupons_family_image_slot_key unique (family_id, image_slot);

create function public.assign_coupon_image_slot() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if TG_OP = 'UPDATE' then
    if new.family_id is distinct from old.family_id or new.image_slot is distinct from old.image_slot then
      raise exception 'coupon_image_slot_immutable';
    end if;
    return new;
  end if;

  -- Serialize allocation for the same group. The unique + range constraints
  -- are the final safeguard even with an older transaction snapshot.
  perform pg_advisory_xact_lock(hashtextextended(new.family_id::text, 87124));
  select slot into new.image_slot from generate_series(1, 100) as slot
  where not exists (select 1 from public.coupons c
    where c.family_id = new.family_id and c.image_slot = slot)
  order by slot limit 1;
  if new.image_slot is null then
    raise exception using errcode = 'P0001', message = 'coupon_limit_reached';
  end if;
  return new;
end $$;
revoke all on function public.assign_coupon_image_slot() from public;
create trigger coupons_image_slot_guard before insert or update of family_id, image_slot
  on public.coupons for each row execute function public.assign_coupon_image_slot();
commit;
