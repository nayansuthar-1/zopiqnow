-- ---------------------------------------------------------------------------
-- 0149 — a refund that stops moving says so.
-- ---------------------------------------------------------------------------
-- 0138 gave `approved` somewhere to go: a five-minute cron hands the refund to
-- Razorpay, collects the answer, and writes `paid` or `failed`. That half works
-- — three refunds have been paid by it and one was refused.
--
-- What 0138 did not build is the other half its own header asks for: **nothing
-- watches**. A refund the gateway refuses, one it never answers for, and one it
-- is never offered in the first place all end in the same place — a row sitting
-- in a table nobody opens, against a notification the customer already received
-- telling them their money is on its way by a date that has now passed.
--
-- Live at the time of writing: **19 refunds, ₹4,660, every one `approved`, the
-- oldest promised for 10 August** — twenty days ago. Not one of them is in
-- flight, and not one of them has been seen by a person.
--
-- ## Why one alert and not nineteen
--
-- 0142 raises one `orphan_payment` per orphaned payment, and is right to: each
-- is a separate sum needing its own trip to the Razorpay dashboard and its own
-- reference typed back. A stalled refund is not that. The console already has
-- the per-item queue — Payouts -> Refunds, with approve, decline and mark paid
-- on every row — so nineteen alert cards would be a second copy of a list that
-- already exists, and an admin would clear them in one place while working them
-- in another.
--
-- What is missing is not a queue. It is the sentence saying the queue has
-- stopped being worked. So: one alert, `subject = 'refunds'`, which the unique
-- index on (kind, subject) keeps at exactly one, rewritten with current numbers
-- on every tick and cleared by the sweep itself once there is nothing left in
-- it.
--
-- ## What counts as stopped
--
--   * **`approved` past `expected_by`.** The promise in the customer's inbox
--     has expired. This is the condition P3 asked for.
--   * **`processing` for more than thirty minutes.** 0138's own threshold,
--     lifted out of the comment it was written in. That state means *handed to
--     the gateway, not confirmed*, and 0138 deliberately never retries it —
--     which only works if somebody is told.
--   * **`failed`.** 0077 defines it as "needs a person" and then tells nobody.
--
-- `requested` is not here. A refund waiting on an admin's approval has been
-- promised to nobody yet, and it is already the top of the Refunds page.
--
-- ## The nineteen are the point, not a false positive
--
-- All nineteen name a `pay_mock_…` capture, so `pay_approved_refunds` skips
-- them by design — no money was ever taken, so none can go back. 0138 left them
-- "for a human to decide about" and then provided no way for a human to find
-- out they were waiting. This is that way. The body says so in as many words,
-- so the first thing an admin reads is bookkeeping from before payments existed
-- rather than a gateway on fire.
--
-- ## Emailed once, on the way up
--
-- `email_admin_alert` goes out when the alert is opened and not on the ticks
-- that rewrite it. A standing alert mailing every fifteen minutes is one that
-- gets filtered inside a day, and the console card is the durable half.
--
-- **It sends nothing today.** `email_admin_alert` returns early without
-- `brevo_api_key` in the vault, and the vault holds five secrets, none of them
-- that one. Until it is set this alert is console-only — the same state 0130's
-- rider alert has always shipped in.
-- ---------------------------------------------------------------------------

create or replace function public.sweep_stalled_refunds()
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  -- 0138's number, not a new one: a refund handed to Razorpay that has not come
  -- back in half an hour is the one case its header says to go and look at.
  v_stuck_after constant interval := interval '30 minutes';

  v_total    integer;
  v_rupees   integer;
  v_oldest   date;
  v_overdue  integer;
  v_stuck    integer;
  v_failed   integer;
  v_mock     integer;
  v_body     text;
  v_existing bigint;
  v_alert_id bigint;
begin
  -- One pass over the three conditions, so the total and the breakdown cannot
  -- disagree with each other. `refunds_open_idx` already covers this set.
  select count(*),
         coalesce(sum(amount), 0),
         min(expected_by),
         count(*) filter (where status = 'approved'),
         count(*) filter (where status = 'processing'),
         count(*) filter (where status = 'failed'),
         count(*) filter (where payment_id like 'pay\_mock\_%')
    into v_total, v_rupees, v_oldest, v_overdue, v_stuck, v_failed, v_mock
    from public.refunds
   where (status = 'approved'   and expected_by < current_date)
      or (status = 'processing' and gateway_sent_at < now() - v_stuck_after)
      or  status = 'failed';

  -- ---------------------------------------------------------------------
  -- Nothing owed. Close the alert if one is open.
  -- ---------------------------------------------------------------------
  -- Cleared by the sweep rather than left for somebody to dismiss: this alert
  -- asks one question — is the refund queue moving — and when the answer turns
  -- back to yes there is no decision left for an admin to make. The audit
  -- trigger records it as `system`, which `record_admin_action` already writes
  -- for anything with no JWT behind it.
  if v_total = 0 then
    update public.admin_alerts
       set resolved_at = now(),
           resolved_by = 'system'
     where kind = 'refunds_stalled'
       and subject = 'refunds'
       and resolved_at is null;
    return;
  end if;

  v_body :=
    v_total || ' ' || case when v_total = 1 then 'refund is' else 'refunds are' end
    || ' owed and not moving — ₹' || v_rupees || ' in total.' || chr(10) || chr(10);

  if v_overdue > 0 then
    v_body := v_body
      || '  · ' || v_overdue || ' approved and past the date the customer was '
      || 'promised. The oldest was due ' || to_char(v_oldest, 'DD Mon') || '.' || chr(10);
  end if;

  if v_stuck > 0 then
    v_body := v_body
      || '  · ' || v_stuck || ' handed to Razorpay over 30 minutes ago and never '
      || 'confirmed. Check the Razorpay dashboard for a refund against that '
      || 'payment before doing anything — these are never retried automatically, '
      || 'on purpose.' || chr(10);
  end if;

  if v_failed > 0 then
    v_body := v_body
      || '  · ' || v_failed || ' the gateway refused. Each row carries '
      || 'Razorpay''s own words in its failure reason.' || chr(10);
  end if;

  -- Said before the instruction, because it changes what the instruction means.
  if v_mock > 0 then
    v_body := v_body || chr(10)
      || 'Note: ' || v_mock || ' of these were paid through the mock gateway '
      || 'before Razorpay existed (a pay_mock_ reference). No money was ever '
      || 'captured for them, so none can be sent back, and the payer skips them '
      || 'deliberately. They need a decision — declined with a reason, or '
      || 'settled outside the gateway — not a retry.' || chr(10);
  end if;

  v_body := v_body || chr(10)
    || 'Work them on the Refunds page (Payouts -> Refunds). This alert clears '
    || 'itself when the queue is empty.';

  -- Open already? Then this tick only rewrites the numbers, and sends no mail.
  select id into v_existing
    from public.admin_alerts
   where kind = 'refunds_stalled'
     and subject = 'refunds'
     and resolved_at is null;

  -- Deliberately no `created_at = now()` on the update, unlike 0130: that alert
  -- restamps because each repeat is a fresh incident, and this one is a single
  -- condition that has been true since it was raised. The date on the card
  -- should say how long the queue has been stuck, not when it was last counted.
  insert into public.admin_alerts (kind, subject, title, body)
  values (
    'refunds_stalled', 'refunds',
    v_total || ' ' || case when v_total = 1 then 'refund needs' else 'refunds need' end
      || ' a person',
    v_body
  )
  on conflict (kind, subject) where resolved_at is null
  do update set title = excluded.title,
                body  = excluded.body
  returning id into v_alert_id;

  if v_existing is null then
    perform public.email_admin_alert(v_alert_id);
  end if;
end;
$fn$;

comment on function public.sweep_stalled_refunds() is
  '0149: raises one standing admin alert while any refund is overdue, stuck with the gateway, or failed. Clears itself.';

-- Born executable by PUBLIC *and* with a default grant to `authenticated`.
-- Only cron calls this, so shut both routes.
revoke all on function public.sweep_stalled_refunds() from public, anon, authenticated;

-- Fifteen minutes. The overdue half moves once a day and the stuck half has a
-- thirty-minute threshold, so nothing here is worth a tighter schedule; this
-- matches `flag-orphaned-payments`, the other money sweep that only watches.
select cron.unschedule('sweep-stalled-refunds')
 where exists (select 1 from cron.job where jobname = 'sweep-stalled-refunds');

select cron.schedule(
  'sweep-stalled-refunds',
  '*/15 * * * *',
  $cron$ select public.sweep_stalled_refunds(); $cron$
);
