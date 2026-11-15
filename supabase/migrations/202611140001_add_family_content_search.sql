-- Unified search across a group's schedules, coupons, scraps, travels and current parking spots.
-- Terms are matched with ILIKE (all terms must match). Patterns are escaped here so the
-- API only passes raw words. Member nicknames (schedule owner, scrap author) are searchable
-- too, so a member's name lists everything tied to them. Family scale: no index needed yet.
-- Rows come back in display order per type (display_order starts at 1). Schedules are anchored
-- to schedule_anchor (the caller's end of today): everything up to one month after it is shown
-- newest first, then farther-future schedules nearest first, so far-future entries do not
-- crowd the top. Recurring/anniversary occurrence picks use the anchor itself.
drop function if exists public.search_family_content(uuid, text[], integer, text[]);

create or replace function public.search_family_content(
  target_family_id uuid,
  search_terms text[],
  per_type_limit integer default 21,
  result_types text[] default null,
  schedule_anchor timestamptz default now()
)
returns table (
  result_type text,
  id uuid,
  display_order integer,
  occurred_at timestamptz,
  payload jsonb
)
language sql
stable
security invoker
set search_path = public
as $$
  with patterns as (
    select array_agg(
      '%' || replace(replace(replace(term, '\', '\\'), '%', '\%'), '_', '\_') || '%'
    ) as list
    from unnest(search_terms) as term
    where btrim(term) <> ''
  ),
  wanted as (
    select result_types is null as all_types, coalesce(result_types, '{}'::text[]) as list
  ),
  schedule_matches as (
    -- Recurring programs and anniversaries are stored as one row per occurrence. Rank the
    -- occurrences of each series around the anchor so only the nearest ones are shown.
    select
      s.id,
      s.title,
      s.content,
      s.starts_at,
      s.ends_at,
      s.is_all_day,
      s.created_at,
      s.education_program_id,
      s.anniversary_id,
      m.nickname as member_nickname,
      s.starts_at > schedule_anchor as is_future,
      s.starts_at > schedule_anchor + interval '1 month' as is_beyond_horizon,
      row_number() over (
        partition by s.education_program_id, (s.starts_at > schedule_anchor)
        order by
          case when s.starts_at > schedule_anchor then s.starts_at end asc,
          case when s.starts_at <= schedule_anchor then s.starts_at end desc,
          s.created_at desc
      ) as program_side_rank,
      row_number() over (
        partition by s.anniversary_id
        order by
          (s.starts_at > schedule_anchor),
          case when s.starts_at > schedule_anchor then s.starts_at end asc,
          case when s.starts_at <= schedule_anchor then s.starts_at end desc,
          s.created_at desc
      ) as anniversary_rank
    from public.schedules as s
    left join public.family_members as m on m.id = s.family_member_id
    cross join patterns, wanted
    where s.family_id = target_family_id
      and (wanted.all_types or 'schedule' = any (wanted.list))
      and (
        s.title || E'\n' || coalesce(s.content, '') || E'\n' || coalesce(m.nickname, '')
      ) ilike all (patterns.list)
  ),
  schedule_rows as (
    select
      'schedule'::text as result_type,
      s.id,
      (row_number() over (
        order by
          s.is_beyond_horizon,
          case when not s.is_beyond_horizon then s.starts_at end desc,
          case when s.is_beyond_horizon then s.starts_at end asc,
          s.created_at desc
      ))::integer as display_order,
      s.starts_at as occurred_at,
      jsonb_build_object(
        'id', s.id,
        'title', s.title,
        'content', s.content,
        'starts_at', s.starts_at,
        'ends_at', s.ends_at,
        'is_all_day', s.is_all_day,
        'member_nickname', s.member_nickname,
        'is_recurring', s.education_program_id is not null,
        'is_anniversary', s.anniversary_id is not null
      ) as payload
    from schedule_matches as s
    where
      -- one-off schedules: every match
      (s.education_program_id is null and s.anniversary_id is null)
      -- recurring programs: the latest past and the nearest future occurrence
      or (s.education_program_id is not null and s.program_side_rank = 1)
      -- anniversaries: the latest past occurrence, or the nearest future one if none passed
      or (s.anniversary_id is not null and s.anniversary_rank = 1)
    order by display_order
    limit per_type_limit
  ),
  coupon_rows as (
    select
      'coupon'::text as result_type,
      c.id,
      (row_number() over (order by c.created_at desc))::integer as display_order,
      c.created_at as occurred_at,
      to_jsonb(c) as payload
    from public.coupons as c
    cross join patterns, wanted
    where c.family_id = target_family_id
      and c.deleted_at is null
      and (wanted.all_types or 'coupon' = any (wanted.list))
      and (c.title || E'\n' || c.memo || E'\n' || c.coupon_number) ilike all (patterns.list)
    order by display_order
    limit per_type_limit
  ),
  scrap_post_rows as (
    select
      'scrap_post'::text as result_type,
      p.id,
      (row_number() over (order by p.created_at desc))::integer as display_order,
      p.created_at as occurred_at,
      jsonb_build_object(
        'id', p.id,
        'channel_id', p.channel_id,
        'channel_name', ch.name,
        'content', p.content,
        'link_url', p.link_url,
        'link_title', p.link_title,
        'link_description', p.link_description,
        'author_nickname', coalesce(m.nickname, '알 수 없음'),
        'created_at', p.created_at
      ) as payload
    from public.scrap_posts as p
    join public.scrap_channels as ch on ch.id = p.channel_id
    left join public.family_members as m
      on m.family_id = p.family_id and m.user_id = p.created_by_user_id
    cross join patterns, wanted
    where p.family_id = target_family_id
      and (wanted.all_types or 'scrap_post' = any (wanted.list))
      and (
        p.content || E'\n' || coalesce(p.link_title, '') || E'\n' || coalesce(p.link_description, '')
          || E'\n' || coalesce(m.nickname, '')
      ) ilike all (patterns.list)
    order by display_order
    limit per_type_limit
  ),
  scrap_comment_rows as (
    select
      'scrap_comment'::text as result_type,
      c.id,
      (row_number() over (order by c.created_at desc))::integer as display_order,
      c.created_at as occurred_at,
      jsonb_build_object(
        'id', c.id,
        'post_id', c.post_id,
        'channel_id', p.channel_id,
        'channel_name', ch.name,
        'content', c.content,
        'author_nickname', coalesce(m.nickname, '알 수 없음'),
        'created_at', c.created_at
      ) as payload
    from public.scrap_comments as c
    join public.scrap_posts as p on p.id = c.post_id
    join public.scrap_channels as ch on ch.id = p.channel_id
    left join public.family_members as m
      on m.family_id = c.family_id and m.user_id = c.created_by_user_id
    cross join patterns, wanted
    where c.family_id = target_family_id
      and (wanted.all_types or 'scrap_comment' = any (wanted.list))
      and (c.content || E'\n' || coalesce(m.nickname, '')) ilike all (patterns.list)
    order by display_order
    limit per_type_limit
  ),
  travel_trip_rows as (
    select
      'travel_trip'::text as result_type,
      t.id,
      (row_number() over (order by t.starts_on desc, t.created_at desc))::integer as display_order,
      t.created_at as occurred_at,
      to_jsonb(t) as payload
    from public.travel_trips as t
    cross join patterns, wanted
    where t.family_id = target_family_id
      and (wanted.all_types or 'travel_trip' = any (wanted.list))
      and t.title ilike all (patterns.list)
    order by display_order
    limit per_type_limit
  ),
  travel_itinerary_rows as (
    select
      'travel_itinerary'::text as result_type,
      i.id,
      (row_number() over (order by i.itinerary_date desc, i.sort_order desc))::integer as display_order,
      i.created_at as occurred_at,
      jsonb_build_object(
        'id', i.id,
        'trip_id', i.trip_id,
        'title', i.title,
        'content', i.content,
        'itinerary_date', i.itinerary_date,
        'starts_at', i.starts_at,
        'trip', to_jsonb(t)
      ) as payload
    from public.travel_itineraries as i
    join public.travel_trips as t on t.id = i.trip_id
    cross join patterns, wanted
    where i.family_id = target_family_id
      and (wanted.all_types or 'travel_itinerary' = any (wanted.list))
      and (i.title || E'\n' || coalesce(i.content, '')) ilike all (patterns.list)
    order by display_order
    limit per_type_limit
  ),
  parking_rows as (
    -- Only each vehicle's current location (its latest record) is searchable, by vehicle
    -- nickname, plate number or location. Older parking history is deliberately excluded.
    select
      'parking'::text as result_type,
      latest.id,
      (row_number() over (order by latest.parked_at desc, latest.created_at desc))::integer as display_order,
      latest.parked_at as occurred_at,
      jsonb_build_object(
        'id', latest.id,
        'vehicle_id', latest.vehicle_id,
        'vehicle_nickname', v.nickname,
        'plate_number', v.plate_number,
        'location_text', latest.location_text,
        'parked_at', latest.parked_at
      ) as payload
    from (
      select distinct on (r.vehicle_id) r.*
      from public.parking_records as r
      where r.family_id = target_family_id
      order by r.vehicle_id, r.parked_at desc, r.created_at desc
    ) as latest
    join public.vehicles as v on v.id = latest.vehicle_id
    cross join patterns, wanted
    where (wanted.all_types or 'parking' = any (wanted.list))
      and (v.nickname || E'\n' || v.plate_number || E'\n' || latest.location_text) ilike all (patterns.list)
    order by display_order
    limit per_type_limit
  )
  select * from schedule_rows
  union all select * from coupon_rows
  union all select * from scrap_post_rows
  union all select * from scrap_comment_rows
  union all select * from travel_trip_rows
  union all select * from travel_itinerary_rows
  union all select * from parking_rows;
$$;

-- PostgREST caches function signatures; ask it to reload after the signature change.
notify pgrst, 'reload schema';
