-- 0091 - a key in the catalogue
--
-- Ship-plan S7, 3 August 2026. Two things the edge-function audit found that are
-- fixable in the database. What the audit itself concluded is in the ship plan;
-- this file is only the part that is code.
--
-- --------------------------------------------------------------------------
-- 1. SEC-010 - the service-role key is sitting in a trigger definition.
-- --------------------------------------------------------------------------
--
-- `push_on_notification_insert` calls `send-notification` through
-- `supabase_functions.http_request`, and its headers argument carries
--
--     "Authorization": "Bearer <service_role JWT>"
--
-- in plaintext. A trigger's arguments are not secret storage: `pg_trigger` is
-- world-readable and `pg_get_triggerdef` is executable by PUBLIC, so anything
-- that can read the catalogue can read that key - and the service-role key
-- bypasses RLS entirely. A read-only foothold, a logical backup, a dashboard
-- user or a support export all become full write access to every table.
--
-- **It is not reachable through PostgREST**, which exposes no catalogue, so this
-- is an escalation path rather than an open door. It is still the most valuable
-- single string in the project stored where it did not need to be.
--
-- **And it buys nothing.** `send-notification` is deployed `--no-verify-jwt`, so
-- the gateway does not ask for an Authorization header at all, and the handler
-- authenticates on `x-notify-secret` (constant-time) and then re-reads the row
-- from the table. Verified over HTTP rather than assumed: a POST to the function
-- with **no Authorization header whatsoever** returns `403 Forbidden` from the
-- handler's own secret check - not `401 UNAUTHORIZED_NO_AUTH_HEADER` from the
-- gateway, which is what `razorpay-order` returns to the same request. The
-- gateway is not looking. So the header can go, and nothing changes except that
-- the key stops being in the catalogue.
--
-- **The rewrite reads the existing headers and removes one key.** It does not
-- restate them, because restating them would put `x-notify-secret` into this
-- file and then into git - which is precisely how SEC-007 happened. The secret
-- never leaves the database.
--
-- Checked before trusting the round trip: the arguments contain no escaped
-- bytes, the secret is 64 hex characters and the bearer is a well-formed
-- three-segment JWT, so `encode(tgargs,'escape')` is lossless here.

do $$
declare
  v_args    text[];
  v_headers jsonb;
begin
  select string_to_array(encode(t.tgargs, 'escape'), '\000')
    into v_args
    from pg_trigger t
   where t.tgname = 'push_on_notification_insert'
     and t.tgrelid = 'public.notifications'::regclass
     and not t.tgisinternal;

  if v_args is null then
    raise exception
      'push_on_notification_insert is not on public.notifications. Refusing to guess at the webhook.';
  end if;

  v_headers := (v_args[3])::jsonb;

  -- Already done, or never had one. Either way there is nothing to do, and
  -- re-running a migration must not be how push breaks.
  if not (v_headers ? 'Authorization') then
    raise notice 'No Authorization header on the webhook — nothing to remove.';
    return;
  end if;

  v_headers := v_headers - 'Authorization';

  -- The secret is the only thing authenticating this call. If it is not in the
  -- headers we are about to install, the webhook would start being refused by
  -- its own handler and every push would stop.
  if not (v_headers ? 'x-notify-secret') then
    raise exception
      'The webhook headers carry no x-notify-secret. Refusing to drop the only other credential.';
  end if;

  execute 'drop trigger push_on_notification_insert on public.notifications';

  execute format(
    'create trigger push_on_notification_insert '
    'after insert on public.notifications for each row '
    'execute function supabase_functions.http_request(%L, %L, %L, %L, %L)',
    v_args[1], v_args[2], v_headers::text, v_args[4], v_args[5]
  );
end $$;

-- --------------------------------------------------------------------------
-- 2. A payment intent is a real Razorpay order, and nothing bounded it.
-- --------------------------------------------------------------------------
--
-- `razorpay-order` authenticates properly - it reads the caller from the token
-- with `getUser` rather than believing a user id in the body - but a signed-in
-- customer could call it without limit, and every call creates a real order at
-- Razorpay and a `payment_intents` row here. That is S6's shape exactly: free to
-- call, expensive to answer. It is only latent today because the merchant keys
-- are unset and the function answers `{configured:false}` before doing anything
-- (G3, S5) - which means it arrives the same day payments do.
--
-- Thirty an hour per customer. Deliberately well above the ten orders an hour
-- 0090 allows, because a genuine customer whose UPI app fails will retry, and a
-- refused *retry* is worse than a refused first attempt.
--
-- In the database rather than in the handler, for the reason the whole of Phase
-- 1 exists: a check that lives only in code the client can reach is not a check.
-- `payment_intents_user_idx (user_id, created_at desc)` already exists.
--
-- **Known and accepted:** the handler creates the Razorpay order *before*
-- inserting the intent, so a refusal here leaves an unused order at Razorpay and
-- returns the customer a 500. That is untidy and it is the safe direction - the
-- alternative is a payment that can never become an order. Checking the ceiling
-- in the handler before the Razorpay call is the tidier fix and needs a deploy;
-- it is logged rather than done here.

create or replace function public.payment_intents_reject_too_many()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_max    constant integer := 30;
  v_window constant interval := interval '1 hour';
  v_recent integer;
begin
  select count(*) into v_recent
    from public.payment_intents p
   where p.user_id = new.user_id
     and p.created_at > now() - v_window;

  if v_recent >= v_max then
    raise exception
      'That is % payment attempts in an hour. Please wait before trying again.',
      v_recent using errcode = 'P0001';
  end if;

  return new;
end;
$function$;

revoke execute on function public.payment_intents_reject_too_many() from public;

create trigger payment_intents_reject_too_many
  before insert on public.payment_intents
  for each row execute function public.payment_intents_reject_too_many();
