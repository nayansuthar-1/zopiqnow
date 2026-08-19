-- ---------------------------------------------------------------------------
-- 0132 — the confirmation arrives on WhatsApp, not only inside the app.
-- ---------------------------------------------------------------------------
-- When a kitchen accepts an order, 0047 writes the customer an in-app
-- notification titled "Order confirmed" and 0020's push wakes the phone. Both
-- reach a customer who still has the app. This adds the one channel that
-- reaches everybody: a WhatsApp message carrying the order id, when it was
-- placed, and what it costs.
--
-- ## Why it fires on 'accepted' and not on placement
--
-- 'placed' means the customer paid; it does not mean anybody is cooking. The
-- kitchen has five minutes to answer (0051) and may refuse, and a message that
-- says "confirmed" and is followed by a cancellation is worse than no message.
-- 'accepted' is the first moment the statement is true, and it is the same
-- moment 0047 already calls "Order confirmed" — one event, three channels,
-- consistent wording.
--
-- ## Why the message is a template, and why UTILITY
--
-- WhatsApp permits a business-initiated message only in wording Meta approved
-- beforehand. The template is `zopiq_order_confirmed` (en_US), submitted by
-- `tool/whatsapp-template.mjs`, which also documents why the category is
-- UTILITY and why the three variables are in the order they are. **The name,
-- the language and the parameter order below must match that file**, because
-- Postgres cannot read it — {{1}} order id, {{2}} placed-at, {{3}} rupees.
--
-- Until Meta marks the template APPROVED, every send here fails upstream and
-- the customer simply does not get a WhatsApp. Nothing else changes.
--
-- ## Why this is in the database and not an Edge Function
--
-- The same reason 0046 gives for the Ola call: `pg_net` makes the request,
-- `supabase_vault` holds the token, and there is no deploy to forget. It also
-- avoids a dashboard webhook, which inlines the service-role key into a header
-- that anyone with dashboard access can read.
--
-- `pg_net` is asynchronous — `net.http_post` queues the request and returns an
-- id immediately, so no network round trip happens inside the vendor's
-- `set_order_status` transaction. If that transaction rolls back the queued
-- request rolls back with it, which is exactly right: no acceptance, no
-- message.
--
-- ## The secrets, which are not in this file
--
-- Two Vault entries, set by hand once (the repo is public; a token never enters
-- a migration):
--
--   select vault.create_secret('EAAG…', 'whatsapp_token');
--   select vault.create_secret('1177…', 'whatsapp_phone_number_id');
--
-- The phone number id is the *sender's id*, not its phone number. A missing
-- secret makes this a no-op rather than an error — an unconfigured channel is
-- silence, not a broken order.
--
-- ## How to tell whether a send worked
--
-- `pg_net` files every response in `net._http_response`. Meta answers 200 with
-- a message id on success and 4xx with a reason on failure — the commonest by
-- far being a customer whose number has no WhatsApp account at all, which is
-- not fixable and not an error worth chasing:
--
--   select created, status_code, content
--     from net._http_response
--    where url like '%graph.facebook.com%'
--    order by created desc limit 20;
--
-- ## The side effect worth knowing about
--
-- This WABA has never delivered a single template message, and that zero is the
-- one unmet criterion standing between us and Meta enabling AUTHENTICATION
-- templates — which is what WhatsApp login is waiting on. Every order
-- confirmation sent here is also sending history.

-- ---------------------------------------------------------------------------
-- The send.
-- ---------------------------------------------------------------------------
-- Wrapped whole, like every other courtesy that rides an order (0021, 0046,
-- 0047): a message is never allowed to be the reason a kitchen's acceptance
-- fails. Vault unreachable, secret missing, `pg_net` unhappy — the order is
-- accepted regardless and the customer is one WhatsApp short.
create or replace function public.whatsapp_order_confirmed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token    text;
  v_phone_id text;
  v_to       text;
begin
  begin
    select decrypted_secret into v_token
      from vault.decrypted_secrets where name = 'whatsapp_token';
    select decrypted_secret into v_phone_id
      from vault.decrypted_secrets where name = 'whatsapp_phone_number_id';
    if v_token is null or v_phone_id is null then
      return new;
    end if;

    -- `user_phone` is E.164 from the delivery-phone sheet ('+9198…'); WhatsApp
    -- wants the country code with no '+'. Digits-only is the whole conversion.
    -- Anything shorter than a national number is not worth an API call.
    v_to := regexp_replace(coalesce(new.user_phone, ''), '\D', '', 'g');
    if length(v_to) < 10 then
      return new;
    end if;

    perform net.http_post(
      url := 'https://graph.facebook.com/v23.0/' || v_phone_id || '/messages',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || v_token,
        'Content-Type',  'application/json'
      ),
      body := jsonb_build_object(
        'messaging_product', 'whatsapp',
        'to',               v_to,
        'type',             'template',
        'template', jsonb_build_object(
          'name',     'zopiq_order_confirmed',
          'language', jsonb_build_object('code', 'en_US'),
          'components', jsonb_build_array(
            jsonb_build_object(
              'type', 'body',
              'parameters', jsonb_build_array(
                -- {{1}} the order id, as the customer sees it everywhere else.
                jsonb_build_object('type', 'text', 'text', new.id),
                -- {{2}} when it was placed, in the reader's own time zone. The
                -- column is timestamptz and the reader is in India; UTC on a
                -- receipt reads as an eight-and-a-half-hour error.
                jsonb_build_object(
                  'type', 'text',
                  'text', to_char(new.created_at at time zone 'Asia/Kolkata',
                                  'FMDD Mon YYYY, FMHH12:MI AM')
                ),
                -- {{3}} whole rupees, like every other total in this schema.
                -- The template supplies the ₹, so this is digits only.
                jsonb_build_object('type', 'text', 'text', new.total::text)
              )
            )
          )
        )
      ),
      timeout_milliseconds := 8000
    );
  exception when others then
    -- An acceptance is sacred; a message is not.
    null;
  end;
  return new;
end;
$$;

-- The guard is in the WHEN clause rather than the body so an ordinary status
-- move — preparing, out_for_delivery, delivered — never enters the function at
-- all. `old.status is distinct from 'accepted'` is what makes this once per
-- order: a second UPDATE that leaves the status alone re-fires the trigger but
-- not the message.
drop trigger if exists orders_whatsapp_confirmed on public.orders;
create trigger orders_whatsapp_confirmed
  after update of status on public.orders
  for each row
  when (new.status = 'accepted' and old.status is distinct from 'accepted')
  execute function public.whatsapp_order_confirmed();
