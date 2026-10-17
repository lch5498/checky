create table public.coupon_expiry_deliveries (
  id uuid primary key default gen_random_uuid(),
  coupon_id uuid not null references public.coupons(id) on delete cascade,
  expires_on date not null,
  days_before integer not null check (days_before in (1, 7)),
  status text not null default 'processing'
    check (status in ('processing', 'sent', 'failed', 'no_targets')),
  token_count integer not null default 0,
  success_count integer not null default 0,
  failure_count integer not null default 0,
  error_summary jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (coupon_id, expires_on, days_before)
);

create index coupon_expiry_deliveries_coupon_id_idx
  on public.coupon_expiry_deliveries (coupon_id);

alter table public.coupon_expiry_deliveries enable row level security;

create trigger coupon_expiry_deliveries_set_updated_at
before update on public.coupon_expiry_deliveries
for each row execute function public.set_updated_at();
