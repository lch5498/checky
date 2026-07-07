create table if not exists public.scrap_channels (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  name text not null,
  sort_order integer,
  created_by_user_id uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scrap_channels_name_check check (
    char_length(btrim(name)) between 1 and 60
  )
);

create table if not exists public.scrap_posts (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  channel_id uuid not null references public.scrap_channels(id) on delete cascade,
  content text not null,
  link_url text,
  link_title text,
  link_description text,
  link_image_url text,
  link_site_name text,
  created_by_user_id uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scrap_posts_content_check check (
    char_length(btrim(content)) between 1 and 2000
  )
);

create table if not exists public.scrap_comments (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  post_id uuid not null references public.scrap_posts(id) on delete cascade,
  content text not null,
  created_by_user_id uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scrap_comments_content_check check (
    char_length(btrim(content)) between 1 and 1000
  )
);

create index if not exists scrap_channels_family_id_created_at_idx
  on public.scrap_channels (family_id, created_at desc);

create index if not exists scrap_channels_family_id_sort_order_idx
  on public.scrap_channels (family_id, sort_order);

create index if not exists scrap_posts_channel_id_created_at_idx
  on public.scrap_posts (channel_id, created_at desc);

create index if not exists scrap_comments_post_id_created_at_idx
  on public.scrap_comments (post_id, created_at asc);

alter table public.scrap_channels enable row level security;
alter table public.scrap_posts enable row level security;
alter table public.scrap_comments enable row level security;

drop trigger if exists scrap_channels_set_updated_at on public.scrap_channels;
create trigger scrap_channels_set_updated_at
before update on public.scrap_channels
for each row execute function public.set_updated_at();

drop trigger if exists scrap_posts_set_updated_at on public.scrap_posts;
create trigger scrap_posts_set_updated_at
before update on public.scrap_posts
for each row execute function public.set_updated_at();

drop trigger if exists scrap_comments_set_updated_at on public.scrap_comments;
create trigger scrap_comments_set_updated_at
before update on public.scrap_comments
for each row execute function public.set_updated_at();
