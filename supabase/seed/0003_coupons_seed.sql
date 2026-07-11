-- The coupon book, moved out of Dart. Same two rules the mock carried, now
-- enforced by the database that also applies them.

insert into public.coupons (code, min_subtotal, flat_off, percent_off, max_off)
values
  ('WELCOME50', 199, 50, null, null),
  ('ZOPIQ20',   299, null, 20, 100)
on conflict (code) do nothing;
