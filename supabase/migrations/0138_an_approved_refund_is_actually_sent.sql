-- ---------------------------------------------------------------------------
-- 0138 — an approved refund is actually sent.
-- ---------------------------------------------------------------------------
-- `orders_refund_on_termination` (0077) inserts a refund already `approved` and
-- notifies the customer that their money is coming back. Nothing then sends it.
-- There is no Razorpay refund call anywhere in the eight edge functions, no cron
-- job that looks, and no alarm when a refund passes `expected_by`.
-- `admin_mark_refund_paid` is a person clicking a button after moving the money
-- by hand.
--
-- So `approved` has been a terminus rather than a step. Live at the time of
-- writing: **18 refunds, ₹4,348, every one `approved`**, the oldest overdue
-- since 7 August. This closes that.
--
-- ## What it does not do, and why the backlog does not drain
--
-- All 18 of those refunds name a `pay_mock_…` payment id, because every order
-- this project has ever taken went through the mock gateway — `payment_intents`
-- is empty. **No money was ever captured for any of them, so there is nothing
-- to send back.** Razorpay would answer 400 to all 18 and they would land in
-- `failed`, which is worse than where they are: it would read as a gateway
-- problem rather than as bookkeeping from before payments existed.
--
-- They are therefore excluded here, by the same filter that keeps them out of
-- every future tick, and they are left for a human to decide about. What that
-- decision is — `declined` with a reason, or paid outside the gateway — belongs
-- to whoever knows what those testers were told, not to this file.
--
-- ## Collect first, then fire
--
-- `pg_net` is asynchronous: `net.http_post` queues a request and hands back an
-- id, and the response lands later in `net._http_response`. One function cannot
-- fire a call and read its answer, so this does what `process_order_routes`
-- (0046) does — collects what has come back, then fires what is waiting, in that
-- order, on a schedule.
--
-- ## Where money makes this different from 0046
--
-- 0046 requeues anything it did not get a clean answer for, because asking for a
-- road distance twice costs nothing. **Asking for a refund twice sends the money
-- twice**, and the Razorpay refunds API has no idempotency key to make that
-- safe. So:
--
--   * a refund is moved to `processing` *before* the call is fired, inside the
--     same transaction, with `for update skip locked` — two overlapping ticks
--     cannot both claim it, and the fire step only ever reads `approved`;
--   * a non-200 is `failed` with Razorpay's own words, which is a state 0077
--     already defines as "needs a person";
--   * **a response that never arrives is never retried.** It stays `processing`
--     with the request id that was fired, which is precisely what that state
--     means — handed to the gateway, not confirmed. A person resolves it, and
--     `admin_mark_refund_paid` already accepts `processing` for exactly that.
--
-- A refund sitting in `processing` for more than a few minutes is the one thing
-- here that wants human eyes:
--
--     select id, order_id, payment_id, amount, gateway_sent_at
--       from public.refunds
--      where status = 'processing'
--        and gateway_sent_at < now() - interval '30 minutes';
--
-- Check Razorpay's dashboard for a refund against that payment before doing
-- anything: if one is there, `admin_mark_refund_paid` with its `rfnd_…` id; if
-- not, `admin_approve_refund` puts it back in this queue.
--
-- ## `paid` on a 200 is a small overstatement, and the fix is a webhook
--
-- Razorpay answers a refund request with `status: processed` or `status:
-- pending` — the latter when the customer's bank has not confirmed yet. This
-- marks `paid` on any 200, so a `pending` refund reads as confirmed a little
-- early. Closing that honestly needs `refund.processed` on a webhook, which is
-- not built. It is the right next step and it is not this migration.
--
-- ## The secrets, which are not in this file
--
-- Two Vault entries, set by hand once — the repo is public and a key never
-- enters a migration:
--
--     select vault.create_secret('rzp_test_…', 'razorpay_key_id');
--     select vault.create_secret('…',          'razorpay_key_secret');
--
-- The same pair is also set as Supabase **function** secrets, because
-- `razorpay-order` and `razorpay-verify` run in Deno and read them from there.
-- Two homes for one credential is not duplication for its own sake: each
-- runtime can only reach its own.
--
-- A missing secret makes every tick a no-op, exactly as 0132 does. That is what
-- lets this migration be applied before the keys exist.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. What a refund has to remember between the two ticks.
-- ---------------------------------------------------------------------------
-- `gateway_refund_id` already holds Razorpay's `rfnd_…` once it answers. These
-- two are the in-flight half: which `pg_net` request is carrying this refund,
-- and when it left. `gateway_sent_at` is what the stuck-in-`processing` query
-- above reads, and it is deliberately separate from `paid_at`.
alter table public.refunds
  add column if not exists gateway_request_id bigint,
  add column if not exists gateway_sent_at    timestamptz;

comment on column public.refunds.gateway_request_id is
  '0138: the pg_net request id of the refund call in flight. Null once collected.';
comment on column public.refunds.gateway_sent_at is
  '0138: when the refund was handed to Razorpay. A processing row older than 30 minutes needs a person.';

-- The fire step reads exactly this set every tick.
create index if not exists refunds_payable_idx
  on public.refunds (created_at)
  where status = 'approved' and payment_id is not null;

-- ---------------------------------------------------------------------------
-- 2. The sweeper.
-- ---------------------------------------------------------------------------
create or replace function public.pay_approved_refunds()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  -- Per tick. Well above any plausible backlog, and a ceiling means a bug that
  -- floods `refunds` cannot become a thousand Razorpay calls in one minute.
  v_batch   constant integer := 20;
  v_key_id      text;
  v_key_secret  text;
  v_auth        text;
  r             record;
  v_status      integer;
  v_content     text;
  v_json        jsonb;
  v_refund_id   text;
  v_reason      text;
  v_user        text;
  v_request     bigint;
begin
  -- ---------------------------------------------------------------------
  -- Collect. First, so a finished refund leaves `processing` immediately.
  -- ---------------------------------------------------------------------
  for r in
    select id, order_id, amount, payment_id, gateway_request_id
      from public.refunds
     where status = 'processing'
       and gateway_request_id is not null
     for update skip locked
  loop
    select status_code, content into v_status, v_content
      from net._http_response
     where id = r.gateway_request_id;

    -- Still in flight, or the response was pruned before we read it. Either way
    -- this is not retried — see the header. It stays `processing` for a person.
    if not found then
      continue;
    end if;

    -- A body is not guaranteed to be JSON — a proxy or a gateway between here
    -- and Razorpay answers in HTML, and `::jsonb` on that raises inside a loop
    -- that is holding a row lock on somebody's money.
    begin
      v_json := v_content::jsonb;
    exception when others then
      v_json := null;
    end;

    if v_status = 200 then
      v_refund_id := nullif(trim(coalesce(v_json ->> 'id', '')), '');

      -- A 200 with no refund id is not something to guess about: Razorpay
      -- accepted something and we cannot name it. `refund_paid_has_a_reference`
      -- would refuse the update anyway, so say why and leave it for a person.
      if v_refund_id is null then
        update public.refunds
           set gateway_request_id = null
         where id = r.id;
        raise warning 'refund %: Razorpay answered 200 with no refund id: %', r.id, left(v_content, 200);
        continue;
      end if;

      update public.refunds
         set status            = 'paid',
             gateway_refund_id = v_refund_id,
             paid_at           = now(),
             gateway_request_id = null
       where id = r.id;

      -- The sentence the customer gets is the one `admin_mark_refund_paid`
      -- already sends, because from their side nothing about this is different.
      -- Wrapped whole: a courtesy is never the reason a refund fails to record.
      begin
        select o.user_id into v_user
          from public.orders o where o.id = r.order_id;

        insert into public.notifications
          (audience, user_id, kind, title, body, order_id)
        values (
          'customer', v_user, 'refund',
          'Refund sent',
          '₹' || r.amount || ' for order ' || r.order_id ||
            ' has been sent back to your original payment method.',
          r.order_id
        );
      exception when others then
        null;
      end;

    else
      -- Razorpay's own description is the most useful thing a person can be
      -- given here — 'the payment has been fully refunded already' and 'this
      -- payment was never captured' need completely different answers.
      v_reason := nullif(
        trim(coalesce(v_json #>> '{error,description}', '')), ''
      );

      update public.refunds
         set status             = 'failed',
             failure_reason     = coalesce(
               v_reason,
               'Razorpay refused the refund (HTTP ' || coalesce(v_status::text, '?') || ').'
             ),
             gateway_request_id = null
       where id = r.id;

      raise warning 'refund % failed: HTTP % %', r.id, v_status, left(coalesce(v_content, ''), 200);
    end if;
  end loop;

  -- ---------------------------------------------------------------------
  -- Fire. Nothing below runs without both keys.
  -- ---------------------------------------------------------------------
  select decrypted_secret into v_key_id
    from vault.decrypted_secrets where name = 'razorpay_key_id';
  select decrypted_secret into v_key_secret
    from vault.decrypted_secrets where name = 'razorpay_key_secret';

  if v_key_id is null or v_key_secret is null then
    return;
  end if;

  v_auth := 'Basic ' || encode(convert_to(v_key_id || ':' || v_key_secret, 'utf8'), 'base64');

  for r in
    select id, order_id, amount, payment_id
      from public.refunds
     where status = 'approved'
       -- A real Razorpay capture and nothing else. `pay_mock_…` is every refund
       -- raised before payments existed: no money was taken, so none goes back.
       -- See the header — those are a person's decision, not this loop's.
       and payment_id like 'pay\_%'
       and payment_id not like 'pay\_mock\_%'
     order by created_at
     limit v_batch
     for update skip locked
  loop
    -- Claimed before the call is fired, in this transaction. A tick that
    -- overlaps the next one cannot read this row as `approved` again.
    update public.refunds
       set status = 'processing'
     where id = r.id;

    select net.http_post(
      url     := 'https://api.razorpay.com/v1/payments/' || r.payment_id || '/refund',
      headers := jsonb_build_object(
        'Authorization', v_auth,
        'Content-Type',  'application/json'
      ),
      body := jsonb_build_object(
        -- Paise. Every money column in this schema is whole rupees and Razorpay
        -- takes nothing else; the conversion happens here and nowhere else.
        'amount', r.amount * 100,
        -- 'normal' settles through the customer's bank in the usual few days.
        -- 'optimum' costs a fee to be faster and is not worth it for a refund
        -- the customer has already been told is coming.
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
     where id = r.id;
  end loop;
end;
$$;

comment on function public.pay_approved_refunds() is
  '0138: sends approved refunds to Razorpay and collects the answers. Excludes pay_mock_ captures. Never retries an unanswered call.';

-- New functions are executable by PUBLIC *and* carry a default grant to
-- `authenticated`. Only cron calls this, so shut both routes.
revoke all on function public.pay_approved_refunds() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Run it.
-- ---------------------------------------------------------------------------
-- Five minutes, not one. A refund is owed within days, `expected_by` is a date,
-- and there is nothing a customer sees sooner for a tighter schedule. Most ticks
-- do nothing at all.
select cron.unschedule('pay-approved-refunds')
 where exists (select 1 from cron.job where jobname = 'pay-approved-refunds');

select cron.schedule(
  'pay-approved-refunds',
  '*/5 * * * *',
  $$ select public.pay_approved_refunds(); $$
);
