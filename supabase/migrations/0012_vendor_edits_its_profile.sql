-- Step 10, migration 12: a restaurant edits its own storefront.
--
-- The vendor already owns two writes to their own restaurant: the open/closed
-- switch (0011) and, through the menu policies (0010), their dishes. This adds
-- the third — the restaurant's public face on the customer app: its name, its
-- cuisines, what it costs, whether it's pure-veg, its offer line, its prep time.
--
-- Same shape as every vendor write before it, and the shape is the whole point.
-- There is no `update` grant on `restaurants` for a vendor, because RLS chooses
-- *rows*, not *columns*, and an update policy that lets a kitchen set `name` is
-- one widened `using` clause away from letting it set `rating` (which is earned,
-- not typed) or `is_active` (which is ops delisting them, not theirs to flip).
-- So the write is a function that can reach exactly six columns and no others.

create or replace function public.update_restaurant_profile(
  p_name          text,
  p_cuisines      text[],
  p_price_for_two integer,
  p_is_veg        boolean,
  p_promo_text    text,
  p_eta_minutes   integer
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant text;
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null then
    raise exception 'You do not work at a restaurant on Zopiqnow.'
      using errcode = 'P0001';
  end if;

  -- Validated here so the vendor gets a sentence, not a check-constraint dump.
  -- The table's own checks (`price_for_two > 0`, `eta_minutes > 0`) are still the
  -- guard behind these — a check the client can read is a check, not a guard.
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'Your restaurant needs a name.' using errcode = 'P0001';
  end if;
  if p_price_for_two is null or p_price_for_two <= 0 then
    raise exception 'The cost for two has to be more than zero.'
      using errcode = 'P0001';
  end if;
  if p_eta_minutes is null or p_eta_minutes <= 0 then
    raise exception 'The prep time has to be more than zero minutes.'
      using errcode = 'P0001';
  end if;

  update public.restaurants
     set name          = trim(p_name),
         cuisines      = coalesce(p_cuisines, '{}'),
         price_for_two = p_price_for_two,
         is_veg        = coalesce(p_is_veg, false),
         -- An empty offer line is *no* offer, not an empty badge on the card.
         promo_text    = nullif(trim(coalesce(p_promo_text, '')), ''),
         eta_minutes   = p_eta_minutes
   where id = v_restaurant;

  -- `restaurants_set_search_text` (0001) fires on this update because it touches
  -- `name` and `cuisines`, so the search index the customer app queries stays in
  -- step without a line here to remember it.
end;
$$;

grant execute on function public.update_restaurant_profile(
  text, text[], integer, boolean, text, integer
) to authenticated;
