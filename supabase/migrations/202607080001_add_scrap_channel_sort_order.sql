alter table public.scrap_channels
  add column if not exists sort_order integer;

update public.scrap_channels
set sort_order = ranked.row_number
from (
  select
    id,
    row_number() over (
      partition by family_id
      order by created_at desc
    ) as row_number
  from public.scrap_channels
  where sort_order is null
) ranked
where public.scrap_channels.id = ranked.id
  and public.scrap_channels.sort_order is null;

create index if not exists scrap_channels_family_id_sort_order_idx
  on public.scrap_channels (family_id, sort_order);
