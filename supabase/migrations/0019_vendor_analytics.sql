-- Step, migration 19: what the day was made of, beyond the money.
--
-- Phase 6. Payments (0017) answers "how much did I earn"; this answers the
-- questions a kitchen asks around that number — *what* sold, and *when* the
-- rush came. Both are read-only reflections of orders already delivered, and
-- like the earnings summary they are computed on the way out, never stored, so
-- a restaurant sees the truth as of the moment it looks.
--
-- Same rule as every vendor read since 0009: scoped to `staff_restaurant_id()`,
-- a `security definer` function the vendor may call but whose figures it can
-- never write. There is nothing here a restaurant could edit to flatter itself.

-- ---------------------------------------------------------------------------
-- vendor_analytics: totals, the best-sellers, and the shape of the day.
-- ---------------------------------------------------------------------------
-- Over delivered orders in a date window:
--   * order_count / items_sold / avg_order_value — the headline three.
--   * top_dishes — the eight items that moved the most units, revenue breaking
--     ties, so "best-seller" is a fact about the till and not a guess.
--   * hourly    — order volume bucketed by hour of day, in India where the
--     kitchens are, so "we get slammed at 8pm" is a curve and not a hunch.
create or replace function public.vendor_analytics(
  p_from date,
  p_to   date
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_restaurant text;
  v_result     jsonb;
begin
  v_restaurant := public.staff_restaurant_id();
  if v_restaurant is null then
    raise exception 'You do not work at a restaurant on Zopiqnow.'
      using errcode = 'P0001';
  end if;

  with delivered as (
    select o.id, o.subtotal, o.created_at
    from public.orders o
    where o.restaurant_id = v_restaurant
      and o.status = 'delivered'
      and o.created_at::date between p_from and p_to
  ),
  items as (
    select oi.name, oi.quantity, oi.line_total
    from public.order_items oi
    join delivered d on d.id = oi.order_id
  ),
  top_dishes as (
    select
      i.name                     as name,
      sum(i.quantity)::integer   as qty,
      sum(i.line_total)::integer as revenue
    from items i
    group by i.name
    order by qty desc, revenue desc
    limit 8
  ),
  hourly as (
    select
      extract(hour from (d.created_at at time zone 'Asia/Kolkata'))::int as hour,
      count(*)::integer as orders
    from delivered d
    group by 1
  )
  select jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'order_count',     (select count(*) from delivered),
    'items_sold',      coalesce((select sum(quantity) from items), 0),
    'avg_order_value', coalesce((select round(avg(subtotal))::integer from delivered), 0),
    'top_dishes', coalesce(
      (select jsonb_agg(
                jsonb_build_object('name', name, 'qty', qty, 'revenue', revenue)
                order by qty desc, revenue desc
              )
       from top_dishes),
      '[]'::jsonb
    ),
    'hourly', coalesce(
      (select jsonb_agg(
                jsonb_build_object('hour', hour, 'orders', orders)
                order by hour
              )
       from hourly),
      '[]'::jsonb
    )
  ) into v_result;

  return v_result;
end;
$$;

grant execute on function public.vendor_analytics(date, date) to authenticated;
