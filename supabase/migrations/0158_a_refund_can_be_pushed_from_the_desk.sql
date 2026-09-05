-- ---------------------------------------------------------------------------
-- 0158 — a refund can be pushed from the desk.
-- ---------------------------------------------------------------------------
-- 0138 wired Razorpay to the refund queue and it works: of the four refunds on
-- this platform against a real capture, three paid themselves without anybody
-- touching them. The console does not know that. Its own header still says
--
--     **This page does not move money.** No gateway is wired in yet (PAY-001)
--
-- which stopped being true three months ago, and nothing on the screen tells an
-- admin that approving a refund will send it. So the one thing the page is sure
-- of is wrong, and the useful thing it could say it does not say.
--
-- What is actually missing is smaller than a gateway: **a way to say "now"**.
-- `pay_approved_refunds` runs every five minutes, which is the right cadence for
-- a queue and the wrong one for a person on the phone to a customer who wants to
-- know their money is on its way.
--
-- ## Why this is two steps and not one
--
-- `net.http_post` does not send anything. It queues a row, and pg_net's worker
-- dispatches it **after the calling transaction commits** — so a function cannot
-- fire a request and read its answer, however long it waits. `http_collect_response`
-- with `async := false` would block forever inside the transaction that queued
-- the request.
--
-- That is why the cron does it across two ticks, and why this does it across two
-- calls: the console fires, waits a moment, and asks again. The same shape, at a
-- pace a person set instead of a schedule.
--
-- ## Why the cron is rewritten
--
-- To keep one definition of how a refund is sent. `admin_push_refund` needs
-- exactly what `pay_approved_refunds` already does, and the copy-and-adjust
-- version of that is two functions that agree today and drift the first time
-- either is touched — a refund sent with different arguments depending on who
-- was in a hurry. So the fire half and the collect half come out as their own
-- functions, and both callers use them.
--
-- `pay_approved_refunds` keeps its name, its signature, its batch ceiling, its
-- `for update skip locked` and its collect-before-fire order. What it loses is
-- the sixty lines it now shares.
--
-- ## What is unchanged, deliberately
--
-- A `pay_mock_…` payment id is still never sent. Nineteen refunds worth ₹4,660
-- carry one: they predate payments, no money was ever taken, and there is
-- nothing at Razorpay to send back. They stay `approved` until a person settles
-- them with "Mark sent", which is a decision and not a loop's to make. The
-- console now says so on the row rather than leaving them looking stuck.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Fire one refund at Razorpay.
-- ---------------------------------------------------------------------------
-- The caller holds the row lock and has already decided this refund should go.
-- Raises rather than returns a code: every caller treats a refund it cannot send
-- as a failure to report, and there is no third answer.
create or replace function public.refund_fire(p_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  r            record;
  v_key_id     text;
  v_key_secret text;
  v_request    bigint;
begin
  select id, order_id, amount, payment_id into r
    from public.refunds where id = p_id;

  select decrypted_secret into v_key_id
    from vault.decrypted_secrets where name = 'razorpay_key_id';
  select decrypted_secret into v_key_secret
    from vault.decrypted_secrets where name = 'razorpay_key_secret';

  if v_key_id is null or v_key_secret is null then
    raise exception 'Razorpay is not configured on this database.'
      using errcode = 'P0001';
  end if;

  -- Claimed before the call is fired, in this transaction, so a cron tick that
  -- overlaps cannot read the row as `approved` and send it twice.
  update public.refunds set status = 'processing' where id = p_id;

  select net.http_post(
    url     := 'https://api.razorpay.com/v1/payments/' || r.payment_id || '/refund',
    headers := jsonb_build_object(
      'Authorization',
      'Basic ' || encode(convert_to(v_key_id || ':' || v_key_secret, 'utf8'), 'base64'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      -- Paise. Every money column in this schema is whole rupees and Razorpay
      -- takes nothing else; the conversion happens here and nowhere else.
      'amount', r.amount * 100,
      -- 'normal' settles through the customer's bank in the usual few days.
      -- 'optimum' costs a fee to be faster and is not worth it for a refund the
      -- customer has already been told is coming.
      'speed', 'normal',
      'receipt', 'zpq_rfnd_' || r.id,
      'notes', jsonb_build_object(
        'refund_id', r.id::text,
        'order_id',  r.order_id
      )
    )
  ) into v_request;

  update public.refunds
     set gateway_request_id = v_request,
         gateway_sent_at    = now()
   where id = p_id;
end;
$fn$;

comment on function public.refund_fire(bigint) is
  '0158: sends one approved refund to Razorpay and marks it processing. The single definition of how a refund is sent — used by the cron and by the console.';

revoke all on function public.refund_fire(bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Read Razorpay's answer, if it has arrived.
-- ---------------------------------------------------------------------------
-- Returns the sentence describing what happened, or **null** while the request
-- is still in flight. Null is not an error: pg_net's worker is asynchronous and
-- "not yet" is the normal answer for the first second or two.
create or replace function public.refund_collect(p_id bigint)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  r           record;
  v_status    integer;
  v_content   text;
  v_json      jsonb;
  v_refund_id text;
  v_reason    text;
  v_user      text;
begin
  select id, order_id, amount, gateway_request_id into r
    from public.refunds where id = p_id;

  if r.gateway_request_id is null then
    return null;
  end if;

  select status_code, content into v_status, v_content
    from net._http_response
   where id = r.gateway_request_id;

  -- Still in flight, or the response was pruned before anybody read it. Neither
  -- is retried here — a second call to Razorpay for money that may already have
  -- moved is the one mistake this whole path exists to avoid.
  if not found then
    return null;
  end if;

  -- A body is not guaranteed to be JSON: a proxy between here and Razorpay
  -- answers in HTML, and `::jsonb` on that would raise while holding a lock on
  -- somebody's money.
  begin
    v_json := v_content::jsonb;
  exception when others then
    v_json := null;
  end;

  if v_status = 200 then
    v_refund_id := nullif(trim(coalesce(v_json ->> 'id', '')), '');

    -- A 200 with no refund id is not something to guess about: Razorpay accepted
    -- something and we cannot name it. `refund_paid_has_a_reference` would
    -- refuse the update anyway, so say so and leave it for a person.
    if v_refund_id is null then
      update public.refunds set gateway_request_id = null where id = p_id;
      return 'Razorpay accepted it but did not return a reference. Left with the gateway for somebody to check by hand.';
    end if;

    update public.refunds
       set status             = 'paid',
           gateway_refund_id  = v_refund_id,
           paid_at            = now(),
           gateway_request_id = null
     where id = p_id;

    -- The sentence the customer gets is the one `admin_mark_refund_paid` already
    -- sends, because from their side nothing about this is different. Wrapped
    -- whole: a courtesy is never the reason a refund fails to record.
    begin
      select o.user_id into v_user from public.orders o where o.id = r.order_id;

      insert into public.notifications
        (audience, user_id, kind, title, body, order_id)
      values (
        'customer', v_user, 'refund', 'Refund sent',
        '₹' || r.amount || ' for order ' || r.order_id ||
          ' has been sent back to your original payment method.',
        r.order_id
      );
    exception when others then
      null;
    end;

    return 'Razorpay paid it. Reference ' || v_refund_id || '.';
  end if;

  -- Razorpay's own description is the most useful thing a person can be given
  -- here — 'the payment has been fully refunded already' and 'this payment was
  -- never captured' need completely different answers.
  v_reason := nullif(trim(coalesce(v_json #>> '{error,description}', '')), '');

  update public.refunds
     set status             = 'failed',
         failure_reason     = coalesce(
           v_reason,
           'Razorpay refused the refund (HTTP ' || coalesce(v_status::text, '?') || ').'
         ),
         gateway_request_id = null
   where id = p_id;

  return 'Razorpay refused it: ' || coalesce(v_reason, 'HTTP ' || coalesce(v_status::text, '?')) || '.';
end;
$fn$;

comment on function public.refund_collect(bigint) is
  '0158: reads Razorpay''s answer for one refund and settles it paid or failed. Returns null while the request is still in flight.';

revoke all on function public.refund_collect(bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The cron, now sharing those two.
-- ---------------------------------------------------------------------------
-- Same name, same signature, same batch ceiling, same `for update skip locked`,
-- same collect-before-fire order — so a finished refund leaves `processing` on
-- the tick it finished rather than the one after.
create or replace function public.pay_approved_refunds()
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  -- Per tick. Well above any plausible backlog, and a ceiling means a bug that
  -- floods `refunds` cannot become a thousand Razorpay calls in one minute.
  v_batch constant integer := 20;
  r       record;
begin
  for r in
    select id from public.refunds
     where status = 'processing' and gateway_request_id is not null
     for update skip locked
  loop
    perform public.refund_collect(r.id);
  end loop;

  -- Nothing below runs without both keys, and `refund_fire` raises rather than
  -- returning when they are missing — so the check stays here, where a missing
  -- key means "do nothing quietly" rather than "fail a person's button".
  if not exists (
    select 1 from vault.decrypted_secrets where name = 'razorpay_key_id'
  ) or not exists (
    select 1 from vault.decrypted_secrets where name = 'razorpay_key_secret'
  ) then
    return;
  end if;

  for r in
    select id from public.refunds
     where status = 'approved'
       -- A real Razorpay capture and nothing else. `pay_mock_…` is every refund
       -- raised before payments existed: no money was taken, so none goes back.
       -- Those are a person's decision, not this loop's.
       and payment_id like 'pay\_%'
       and payment_id not like 'pay\_mock\_%'
     order by created_at
     limit v_batch
     for update skip locked
  loop
    perform public.refund_fire(r.id);
  end loop;
end;
$fn$;

comment on function public.pay_approved_refunds() is
  '0138, rebuilt on 0158''s two halves: collects every answer Razorpay has returned, then sends the next batch of approved refunds. Every five minutes.';

revoke all on function public.pay_approved_refunds() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The button.
-- ---------------------------------------------------------------------------
-- One RPC for both halves, because from the desk it is one intent — "deal with
-- this refund now" — and which half runs depends only on where the refund
-- already is. The console calls it, waits a couple of seconds, and calls it
-- again; the first call fires and the second reports.
--
-- Every refusal below is a sentence rather than a silence, because this button
-- is pressed with a customer waiting and "nothing happened" is the worst
-- possible answer.
create or replace function public.admin_push_refund(p_id bigint)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  r        record;
  v_said   text;
begin
  perform public.assert_admin();

  select * into r from public.refunds where id = p_id for update;

  if r.id is null then
    raise exception 'No such refund.' using errcode = 'P0001';
  end if;

  -- Already settled. Said plainly rather than treated as an error: pressing it
  -- twice is what a person does when they are not sure the first press landed.
  if r.status = 'paid' then
    return 'Already paid — reference ' || coalesce(r.gateway_refund_id, '—') || '.';
  end if;

  if r.status in ('requested', 'declined') then
    raise exception 'This refund has not been approved yet.' using errcode = 'P0001';
  end if;

  -- In flight: ask for the answer.
  if r.status = 'processing' then
    v_said := public.refund_collect(p_id);
    if v_said is null then
      return 'Still with Razorpay. Give it a moment and check again.';
    end if;
    return v_said;
  end if;

  -- `approved` or `failed` — send it.
  --
  -- `failed` is deliberately sendable. Razorpay refuses for reasons that get
  -- fixed ("this payment was never captured" is true until the capture lands),
  -- and the alternative is an admin re-approving the row just to make a button
  -- appear, which is what happened to refund 98 on this database.
  if r.payment_id is null
     or r.payment_id not like 'pay\_%'
     or r.payment_id like 'pay\_mock\_%' then
    raise exception 'There is no Razorpay payment behind this refund, so there is nothing to send back. Settle it with "Mark sent" once the money has gone out another way.'
      using errcode = 'P0001';
  end if;

  -- `failed` carries a `failure_reason` the constraint required; sending again
  -- clears it, so the row does not show yesterday's refusal beside today's
  -- attempt.
  update public.refunds set failure_reason = null where id = p_id;

  perform public.refund_fire(p_id);

  return 'Sent to Razorpay. The answer usually lands within a few seconds.';
end;
$fn$;

comment on function public.admin_push_refund(bigint) is
  '0158: sends one refund to Razorpay now, or reads the answer if it is already in flight. The console''s "Send now" and "Check again" are the same call.';

revoke all on function public.admin_push_refund(bigint) from public, anon, authenticated;
grant execute on function public.admin_push_refund(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- The queue, saying which rows the gateway can actually take.
-- ---------------------------------------------------------------------------
-- The console has to know whether to offer the button, and the only honest
-- answer is the one this database uses: a `payment_id` that is a real Razorpay
-- capture. **`payment_method` is not that answer.** Every refund on this
-- platform sits on a `upi` order — all twenty-three of them — and nineteen carry
-- a `pay_mock_…` id from before payments existed. Deciding by payment method
-- would put a button on all twenty-three and have nineteen of them fail.
--
-- So the rule is computed here, once, and shipped as a boolean. The alternative
-- was sending `payment_id` to the browser and letting it re-implement the
-- `like` — a second copy of the rule, in a different language, free to drift,
-- and a gateway payment id in a bundle that has no use for one.
--
-- Dropped rather than replaced: `create or replace` cannot add an output column.
-- The signature is unchanged, so nothing that calls it has to change.
drop function if exists public.admin_list_refunds(text);

create function public.admin_list_refunds(p_status text default null)
returns table (
  id bigint,
  order_id text,
  restaurant_id text,
  restaurant_name text,
  user_phone text,
  order_total integer,
  payment_method text,
  amount integer,
  status text,
  reason text,
  funded_by text,
  requested_by text,
  approved_by text,
  gateway_refund_id text,
  failure_reason text,
  expected_by date,
  settlement_id bigint,
  created_at timestamptz,
  paid_at timestamptz,
  -- New in 0158. True when Razorpay has something to send back.
  gateway_backed boolean
)
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  perform public.assert_admin();

  return query
    select r.id, r.order_id, o.restaurant_id, o.restaurant_name, o.user_phone,
           o.total, o.payment_method,
           r.amount, r.status, r.reason, r.funded_by, r.requested_by,
           r.approved_by, r.gateway_refund_id, r.failure_reason, r.expected_by,
           r.settlement_id, r.created_at, r.paid_at,
           (r.payment_id like 'pay\_%' and r.payment_id not like 'pay\_mock\_%')
      from public.refunds r
      join public.orders o on o.id = r.order_id
     where p_status is null or r.status = p_status
     -- Oldest first. This is a work queue and the thing that has been waiting
     -- longest is the thing somebody is chasing.
     order by r.created_at;
end;
$fn$;

comment on function public.admin_list_refunds(text) is
  '0158: the refund queue, oldest first, each row saying whether Razorpay has a payment to send back.';

revoke all on function public.admin_list_refunds(text) from public, anon, authenticated;
grant execute on function public.admin_list_refunds(text) to authenticated;
