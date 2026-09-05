-- ---------------------------------------------------------------------------
-- 0154 — one order, on one page.
-- ---------------------------------------------------------------------------
-- An admin answering "what happened to ZPQ-1188?" opens the live board for the
-- order's own facts, All orders for the ones that have ended, Support for the
-- photos, and Refunds for the money — and after all four still cannot see the
-- conversation between the rider and the customer, whether the payment was ever
-- verified, or which admin cancelled it.
--
-- Every one of those facts is already in this database. None of them is reachable
-- together. This function is the join.
--
-- ## Shape
--
-- One `jsonb`, following `admin_get_restaurant` (0030) rather than the
-- table-returning style of `admin_orders` — the answer here is a tree with six
-- lists hanging off it, and six round trips to draw one page is six chances for
-- the page to show a half-consistent order.
--
-- ## What it deliberately does not return
--
-- **The handover codes.** `delivery_codes` holds the pickup code the vendor
-- reads out and the delivery code the customer reads out (0049). The whole point
-- of them is that the person confirming a handover cannot be the person
-- performing it. An admin who can read the codes can close a handover that never
-- happened, from a desk, and the audit trail would show a clean delivery. So this
-- returns the *attempt counts* and nothing else: "the rider has typed the pickup
-- code wrong four times" is the diagnostic support actually needs, and it does
-- not hand anybody the code.
--
-- **A full account number, anywhere.** Nothing here touches a bank table.
--
-- ## The timeline, and the honest gap in it
--
-- There is no status-transition log in this schema — `orders.status` is updated
-- in place, so a delivered order does not remember when it was accepted. What
-- this function returns are the transition timestamps that *are* stored, each as
-- itself and never as a guess:
--
--   * `created_at` — placed.
--   * `accept_deadline` — the promise the kitchen was held to (0058).
--   * `ready_by` — written **when the kitchen accepted**, as accept-time plus the
--     prep minutes it chose (0015). It is therefore evidence that an accept
--     happened and roughly when, and it is *not* an `accepted_at`; the console
--     labels it as what it is.
--   * `ready_at`, `dispatch_started_at`, `invoiced_at` — real events, real times.
--   * the delivery's five milestones, which are the best-recorded part of the
--     whole order (0056, 8g).
--
-- A true per-transition log with an actor on each row would be a trigger on the
-- busiest table in the system, and is a decision of its own rather than a detail
-- of this one. Not built here. Where an *admin* moved the order — a support
-- cancel, a release, a delete — `admin_actions` has the actor and the time
-- already, and this function returns those rows.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- An audit row's `detail`, reduced to what actually changed.
-- ---------------------------------------------------------------------------
-- 0092's triggers write `{before: <whole row>, after: <whole row>}`. That is the
-- right thing to store — a dispute is answered by the whole row, not by the
-- fields somebody thought to record — and the wrong thing to send to a browser
-- drawing a timeline. One refund moving `approved -> processing -> paid` carries
-- four complete copies of the same nineteen-column row, of which six values
-- differ.
--
-- So the trail keeps everything and the page is told what changed:
-- `{status: {from: 'approved', to: 'processing'}}`. Anything that is not a
-- before/after pair — an insert's payload, a delete's snapshot — is passed
-- through untouched, because for those the whole thing *is* the change.
create or replace function public.audit_detail_changes(p_detail jsonb)
returns jsonb
language sql
immutable
as $fn$
  select case
    when p_detail ? 'before' and p_detail ? 'after' then
      coalesce((
        select jsonb_object_agg(k, jsonb_build_object(
                 'from', p_detail -> 'before' -> k,
                 'to',   p_detail -> 'after'  -> k))
          from jsonb_object_keys(
                 (p_detail -> 'before') || (p_detail -> 'after')) k
         -- `is distinct from` rather than `<>`, so a column going null -> value
         -- counts as a change instead of vanishing from the list.
         where (p_detail -> 'before' -> k) is distinct from (p_detail -> 'after' -> k)
      ), '{}'::jsonb)
    else p_detail
  end;
$fn$;

comment on function public.audit_detail_changes(jsonb) is
  '0154: an admin_actions detail reduced to its changed fields, as {col: {from, to}}. Anything that is not a before/after pair passes through.';

revoke all on function public.audit_detail_changes(jsonb) from public, anon, authenticated;

create or replace function public.admin_order_detail(p_order_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_order   public.orders%rowtype;
  v_deleted public.admin_order_deletions%rowtype;
  v_result  jsonb;
begin
  perform public.assert_admin();

  -- Case-folded, because an admin pasting an id out of a WhatsApp message gets
  -- whatever case that message had. `admin_orders` already matches this way.
  select * into v_order
    from public.orders o
   where upper(o.id) = upper(trim(p_order_id));

  if v_order.id is null then
    -- An order deleted from All orders (0069) leaves a row here and nothing
    -- else. Its id survives in a customer's inbox, in a settlement and in a
    -- WhatsApp confirmation, so somebody will look one up after it is gone —
    -- and "No such order" would be the wrong answer to that. Say who removed it.
    select * into v_deleted
      from public.admin_order_deletions dl
     where upper(dl.order_id) = upper(trim(p_order_id));

    if v_deleted.order_id is not null then
      raise exception 'Order % was deleted by % on %. Reason given: %',
        v_deleted.order_id,
        v_deleted.deleted_by,
        to_char(v_deleted.deleted_at, 'DD Mon YYYY'),
        coalesce(nullif(trim(v_deleted.reason), ''), 'none')
        using errcode = 'P0001';
    end if;

    raise exception 'No such order.' using errcode = 'P0001';
  end if;

  select jsonb_build_object(
    'order', to_jsonb(v_order)
               -- Two 4 kB-ish encoded polylines that only a map can read, and
               -- there is no map on this page. Dropped so the payload stays a
               -- page's worth of facts rather than a route.
               - 'route_polyline' - 'live_polyline',

    'restaurant', (
      select jsonb_build_object(
               'id', r.id,
               'name', r.name,
               'phone', r.contact_phone,
               'owner_name', r.owner_name,
               'address_line', r.address_line,
               'city', r.city,
               'latitude', r.latitude,
               'longitude', r.longitude,
               'accepting_orders', r.accepting_orders,
               'is_active', r.is_active)
        from public.restaurants r
       where r.id = v_order.restaurant_id
    ),

    -- The customer as `auth.users` knows them. `orders.user_id` is a uuid held
    -- as text, so the cast is on this side of the comparison; a bad uuid in that
    -- column would raise, and one has never been written by anything but
    -- `place_order`.
    'customer', (
      select jsonb_build_object(
               'user_id', u.id,
               'email', lower(u.email),
               'name', coalesce(
                         nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
                         nullif(trim(u.raw_user_meta_data ->> 'name'), '')),
               'phone', coalesce(nullif(u.phone, ''), v_order.user_phone),
               'is_blocked', (u.banned_until is not null and u.banned_until > now()),
               'created_at', u.created_at,
               -- Not "how many orders" — how many *before this one*. An order
               -- placed by somebody on their first night is a different
               -- conversation from one placed by somebody on their fortieth.
               'orders_before', (
                 select count(*) from public.orders p
                  where p.user_id = u.id::text and p.created_at < v_order.created_at))
        from auth.users u
       where u.id = v_order.user_id::uuid
    ),

    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'name', i.name,
               'menu_item_id', i.menu_item_id,
               'unit_price', i.unit_price,
               'quantity', i.quantity,
               'line_total', i.line_total,
               'gst_rate_bps', i.gst_rate_bps,
               'hsn_code', i.hsn_code,
               'discount_alloc', i.discount_alloc,
               'taxable_value', i.taxable_value,
               'tax_amount', i.tax_amount,
               -- The sizes and add-ons this line was ordered with (0048). Empty
               -- for a dish that asks no questions, which is most of them.
               'options', coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'name', op.name, 'price_delta', op.price_delta)
                        order by op.id)
                   from public.order_item_options op
                  where op.order_item_id = i.id), '[]'::jsonb))
             order by i.id)
        from public.order_items i
       where i.order_id = v_order.id), '[]'::jsonb),

    -- The live delivery. Same `state <> 'cancelled'` predicate as the partial
    -- unique index behind it, so this matches at most one row by construction.
    'delivery', (
      select jsonb_build_object(
               'partner_email', d.partner_email,
               'rider_name', dp.name,
               'rider_phone', dp.phone,
               'rider_vehicle', dp.vehicle,
               'rider_engagement', dp.engagement,
               'state', d.state,
               'claimed_at', d.claimed_at,
               'arrived_at_restaurant_at', d.arrived_at_restaurant_at,
               'picked_up_at', d.picked_up_at,
               'arrived_at_customer_at', d.arrived_at_customer_at,
               'delivered_at', d.delivered_at,
               'distance_km', d.distance_km,
               'pay_base', d.pay_base,
               'pay_per_km', d.pay_per_km,
               'rider_pay', d.rider_pay,
               'payout_id', d.payout_id)
        from public.deliveries d
        left join public.delivery_partners dp on dp.email = d.partner_email
       where d.order_id = v_order.id and d.state <> 'cancelled'
    ),

    -- Every ring this order made, in the order it made them (0148's relay). This
    -- is the answer to "why did nobody come" — five rows all `expired` says the
    -- fleet was asleep, one `declined` and then nothing says the relay ran out.
    'offers', coalesce((
      select jsonb_agg(jsonb_build_object(
               'partner_email', f.partner_email,
               'rider_name', dp.name,
               'state', f.state,
               'offered_at', f.offered_at,
               'expires_at', f.expires_at,
               'responded_at', f.responded_at,
               'distance_km', f.distance_km,
               'ride_km', f.ride_km,
               'rider_pay', f.rider_pay)
             order by f.offered_at)
        from public.delivery_offers f
        left join public.delivery_partners dp on dp.email = f.partner_email
       where f.order_id = v_order.id), '[]'::jsonb),

    -- Attempts only. See the header: the codes themselves are not an admin's to
    -- read, and support has never needed them — it needs to know somebody is
    -- failing to type one.
    'handover', (
      select jsonb_build_object(
               'pickup_attempts', c.pickup_attempts,
               'delivery_attempts', c.delivery_attempts,
               'updated_at', c.updated_at)
        from public.delivery_codes c
       where c.order_id = v_order.id
    ),

    -- The gateway's side of the money (0085). `verified_at` null on a `upi`
    -- order is the single most important field on this page: it means the
    -- kitchen cooked against a payment nobody proved.
    'payment', (
      select jsonb_build_object(
               'razorpay_order_id', pi.razorpay_order_id,
               'razorpay_payment_id', pi.razorpay_payment_id,
               'amount', pi.amount,
               'status', pi.status,
               'instrument', pi.instrument,
               'created_at', pi.created_at,
               'verified_at', pi.verified_at,
               'consumed_at', pi.consumed_at)
        from public.payment_intents pi
       where pi.order_id = v_order.id
       order by pi.created_at desc
       limit 1
    ),

    'refunds', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', rf.id,
               'amount', rf.amount,
               'reason', rf.reason,
               'status', rf.status,
               'funded_by', rf.funded_by,
               'requested_by', rf.requested_by,
               'approved_by', rf.approved_by,
               'expected_by', rf.expected_by,
               'gateway_refund_id', rf.gateway_refund_id,
               'failure_reason', rf.failure_reason,
               'created_at', rf.created_at,
               'approved_at', rf.approved_at,
               'paid_at', rf.paid_at)
             order by rf.created_at)
        from public.refunds rf
       where rf.order_id = v_order.id), '[]'::jsonb),

    -- The conversation (0061). Canned on both sides, which is why it is safe to
    -- show here: there is no free text a customer could have typed into it.
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object(
               'sender', m.sender,
               'code', m.code,
               'body', m.body,
               'created_at', m.created_at,
               'read_at', m.read_at)
             order by m.created_at)
        from public.order_messages m
       where m.order_id = v_order.id), '[]'::jsonb),

    'photos', jsonb_build_object(
      'cooked', v_order.cooked_photo_url,
      'packed', v_order.packed_photo_url,
      'delivery', v_order.delivery_photo_url),

    'review', (
      select jsonb_build_object(
               'food_rating', rv.food_rating,
               'rider_rating', rv.rider_rating,
               'comment', rv.comment,
               'created_at', rv.created_at)
        from public.reviews rv
       where rv.order_id = v_order.id
    ),

    'tickets', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', t.id,
               'category', t.category,
               'body', t.body,
               'status', t.status,
               'created_at', t.created_at,
               'resolved_at', t.resolved_at,
               'resolved_by', t.resolved_by,
               'admin_note', t.admin_note)
             order by t.created_at)
        from public.support_tickets t
       where t.order_id = v_order.id), '[]'::jsonb),

    -- What an admin did to this order, from the append-only trail (0092). The
    -- refund rows are keyed by refund id rather than order id, so they are
    -- picked up through the refunds this order owns — otherwise "who approved
    -- the ₹300 back" would be the one action about this order that its own page
    -- could not show.
    'admin_actions', coalesce((
      select jsonb_agg(jsonb_build_object(
               'actor_email', a.actor_email,
               'action', a.action,
               'target_type', a.target_type,
               'detail', public.audit_detail_changes(a.detail),
               'created_at', a.created_at)
             order by a.created_at)
        from public.admin_actions a
       where (a.target_type = 'orders' and a.target_id = v_order.id)
          or (a.target_type = 'refunds' and a.target_id in (
                select rf.id::text from public.refunds rf
                 where rf.order_id = v_order.id))), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$fn$;

comment on function public.admin_order_detail(text) is
  '0154: every stored fact about one order, as one object — items, delivery, offers, payment, refunds, messages, photos, review, tickets and the admin actions taken on it. Returns handover attempt counts, never the codes.';

-- Born executable by PUBLIC *and* with a default grant to `authenticated`
-- (see 0093). Shut both routes, then reopen the one the console signs in on;
-- `assert_admin()` is what actually decides.
revoke all on function public.admin_order_detail(text) from public, anon, authenticated;
grant execute on function public.admin_order_detail(text) to authenticated;
