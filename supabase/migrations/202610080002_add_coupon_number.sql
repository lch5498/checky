alter table public.coupons
  add column coupon_number text not null default ''
  check (char_length(coupon_number) <= 128);
