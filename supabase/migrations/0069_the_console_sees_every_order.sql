-- ---------------------------------------------------------------------------
-- 0069 — the console sees every order, and can erase one.
-- ---------------------------------------------------------------------------
-- 0066 gave the console a *live board*: `admin_orders` with no argument returns
-- only what has not ended, because that screen answers "what is happening right
-- now". Searching by id or phone was the one way to reach a finished order, and
-- it needs the id or the number in hand.
--
-- This adds the other screen — the whole order book, narrowable by status, by
-- date, by restaurant, and by the same id/phone search — and a delete.
--
-- ===========================================================================
-- On the delete, plainly, because this one deserves the paragraph.
-- ===========================================================================
-- `admin_delete_order` **destroys the row, with no guard on its status.** That
-- is the deliberate, stated choice of the operator of this platform, made after
-- the consequences below were put in front of them. They are recorded here so
-- nobody rediscovers them by accident:
--
--   * **It cascades.** Seven foreign keys point at `orders` with `on delete
--     cascade` — `order_items` (and through it `order_item_options`),
--     `deliveries`, `delivery_codes`, `delivery_offers`, `order_messages`,
--     `order_route_jobs`, and `reviews`. Deleting an order silently deletes the
--     customer's review of it, which also means the restaurant's trigger-computed
--     rating (0062) no longer reflects a review that was counted into it until
--     something recomputes.
--
--   * **It destroys a tax document and leaves a hole where it was.** A delivered
--     order carries `invoice_no` (0063), issued off a per-restaurant,
--     per-financial-year counter. Deleting the order does *not* roll
--     `invoice_counters` back — it cannot, other invoices have been issued since.
--     So the series jumps: ZPQ/R1/2026-27/000041, then 000043. Under section 35
--     of the CGST Act a tax invoice is a record to be retained for 72 months, and
--     a gap in a consecutive series is exactly what an audit looks for.
--
--   * **It rewrites somebody's pay.** Rider earnings (0045) and restaurant
--     settlements are computed by joining `orders`; neither stores its own copy
--     of a delivered order. An order deleted after it was counted quietly reduces
--     a historical total that somebody has already been shown, and in some cases
--     already been paid against.
--
-- What this migration does *not* do is pretend none of that happened. Every
-- deletion writes a row to `admin_order_deletions` first — who, when, why, and a
-- jsonb copy of the order as it stood. That is not a guard and blocks nothing;
-- it is the only thing that will remain, and without it "where did ZPQ-1044 go"
-- has no answer at all.

-- ===========================================================================
-- A. The whole order book.
-- ===========================================================================
-- A separate function rather than more arguments on `admin_orders`, because the
-- two screens want opposite defaults and one function trying to be both would
-- have to read "no filters" as "live only", which is precisely the surprise
-- worth avoiding. `admin_orders` is untouched and the live board keeps working
-- byte-for-byte as it did.
--
-- Every filter is nullable and null means "don't narrow by this". Paged, because
-- unlike the live board this one grows without bound: `p_limit`/`p_offset` with
-- a hard ceiling so a client cannot ask for the table.
create or replace function public.admin_all_orders(
  p_query         text        default null,
  p_status        text        default null,
  p_restaurant_id text        default null,
  p_from          timestamptz default null,
  p_to            timestamptz default null,
  p_limit         integer     default 50,
  p_offset        integer     default 0
)
returns table (
  order_id          text,
  restaurant_id     text,
  restaurant_name   text,
  status            text,
  status_reason     text,
  placed_at         timestamptz,
  total             integer,
  payment_method    text,
  coupon_code       text,
  delivery_to       text,
  customer_phone    text,
  route_km          numeric,
  invoice_no        text,
  rider_name        text,
  rider_phone       text,
  delivery_state    text,
  item_count        integer,
  -- The count of everything matching the filters, repeated on every row. One
  -- round trip instead of two, and the pager needs it to know whether there is
  -- a next page at all.
  total_count       bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_q      text;
  v_digits text;
  v_limit  integer;
begin
  perform public.assert_admin();

  v_q := nullif(trim(coalesce(p_query, '')), '');
  -- Precomputed once. '' when the query is all letters, which is the guard 0066
  -- documents: an empty digit string in a `like '%' || ''` matches every row.
  v_digits := case when v_q is null then null
                   else nullif(regexp_replace(v_q, '[^0-9]', '', 'g'), '') end;
  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  with matched as (
    select
      o.id, o.restaurant_id, o.restaurant_name,
      o.status, o.status_reason, o.created_at,
      o.total, o.payment_method, o.coupon_code,
      o.delivery_to, o.user_phone, o.route_km, o.invoice_no,
      dp.name as rider_name, dp.phone as rider_phone, d.state as delivery_state,
      (select count(*)::integer from public.order_items oi where oi.order_id = o.id)
        as item_count
      from public.orders o
      left join public.deliveries d
             on d.order_id = o.id and d.state <> 'cancelled'
      left join public.delivery_partners dp on dp.email = d.partner_email
     where (p_status        is null or o.status = p_status)
       and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
       and (p_from          is null or o.created_at >= p_from)
       and (p_to            is null or o.created_at <  p_to)
       and (
         v_q is null
         or upper(o.id) = upper(v_q)
         or (v_digits is not null and o.user_phone like '%' || v_digits)
       )
  )
  select
    m.id, m.restaurant_id, m.restaurant_name,
    m.status, m.status_reason, m.created_at,
    m.total, m.payment_method, m.coupon_code,
    m.delivery_to, m.user_phone, m.route_km, m.invoice_no,
    m.rider_name, m.rider_phone, m.delivery_state, m.item_count,
    count(*) over () as total_count
  from matched m
  -- Newest first, unlike the live board's oldest-first. A history is read from
  -- the top; a worklist is worked from the bottom.
  order by m.created_at desc
  limit v_limit offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function public.admin_all_orders(
  text, text, text, timestamptz, timestamptz, integer, integer
) from public, anon, authenticated;
grant execute on function public.admin_all_orders(
  text, text, text, timestamptz, timestamptz, integer, integer
) to authenticated;

-- ===========================================================================
-- B. What remains after an order does not.
-- ===========================================================================
-- Written *before* the delete, in the same transaction, so a deletion that
-- succeeds cannot fail to be recorded and a record cannot survive a delete that
-- rolled back. `order_snapshot` is the whole row as jsonb — not a chosen subset,
-- because the column somebody will wish had been kept is always the one nobody
-- picked.
--
-- No foreign key to `orders`, obviously: the row it describes is about to stop
-- existing. `restaurant_id` is likewise a plain text copy and not a reference —
-- a deleted order's restaurant may itself be delisted later, and this record
-- should outlive that too.
create table if not exists public.admin_order_deletions (
  id              bigserial   primary key,
  order_id        text        not null,
  restaurant_id   text        not null,
  deleted_by      text        not null,
  deleted_at      timestamptz not null default now(),
  reason          text        not null default '',
  -- Kept flat as well as inside the snapshot, so "what did we delete that was
  -- already invoiced" is a query and not a jsonb excavation.
  order_status    text        not null,
  invoice_no      text,
  total           integer,
  order_snapshot  jsonb       not null
);

create index if not exists admin_order_deletions_when_idx
  on public.admin_order_deletions (deleted_at desc);

-- RLS on with no policy at all, and no grant: this table is readable only by
-- the functions below, which run as the definer. The same shape 0063 gave
-- `invoice_counters` — an audit trail the audited party can edit is decoration.
alter table public.admin_order_deletions enable row level security;
revoke all on public.admin_order_deletions from public, anon, authenticated;
revoke all on sequence public.admin_order_deletions_id_seq from public, anon, authenticated;

-- ===========================================================================
-- C. The delete.
-- ===========================================================================
-- No status check, no invoice check. See the paragraph at the top of this file
-- for what that means and for whose decision it was.
--
-- Returns a sentence naming what was destroyed, so the console can say something
-- specific afterwards rather than "done" — including the invoice number, which
-- is the one fact worth having said out loud at the moment it stops existing.
create or replace function public.admin_delete_order(
  p_order_id text,
  p_reason   text default ''
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order   public.orders%rowtype;
  v_items   integer;
  v_admin   text;
begin
  perform public.assert_admin();

  select * into v_order from public.orders where id = p_order_id;
  if not found then
    raise exception 'No order carries the id %.', p_order_id using errcode = 'P0001';
  end if;

  v_admin := coalesce(auth.jwt() ->> 'email', auth.uid()::text, 'unknown');
  select count(*)::integer into v_items
    from public.order_items where order_id = p_order_id;

  insert into public.admin_order_deletions (
    order_id, restaurant_id, deleted_by, reason,
    order_status, invoice_no, total, order_snapshot
  ) values (
    v_order.id, v_order.restaurant_id, v_admin,
    left(trim(coalesce(p_reason, '')), 200),
    v_order.status, v_order.invoice_no, v_order.total, to_jsonb(v_order)
  );

  -- The cascades do the rest: items and their options, the delivery, the codes,
  -- any offer, the messages, the route job, and the review.
  delete from public.orders where id = p_order_id;

  return case
    when v_order.invoice_no is not null then
      format(
        '%s is deleted — %s items, ₹%s, and tax invoice %s. The invoice series now has a gap.',
        v_order.id, v_items, v_order.total, v_order.invoice_no
      )
    else
      format('%s is deleted — %s items, ₹%s.', v_order.id, v_items, v_order.total)
  end;
end;
$$;

revoke all on function public.admin_delete_order(text, text)
  from public, anon, authenticated;
grant execute on function public.admin_delete_order(text, text) to authenticated;

-- ===========================================================================
-- D. Reading the trail back.
-- ===========================================================================
-- Because a record nobody can look at is not a record. The snapshot is
-- deliberately not returned — it can be large, and the console lists deletions
-- rather than reconstructing orders from them.
--
-- `admin_list_…` and not `admin_order_deletions`, which would be legal and would
-- read as a second meaning for the table's own name. The console's other list
-- functions are already `admin_list_coupons` / `_restaurants` / `_broadcasts`.
create or replace function public.admin_list_order_deletions(p_limit integer default 100)
returns table (
  order_id      text,
  restaurant_id text,
  deleted_by    text,
  deleted_at    timestamptz,
  reason        text,
  order_status  text,
  invoice_no    text,
  total         integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin();

  return query
    select d.order_id, d.restaurant_id, d.deleted_by, d.deleted_at,
           d.reason, d.order_status, d.invoice_no, d.total
      from public.admin_order_deletions d
     order by d.deleted_at desc
     limit least(greatest(coalesce(p_limit, 100), 1), 500);
end;
$$;

revoke all on function public.admin_list_order_deletions(integer)
  from public, anon, authenticated;
grant execute on function public.admin_list_order_deletions(integer) to authenticated;
