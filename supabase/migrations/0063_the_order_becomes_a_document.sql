-- ---------------------------------------------------------------------------
-- 0063 — the order becomes a document. (Phase B6, the digital invoice)
-- ---------------------------------------------------------------------------
-- An order screen is a *view* of a row. An invoice is a **document**: a thing
-- with a number that is never reused, issued once, which says the same thing in
-- a year as it says today. The difference matters because somebody claims this
-- against their expenses, and "whatever the orders table says right now" is not
-- an answer a finance team accepts.
--
-- Everything the document needs already exists and is already frozen. 0003 made
-- `order_items` carry the name and price *as charged* so a renamed dish cannot
-- rewrite a receipt; 0048 froze the chosen options beside them; 0005 froze the
-- restaurant's name onto the order. This migration adds the two things a row
-- has never had — **a number** and **the papers of the seller** — and one
-- function that assembles the whole thing in a single call.
--
-- **What it does not do: change a single figure.** Not one paisa moves. The tax
-- an order was charged is the tax the invoice states, split into its halves and
-- labelled. A migration that "corrects" the GST treatment of orders already
-- placed would be rewriting receipts, which is the exact thing the rest of this
-- schema has spent sixty migrations refusing to do.
--
-- **The number is issued on delivery, not on placement.** A tax invoice is
-- raised against a supply that happened. An order that gets cancelled or
-- rejected never becomes a document and never consumes a number — a gap in a
-- statutory series is a question somebody has to answer, so the series is only
-- ever advanced by a meal that arrived.
--
-- **One series per restaurant per financial year.** The supplier of the food is
-- the kitchen, not us, so the kitchen's series is the one that has to be
-- consecutive. A single platform-wide sequence would give one restaurant the
-- numbers 4, 19 and 3,004, which is not a series.

-- ===========================================================================
-- A. The counter.
-- ===========================================================================
-- A row per (restaurant, financial year), bumped by an atomic upsert. Not a
-- Postgres sequence: sequences are per-object (we would need one per restaurant
-- per year, created on the fly) and, more to the point, they do not roll back —
-- a failed transaction would burn a number and leave the gap this file exists
-- to avoid.
create table if not exists public.invoice_counters (
  restaurant_id text not null references public.restaurants (id) on delete cascade,
  fy            text not null,
  next_no       integer not null default 0 check (next_no >= 0),
  primary key (restaurant_id, fy)
);

alter table public.invoice_counters enable row level security;
revoke all on public.invoice_counters from public, anon, authenticated;

-- India's financial year runs April to March, so an order placed in March 2027
-- belongs to "2026-27" and one placed that April starts "2027-28". Written as a
-- function because two places need it — the issuer below and any later report —
-- and two copies of a date rule is one copy too many.
create or replace function public.financial_year(p_at timestamptz)
returns text
language sql
stable
as $$
  -- `stable`, not `immutable`: `timestamptz at time zone <name>` is itself only
  -- stable in Postgres (the zone database can be reloaded), and claiming more
  -- than the parts claim is how a function ends up wrong inside an index.
  select case
           when extract(month from p_at at time zone 'Asia/Kolkata') >= 4
             then to_char(p_at at time zone 'Asia/Kolkata', 'YYYY') || '-' ||
                  to_char((p_at at time zone 'Asia/Kolkata') + interval '1 year', 'YY')
           else to_char((p_at at time zone 'Asia/Kolkata') - interval '1 year', 'YYYY') || '-' ||
                to_char(p_at at time zone 'Asia/Kolkata', 'YY')
         end;
$$;

-- ===========================================================================
-- B. The number on the order.
-- ===========================================================================
alter table public.orders
  add column if not exists invoice_no   text,
  add column if not exists invoiced_at  timestamptz;

-- Unique across the platform, not merely within a restaurant: the restaurant id
-- is inside the string, so a collision would mean the counter handed the same
-- number twice, and that is a bug worth a constraint violation rather than a
-- duplicated document.
create unique index if not exists orders_invoice_no_key
  on public.orders (invoice_no) where invoice_no is not null;

-- ---------------------------------------------------------------------------
-- Issuing it.
-- ---------------------------------------------------------------------------
-- A trigger and not a step inside the rider's `complete_delivery`, because
-- there is more than one way an order reaches `delivered` (the rider's app
-- today; a support override tomorrow) and every one of them owes an invoice.
-- The rule is about the *state*, so it lives on the state change.
--
-- `invoice_no is null` guards re-entry: a row that somehow arrives at
-- `delivered` twice keeps the number it was already issued.
create or replace function public.orders_issue_invoice()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fy  text;
  v_no  integer;
begin
  if new.status <> 'delivered' or new.invoice_no is not null then
    return new;
  end if;

  v_fy := public.financial_year(now());

  insert into public.invoice_counters (restaurant_id, fy, next_no)
  values (new.restaurant_id, v_fy, 1)
  on conflict (restaurant_id, fy)
    do update set next_no = invoice_counters.next_no + 1
  returning next_no into v_no;

  -- `ZPQ/<restaurant>/<FY>/<n>` — the platform, the supplier, the year and a
  -- consecutive number. Padded to six digits so a year's invoices sort as text.
  new.invoice_no  := 'ZPQ/' || upper(new.restaurant_id) || '/' || v_fy || '/'
                     || lpad(v_no::text, 6, '0');
  new.invoiced_at := now();

  return new;
end;
$$;

drop trigger if exists orders_invoice_on_delivery on public.orders;
create trigger orders_invoice_on_delivery
  before update of status on public.orders
  for each row
  when (new.status = 'delivered' and old.status is distinct from 'delivered')
  execute function public.orders_issue_invoice();

-- Orders delivered before this file existed. Numbered in the order they were
-- delivered, so the series reads chronologically rather than by whatever order
-- an update happened to visit rows in. `invoiced_at` is set to `created_at` and
-- not to now(): backdating the document to the day of the supply is the honest
-- thing, and pretending a 2026 meal was invoiced today is not.
do $$
declare
  r record;
  v_fy text;
  v_no integer;
begin
  for r in
    select id, restaurant_id, created_at
      from public.orders
     where status = 'delivered' and invoice_no is null
     order by created_at
  loop
    v_fy := public.financial_year(r.created_at);

    insert into public.invoice_counters (restaurant_id, fy, next_no)
    values (r.restaurant_id, v_fy, 1)
    on conflict (restaurant_id, fy)
      do update set next_no = invoice_counters.next_no + 1
    returning next_no into v_no;

    update public.orders
       set invoice_no = 'ZPQ/' || upper(r.restaurant_id) || '/' || v_fy || '/'
                        || lpad(v_no::text, 6, '0'),
           invoiced_at = r.created_at
     where id = r.id;
  end loop;
end;
$$;

-- ===========================================================================
-- C. The document.
-- ===========================================================================
-- The GST rate this platform charges, as one fact. `place_order` has hard-coded
-- 5% since 0003 and this file does not touch that — but the *presentation* of
-- that 5% as two 2.5% halves has to agree with it exactly, so it reads the same
-- constant rather than a second copy that could drift.
create or replace function public.gst_rate_percent()
returns numeric language sql immutable as $$ select 5.0 $$;

-- The whole invoice in one jsonb, for one order, for the person who bought it.
--
-- **Security definer, and it reads `restaurant_legal`** — a table with RLS on
-- and no policy at all (0028), unreachable by vendor, customer or admin through
-- PostgREST. That is not a hole being punched: a GSTIN is printed on the face
-- of every tax invoice in the country, and a customer is entitled to the one
-- for their own purchase. The function hands out exactly two fields of that
-- table, for exactly one order, to exactly its buyer.
--
-- **The tax is stated on the basis it was charged on.** `orders.taxes` was
-- computed on the subtotal *before* the discount (0003, unchanged), so the
-- document shows the subtotal as the taxable value and the discount as a
-- deduction below it, rather than quietly implying a taxable value that would
-- not reproduce the tax printed next to it. The delivery fee carries no tax
-- here because none was charged on it — printing a notional 18% on a line
-- nobody paid tax on would make the document wrong in order to make it look
-- more complete.
create or replace function public.order_invoice(p_order_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user  text;
  v_o     public.orders;
  v_r     record;
  v_legal record;
  v_lines jsonb;
  v_cgst  integer;
  v_sgst  integer;
begin
  v_user := auth.uid()::text;
  if v_user is null then
    raise exception 'Please sign in to view this invoice.' using errcode = 'P0001';
  end if;

  select * into v_o from public.orders where id = p_order_id;
  if not found or v_o.user_id <> v_user then
    raise exception 'We couldn''t find that order.' using errcode = 'P0001';
  end if;

  if v_o.invoice_no is null then
    raise exception 'An invoice is issued once your order has been delivered.'
      using errcode = 'P0001';
  end if;

  select r.name, r.address_line, r.city, r.state, r.pincode, r.contact_phone
    into v_r
    from public.restaurants r
   where r.id = v_o.restaurant_id;

  select l.gst_number, l.fssai_number
    into v_legal
    from public.restaurant_legal l
   where l.restaurant_id = v_o.restaurant_id;

  -- The frozen lines, options and all, in the order they were bought.
  select coalesce(jsonb_agg(line order by line_id), '[]'::jsonb)
    into v_lines
    from (
      select oi.id as line_id,
             jsonb_build_object(
               'name',       oi.name,
               'options',    coalesce(
                               (select jsonb_agg(o.name order by o.id)
                                  from public.order_item_options o
                                 where o.order_item_id = oi.id),
                               '[]'::jsonb
                             ),
               'quantity',   oi.quantity,
               'unit_price', oi.unit_price,
               'line_total', oi.line_total
             ) as line
        from public.order_items oi
       where oi.order_id = p_order_id
    ) s;

  -- Halves that add back up. The rounding goes to CGST and SGST takes the
  -- remainder, so `cgst + sgst = taxes` for every odd figure too — an invoice
  -- whose parts do not sum to its total is a rejected invoice.
  v_cgst := round(v_o.taxes / 2.0);
  v_sgst := v_o.taxes - v_cgst;

  return jsonb_build_object(
    'invoice_no',     v_o.invoice_no,
    'invoiced_at',    v_o.invoiced_at,
    'order_id',       v_o.id,
    'placed_at',      v_o.created_at,

    'seller', jsonb_build_object(
      'name',    v_o.restaurant_name,
      'address', nullif(concat_ws(', ',
                   nullif(v_r.address_line, ''), nullif(v_r.city, ''),
                   nullif(v_r.state, ''),        nullif(v_r.pincode, '')
                 ), ''),
      'phone',   v_r.contact_phone,
      'gstin',   v_legal.gst_number,
      'fssai',   v_legal.fssai_number
    ),

    'buyer', jsonb_build_object(
      'phone',   v_o.user_phone,
      'address', v_o.delivery_to
    ),

    -- Printed on every invoice, and here it is the state the food was delivered
    -- in — which for an intra-state supply is also the seller's. Null on a
    -- restaurant an admin has not finished, and the document simply omits the
    -- line rather than guessing.
    'place_of_supply', nullif(v_r.state, ''),

    'lines',          v_lines,

    'taxable_value',  v_o.subtotal,
    'discount',       v_o.discount,
    'coupon_code',    v_o.coupon_code,
    'delivery_fee',   v_o.delivery_fee,
    'gst_rate',       public.gst_rate_percent(),
    'cgst',           v_cgst,
    'sgst',           v_sgst,
    'taxes',          v_o.taxes,
    'total',          v_o.total,

    'payment_method', v_o.payment_method,
    'payment_id',     v_o.payment_id
  );
end;
$$;

grant execute on function public.order_invoice(text) to authenticated;
